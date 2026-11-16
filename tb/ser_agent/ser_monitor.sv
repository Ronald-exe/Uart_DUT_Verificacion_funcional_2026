class ser_monitor extends uvm_monitor;
  `uvm_component_utils(ser_monitor)
  ser_agent_cfg cfg;
  uvm_analysis_port #(ser_item) ap;
  bit is_tx = 1;
  function new(string name = "ser_monitor", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    if (!uvm_config_db#(ser_agent_cfg)::get(this, "", "cfg", cfg)) begin
      `uvm_fatal("NOCFG", "Serial monitor configuration is missing")
    end
    // Require serial and reset handles before observing -- an absent interface should fail before traffic starts -- alex
    if ((cfg.vif == null) || (cfg.reset_vif == null)) begin
      `uvm_fatal("SER_VIF", "Serial monitor requires serial and reset interfaces")
    end
  endfunction
  // Keep four-state samples until unknown detection is recorded rather than hiding X in a bit return -- alex
  // function bit line();
  function logic line();
    return is_tx ? cfg.vif.mon_cb.stx : cfg.vif.mon_cb.srx;
  endfunction
  task wait_cycles(int unsigned count);
    repeat (count) @(cfg.vif.mon_cb);
  endtask
  // Decode with the format captured at the start edge -- keep observed parity and stop checks here and pass the results to the scoreboard -- alex
  // b = cfg.bit_cycles();
  // for (int i = 0; i < cfg.n_bits(); i++) begin
  //   wait_cycles(b);
  //   it.data[i] = line();
  // end
  // if (cfg.pen) begin
  //   wait_cycles(b);
  //   p = line();
  //   it.parity_err = (p != cfg.parity_bit(it.data));
  // end
  // wait_cycles(b);
  // it.frame_err = (line() == 1'b0);
  task decode(ser_item it);
    int unsigned period_cycles;
    int unsigned low_cycles;
    bit parity;
    logic sample;
    bit [7:0] control;
    control = it.line_control;
    period_cycles = 16 * int'(it.divisor);
    wait_cycles(period_cycles / 2);
    // Publish an observed short start pulse rather than silently dropping it -- this remains an observation, not a scoreboard verdict -- alex
    // if (line() !== 1'b0) continue;
    if (line() !== 0) begin
      it.glitch_event = 1;
      it.unknown_seen = $isunknown(line());
      return;
    end
    parity = 0;
    for (int i = 0; i < 5 + int'(control[1:0]); i++) begin
      wait_cycles(period_cycles);
      sample = line();
      it.unknown_seen |= $isunknown(sample);
      it.data[i] = sample;
      parity ^= sample;
    end
    if (control[3]) begin
      case (control[5:4])
        0: parity = ~parity;
        1: parity = parity;
        2: parity = 1;
        3: parity = 0;
      endcase
      wait_cycles(period_cycles);
      sample = line();
      it.unknown_seen |= $isunknown(sample);
      it.parity_err = (sample !== parity);
    end
    wait_cycles(period_cycles);
    sample = line();
    it.unknown_seen |= $isunknown(sample);
    it.frame_err = (sample !== 1);
    if (it.frame_err) begin
      // A bad stop is not automatically a break -- observe whether the line stays low long enough -- alex
      low_cycles = 0;
      while ((line() === 0) && (low_cycles < 2 * period_cycles)) begin
        wait_cycles(1);
        low_cycles++;
      end
      it.break_err = (it.data == 0) && (low_cycles >= period_cycles);
      if (it.break_err) begin
        it.parity_err = 0;
        it.frame_err = 0;
      end
    end
  endtask
  task run_phase(uvm_phase phase);
    ser_item it;
    ser_item start;
    logic previous;
    int unsigned epoch;
    previous = 1;
    forever begin
      @(cfg.vif.mon_cb);
      if ((cfg.reset_vif.rst !== 0) || (cfg.dl == 0) ||
          (is_tx && (cfg.mcr[4] || cfg.lcr[6]))) begin
        previous = 1;
        continue;
      end
      if ($isunknown(line())) begin
        `uvm_error("SER_UNKNOWN", "An active serial line contains X or Z")
      end
      // Require a falling edge and publish its timestamp -- a low line by itself can be the middle of an existing frame -- alex
      // if (line() !== 1'b0 || cfg.dl == 0) continue;
      if ((previous === 1) && (line() === 0)) begin
        it = ser_item::type_id::create("observed_frame");
        it.is_tx = is_tx;
        it.line_control = cfg.lcr;
        it.divisor = cfg.dl;
        it.started_at = $time;
        it.baud_error_pct = is_tx ? 0 : cfg.source_skew;
        epoch = cfg.epoch;
        start = ser_item::type_id::create("observed_start");
        start.start_event = 1;
        start.is_tx = is_tx;
        start.line_control = it.line_control;
        start.divisor = it.divisor;
        start.started_at = it.started_at;
        ap.write(start);
        // Stop decoding on reset or a new framing epoch and publish an aborted observation -- partial bytes must not look complete -- alex
        fork
          decode(it);
          begin
            wait ((cfg.reset_vif.rst !== 0) || (cfg.epoch != epoch));
            it.aborted = 1;
          end
        join_any
        disable fork;
        it.finished_at = $time;
        it.completed = !it.aborted;
        ap.write(it);
        // A long low condition produces one break observation rather than repeated fake starts -- alex
        while ((line() !== 1) && (cfg.reset_vif.rst === 0)) begin
          @(cfg.vif.mon_cb);
        end
      end
      previous = line();
    end
  endtask
endclass
