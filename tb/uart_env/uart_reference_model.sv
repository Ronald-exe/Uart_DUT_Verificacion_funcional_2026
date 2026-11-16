class uart_reference_model extends uvm_object;
  `uvm_object_utils(uart_reference_model)
  // Bits 0 through 4 select BUG-01 through BUG-05 -- zero keeps the specification behavior
  // The scoreboard runs separate instances so a permitted bug cannot alter the strict expectation -- alex
  bit [4:0] bugs;
  bit [7:0] lcr = 3;
  bit [4:0] mcr;
  bit [3:0] ier;
  bit [1:0] fcr = 3;
  bit [15:0] dl;
  bit [7:0] scratch;
  // These memories are predicted from bus writes and sampled serial input -- never copied from DUT storage -- alex
  bit [7:0] tx_mem[16];
  bit [7:0] rx_mem[16];
  bit [2:0] rx_flags[16];
  // Keep baud uncertainty with the stored byte -- software may read it long after source timing returns to normal -- alex
  bit rx_uncertain[16];
  int unsigned tx_top, tx_bottom, tx_count;
  int unsigned rx_top, rx_bottom, rx_count;
  int unsigned tx_state, tx_counter, tx_bits;
  bit [7:0] tx_shift;
  bit tx_parity, tx_pin = 1;
  bit tx_pop;
  int unsigned rx_state, rx_counter, rx_bits;
  bit [7:0] rx_shift;
  bit rx_parity, rx_parity_error, rx_frame_error;
  bit rx_push, rx_push_q;
  bit [7:0] rx_pending_data;
  bit [2:0] rx_pending_flags;
  bit rx_pending_uncertain;
  bit rx_sync1 = 1, rx_sync2 = 1;
  int unsigned low_counter = 159;
  int unsigned timeout_counter = 639;
  int unsigned block_counter;
  bit rx_reset, tx_reset;
  bit overrun;
  bit [7:0] lsr = 8'h60;
  bit [7:0] raw_lsr_delayed;
  bit [7:0] msr;
  bit [3:0] modem_delayed;
  bit modem_clear = 1;
  bit [4:0] pending, irq_delayed;
  bit [7:0] iir = 8'hc1;
  bit irq;
  bit [7:0] previous_regs[8];
  bit previous_empty = 1;
  bit previous_uncertain;
  bit [31:0] previous_debug1, previous_debug2;
  longint unsigned accepted_tx, accepted_rx, dropped_tx, dropped_rx;
  longint unsigned read_rx, completed_tx;
  bit loaded;
  bit [7:0] loaded_data;
  bit [7:0] loaded_lcr;
  bit frame_finished;
  bit wb_cyc_reg, wb_stb_reg, wb_we_reg;
  bit [4:0] wb_adr_reg;
  bit [3:0] wb_sel_reg;
  bit [31:0] wb_data_reg;
  int unsigned wb_state;
  bit wb_enable = 1;
  bit fifo_tx_push, fifo_rx_pop;
  bit [7:0] fifo_tx_data;
  bit start_divisor;
  int unsigned divider_count;
  bit baud_tick;

  function new(string name = "uart_reference_model");
    super.new(name);
  endfunction

  function void reset_model();
    bit [4:0] saved_bugs;
    // Reset must not turn a permitted-bug instance back into the strict model
    // The cumulative traffic counters also survive -- clearing hardware state must not erase run accounting -- alex
    saved_bugs = bugs;
    lcr = 3;
    mcr = 0;
    ier = 0;
    fcr = 3;
    dl = 0;
    scratch = 0;
    tx_top = 0;
    tx_bottom = 0;
    tx_count = 0;
    rx_top = 0;
    rx_bottom = 0;
    rx_count = 0;
    tx_state = 0;
    tx_counter = 0;
    tx_bits = 0;
    tx_shift = 0;
    tx_parity = 0;
    tx_pin = 1;
    tx_pop = 0;
    rx_state = 0;
    rx_counter = 0;
    rx_bits = 0;
    rx_shift = 0;
    rx_parity = 0;
    rx_parity_error = 0;
    rx_frame_error = 0;
    rx_push = 0;
    rx_push_q = 0;
    rx_pending_data = 0;
    rx_pending_flags = 0;
    rx_pending_uncertain = 0;
    rx_sync1 = 1;
    rx_sync2 = 1;
    low_counter = 159;
    timeout_counter = 639;
    block_counter = 0;
    rx_reset = 0;
    tx_reset = 0;
    overrun = 0;
    lsr = 'h60;
    raw_lsr_delayed = 'h60;
    msr = 0;
    modem_delayed = 0;
    modem_clear = 1;
    pending = 0;
    irq_delayed = 0;
    iir = 'hc1;
    irq = 0;
    previous_empty = 1;
    previous_uncertain = 0;
    loaded = 0;
    frame_finished = 0;
    foreach (rx_flags[i]) begin
      rx_flags[i] = 0;
      rx_uncertain[i] = 0;
    end
    wb_cyc_reg = 0;
    wb_stb_reg = 0;
    wb_we_reg = 0;
    wb_adr_reg = 0;
    wb_sel_reg = 0;
    wb_data_reg = 0;
    wb_state = 0;
    wb_enable = 1;
    fifo_tx_push = 0;
    fifo_rx_pop = 0;
    fifo_tx_data = 0;
    start_divisor = 0;
    divider_count = 0;
    baud_tick = 0;
    bugs = saved_bugs;
  endfunction

  function int unsigned character_ticks(bit [7:0] control);
    int unsigned half_bits;
    // Count half-bits to represent the 5-data-bit extended stop exactly -- it lasts one and a half bits -- alex
    half_bits = 2 * (1 + 5 + int'(control[1:0]) + int'(control[3]));
    half_bits += !control[2] ? 2 : ((control[1:0] == 0) ? 3 : 4);
    return half_bits * 8;
  endfunction

  function bit [7:0] register_value(int unsigned index);
    case (index)
      0: return lcr[7] ? dl[7:0] : rx_mem[rx_bottom];
      1: return lcr[7] ? dl[15:8] : {4'b0, ier};
      2: return iir;
      3: return lcr;
      4: return 0;
      5: return lsr;
      6: return msr;
      7: return scratch;
      default: return 0;
    endcase
  endfunction

  function void step_transmitter(bit tick);
    bit parity;
    // loaded and frame_finished are one-clock events -- leaving them set between baud ticks would queue the same TX byte repeatedly -- alex
    loaded = 0;
    frame_finished = 0;
    if (!tick) begin
      tx_pop = 0;
      return;
    end
    // Separate FIFO load from start-bit timing so the byte and its pop occur in the right clock order
    // The states are 0 idle, 5 load, 1 start, 2 data, 3 parity and 4 stop -- alex
    case (tx_state)
      0: begin
        tx_pin = 1;
        if (tx_count != 0) begin
          tx_pop = 0;
          tx_state = 5;
        end
      end
      5: begin
        tx_shift = tx_mem[tx_bottom];
        tx_bits = 4 + int'(lcr[1:0]);
        parity = 0;
        for (int i = 0; i < 5 + int'(lcr[1:0]); i++) begin
          parity ^= tx_shift[i];
        end
        tx_parity = parity;
        tx_pop = 1;
        tx_state = 1;
        loaded = 1;
        loaded_data = tx_shift;
        loaded_lcr = lcr;
      end
      1: begin
        tx_pop = 0;
        tx_pin = 0;
        if (tx_counter == 0) begin
          tx_counter = 15;
        end else if (tx_counter == 1) begin
          tx_counter = 0;
          tx_state = 2;
        end else begin
          tx_counter--;
        end
      end
      2: begin
        tx_pin = tx_shift[0];
        if (tx_counter == 0) begin
          tx_counter = 15;
        end else if (tx_counter == 1) begin
          tx_counter = 0;
          if (tx_bits != 0) begin
            tx_bits--;
            tx_shift >>= 1;
          end else if (!lcr[3]) begin
            tx_state = 4;
          end else begin
            case (lcr[5:4])
              0: tx_shift[0] = ~tx_parity;
              1: tx_shift[0] = tx_parity;
              2: tx_shift[0] = 1;
              3: tx_shift[0] = 0;
            endcase
            tx_state = 3;
          end
        end else begin
          tx_counter--;
        end
      end
      3: begin
        tx_pin = tx_shift[0];
        if (tx_counter == 0) begin
          tx_counter = 15;
        end else if (tx_counter == 1) begin
          tx_counter = 0;
          tx_state = 4;
        end else begin
          tx_counter--;
        end
      end
      4: begin
        tx_pin = 1;
        if (tx_counter == 0) begin
          // The transition clocks contribute to the stop interval too
          // Reloading a full 16, 24 or 32 here would stretch the stop beyond the selected duration -- alex
          tx_counter = !lcr[2] ? 13 : ((lcr[1:0] == 0) ? 21 : 29);
        end else if (tx_counter == 1) begin
          tx_counter = 0;
          tx_state = 0;
          frame_finished = 1;
          completed_tx++;
        end else begin
          tx_counter--;
        end
      end
    endcase
  endfunction

  function void step_receiver(bit tick, logic serial, bit uncertain);
    bit break_detected;
    int unsigned old_counter;
    break_detected = (low_counter == 0);
    // All decisions in this call use the pre-clock counter value -- assignments below must not move a sample one tick earlier -- alex
    old_counter = rx_counter;
    if (rx_state != 0) begin
      // A brief out-of-tolerance interval anywhere in the frame affects this byte, even if timing recovers before its stop bit -- alex
      rx_pending_uncertain |= uncertain;
    end
    // A low stop bit is not enough to call a break -- require a continuous low interval spanning a whole character -- alex
    if (serial === 1) begin
      low_counter = character_ticks(lcr) - 1;
    end else if (tick && (low_counter != 0)) begin
      low_counter--;
    end
    if (!tick) begin
      return;
    end
    // Count down on the 16x tick -- counter 7 samples the middle and counter 0 advances to the next bit
    // Read the live LCR here so reconfiguration changes reception instead of inventing a perfectly decoded old-format byte -- alex
    case (rx_state)
      0: begin
        rx_push = 0;
        rx_counter = 14;
        if ((serial === 0) && !break_detected) begin
          rx_state = 1;
          rx_pending_uncertain = uncertain;
        end
      end
      1: begin
        rx_push = 0;
        if (old_counter == 7) begin
          rx_state = (serial === 1) ? 0 : 6;
        end
        rx_counter = (old_counter - 1) & 15;
      end
      6: begin
        rx_bits = 4 + int'(lcr[1:0]);
        if (old_counter == 0) begin
          rx_state = 2;
          rx_shift = 0;
        end
        rx_counter = (old_counter - 1) & 15;
      end
      2: begin
        if (old_counter == 7) begin
          case (lcr[1:0])
            0: rx_shift[4:0] = {serial, rx_shift[4:1]};
            1: rx_shift[5:0] = {serial, rx_shift[5:1]};
            2: rx_shift[6:0] = {serial, rx_shift[6:1]};
            3: rx_shift = {serial, rx_shift[7:1]};
          endcase
        end
        if (old_counter == 0) begin
          rx_state = 7;
        end
        rx_counter = (old_counter - 1) & 15;
      end
      7: begin
        if (rx_bits == 0) begin
          rx_state = lcr[3] ? 3 : 4;
          if (!lcr[3]) begin
            rx_parity_error = 0;
          end
        end else begin
          rx_bits--;
          rx_state = 2;
        end
        rx_counter = 14;
      end
      3: begin
        if (old_counter == 7) begin
          rx_parity = serial;
          rx_state = 8;
        end
        rx_counter = (old_counter - 1) & 15;
      end
      8: begin
        rx_counter = (old_counter - 1) & 15;
        rx_state = 5;
      end
      5: begin
        case (lcr[5:4])
          0: rx_parity_error = !(^{rx_shift, rx_parity});
          1: rx_parity_error = ^{rx_shift, rx_parity};
          2: rx_parity_error = !rx_parity;
          3: rx_parity_error = rx_parity;
        endcase
        rx_counter = (old_counter - 1) & 15;
        rx_state = 9;
      end
      9: begin
        if (old_counter == 0) begin
          rx_state = 4;
          rx_counter = 14;
        end else begin
          rx_counter = (old_counter - 1) & 15;
        end
      end
      4: begin
        if (old_counter == 7) begin
          rx_frame_error = (serial !== 1);
          rx_state = 10;
        end
        rx_counter = (old_counter - 1) & 15;
      end
      10: begin
        if ((serial === 1) || break_detected || !rx_frame_error) begin
          rx_pending_data = break_detected ? 0 : rx_shift;
          // Store BI, PE and FE with the byte -- a detected break reports BI on zero data instead of independent parity and framing errors -- alex
          rx_pending_flags = break_detected ? 3'b100 : {1'b0, rx_parity_error, rx_frame_error};
          rx_push = 1;
          rx_state = ((serial !== 1) && !break_detected) ? 1 : 0;
          if (rx_state == 1) begin
            rx_counter = 14;
          end
        end
      end
    endcase
  endfunction

  function void step(bit tick, logic external_rx, bit [3:0] pins,
                     wb_item access, int unsigned index, bit [7:0] data, bit uncertain, uart_irq_sample bus = null);
    bit wr, rd, fifo_wr, fifo_rd, ls_read, ii_read, ms_read;
    bit pop_tx, push_rx, push_tx, pop_rx;
    bit [7:0] tx_wire_data;
    bit old_rx_reset, old_tx_reset;
    bit [7:0] raw_lsr;
    bit any_error;
    bit [4:0] sources;
    bit [4:0] rises;
    bit [4:0] old_pending;
    bit [3:0] effective_pins;
    bit [3:0] changes;
    bit [3:0] old_modem;
    bit [7:0] old_lsr;
    bit [7:0] old_iir;
    logic serial;
    int unsigned tx_before;
    int unsigned rx_before;
    // Acknowledgement follows the register strobe -- model that pipeline instead of moving side effects to ACK -- alex
    if (bus != null) begin
      wr = wb_cyc_reg && wb_stb_reg && wb_we_reg && wb_enable;
      rd = wb_cyc_reg && wb_stb_reg && !wb_we_reg && wb_enable;
`ifdef DATA_BUS_WIDTH_8
      index = wb_adr_reg;
      data = wb_data_reg[7:0];
`else
      case (wb_sel_reg)
        8: begin index = int'({wb_adr_reg[4:2],2'b00}); data = wb_data_reg[31:24]; end
        4: begin index = int'({wb_adr_reg[4:2],2'b01}); data = wb_data_reg[23:16]; end
        2: begin index = int'({wb_adr_reg[4:2],2'b10}); data = wb_data_reg[15:8]; end
        1: begin index = int'({wb_adr_reg[4:2],2'b11}); data = wb_data_reg[7:0]; end
        default: begin index = int'({wb_adr_reg[4:2],2'b00}); data = wb_data_reg[7:0]; end
      endcase
`endif
    end else begin
      // Standalone FIFO tests can supply a direct accepted operation without a physical bus pipeline
      wr = 0;
      rd = 0;
      if (access != null) begin
        wr = access.we;
        rd = !access.we;
      end
    end
    fifo_wr = wr && (index == 0) && !lcr[7];
    fifo_rd = rd && (index == 0) && !lcr[7];
    ls_read = rd && (index == 5) && !lcr[7];
    ii_read = rd && (index == 2) && !lcr[7];
    ms_read = rd && (index == 6) && !lcr[7];
    push_tx = (bus == null) ? fifo_wr : fifo_tx_push;
    pop_rx = (bus == null) ? fifo_rd : fifo_rx_pop;
    tx_wire_data = (bus == null) ? data : fifo_tx_data;
    pop_tx = tx_pop;
    // rx_push can stay high until the receiver changes state -- only its rising edge may enqueue one character -- alex
    push_rx = rx_push && !rx_push_q;
    rx_push_q = rx_push;
    tx_before = tx_count;
    rx_before = rx_count;
    old_rx_reset = rx_reset;
    old_tx_reset = tx_reset;
    old_lsr = lsr;
    old_iir = iir;
    old_pending = pending;
    old_modem = msr[3:0];

    // Save read values before applying FIFO pops or read-to-clear effects
    // The bus response must describe the value that caused the side effect, not the state left afterward -- alex
    foreach (previous_regs[i]) begin
      previous_regs[i] = register_value(i);
    end
    previous_empty = (rx_count == 0);
    previous_uncertain = (rx_count != 0) && rx_uncertain[rx_bottom];
    previous_debug1 = {msr, lcr, iir[3:0], ier, lsr};
    previous_debug2 = {8'b0, fcr, mcr, 5'(rx_count), 4'(rx_state), 5'(tx_count), 3'(tx_state)};

    // Only active FIFO entries contribute error flags -- stale bits in a slot that has been popped are not pending receive errors -- alex
    any_error = overrun;
    for (int i = 0; i < rx_count; i++) begin
      any_error |= |rx_flags[(rx_bottom+i)%16];
    end
    raw_lsr = {any_error, (tx_count == 0) && (block_counter == 0) && (tx_state == 0),
               (tx_count == 0) && (block_counter == 0), rx_flags[rx_bottom][2],
               rx_flags[rx_bottom][0], rx_flags[rx_bottom][1], overrun, (rx_count != 0)};
    lsr[0] = old_rx_reset ? 0 : (rx_count != 0);
    // These LSR bits latch new error edges and clear on a status read
    // Keeping the delayed raw flags avoids immediately relatching an old condition on the very next clock -- alex
    lsr[4:1] = ls_read ? 0 : (lsr[4:1] | (raw_lsr[4:1] & ~raw_lsr_delayed[4:1]));
    lsr[5] = fifo_wr ? 0 : (lsr[5] | (raw_lsr[5] && !raw_lsr_delayed[5]));
    lsr[6] = fifo_wr ? 0 : (lsr[6] | (raw_lsr[6] && !raw_lsr_delayed[6]));
    lsr[7] = ls_read ? 0 : (lsr[7] | (raw_lsr[7] && !raw_lsr_delayed[7]));
    raw_lsr_delayed = raw_lsr;

    // A pending interrupt has its own acknowledgement rule -- reading LSR, IIR, RBR or MSR does not clear every source
    // Keep the previous pending state for this clock before choosing the new IRQ and IIR values -- alex
    sources[0] = ier[2] && (|old_lsr[4:1]);
    sources[1] = ier[0] && (rx_count >= (fcr == 0 ? 1 : (fcr == 1 ? 4 : (fcr == 2 ? 8 : 14))));
    sources[2] = ier[0] && (timeout_counter == 0) && (rx_count != 0);
    sources[3] = ier[1] && old_lsr[5];
    sources[4] = ier[3] && (|old_modem);
    rises = sources & ~irq_delayed;
    irq_delayed = sources;
    pending[0] = ls_read ? 0 : (rises[0] || (pending[0] && ier[2]));
    pending[1] = ((rx_count == (fcr == 0 ? 1 : (fcr == 1 ? 4 : (fcr == 2 ? 8 : 14)))) && fifo_rd) ? 0 : (rises[1] || (pending[1] && ier[0]));
    pending[2] = fifo_rd ? 0 : (rises[2] || (pending[2] && ier[0]));
    pending[3] = (fifo_wr || (ii_read && (old_iir[3:0] == 2))) ? 0 : (rises[3] || (pending[3] && ier[1]));
    pending[4] = ms_read ? 0 : (rises[4] || (pending[4] && ier[3]));
    irq = old_pending[0] ? !ls_read : old_pending[1] ? 1 : old_pending[2] ? !fifo_rd :
          old_pending[3] ? !(fifo_wr && ii_read) : old_pending[4] ? !ms_read : 0;
    iir = old_pending[0] ? 'hc6 : sources[1] ? 'hc4 : old_pending[2] ? 'hcc :
          old_pending[3] ? 'hc2 : old_pending[4] ? 'hc0 : 'hc1;

    // External modem inputs are active-low, while loopback uses internal MCR levels
    // BUG-02 changes the external level polarity -- BUG-05 changes where delta events come from -- alex
    effective_pins = mcr[4] ? {mcr[3], mcr[2], mcr[0], mcr[1]} : ~pins;
    if (bugs[1] && !mcr[4]) begin
      effective_pins = pins;
    end
    changes = (mcr[4] && !bugs[4]) ? (effective_pins ^ modem_delayed) : ((~pins) ^ modem_delayed);
    if (!bugs[2]) begin
      // The specified RI event is a physical rising edge -- its active-low MSR level falls -- alex
      changes[2] = modem_delayed[2] && !(mcr[4] ? effective_pins[2] : ~pins[2]);
    end
    msr = {effective_pins, modem_clear ? 4'b0 : (old_modem | changes)};
    modem_delayed = (mcr[4] && !bugs[4]) ? effective_pins : ~pins;
    modem_clear = modem_clear ? 0 : ms_read;

    // Receive timeout needs pending data and no FIFO activity for four character times -- a read or new byte restarts it -- alex
    if (push_rx || pop_rx || (rx_count == 0)) begin
      timeout_counter = 4 * character_ticks(lcr) - 1;
    end else if (tick && (timeout_counter != 0)) begin
      timeout_counter--;
    end
    // A first THR write clears the empty indications before the serializer reacts
    // Hold the empty detection off through the character interval instead of immediately declaring the still-empty FIFO ready -- alex
    if (old_lsr[5] && fifo_wr) begin
      block_counter = character_ticks(lcr) - 17;
    end else if (tick && (block_counter != 0)) begin
      block_counter--;
    end

    // Loopback receives the predicted transmitter waveform -- external SRX is still observed but isolated -- alex
    serial = mcr[4] ? (lcr[6] ? 0 : tx_pin) : rx_sync2;
    // External SRX passes through the input synchronizer -- internal loopback above bypasses those two clock stages -- alex
    rx_sync2 = rx_sync1;
    rx_sync1 = external_rx;
    step_receiver(tick, serial, uncertain);
    step_transmitter(tick);

    // FIFO clear is a stored pulse from the previous register clock -- apply that pulse before handling this clock traffic -- alex
    if (old_tx_reset) begin
      dropped_tx += longint'(tx_count);
      tx_top = 0;
      tx_bottom = 0;
      tx_count = 0;
    end else begin
      if (push_tx) begin
        // This write intentionally happens even when TX is full -- AMB-09 overwrites the next byte without increasing the count -- alex
        tx_mem[tx_top] = tx_wire_data;
        accepted_tx++;
      end
      case ({push_tx, pop_tx})
        2'b00: begin
          // No transfer leaves the FIFO pointers and count unchanged
        end
        2'b10: if (tx_before < 16) begin
          tx_top = (tx_top + 1) % 16;
          tx_count++;
        end else begin
          dropped_tx++;
        end
        2'b01: if (tx_before != 0) begin
          tx_bottom = (tx_bottom + 1) % 16;
          tx_count--;
        end
        // A simultaneous push and pop advances both ends while leaving occupancy unchanged -- alex
        2'b11: begin
          tx_top = (tx_top + 1) % 16;
          tx_bottom = (tx_bottom + 1) % 16;
        end
      endcase
    end
    if (old_rx_reset) begin
      dropped_rx += longint'(rx_count);
      rx_top = 0;
      rx_bottom = 0;
      rx_count = 0;
      overrun = 0;
      foreach (rx_flags[i]) begin
        rx_flags[i] = 0;
      end
    end else begin
      if (ls_read) begin
        overrun = 0;
      end else if (push_rx && !pop_rx && (rx_before == 16)) begin
        overrun = 1;
      end
      if (push_rx) begin
        accepted_rx++;
        // A full RX FIFO normally rejects new data -- BUG-04 still replaces its oldest payload
        // Keep that replacement separate from the flags below, which do not get overwritten by the same full-FIFO event -- alex
        if ((rx_before < 16) || pop_rx || bugs[3]) begin
          rx_mem[rx_top] = rx_pending_data;
          rx_uncertain[rx_top] = rx_pending_uncertain;
        end
      end
      case ({push_rx, pop_rx})
        2'b00: begin
          // No transfer leaves the FIFO pointers and count unchanged
        end
        2'b10: if (rx_before < 16) begin
          rx_flags[rx_top] = rx_pending_flags;
          rx_top = (rx_top + 1) % 16;
          rx_count++;
        end else begin
          dropped_rx++;
        end
        2'b01: if (rx_before != 0) begin
          rx_flags[rx_bottom] = 0;
          rx_bottom = (rx_bottom + 1) % 16;
          rx_count--;
          read_rx++;
        end
        2'b11: begin
          rx_flags[rx_top] = rx_pending_flags;
          rx_top = (rx_top + 1) % 16;
          rx_bottom = (rx_bottom + 1) % 16;
          read_rx++;
        end
      endcase
    end
    // DR follows actual storage occupancy -- an empty read cannot invent a received character -- alex
    lsr[0] = (rx_count != 0);
    // This divider supplies timing when baud_o is not compiled in -- it cannot by itself prove the DUT divider is correct -- alex
    baud_tick = (dl != 0) && (divider_count == 0);
    if (start_divisor || (divider_count == 0)) begin
      divider_count = (int'(dl)-1) & 'hffff;
    end else begin
      divider_count--;
    end
    start_divisor = wr && (index == 0) && lcr[7];
    fifo_tx_push = fifo_wr;
    fifo_tx_data = data;
    fifo_rx_pop = fifo_rd;
    rx_reset = wr && (index == 2) && data[1];
    tx_reset = wr && (index == 2) && data[2];
    // Apply register writes last so work already sampled on this clock uses the old configuration -- alex
    if (wr) begin
      case (index)
        0: if (lcr[7]) begin
          dl[7:0] = data;
        end
        1: if (lcr[7]) begin
          dl[15:8] = data;
        end else begin
          ier = data[3:0];
        end
        2: fcr = data[7:6];
        3: lcr = data;
        4: mcr = data[4:0];
        7: scratch = data;
      endcase
    end

    if (bus != null) begin
      // A held CYC and STB must not repeat the register strobe while ACK is moving through the bus pipeline
      // Track that front-end delay rather than performing every side effect again on each sampled high clock -- alex
      case (wb_state)
        0: if (wb_cyc_reg && wb_stb_reg) begin
          wb_enable = 0;
          wb_state = 1;
        end else begin
          wb_enable = 1;
        end
        1: begin
          wb_enable = 0;
          wb_state = 2;
        end
        default: begin
          wb_enable = 0;
          wb_state = 0;
        end
      endcase
      wb_cyc_reg = bus.wb_cyc;
      wb_stb_reg = bus.wb_stb;
      wb_we_reg = bus.wb_we;
      wb_adr_reg = bus.wb_adr;
      wb_sel_reg = bus.wb_sel;
      wb_data_reg = bus.wb_data;
    end
  endfunction
endclass
