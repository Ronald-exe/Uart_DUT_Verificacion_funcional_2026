class modem_item extends uvm_sequence_item;
  `uvm_object_utils(modem_item)
  // Bit order is DCD, RI, DSR, CTS -- these are physical input levels, not decoded MSR bits -- alex
  rand bit [3:0] pins;
  int unsigned hold_cycles = 1;
  // The monitor fills the outputs and timestamp -- the driver only consumes pins and hold_cycles -- alex
  logic rts;
  logic dtr;
  bit unknown_seen;
  time observed_at;
  function new(string name = "modem_item");
    super.new(name);
  endfunction
endclass
