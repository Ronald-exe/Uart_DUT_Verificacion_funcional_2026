class uart_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(uart_scoreboard)
  uart_env_cfg cfg;
  uvm_tlm_analysis_fifo #(wb_item) wb_in;
  uvm_tlm_analysis_fifo #(ser_item) tx_in;
  uvm_tlm_analysis_fifo #(ser_item) rx_in;
  uvm_tlm_analysis_fifo #(modem_item) modem_in;
  uvm_tlm_analysis_fifo #(uart_irq_sample) irq_in;
  uart_reference_model expected;
  uart_reference_model documented;
  // A model with all bugs enabled is useful for diagnosis, but cannot decide what passes
  // If only BUG-04 is waived, permitted must still reject the modem bugs reproduced by documented -- alex
  uart_reference_model permitted;
  typedef struct packed {
    longint unsigned cycle;
    bit [7:0] lsr;
    bit [7:0] iir;
    bit [7:0] msr;
    bit irq;
  } status_entry;
  status_entry history[$];
  status_entry known_history[$];
  status_entry permitted_history[$];
  ser_item tx_expected[$];
  ser_item active_tx;
  longint unsigned cycle;
  longint unsigned wb_observed;
  longint unsigned tx_compared;
  longint unsigned rx_compared;
  longint unsigned rx_observed;
  longint unsigned tx_aborted;
  longint unsigned empty_reads;
  longint unsigned uncertain_reads;
  longint unsigned status_checks;
  longint unsigned irq_checks;
  longint unsigned baud_checks;
  longint unsigned resets;
  longint unsigned tx_fifo_reset_entries;
  longint unsigned rx_fifo_reset_entries;
  longint unsigned modem_events;
  bit in_reset = 1;
  bit finished;
  int unsigned old_epoch;
  int unsigned baud_epoch;
  longint unsigned baud_last;
  longint unsigned baud_settle;
  bit baud_seen;
  bit [1:0] modem_bad_previous;
  bit [1:0] modem_wanted_previous;
  bit modem_error_active;
  bit irq_bad_previous;
  time invalid_tx_since;
  time invalid_tx_until;
  bit invalid_tx_range;
  int unsigned estimated_divider;

  function new(string name = "uart_scoreboard", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(uart_env_cfg)::get(this, "", "cfg", cfg)) begin
      `uvm_fatal("SCB_NOCFG", "Scoreboard configuration is missing")
    end
    wb_in = new("wb_in", this);
    tx_in = new("tx_in", this);
    rx_in = new("rx_in", this);
    modem_in = new("modem_in", this);
    irq_in = new("irq_in", this);
    expected = uart_reference_model::type_id::create("expected");
    documented = uart_reference_model::type_id::create("documented");
    permitted = uart_reference_model::type_id::create("permitted");
    permitted.bugs = cfg.waiver_mask();
    documented.bugs = '1;
    expected.reset_model();
    documented.reset_model();
    permitted.reset_model();
  endfunction

  function int unsigned index_of(wb_item it);
`ifdef DATA_BUS_WIDTH_8
    return it.adr;
`else
    case (it.sel)
      8: return {it.adr[4:2], 2'b00};
      4: return {it.adr[4:2], 2'b01};
      2: return {it.adr[4:2], 2'b10};
      1: return {it.adr[4:2], 2'b11};
      default: return {it.adr[4:2], 2'b00};
    endcase
`endif
  endfunction
  function bit [7:0] byte_of(wb_item it);
`ifdef DATA_BUS_WIDTH_8
    return it.data[7:0];
`else
    case (it.sel)
      8: return it.data[31:24];
      4: return it.data[23:16];
      2: return it.data[15:8];
      default: return it.data[7:0];
    endcase
`endif
  endfunction

  function bit rx_timing_uncertain();
    longint unsigned source_scaled;
    longint unsigned nominal_period;
    // Compare the rounded source period with the current DUT period, not just the requested error percentage
    // Live reconfiguration can change their difference after the source frame has already started -- alex
    source_scaled = longint'(cfg.ser.source_period) * 100;
    nominal_period = 16 * longint'(expected.dl);
    return cfg.ser.source_frame_active && (expected.dl != 0) &&
           ((source_scaled < nominal_period*97) || (source_scaled > nominal_period*103));
  endfunction

  function void compare_value(string id, bit [31:0] actual, bit [31:0] wanted,
                              bit [31:0] known, bit [4:0] causes, bit [31:0] mask = 'hff, logic [31:0] approved = 'x);
    string message;
    cfg.observed_checks++;
    if ((actual & mask) == (wanted & mask)) begin
      return;
    end
    message = $sformatf("%s cycle=%0d actual=%08h expected=%08h mask=%08h documented=%08h causes=%05b",
                        id, cycle, actual, wanted, mask, known, causes);
    // The default 'x means this caller did not supply a combined-waiver prediction
    // It is a sentinel for selecting the fallback, not permission for unknown DUT data -- alex
    if ($isunknown(approved)) begin
      approved = cfg.bugs_waived(causes) ? known : wanted;
    end
    // A waived bug must explain this exact value -- enabling its bit alone is not enough -- alex
    if ((|causes) && ((actual & mask) == (approved & mask)) &&
        ((approved & mask) != (wanted & mask))) begin
      cfg.report_known_bug(causes & cfg.waiver_mask(), message);
    end else if ((|causes) && ((actual & mask) == (known & mask)) &&
                 ((known & mask) != (wanted & mask))) begin
      // This value is recognizable, but the active waiver set did not allow it
      // Force an error so recognizing a known bug does not automatically excuse it -- alex
      cfg.report_known_bug(causes, message, 1);
    end else begin
      `uvm_error(id, message)
    end
  endfunction

  function void save_history();
    status_entry sample;
    longint unsigned window;
    // The plan allows one bit time for status propagation
    // Keep recent states instead of pausing checks after each read -- polling could otherwise keep checks paused forever -- alex
    window = 16 * longint'((expected.dl == 0) ? cfg.ser.source_dl : expected.dl);
    sample = '{cycle, expected.lsr, expected.iir, expected.msr, expected.irq};
    if (history.size() == 0) begin
      history.push_back(sample);
    end else if ((history[$].lsr != sample.lsr) ||
        (history[$].iir != sample.iir) || (history[$].msr != sample.msr) ||
        (history[$].irq != sample.irq)) begin
      history.push_back(sample);
    end
    sample = '{cycle, documented.lsr, documented.iir, documented.msr, documented.irq};
    if (known_history.size() == 0) begin
      known_history.push_back(sample);
    end else if ((known_history[$].lsr != sample.lsr) ||
        (known_history[$].iir != sample.iir) || (known_history[$].msr != sample.msr) ||
        (known_history[$].irq != sample.irq)) begin
      known_history.push_back(sample);
    end
    sample = '{cycle, permitted.lsr, permitted.iir, permitted.msr, permitted.irq};
    if (permitted_history.size() == 0) begin
      permitted_history.push_back(sample);
    end else if ((permitted_history[$].lsr != sample.lsr) ||
        (permitted_history[$].iir != sample.iir) || (permitted_history[$].msr != sample.msr) ||
        (permitted_history[$].irq != sample.irq)) begin
      permitted_history.push_back(sample);
    end
    // Look at entry 1 before removing entry 0
    // The older entry may have started outside the window but still describe the state at its left boundary
    // Use the same trimming rule for all three histories so their allowed timing stays comparable -- alex
    while (permitted_history.size() > 1) begin
      if (cycle < window) begin
        break;
      end
      if (permitted_history[1].cycle > cycle-window) begin
        break;
      end
      void'(permitted_history.pop_front());
    end
    while (history.size() > 1) begin
      if (cycle < window) begin
        break;
      end
      if (history[1].cycle > cycle-window) begin
        break;
      end
      void'(history.pop_front());
    end
    while (known_history.size() > 1) begin
      if (cycle < window) begin
        break;
      end
      if (known_history[1].cycle > cycle-window) begin
        break;
      end
      void'(known_history.pop_front());
    end
  endfunction
  function bit status_matches(bit [7:0] actual, int unsigned index, int unsigned which = 0);
    status_entry entries[$];
    entries = (which == 2) ? permitted_history : ((which == 1) ? known_history : history);
    foreach (entries[i]) begin
      case (index)
        2: begin
          if (actual == entries[i].iir) begin
            return 1;
          end
        end
        5: begin
          if (actual == entries[i].lsr) begin
            return 1;
          end
        end
        6: begin
          if (actual == entries[i].msr) begin
            return 1;
          end
        end
      endcase
    end
    return 0;
  endfunction

  function void observe_read(wb_item it, int unsigned index);
    bit [7:0] actual;
    bit [4:0] causes;
    actual = byte_of(it);
    causes = 0;
    if (index == 6) begin
      // MSR mixes three different bug effects -- comparing the whole byte under one waiver would hide too much
      // Check levels with BUG-02, the other deltas with BUG-05 in loopback, and RI with BUG-03 or BUG-05
      // The five-bit cause masks use BUG-01 in bit 0 through BUG-05 in bit 4 -- alex
      compare_value("SCB_MSR_LEVELS",actual,expected.previous_regs[6],documented.previous_regs[6],
                    expected.mcr[4] ? 0 : 5'b00010,'hf0,permitted.previous_regs[6]);
      compare_value("SCB_MSR_DELTAS",actual,expected.previous_regs[6],documented.previous_regs[6],
                    expected.mcr[4] ? 5'b10000 : 0,'h0b,permitted.previous_regs[6]);
      compare_value("SCB_MSR_TERI",actual,expected.previous_regs[6],documented.previous_regs[6],
                    expected.mcr[4] ? 5'b10100 : 5'b00100,'h04,permitted.previous_regs[6]);
      status_checks++;
      return;
    end
`ifndef DATA_BUS_WIDTH_8
    // Handle full-word debug reads before extracting an ordinary register byte
    // Their four lanes contain different fields, so a byte-only comparison would miss most of the response -- alex
    if (it.sel == 15) begin
      if (it.adr == 8) begin
        compare_value("SCB_DEBUG1", it.data, expected.previous_debug1, documented.previous_debug1, 5'b10110, '1,permitted.previous_debug1);
      end else if (it.adr == 12) begin
        compare_value("SCB_DEBUG2", it.data, expected.previous_debug2, documented.previous_debug2, 0, '1);
      end else begin
        compare_value("SCB_DEBUG_DEFAULT", it.data, 0, 0, 0, '1);
      end
      return;
    end
    if (!(it.sel inside {1,2,4,8})) begin
      compare_value("SCB_ODD_SEL", it.data, 0, 0, 0, '1);
      return;
    end
`endif
    if ((index == 0) && !expected.lcr[7]) begin
      // An empty RBR has no specified payload -- count the read without inventing an expected byte -- alex
      if (expected.previous_empty) begin
        empty_reads++;
        return;
      end
      // AMB-12 excuses this out-of-tolerance payload, not its status or interrupt behavior -- alex
      if (expected.previous_uncertain) begin
        uncertain_reads++;
        return;
      end
      rx_compared++;
      // RX overflow may replace the oldest byte under BUG-04
      // The alternate model must predict that replacement -- an arbitrary wrong byte still fails -- alex
      causes = 5'b01000;
    end
    if (index inside {2,5,6}) begin
      status_checks++;
      if (status_matches(actual, index)) begin
        cfg.observed_checks++;
        return;
      end
      causes = (index == 5) ? 0 : (expected.mcr[4] ? 5'b10100 : 5'b00100);
      if ((|causes) && status_matches(actual, index, 2)) begin
        cfg.report_known_bug(causes & cfg.waiver_mask(), $sformatf("Status %0d matches only documented bugs at cycle %0d actual=%02h", index, cycle, actual));
        return;
      end
    end
    if (index < 8) begin
      compare_value("SCB_REGISTER", actual, expected.previous_regs[index], documented.previous_regs[index], causes, 'hff,permitted.previous_regs[index]);
    end else begin
      compare_value("SCB_UNMAPPED", actual, 0, 0, 0);
    end
  endfunction

  function void observe_tx(ser_item it);
    ser_item wanted;
    bit [7:0] mask;
    // A format change can make the monitor finish decoding later than the model notices the interruption
    // Use the frame start time here so that late publication cannot consume the next valid expected byte -- alex
    if (invalid_tx_range && (it.started_at >= invalid_tx_since) &&
        ((invalid_tx_until == 0) || (it.started_at <= invalid_tx_until))) begin
      if (!it.start_event) begin
        tx_aborted++;
      end
      return;
    end
    if (it.start_event || it.glitch_event) begin
      return;
    end
    if (it.unknown_seen) begin
      `uvm_error("SCB_SERIAL_UNKNOWN", "TX frame contains unknown samples")
    end
    if (tx_expected.size() == 0) begin
      if (!it.aborted) begin
        `uvm_error("SCB_TX_UNEXPECTED", "TX frame has no predicted transmitted character")
      end
      return;
    end
    wanted = tx_expected.pop_front();
    if (it.aborted || wanted.aborted) begin
      tx_aborted++;
      return;
    end
    // With WLS zero only five bits went over the wire -- ignore the three unused upper bits -- alex
    mask = 'hff >> (3 - int'(wanted.line_control[1:0]));
    compare_value("SCB_TX_DATA", it.data, wanted.data, wanted.data, 0, mask);
    if (it.parity_err || it.frame_err || it.break_err) begin
      `uvm_error("SCB_TX_FRAME", "DUT TX framing does not match the programmed format")
    end
    tx_compared++;
  endfunction

  function void check_modem(uart_irq_sample sample);
    bit [1:0] wanted;
    bit [1:0] actual;
    wanted = {~expected.mcr[1], ~expected.mcr[0]};
    actual = {sample.rts, sample.dtr};
    // A polarity bug can stay present for thousands of clocks without changing
    // Report it again only when the observed or expected pair changes, or after it first returns to normal -- alex
    if (actual != wanted) begin
      if (!modem_error_active || (actual != modem_bad_previous) || (wanted != modem_wanted_previous)) begin
        compare_value("SCB_MODEM_OUTPUT", actual, wanted, {expected.mcr[1], expected.mcr[0]}, 1, 3);
      end
    end else begin
      cfg.observed_checks++;
    end
    modem_error_active = (actual != wanted);
    modem_bad_previous = actual;
    modem_wanted_previous = wanted;
    // Loopback routes TX internally -- the external STX pin must stay idle
    // Outside loopback, transmit break instead requires that physical pin to stay low -- alex
    if (expected.mcr[4] && (sample.stx !== 1)) begin
      `uvm_error("SCB_LOOPBACK_TX", "STX must remain high during loopback")
    end else if (!expected.mcr[4] && expected.lcr[6] && (sample.stx !== 0)) begin
      `uvm_error("SCB_BREAK_TX", "TX break must hold STX low")
    end
  endfunction
  function void check_baud(uart_irq_sample sample);
`ifdef UART_HAS_BAUDRATE_OUTPUT
    if (baud_epoch != cfg.ser.epoch) begin
      baud_epoch = cfg.ser.epoch;
      baud_seen = 0;
      // Discard the interval across this update -- the two clock stages need to settle first -- alex
      baud_settle = cycle + 2;
    end
    if (cycle <= baud_settle) begin
      return;
    end
    if ($isunknown(sample.baud)) begin
      `uvm_error("SCB_BAUD_UNKNOWN", "baud_o contains X or Z")
    end
    if (expected.dl == 0) begin
      if (sample.baud !== 0) begin
        `uvm_error("SCB_BAUD_ZERO", "baud_o is active with DL zero")
      end
      return;
    end
    // A stuck-low baud output has no tick intervals to compare -- require the first tick as well -- alex
    if (!baud_seen && (cycle > baud_settle + expected.dl + 2)) begin
      `uvm_error("SCB_BAUD_START", "No initial baud_o tick arrived within the programmed period")
      baud_settle = cycle;
    end
    if (sample.baud === 1) begin
      if (baud_seen && ((cycle - baud_last) != expected.dl)) begin
        `uvm_error("SCB_BAUD_PERIOD", "baud_o period differs from DL")
      end
      baud_seen = 1;
      baud_last = cycle;
      baud_checks++;
    end else if (baud_seen && ((cycle - baud_last) >= expected.dl)) begin
      `uvm_error("SCB_BAUD_MISSING", "Expected baud_o tick is missing")
    end
`endif
  endfunction

  task run_phase(uvm_phase phase);
    wb_item access;
    wb_item extra;
    ser_item serial;
    modem_item modem;
    uart_irq_sample sample;
    int unsigned index;
    bit [7:0] value;
    bit tick;
    bit seen_irq;
    bit seen_known_irq;
    bit seen_permitted_irq;
    forever begin
      @(cfg.wb.vif.mon_cb);
      // The monitors wake on this same clocking event
      // Yield 1 ps so a FIFO that is still empty only because its monitor has not run is not mistaken for missing traffic -- alex
      #1ps;
      // Despite its name this input carries the full per-clock pin and bus sample
      // It is the timing reference here -- bus and serial transactions alone cannot describe clocks with no completed transfer -- alex
      while (irq_in.try_get(sample)) begin
        cycle = sample.cycle;
        if (sample.reset !== 0) begin
          if (!in_reset) begin
            resets++;
          end
          // Check completed predictions before flushing reset state
          // Reset may discard pending work, but must not erase evidence that an already finished character was never observed -- alex
          foreach (tx_expected[i]) begin
            if (tx_expected[i].completed && !tx_expected[i].aborted) begin
              `uvm_error("SCB_TX_MISSING_BEFORE_RESET", "A completed TX character had no monitor observation before reset")
            end
          end
          // Keep reset losses separate from the clear and overflow counts maintained by the model -- alex
          tx_fifo_reset_entries += expected.tx_count;
          rx_fifo_reset_entries += expected.rx_count;
          expected.reset_model();
          documented.reset_model();
          permitted.reset_model();
          tx_aborted += tx_expected.size();
          tx_expected.delete();
          active_tx = null;
          invalid_tx_range = 0;
          // Old status values must stop being acceptable after reset -- alex
          history.delete();
          known_history.delete();
          permitted_history.delete();
          wb_in.flush();
          tx_in.flush();
          rx_in.flush();
          baud_seen = 0;
          in_reset = 1;
          continue;
        end
        in_reset = 0;
        if ($isunknown({sample.wb_cyc,sample.wb_stb,sample.wb_we}) ||
            $isunknown({sample.irq,sample.srx,sample.stx,sample.rts,sample.dtr,sample.pins})) begin
          `uvm_error("SCB_PIN_UNKNOWN", "An active observed DUT pin contains X or Z")
        end
        access = null;
        index = 0;
        value = 0;
        if (wb_in.try_get(access)) begin
          wb_observed++;
          index = index_of(access);
          value = byte_of(access);
          // The item stores two-state data, so rely on the unknown flags captured by the monitor before conversion
          // Only the explicitly unspecified RBR payload cases may contain unknown data -- control fields never get that exception -- alex
          if (access.control_unknown || (access.data_unknown &&
              (access.we || (index != 0) || expected.lcr[7] ||
               (!expected.previous_empty && !expected.previous_uncertain)))) begin
            `uvm_error("SCB_BUS_UNKNOWN", "A defined acknowledged value contains X or Z")
          end
          if (!access.we) begin
            // Use the saved register snapshot before advancing this clock
            // The acknowledged read can clear status or pop RBR -- comparing afterward would compare against its own side effect -- alex
            observe_read(access, index);
          end
        end
        if (wb_in.try_get(extra)) begin
          `uvm_error("SCB_BUS_MULTIPLE", "More than one acknowledged access appeared in one clock")
        end
        // A character spanning two line settings cannot be checked as a complete frame in either format -- alex
        if (cfg.ser.epoch != old_epoch) begin
          if (active_tx != null) begin
            if (!active_tx.completed) begin
              active_tx.aborted = 1;
              invalid_tx_range = 1;
              invalid_tx_since = active_tx.started_at;
              invalid_tx_until = 0;
            end
          end
          old_epoch = cfg.ser.epoch;
        end
`ifdef UART_HAS_BAUDRATE_OUTPUT
        tick = sample.baud === 1;
`else
        tick = expected.baud_tick;
`endif
        // Check the sampled pins before step applies new register state -- otherwise valid old outputs look late -- alex
        check_modem(sample);
        check_baud(sample);
        expected.step(tick, sample.srx, sample.pins, access, index, value,
                      rx_timing_uncertain(),sample);
        documented.step(tick, sample.srx, sample.pins, access, index, value,
                        rx_timing_uncertain(),sample);
        permitted.step(tick, sample.srx, sample.pins, access, index, value,
                       rx_timing_uncertain(),sample);
        // Queue a TX expectation when the modeled serializer loads a byte, not for every THR write
        // A full FIFO write can replace pending data, so write order alone is no longer the transmitted order -- alex
        if (expected.loaded) begin
          active_tx = ser_item::type_id::create("predicted_tx");
          active_tx.data = expected.loaded_data;
          active_tx.started_at = $time;
          active_tx.line_control = expected.loaded_lcr;
          // Loopback and break have no normal external frame -- retain its timing without waiting for an STX byte -- alex
          active_tx.aborted = expected.mcr[4] || expected.lcr[6] ||
                              (cfg.ser.lcr[6:0] != expected.loaded_lcr[6:0]);
          tx_expected.push_back(active_tx);
        end
        while (tx_in.try_get(serial)) begin
          observe_tx(serial);
        end
        if (expected.frame_finished && (active_tx != null)) begin
          active_tx.completed = 1;
          if (active_tx.aborted && invalid_tx_range && (invalid_tx_until == 0)) begin
            invalid_tx_until = $time;
          end
        end
        if (expected.frame_finished && (active_tx != null)) begin
          // Remove this object by identity, not by popping the oldest entry
          // Its interrupted observation may already have consumed it -- do not accidentally remove the next character -- alex
          if (active_tx.aborted) begin
            foreach (tx_expected[i]) begin
              if (tx_expected[i] == active_tx) begin
                tx_expected.delete(i);
                tx_aborted++;
                break;
              end
            end
          end
        end
        // Seeing activity on SRX does not prove the DUT stored a byte -- the receiver model predicts RBR contents -- alex
        while (rx_in.try_get(serial)) begin
          if (!serial.start_event) begin
            rx_observed++;
          end
          if (serial.unknown_seen) begin
            `uvm_error("SCB_RX_UNKNOWN", "RX observation contains X or Z")
          end
        end
        while (modem_in.try_get(modem)) begin
          modem_events++;
          if (modem.unknown_seen) begin
            `uvm_error("SCB_MODEM_UNKNOWN", "Modem observation contains X or Z")
          end
        end
        save_history();
        seen_irq = 0;
        seen_known_irq = 0;
        seen_permitted_irq = 0;
        foreach (history[i]) begin
          seen_irq |= (sample.irq === history[i].irq);
        end
        foreach (known_history[i]) begin
          seen_known_irq |= (sample.irq === known_history[i].irq);
        end
        foreach (permitted_history[i]) begin
          seen_permitted_irq |= (sample.irq === permitted_history[i].irq);
        end
        irq_checks++;
        // Do not flood the log for one continuous IRQ mismatch -- rearm after IRQ matches the specification again -- alex
        if (!seen_irq && !irq_bad_previous) begin
          if (seen_permitted_irq) begin
            cfg.report_known_bug((expected.mcr[4] ? 5'b10100 : 5'b00100) & cfg.waiver_mask(), $sformatf("IRQ matches only documented bugs at cycle %0d", cycle));
          end else if (seen_known_irq) begin
            cfg.report_known_bug(expected.mcr[4] ? 5'b10100 : 5'b00100,
                                 $sformatf("Unwaived documented IRQ discrepancy at cycle %0d",cycle),1);
          end else begin
            `uvm_error("SCB_IRQ", "IRQ differs from the reference priority and pending model")
          end
        end
        irq_bad_previous = !seen_irq;
      end
    end
  endtask
  function void expect_totals(longint unsigned tx, longint unsigned rx);
    if ((cfg.ser.dl == 0) && (active_tx != null)) begin
      if (active_tx.aborted) begin
        // DL zero can suspend a character indefinitely -- report that outstanding character rather than call it compared -- alex
        foreach (tx_expected[i]) begin
          if (tx_expected[i] == active_tx) begin
            tx_expected.delete(i);
            tx_aborted++;
            break;
          end
        end
      end
    end
    // tx and rx are requested counts, not an expected delivered total after reset, clear or overflow
    // Completion means the sequence reached this point -- check_phase still rejects pending work and missing comparisons -- alex
    finished = 1;
  endfunction
  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    if (!finished) begin
      `uvm_error("SCB_INCOMPLETE", "The general sequence did not finish")
    end
    // Do not require irq_in to be empty -- the free-running sampler can publish one last clock as the phase ends
    // Actual bus transactions, frame observations and predicted characters must still have been consumed -- alex
    if ((wb_in.used() != 0) || (tx_in.used() != 0) || (rx_in.used() != 0) ||
        (modem_in.used() != 0) || (tx_expected.size() != 0)) begin
      `uvm_error("SCB_PENDING", "Observations or predicted frames remain at test completion")
    end
    if ((expected.rx_count != 0) || (expected.tx_count != 0) ||
        ((cfg.ser.dl != 0) && (expected.tx_state != 0))) begin
      `uvm_error("SCB_REFERENCE_PENDING", $sformatf("Reference storage did not drain -- TX=%0d RX=%0d TX state=%0d DL=%0d",
                 expected.tx_count,expected.rx_count,expected.tx_state,cfg.ser.dl))
    end
    // A disconnected or stalled monitor can otherwise make the log look quiet
    // Every completed driver request needs one observed ACK, and every request needs completion or reset cancellation -- alex
    if ((wb_observed != cfg.wb.completed_items) ||
        (cfg.wb.requested_items != cfg.wb.completed_items + cfg.wb.aborted_items)) begin
      `uvm_error("SCB_BUS_COUNTS", $sformatf("Driver requested=%0d completed=%0d aborted=%0d monitor observed=%0d",
                 cfg.wb.requested_items,cfg.wb.completed_items,cfg.wb.aborted_items,wb_observed))
    end
    // Even consistent zero traffic counts are not enough to declare verification successful -- alex
    if (cfg.observed_checks == 0) begin
      `uvm_error("SCB_NO_CHECKS", "No reference comparisons were performed")
    end
  endfunction
  function void report_phase(uvm_phase phase);
    string summary;
    super.report_phase(phase);
    summary = $sformatf("TX compared=%0d RX compared=%0d RX observed=%0d bus observed=%0d",
                        tx_compared,rx_compared,rx_observed,wb_observed);
    summary = {summary,$sformatf(" status checks=%0d IRQ checks=%0d baud checks=%0d resets=%0d",
                                status_checks,irq_checks,baud_checks,resets)};
    // Keep discarded or deliberately uncomparable traffic visible instead of including it in the compared totals -- alex
    summary = {summary,$sformatf(" TX aborted/suppressed=%0d empty reads=%0d out-of-tolerance reads=%0d",
                                tx_aborted,empty_reads,uncertain_reads)};
    summary = {summary,$sformatf(" modem events=%0d TX overflow/clear=%0d RX overflow/clear=%0d",
                                modem_events,expected.dropped_tx,expected.dropped_rx)};
    `uvm_info("SCB_SUMMARY",summary,UVM_LOW)
    `uvm_info("SCB_RESET_DISCARDS",$sformatf("TX FIFO entries cleared by reset=%0d RX FIFO entries cleared by reset=%0d",tx_fifo_reset_entries,rx_fifo_reset_entries),UVM_LOW)
    for (int i = 1; i <= 5; i++) begin
      `uvm_info("SCB_KNOWN_BUG_SUMMARY", $sformatf("BUG-%02d observed checks=%0d waived=%b", i, cfg.known_bug_count[i], cfg.waived[i]), UVM_LOW)
    end
  endfunction
endclass
