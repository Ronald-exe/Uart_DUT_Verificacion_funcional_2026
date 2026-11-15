
// Reuse the original address conversion and only add idle cycles for RAL accesses
// Keep this local so we do not have to modify the original adapter or Wishbone driver
class uart_timed_reg_adapter extends uart_reg_adapter;
  `uvm_object_utils(uart_timed_reg_adapter)

  function new(string name = "uart_timed_reg_adapter");
    super.new(name);
  endfunction

  // Let the original adapter build the item so the register addressing stays consistent
  // Only change its delay -- the unchanged driver needs room between consecutive accesses
  virtual function uvm_sequence_item reg2bus(const ref uvm_reg_bus_op rw);
    uvm_sequence_item base_item;
    wb_item item;
    base_item = super.reg2bus(rw);
    if (!$cast(item, base_item))
      `uvm_fatal("UART_ADAPTER", "El adaptador original no devolvio wb_item")
    item.delay = 2;
    return item;
  endfunction
endclass : uart_timed_reg_adapter

// Build and connect the reusable pieces here so the test only has to configure and start them
// Keep stimulus in sequences and comparisons in the scoreboard
class uart_env extends uvm_env;
  `uvm_component_utils(uart_env)
  uart_env_cfg cfg;
  wb_agent wb_agt;
  ser_agent ser_agt;
  uart_reg_block regm;
  uart_timed_reg_adapter adapter;
  uvm_reg_predictor #(wb_item) predictor;
  uart_scoreboard scb;
  uart_vsequencer vseqr;

  function new(string name = "uart_env", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  // Distribute configuration before the children build because their drivers and monitors read it there
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(uart_env_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("UART_ENV_CFG", "Ambiente sin configuracion")
    // Use the config types the existing agents already expect
    // Share one serial config handle so the driver and both monitors use the same line format
    uvm_config_db#(wb_agent_cfg)::set(this, "wb_agt*", "cfg", cfg.wb);
    uvm_config_db#(ser_agent_cfg)::set(this, "ser_agt*", "cfg", cfg.ser);
    uvm_config_db#(uart_env_cfg)::set(this, "scb", "cfg", cfg);
    wb_agt = wb_agent::type_id::create("wb_agt", this);
    ser_agt = ser_agent::type_id::create("ser_agt", this);
    // RAL has no component build phase -- call its build explicitly or the maps and registers stay empty
    regm = uart_reg_block::type_id::create("regm");
    regm.build();
    adapter = uart_timed_reg_adapter::type_id::create("adapter");
    predictor = uvm_reg_predictor#(wb_item)::type_id::create("predictor", this);
    scb = uart_scoreboard::type_id::create("scb", this);
    vseqr = uart_vsequencer::type_id::create("vseqr", this);
  endfunction

  // Wait until connect phase because all child components and their ports must exist first
  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    // DLAB changes the register meaning rather than the physical bus
    // Connect both maps to the same sequencer -- let the monitor-fed predictor update the mirror
    // Disable auto prediction so it does not predict the same access a second time
    regm.map_dlab0.set_sequencer(wb_agt.sqr, adapter);
    regm.map_dlab1.set_sequencer(wb_agt.sqr, adapter);
    regm.map_dlab0.set_auto_predict(0);
    regm.map_dlab1.set_auto_predict(0);
    predictor.map = regm.map_dlab0;
    predictor.adapter = adapter;
    // Send the observed bus access to both consumers -- RAL tracks registers and the scoreboard tracks data
    wb_agt.mon.ap.connect(predictor.bus_in);
    wb_agt.mon.ap.connect(scb.wb_in.analysis_export);
    // These monitor names follow the DUT -- STX is what it sends and SRX is what it receives
    // Keep separate inputs so the scoreboard knows the direction from the connection itself
    ser_agt.mon_tx.ap.connect(scb.tx_in.analysis_export);
    ser_agt.mon_rx.ap.connect(scb.rx_in.analysis_export);
    // Give the virtual sequencer handles rather than another driver connection
    // The real agent sequencers still own the item handshakes
    vseqr.wb_sqr = wb_agt.sqr;
    vseqr.ser_sqr = ser_agt.sqr;
    vseqr.regm = regm;
    vseqr.predictor = predictor;
    vseqr.cfg = cfg;
  endfunction

  // Check the actual destination too -- the right count can still mean the wrong connection
  // Use port component handles here so the same helper works with different transaction types
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

  // Wait until binding resolution is finished before asking ports for their sizes
  // Fail before traffic starts -- an analysis port is allowed to have no subscribers in UVM
  function void end_of_elaboration_phase(uvm_phase phase);
    super.end_of_elaboration_phase(phase);

    // Check handles first so a missing component gives our report rather than a null dereference
    if ((cfg == null) || (wb_agt == null) || (ser_agt == null) ||
        (regm == null) || (adapter == null) || (predictor == null) ||
        (scb == null) || (vseqr == null)) begin
      `uvm_fatal("UART_CONNECTION", "A required environment component or configuration is missing")
      return;
    end
    if ((cfg.wb == null) || (cfg.ser == null) ||
        (wb_agt.drv == null) || (wb_agt.mon == null) || (wb_agt.sqr == null) ||
        (ser_agt.drv == null) || (ser_agt.mon_tx == null) ||
        (ser_agt.mon_rx == null) || (ser_agt.sqr == null) ||
        (scb.wb_in == null) || (scb.tx_in == null) || (scb.rx_in == null) ||
        (regm.map_dlab0 == null) || (regm.map_dlab1 == null)) begin
      `uvm_fatal("UART_CONNECTION", "A required agent child, scoreboard input, or register map is missing")
      return;
    end

    // Getting a config object is not enough -- its interface can still be null
    // Also check the config identity so a child cannot silently use another interface or format
    if ((cfg.wb.vif == null) || (cfg.ser.vif == null) || (cfg.mdm_vif == null)) begin
      `uvm_fatal("UART_CONNECTION", "A required virtual interface is null")
    end
    if ((wb_agt.drv.cfg != cfg.wb) || (wb_agt.mon.cfg != cfg.wb) ||
        (ser_agt.drv.cfg != cfg.ser) || (ser_agt.mon_tx.cfg != cfg.ser) ||
        (ser_agt.mon_rx.cfg != cfg.ser) || (scb.cfg != cfg)) begin
      `uvm_fatal("UART_CONNECTION", "An agent child or scoreboard is using the wrong configuration")
    end
    if (!ser_agt.mon_tx.is_tx || ser_agt.mon_rx.is_tx) begin
      `uvm_fatal("UART_CONNECTION", "Serial monitors are assigned to the wrong lines")
    end

    // Check resolved implementations as well as direct links -- no empty forwarding chain can pass
    if ((wb_agt.drv.seq_item_port.size() != 1) ||
        (ser_agt.drv.seq_item_port.size() != 1) ||
        (wb_agt.mon.ap.size() != 2) ||
        (ser_agt.mon_tx.ap.size() != 1) || (ser_agt.mon_rx.ap.size() != 1)) begin
      `uvm_fatal("UART_CONNECTION", "A required port has an unexpected number of resolved connections")
    end
    check_link(wb_agt.drv.seq_item_port.get_comp(), wb_agt.sqr.seq_item_export.get_comp(), 1);
    check_link(ser_agt.drv.seq_item_port.get_comp(), ser_agt.sqr.seq_item_export.get_comp(), 1);
    check_link(wb_agt.mon.ap.get_comp(), predictor.bus_in.get_comp(), 2);
    check_link(wb_agt.mon.ap.get_comp(), scb.wb_in.analysis_export.get_comp(), 2);
    check_link(ser_agt.mon_tx.ap.get_comp(), scb.tx_in.analysis_export.get_comp(), 1);
    check_link(ser_agt.mon_rx.ap.get_comp(), scb.rx_in.analysis_export.get_comp(), 1);

    // The virtual sequencer uses handles rather than TLM connections -- validate those separately
    if ((vseqr.wb_sqr != wb_agt.sqr) || (vseqr.ser_sqr != ser_agt.sqr) ||
        (vseqr.regm != regm) || (vseqr.predictor != predictor) || (vseqr.cfg != cfg)) begin
      `uvm_fatal("UART_CONNECTION", "The virtual sequencer has a missing or incorrect reference")
    end

    // Both banks must reach the real bus and use the same adapter as the observed predictor
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

