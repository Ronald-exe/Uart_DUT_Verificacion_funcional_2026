// Keep the handles needed by the main sequence in one place
// There is no extra driver here -- each agent still handles its own protocol
class uart_vsequencer extends uvm_sequencer;
  `uvm_component_utils(uart_vsequencer)
  // Use the original agent sequencers so their drivers keep the normal UVM item handshake
  uvm_sequencer #(wb_item) wb_sqr;
  uvm_sequencer #(ser_item) ser_sqr;
  // Keep access to the predictor because changing DLAB also changes how bus observations are decoded
  uart_reg_block regm;
  uvm_reg_predictor #(wb_item) predictor;
  uart_env_cfg cfg;

  function new(string name = "uart_vsequencer", uvm_component parent = null);
    super.new(name, parent);
  endfunction
endclass : uart_vsequencer
