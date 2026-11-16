class uart_vsequencer extends uvm_sequencer;
  `uvm_component_utils(uart_vsequencer)
  // These handles point at existing agent sequencers -- this virtual sequencer has no driver of its own -- alex
  uvm_sequencer #(wb_item) wb_sqr;
  uvm_sequencer #(ser_item) ser_sqr;
  uvm_sequencer #(modem_item) mdm_sqr;
  // Share the actual register model and predictor, not copies -- frontdoor programming and observed bank state must agree -- alex
  uart_reg_block regm;
  uvm_reg_predictor #(wb_item) predictor;
  uart_env_cfg cfg;

  function new(string name = "uart_vsequencer", uvm_component parent = null);
    super.new(name, parent);
  endfunction
endclass : uart_vsequencer
