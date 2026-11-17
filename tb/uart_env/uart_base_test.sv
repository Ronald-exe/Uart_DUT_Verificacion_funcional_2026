// Keep one test class and select traffic through plusargs
// Changing the count or seed should not require another test class or a recompile
class uart_base_test extends uvm_test;
  `uvm_component_utils(uart_base_test)
  uart_env_cfg cfg;
  uart_env env;

  function new(string name = "uart_base_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  // Get the interfaces from the top and validate configuration before building the environment
  // Reject the 8-bit variant here because the original adapter only translates the 32-bit bus
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
`ifdef DATA_BUS_WIDTH_8
    `uvm_fatal("UART_BUS_WIDTH", "El adaptador original requiere el bus de 32 bits; BUS8 pendiente")
`endif
    cfg = uart_env_cfg::type_id::create("cfg");
    if (!uvm_config_db#(virtual wb_if)::get(this, "", "wb_vif", cfg.wb.vif))
      `uvm_fatal("UART_VIF", "No se encontro wb_vif")
    if (!uvm_config_db#(virtual uart_ser_if)::get(this, "", "ser_vif", cfg.ser.vif))
      `uvm_fatal("UART_VIF", "No se encontro ser_vif")
    if (!uvm_config_db#(virtual modem_if)::get(this, "", "mdm_vif", cfg.mdm_vif))
      `uvm_fatal("UART_VIF", "No se encontro mdm_vif")
    // Use this component as the config report context so the messages have a useful UVM path
    cfg.parse_plusargs(this);
    uvm_config_db#(uart_env_cfg)::set(this, "env", "cfg", cfg);
    env = uart_env::type_id::create("env", this);
  endfunction

  // Only include LCR, IER and SCR in this reset check for now
  // They have stable readable values and implemented backdoor paths
  // Exclude the others from this specific sequence -- leave the rest of the checking alone
  function void end_of_elaboration_phase(uvm_phase phase);
    uvm_reg registers[$];
    super.end_of_elaboration_phase(phase);
    env.regm.get_registers(registers);
    foreach (registers[i]) begin
      if ((registers[i] != env.regm.LCR) &&
          (registers[i] != env.regm.IER) &&
          (registers[i] != env.regm.SCR)) begin
        uvm_resource_db#(bit)::set({"REG::", registers[i].get_full_name()},
                                  "NO_REG_HW_RESET_TEST", 1, this);
      end
    end
  endfunction

  // Raise the objection before starting so UVM does not finish while traffic is still running
  // Run a watchdog beside the sequence because a missing handshake would otherwise wait forever
  task run_phase(uvm_phase phase);
    uart_main_vseq seq;
    bit completed;
    phase.raise_objection(this);
    seq = uart_main_vseq::type_id::create("main_sequence");
    completed = 0;
    fork
      begin
        seq.start(env.vseqr);
        completed = 1;
      end
      begin
        repeat (cfg.timeout_cycles) @(cfg.wb.vif.drv_cb);
        `uvm_fatal("UART_TIMEOUT", "La secuencia excedio su presupuesto de ciclos")
      end
    join_any
    disable fork;
    // Let the last observations reach the scoreboard before handing over the final counts
    // Only set targets after completion so a killed sequence cannot look like a completed run
    if (completed) begin
      repeat (3) @(cfg.wb.vif.drv_cb);
      env.scb.expect_totals(seq.planned_tx, seq.planned_rx);
    end
    phase.drop_objection(this);
  endtask

  // Check the report counts after check phase so pending-data errors also affect the result
  // Passing this test only covers the implemented E2 checks
  function void report_phase(uvm_phase phase);
    uvm_report_server reports;
    super.report_phase(phase);
    reports = uvm_report_server::get_server();
    if ((reports.get_severity_count(UVM_ERROR) == 0) &&
        (reports.get_severity_count(UVM_FATAL) == 0))
      `uvm_info("UART_E2_PASS", "Sin errores en el alcance E2: reset RAL y datos normales TX/RX", UVM_NONE)
    else
      `uvm_info("UART_E2_FAIL", "Hay errores: revisar los reportes UVM anteriores", UVM_NONE)
  endfunction
endclass : uart_base_test
