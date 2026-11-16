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
        repeat (cfg.timeout_cycles) @(cfg.wb.vif.drv_cb);
        `uvm_fatal("UART_TIMEOUT", "La secuencia excedio su presupuesto de ciclos")
      end
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
