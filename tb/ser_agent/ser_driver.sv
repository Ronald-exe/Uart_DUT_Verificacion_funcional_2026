class ser_driver extends uvm_driver #(ser_item);
  `uvm_component_utils(ser_driver)
  ser_agent_cfg cfg;
  function new(string name = "ser_driver", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(ser_agent_cfg)::get(this, "", "cfg", cfg)) begin
      `uvm_fatal("NOCFG", "Serial driver configuration is missing")
    end
    // Check both handles before driving -- reset cancellation needs the existing bus interface too -- alex
    if ((cfg.vif == null) || (cfg.reset_vif == null)) begin
      `uvm_fatal("SER_VIF", "Serial driver requires serial and reset interfaces")
    end
  endfunction
  // Use a wide cycle count so long gaps and slow-divisor break stimulus do not overflow the timing helper -- alex
  task put_bit(bit value, longint unsigned cycles);
    cfg.vif.drv_cb.srx <= value;
    repeat (cycles) @(cfg.vif.drv_cb);
  endtask
  task drive_char(ser_item it);
    int unsigned period_cycles;
    int unsigned stop_count;
    bit [7:0] control;
    bit parity;
    // The external sender keeps the format captured at frame start even if software reconfigures the DUT -- alex
    control = cfg.lcr;
    it.line_control = control;
    // Do not stop the external sender just because the DUT clock is stopped -- retain its last nonzero divisor for DL zero scenarios -- alex
    // int unsigned b = cfg.bit_cycles();
    // if (cfg.dl == 0) begin
    //   `uvm_warning("SER_DRV", "DL = 0: no se manda el caracter")
    //   return;
    // end
    it.divisor = (cfg.dl == 0) ? cfg.source_dl : cfg.dl;
    cfg.source_skew = it.baud_error_pct;
    it.started_at = $time;
    // Apply the requested signed baud offset to the source period -- keep this independent of the DUT divider -- alex
    period_cycles = (16 * int'(it.divisor) * (100 + it.baud_error_pct) + 50) / 100;
    if (period_cycles == 0) begin
      `uvm_fatal("SER_PERIOD", "Serial stimulus needs a nonzero source bit period")
    end
    cfg.source_period = period_cycles;
    cfg.source_frame_active = 0;
    put_bit(1, longint'(it.gap) * period_cycles);
    // Add explicit short-pulse and sustained-break paths -- normal framing alone cannot generate these scenarios -- alex
    if (it.inject_glitch) begin
      put_bit(0, it.glitch_cycles);
      put_bit(1, period_cycles);
    end
    cfg.source_frame_active = 1;
    if (it.inject_break) begin
      put_bit(0, longint'(14) * period_cycles);
      put_bit(1, 2 * period_cycles);
      return;
    end
    put_bit(0, period_cycles);
    parity = 0;
    // Use the captured format for all bits and allow the requested parity corruption after calculating the normal parity -- alex
    // for (int i = 0; i < cfg.n_bits(); i++)
    //   put_bit(it.data[i], b);
    // if (cfg.pen)
    //   put_bit(cfg.parity_bit(it.data), b);
    for (int i = 0; i < 5 + int'(control[1:0]); i++) begin
      put_bit(it.data[i], period_cycles);
      parity ^= it.data[i];
    end
    if (control[3]) begin
      case (control[5:4])
        0: parity = ~parity;
        1: parity = parity;
        2: parity = 1;
        3: parity = 0;
      endcase
      put_bit(parity ^ it.inject_parity_error, period_cycles);
    end
    stop_count = control[2] ? ((control[1:0] == 0) ? period_cycles * 3 / 2 : 2 * period_cycles) : period_cycles;
    // Select normal stop, bad first stop or bad second stop explicitly -- second-stop corruption only applies when that stop exists -- alex
    // put_bit(1'b1, cfg.stop_cycles());
    if (it.inject_stop2_error && control[2] && (control[1:0] != 0)) begin
      put_bit(1, period_cycles);
      put_bit(0, stop_count - period_cycles);
    end else begin
      put_bit(!it.inject_frame_error, stop_count);
    end
    // Recover high after a bad stop so the receiver can retire FE rather than turn it into a break -- alex
    put_bit(1, period_cycles);
  endtask
  task run_phase(uvm_phase phase);
    ser_item it;
    cfg.vif.drv_cb.srx <= 1;
    forever begin
      seq_item_port.get_next_item(it);
      it.aborted = 0;
      it.completed = 0;
      wait (cfg.reset_vif.rst === 0);
      @(cfg.vif.drv_cb);
      // Race the waveform against reset and cancel the losing branch -- item_done still releases the sequencer after an aborted frame -- alex
      fork
        begin
          drive_char(it);
          it.completed = 1;
        end
        begin
          wait (cfg.reset_vif.rst !== 0);
          it.aborted = 1;
        end
      join_any
      disable fork;
      cfg.vif.drv_cb.srx <= 1;
      cfg.source_skew = 0;
      cfg.source_frame_active = 0;
      it.finished_at = $time;
      seq_item_port.item_done();
    end
  endtask
endclass
