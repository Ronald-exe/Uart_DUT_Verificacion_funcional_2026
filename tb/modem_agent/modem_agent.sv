class modem_driver extends uvm_driver #(modem_item);
  `uvm_component_utils(modem_driver)
  modem_agent_cfg cfg;
  function new(string name = "modem_driver", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(modem_agent_cfg)::get(this, "", "cfg", cfg)) begin
      `uvm_fatal("MODEM_CFG", "Modem driver configuration is missing")
    end
  endfunction
  task run_phase(uvm_phase phase);
    modem_item it;
    forever begin
      seq_item_port.get_next_item(it);
      @(cfg.vif.drv_cb);
      // Drive literal physical pin levels -- applying active-low interpretation here as well as in the model would invert them twice -- alex
      cfg.vif.drv_cb.dcd <= it.pins[3];
      cfg.vif.drv_cb.ri <= it.pins[2];
      cfg.vif.drv_cb.dsr <= it.pins[1];
      cfg.vif.drv_cb.cts <= it.pins[0];
      repeat (it.hold_cycles) @(cfg.vif.drv_cb);
      seq_item_port.item_done();
    end
  endtask
endclass

class modem_monitor extends uvm_monitor;
  `uvm_component_utils(modem_monitor)
  modem_agent_cfg cfg;
  uvm_analysis_port #(modem_item) ap;
  function new(string name = "modem_monitor", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    if (!uvm_config_db#(modem_agent_cfg)::get(this, "", "cfg", cfg)) begin
      `uvm_fatal("MODEM_CFG", "Modem monitor configuration is missing")
    end
  endfunction
  task run_phase(uvm_phase phase);
    logic [5:0] previous;
    logic [5:0] current;
    bit first;
    modem_item it;
    first = 1;
    forever begin
      @(cfg.vif.mon_cb);
      current = {cfg.vif.mon_cb.rts, cfg.vif.mon_cb.dtr, cfg.vif.mon_cb.dcd,
                 cfg.vif.mon_cb.ri, cfg.vif.mon_cb.dsr, cfg.vif.mon_cb.cts};
      // Publish the initial levels even with no edge -- later, case inequality also catches transitions into X or Z -- alex
      if (first || (current !== previous)) begin
        it = modem_item::type_id::create("observed_modem");
        {it.rts, it.dtr, it.pins} = current;
        // Record unknowns before assigning pin inputs into the two-state item field -- the conversion alone would hide them -- alex
        it.unknown_seen = $isunknown(current);
        it.observed_at = $time;
        ap.write(it);
        previous = current;
        first = 0;
      end
    end
  endtask
endclass

class modem_agent extends uvm_agent;
  `uvm_component_utils(modem_agent)
  modem_driver drv;
  modem_monitor mon;
  uvm_sequencer #(modem_item) sqr;
  function new(string name = "modem_agent", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    drv = modem_driver::type_id::create("drv", this);
    mon = modem_monitor::type_id::create("mon", this);
    sqr = uvm_sequencer#(modem_item)::type_id::create("sqr", this);
  endfunction
  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    drv.seq_item_port.connect(sqr.seq_item_export);
  endfunction
endclass
