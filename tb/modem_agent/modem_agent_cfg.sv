class modem_agent_cfg extends uvm_object;
  `uvm_object_utils(modem_agent_cfg)
  virtual modem_if vif;
  virtual wb_if reset_vif;
  // Apply this probability independently to each input -- several pins may change in the same item -- alex
  int unsigned toggle_pct = 20;
  function new(string name = "modem_agent_cfg");
    super.new(name);
  endfunction
endclass
