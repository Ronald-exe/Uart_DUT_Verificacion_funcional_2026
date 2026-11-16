class uart_base_test extends uvm_test;
  `uvm_component_utils(uart_base_test)
  uart_env_cfg cfg;
  uart_env env;

  function new(string name = "uart_base_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    cfg = uart_env_cfg::type_id::create("cfg");
    if (!uvm_config_db#(virtual wb_if)::get(this, "", "wb_vif", cfg.wb.vif))
      `uvm_fatal("UART_VIF", "No se encontro wb_vif")
    if (!uvm_config_db#(virtual uart_ser_if)::get(this, "", "ser_vif", cfg.ser.vif))
      `uvm_fatal("UART_VIF", "No se encontro ser_vif")
    if (!uvm_config_db#(virtual modem_if)::get(this, "", "mdm_vif", cfg.mdm_vif))
      `uvm_fatal("UART_VIF", "No se encontro mdm_vif")
    // Validate knobs before creating children -- otherwise some components may build with settings we later reject
    // Pass this test as the report context because cfg itself has no component path -- alex
    cfg.parse_plusargs(this);
    uvm_config_db#(uart_env_cfg)::set(this, "env", "cfg", cfg);
    env = uart_env::type_id::create("env", this);
  endfunction

  function void end_of_elaboration_phase(uvm_phase phase);
    uvm_reg registers[$];
    super.end_of_elaboration_phase(phase);
    env.regm.get_registers(registers);
    foreach (registers[i]) begin
      if ((registers[i] != env.regm.LCR) &&
          (registers[i] != env.regm.IER) &&
          (registers[i] != env.regm.SCR)) begin
        // The generic reset and bit-bash sequences cannot manage DLAB banking or FIFO/status side effects
        // Keep their E2 scope at LCR, IER and SCR -- NO_REG_TESTS applies to both sequences, not just reset -- alex
        uvm_resource_db#(bit)::set({"REG::", registers[i].get_full_name()},
                                  "NO_REG_TESTS", 1, this);
      end
    end
  endfunction

  task report_progress(uart_main_vseq seq);
    // Stay blocked when disabled -- returning here would win join_any and cancel the real test -- alex
    wait (cfg.progress_cycles != 0);
    forever begin
      repeat (cfg.progress_cycles) @(negedge cfg.wb.vif.clk);
      // Sample between active clock edges -- this task observes only and performs no bus or RAL access -- alex
      `uvm_info("UART_PROGRESS", $sformatf("time=%0t cycle=%0d iter=%0d/%0d stage=%s service=%s control=%s bus=%s done_tx_rx_control=%b%b%b stop=%b service_wait=%0d tail_wait=%0d modem_hold=%0d",
        $time, env.scb.cycle, seq.iteration, cfg.sw.n_iter, seq.stage,
        seq.service_stage, seq.control_stage, seq.bus_activity,
        seq.tx_done, seq.rx_done, seq.control_done, seq.workers_stop,
        seq.service_wait_left, seq.tail_wait_left, seq.modem_hold_cycles), UVM_LOW)
      `uvm_info("UART_PROGRESS_STATE", $sformatf("DL_observed=%0d DL_model=%0d source_DL=%0d LCR=%02h MCR=%02h source_active=%b WB_requested=%0d WB_completed=%0d WB_observed=%0d cyc_stb_ack=%b%b%b irq=%b FIFO_tx_rx=%0d/%0d state_tx_rx=%0d/%0d LSR_model=%02h LSR_drain=%02h TX_compared=%0d RX_compared=%0d",
        cfg.ser.dl, env.scb.expected.dl, cfg.ser.source_dl, cfg.ser.lcr, cfg.ser.mcr,
        cfg.ser.source_frame_active, cfg.wb.requested_items, cfg.wb.completed_items,
        env.scb.wb_observed, cfg.wb.vif.mon_cb.cyc, cfg.wb.vif.mon_cb.stb,
        cfg.wb.vif.mon_cb.ack, cfg.wb.vif.mon_cb.irq,
        env.scb.expected.tx_count, env.scb.expected.rx_count,
        env.scb.expected.tx_state, env.scb.expected.rx_state,
        env.scb.expected.lsr, seq.drain_lsr, env.scb.tx_compared, env.scb.rx_compared), UVM_LOW)
      // Flush periodic reports so file buffering does not look like a stopped simulation -- alex
      $fflush();
    end
  endtask

  task run_phase(uvm_phase phase);
    uart_main_vseq seq;
    bit completed;
    // Hold the phase while the sequence blocks on driver handshakes -- an idle moment on the pins is not test completion -- alex
    phase.raise_objection(this);
    seq = uart_main_vseq::type_id::create("main_sequence");
    completed = 0;
    fork
      begin
        seq.start(env.vseqr);
        completed = 1;
      end
      begin
        // The driver timeout only covers its own request -- this watchdog also catches a stuck RAL or sequence wait -- alex
        // The general budget exceeds 32 bits -- VCS truncated the previous repeat count -- alex
        // repeat (cfg.timeout_cycles) @(cfg.wb.vif.drv_cb);
        for (longint unsigned elapsed = 0; elapsed < cfg.timeout_cycles; elapsed++) begin
          @(cfg.wb.vif.drv_cb);
        end
        `uvm_fatal("UART_TIMEOUT", "La secuencia excedio su presupuesto de ciclos")
      end
      report_progress(seq);
    join_any
    disable fork;
    // Only a sequence that returned may mark the scoreboard finished
    // Leave three clocks for the last observations to arrive before dropping the phase objection -- alex
    if (completed) begin
      repeat (3) @(cfg.wb.vif.drv_cb);
      env.scb.expect_totals(seq.planned_tx, seq.planned_rx);
    end
    phase.drop_objection(this);
  endtask

  function void report_phase(uvm_phase phase);
    uvm_report_server reports;
    super.report_phase(phase);
    // Decide the final banner here, after check_phase can report missing observations
    // Finishing the stimulus sequence by itself is not a pass -- alex
    reports = uvm_report_server::get_server();
    if ((reports.get_severity_count(UVM_ERROR) != 0) ||
        (reports.get_severity_count(UVM_FATAL) != 0)) begin
      `uvm_info("UART_FAIL", "Errors were reported -- inspect the log", UVM_NONE)
    // A waived DUT discrepancy is still a discrepancy -- keep that distinction in the result consumed by the runner -- alex
    end else if (cfg.known_bug_checks != 0) begin
      `uvm_info("UART_PASS_WITH_KNOWN_BUGS", "Checks completed with documented waived DUT discrepancies -- inspect the bug summary", UVM_NONE)
    end else begin
      `uvm_info("UART_PASS", "Checks completed without discrepancies", UVM_NONE)
    end
  endfunction
endclass : uart_base_test
