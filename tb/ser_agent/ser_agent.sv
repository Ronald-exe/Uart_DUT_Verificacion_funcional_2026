class ser_agent extends uvm_agent;
  `uvm_component_utils(ser_agent)
  // Read the active/passive setting here so a passive agent does not create stimulus components -- alex
  ser_agent_cfg cfg;
  ser_driver drv;
  ser_monitor mon_tx;
  ser_monitor mon_rx;
  uvm_sequencer #(ser_item) sqr;
  function new(string name = "ser_agent",uvm_component parent = null);
    super.new(name,parent);
  endfunction
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(ser_agent_cfg)::get(this,"","cfg",cfg)) begin
      `uvm_fatal("NOCFG","Serial agent configuration is missing")
    end
    mon_tx = ser_monitor::type_id::create("mon_tx",this);
    mon_rx = ser_monitor::type_id::create("mon_rx",this);
    mon_tx.is_tx = 1;
    mon_rx.is_tx = 0;
    // Keep both monitors in either mode -- only the driver and sequencer need the active guard -- alex
    if (cfg.active == UVM_ACTIVE) begin
      drv = ser_driver::type_id::create("drv",this);
      sqr = uvm_sequencer#(ser_item)::type_id::create("sqr",this);
    end
  endfunction
  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    // A passive agent has no driver -- only connect this port when the active components exist -- alex
    if (drv != null) begin
      drv.seq_item_port.connect(sqr.seq_item_export);
    end
  endfunction
endclass
