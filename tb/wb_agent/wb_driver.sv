class wb_driver extends uvm_driver #(wb_item);
  `uvm_component_utils(wb_driver)
  wb_agent_cfg cfg;
  function new(string name = "wb_driver", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(wb_agent_cfg)::get(this, "", "cfg", cfg)) begin
      `uvm_fatal("NOCFG", "Wishbone driver configuration is missing")
    end
    // Check the virtual interface before starting any cycle so a missing connection cannot look like an idle passing test -- alex
    if (cfg.vif == null) begin
      `uvm_fatal("WB_VIF", "Wishbone interface is null")
    end
  endfunction
  // Share bus recovery between normal completion and cancellation so reset cannot leave CYC or STB asserted -- alex
  task idle_bus();
    cfg.vif.drv_cb.cyc <= 0;
    cfg.vif.drv_cb.stb <= 0;
    cfg.vif.drv_cb.we <= 0;
  endtask
  task drive_item(wb_item it);
    repeat (it.delay) @(cfg.vif.drv_cb);
    cfg.vif.drv_cb.cyc <= 1;
    cfg.vif.drv_cb.adr <= it.adr;
    cfg.vif.drv_cb.sel <= it.sel;
    cfg.vif.drv_cb.we <= it.we;
    cfg.vif.drv_cb.dat_m2s <= it.data;
    repeat (it.stb_delay) @(cfg.vif.drv_cb);
    cfg.vif.drv_cb.stb <= 1;
    do begin
      @(cfg.vif.drv_cb);
    end while (cfg.vif.drv_cb.ack !== 1);
    // Record unknown read data before assigning it to the original two-state payload field -- alex
    // if (!it.we) it.data = cfg.vif.drv_cb.dat_s2m;
    if (!it.we) begin
      it.unknown_seen = $isunknown(cfg.vif.drv_cb.dat_s2m);
      it.data = cfg.vif.drv_cb.dat_s2m;
    end
    it.completed = 1;
  endtask
  task run_phase(uvm_phase phase);
    wb_item it;
    idle_bus();
    forever begin
      seq_item_port.get_next_item(it);
      cfg.requested_items++;
      it.completed = 0;
      it.aborted = 0;
      it.timed_out = 0;
      wait (cfg.vif.rst === 0);
      // Wait for stale ACK to clear before another classic bus cycle can begin -- alex
      @(cfg.vif.drv_cb);
      while (cfg.vif.drv_cb.ack !== 0) begin
        @(cfg.vif.drv_cb);
      end
      // Bound the active transfer and race it against reset -- only the completed branch contributes to the successful-access count -- alex
      fork
        drive_item(it);
        begin
          wait (cfg.vif.rst !== 0);
          it.aborted = 1;
        end
        begin
          repeat (cfg.timeout_cycles) @(cfg.vif.drv_cb);
          it.timed_out = 1;
          `uvm_fatal("WB_TIMEOUT", "Wishbone ACK timeout")
        end
      join_any
      disable fork;
      idle_bus();
      @(cfg.vif.drv_cb);
      if (it.completed) begin
        cfg.completed_items++;
      end else if (it.aborted) begin
        cfg.aborted_items++;
      end
      seq_item_port.item_done();
    end
  endtask
endclass
