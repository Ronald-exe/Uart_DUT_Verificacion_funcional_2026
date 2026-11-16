
class uart_timed_reg_adapter extends uart_reg_adapter;
  `uvm_object_utils(uart_timed_reg_adapter)

  function new(string name = "uart_timed_reg_adapter");
    super.new(name);
  endfunction

  virtual function uvm_sequence_item reg2bus(const ref uvm_reg_bus_op rw);
    uvm_sequence_item base_item;
    wb_item item;
    base_item = super.reg2bus(rw);
    if (!$cast(item, base_item))
      `uvm_fatal("UART_ADAPTER", "El adaptador original no devolvio wb_item")
    // Keep a short idle gap for back-to-back RAL accesses -- address packing still comes from the base adapter -- alex
    item.delay = 2;
    return item;
  endfunction
endclass : uart_timed_reg_adapter

class uart_env extends uvm_env;
  `uvm_component_utils(uart_env)
  uart_env_cfg cfg;
  wb_agent wb_agt;
  ser_agent ser_agt;
  uart_reg_block regm;
  uart_timed_reg_adapter adapter;
  uart_dlab_predictor predictor;
  uart_line_observer line_observer;
  modem_agent mdm_agt;
  uart_int_monitor int_mon;
  uart_scoreboard scb;
  uart_vsequencer vseqr;

  function new(string name = "uart_env", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(uart_env_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("UART_ENV_CFG", "Ambiente sin configuracion")
    // Publish the same config objects before the children build
    // Copies here would let an observed LCR change update one monitor while leaving the driver on the old format -- alex
    uvm_config_db#(wb_agent_cfg)::set(this, "wb_agt*", "cfg", cfg.wb);
    uvm_config_db#(ser_agent_cfg)::set(this, "ser_agt*", "cfg", cfg.ser);
    uvm_config_db#(uart_env_cfg)::set(this, "scb", "cfg", cfg);
    uvm_config_db#(modem_agent_cfg)::set(this, "mdm_agt*", "cfg", cfg.mdm);
    wb_agt = wb_agent::type_id::create("wb_agt", this);
    ser_agt = ser_agent::type_id::create("ser_agt", this);
    // RAL is an object -- the UVM component build traversal will not build its register maps for us -- alex
    regm = uart_reg_block::type_id::create("regm");
    regm.build();
    adapter = uart_timed_reg_adapter::type_id::create("adapter");
    // Both observers use actual bus writes -- raw register traffic can change DLAB or framing outside program_uart -- alex
    predictor = uart_dlab_predictor::type_id::create("predictor", this);
    predictor.regm = regm;
    line_observer = uart_line_observer::type_id::create("line_observer", this);
    line_observer.cfg = cfg;
    line_observer.regm = regm;
    line_observer.predictor = predictor;
    mdm_agt = modem_agent::type_id::create("mdm_agt", this);
    int_mon = uart_int_monitor::type_id::create("int_mon", this);
    int_mon.cfg = cfg;
    scb = uart_scoreboard::type_id::create("scb", this);
    vseqr = uart_vsequencer::type_id::create("vseqr", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    // DLAB selects register meaning, not a second bus -- both maps must reach the same master -- alex
    regm.map_dlab0.set_sequencer(wb_agt.sqr, adapter);
    regm.map_dlab1.set_sequencer(wb_agt.sqr, adapter);
    // The observed predictor owns the mirror -- auto prediction would update it again from the requested access -- alex
    regm.map_dlab0.set_auto_predict(0);
    regm.map_dlab1.set_auto_predict(0);
    predictor.map = regm.map_dlab0;
    predictor.adapter = adapter;
    // Fan out each observed access to three consumers -- mirror prediction, live framing and scoreboard
    // The framing observer needs the same completed writes as the predictor rather than sequence intent -- alex
    wb_agt.mon.ap.connect(predictor.bus_in);
    wb_agt.mon.ap.connect(line_observer.analysis_export);
    // Send modem changes and clock-by-clock samples separately
    // The scoreboard needs continuous samples for IRQ and baud timing even when no pin changes -- alex
    mdm_agt.mon.ap.connect(scb.modem_in.analysis_export);
    int_mon.ap.connect(scb.irq_in.analysis_export);
    wb_agt.mon.ap.connect(scb.wb_in.analysis_export);
    // Direction follows the DUT pins -- STX observations check what it sent, SRX observations describe its input -- alex
    ser_agt.mon_tx.ap.connect(scb.tx_in.analysis_export);
    ser_agt.mon_rx.ap.connect(scb.rx_in.analysis_export);
    // These are references for coordination -- connecting a second driver path here would bypass the agent sequencers -- alex
    vseqr.wb_sqr = wb_agt.sqr;
    vseqr.ser_sqr = ser_agt.sqr;
    vseqr.mdm_sqr = mdm_agt.sqr;
    vseqr.regm = regm;
    vseqr.predictor = predictor;
    vseqr.cfg = cfg;
  endfunction

  function void check_link(uvm_port_component_base source,
                           uvm_port_component_base destination,
                           int unsigned expected_count);
    uvm_port_list connected;
    string destination_name;
    if ((source == null) || (destination == null)) begin
      `uvm_fatal("UART_CONNECTION", "A required TLM endpoint is null")
      return;
    end
    source.get_connected_to(connected);
    if (connected.num() != expected_count) begin
      `uvm_fatal("UART_CONNECTION", $sformatf("%s has %0d direct connections -- expected %0d",
                 source.get_full_name(), connected.num(), expected_count))
      return;
    end
    // The right number of connections can still lead to the wrong consumer
    // Check both the path and the handle so an unrelated port with a matching count cannot pass -- alex
    destination_name = destination.get_full_name();
    if (!connected.exists(destination_name)) begin
      `uvm_fatal("UART_CONNECTION", $sformatf("Missing connection from %s to %s",
                 source.get_full_name(), destination_name))
      return;
    end
    if (connected[destination_name] != destination) begin
      `uvm_fatal("UART_CONNECTION", $sformatf("Wrong destination handle for %s", destination_name))
    end
  endfunction

  // Port sizes are resolved by this phase -- connect_phase is too early to inspect them
  // UVM permits an unused analysis port, so required checking paths need our explicit validation -- alex
  function void end_of_elaboration_phase(uvm_phase phase);
    super.end_of_elaboration_phase(phase);

    // Stop before dereferencing any missing child -- otherwise a null-handle failure hides which connection was absent -- alex
    if ((cfg == null) || (wb_agt == null) || (ser_agt == null) ||
        (regm == null) || (adapter == null) || (predictor == null) ||
        (scb == null) || (vseqr == null) || (mdm_agt == null) ||
        (int_mon == null) || (line_observer == null)) begin
      `uvm_fatal("UART_CONNECTION", "A required environment component or configuration is missing")
      return;
    end
    if ((cfg.wb == null) || (cfg.ser == null) ||
        (wb_agt.drv == null) || (wb_agt.mon == null) || (wb_agt.sqr == null) ||
        (ser_agt.drv == null) || (ser_agt.mon_tx == null) ||
        (ser_agt.mon_rx == null) || (ser_agt.sqr == null) ||
        (scb.wb_in == null) || (scb.tx_in == null) || (scb.rx_in == null) ||
        (mdm_agt.drv == null) || (mdm_agt.mon == null) || (mdm_agt.sqr == null) ||
        (scb.modem_in == null) || (scb.irq_in == null) ||
        (regm.map_dlab0 == null) || (regm.map_dlab1 == null)) begin
      `uvm_fatal("UART_CONNECTION", "A required agent child, scoreboard input, or register map is missing")
      return;
    end

    // A valid config handle can still contain no interface -- check both levels -- alex
    if ((cfg.wb.vif == null) || (cfg.ser.vif == null) || (cfg.mdm_vif == null)) begin
      `uvm_fatal("UART_CONNECTION", "A required virtual interface is null")
    end
    // A second config instance can contain valid interfaces yet miss later framing updates
    // Require the shared object, not just any object of the correct type -- alex
    if ((wb_agt.drv.cfg != cfg.wb) || (wb_agt.mon.cfg != cfg.wb) ||
        (ser_agt.drv.cfg != cfg.ser) || (ser_agt.mon_tx.cfg != cfg.ser) ||
        (ser_agt.mon_rx.cfg != cfg.ser) || (scb.cfg != cfg)) begin
      `uvm_fatal("UART_CONNECTION", "An agent child or scoreboard is using the wrong configuration")
    end
    if (!ser_agt.mon_tx.is_tx || ser_agt.mon_rx.is_tx) begin
      `uvm_fatal("UART_CONNECTION", "Serial monitors are assigned to the wrong lines")
    end

    // size checks the resolved implementations, check_link below checks the direct wiring
    // Wishbone has three consumers now -- predictor, line observer and scoreboard -- alex
    if ((wb_agt.drv.seq_item_port.size() != 1) ||
        (ser_agt.drv.seq_item_port.size() != 1) ||
        (wb_agt.mon.ap.size() != 3) ||
        (ser_agt.mon_tx.ap.size() != 1) || (ser_agt.mon_rx.ap.size() != 1) ||
        (mdm_agt.drv.seq_item_port.size() != 1) || (mdm_agt.mon.ap.size() != 1) ||
        (int_mon.ap.size() != 1)) begin
      `uvm_fatal("UART_CONNECTION", "A required port has an unexpected number of resolved connections")
    end
    check_link(wb_agt.drv.seq_item_port.get_comp(), wb_agt.sqr.seq_item_export.get_comp(), 1);
    check_link(ser_agt.drv.seq_item_port.get_comp(), ser_agt.sqr.seq_item_export.get_comp(), 1);
    check_link(wb_agt.mon.ap.get_comp(), predictor.bus_in.get_comp(), 3);
    check_link(wb_agt.mon.ap.get_comp(), scb.wb_in.analysis_export.get_comp(), 3);
    check_link(wb_agt.mon.ap.get_comp(), line_observer.analysis_export.get_comp(), 3);
    check_link(mdm_agt.drv.seq_item_port.get_comp(), mdm_agt.sqr.seq_item_export.get_comp(), 1);
    check_link(mdm_agt.mon.ap.get_comp(), scb.modem_in.analysis_export.get_comp(), 1);
    check_link(int_mon.ap.get_comp(), scb.irq_in.analysis_export.get_comp(), 1);
    check_link(ser_agt.mon_tx.ap.get_comp(), scb.tx_in.analysis_export.get_comp(), 1);
    check_link(ser_agt.mon_rx.ap.get_comp(), scb.rx_in.analysis_export.get_comp(), 1);

    // TLM port checks cannot see these plain handles -- a null or swapped sequencer needs its own check -- alex
    if ((vseqr.wb_sqr != wb_agt.sqr) || (vseqr.ser_sqr != ser_agt.sqr) || (vseqr.mdm_sqr != mdm_agt.sqr) ||
        (vseqr.regm != regm) || (vseqr.predictor != predictor) || (vseqr.cfg != cfg)) begin
      `uvm_fatal("UART_CONNECTION", "The virtual sequencer has a missing or incorrect reference")
    end

    // A populated RAL model can still be disconnected -- verify both maps and the predictor share the real bus path -- alex
    if ((regm.map_dlab0.get_sequencer() != wb_agt.sqr) ||
        (regm.map_dlab1.get_sequencer() != wb_agt.sqr) ||
        (regm.map_dlab0.get_adapter() != adapter) ||
        (regm.map_dlab1.get_adapter() != adapter) ||
        regm.map_dlab0.get_auto_predict() || regm.map_dlab1.get_auto_predict() ||
        (predictor.adapter != adapter) || (predictor.map != regm.map_dlab0)) begin
      `uvm_fatal("UART_CONNECTION", "RAL maps or predictor are not connected as expected")
    end
    `uvm_info("UART_CONNECTION", "Environment connection checks completed", UVM_LOW)
  endfunction
endclass : uart_env

