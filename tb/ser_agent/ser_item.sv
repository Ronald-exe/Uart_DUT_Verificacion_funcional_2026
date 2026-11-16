class ser_item extends uvm_sequence_item;
  `uvm_object_utils(ser_item)
  // Keep stimulus choices separate from observed errors so the monitor never inherits an injection request -- alex
  rand bit [7:0] data;
  rand int unsigned gap;
  // These fields are requests from the sequence to the driver -- observed error fields below remain separate -- alex
  rand bit inject_parity_error;
  rand bit inject_frame_error;
  rand bit inject_break;
  rand bit inject_stop2_error;
  rand bit inject_glitch;
  rand int signed baud_error_pct;
  rand int unsigned glitch_cycles;
  bit parity_err;
  bit frame_err;
  // Publish framing and completion metadata so the scoreboard can distinguish a full character from a glitch or interrupted frame -- alex
  bit break_err;
  bit unknown_seen;
  bit aborted;
  bit completed;
  bit start_event;
  bit glitch_event;
  bit is_tx;
  bit [7:0] line_control;
  bit [15:0] divisor;
  time started_at;
  time finished_at;
  function new(string name = "ser_item");
    super.new(name);
  endfunction
  function string convert2string();
    // Include break, abort and baud offset in the existing printable representation so debug reports retain that context -- alex
    // return $sformatf("data=0x%02h gap=%0d pe=%0b fe=%0b", data, gap, parity_err, frame_err);
    return $sformatf("data=%02h gap=%0d pe=%b fe=%b bi=%b aborted=%b skew=%0d", data, gap, parity_err, frame_err, break_err, aborted, baud_error_pct);
  endfunction
endclass
