class ser_agent_cfg extends uvm_object;
  `uvm_object_utils(ser_agent_cfg)
  virtual uart_ser_if vif;
  // Get reset through the existing bus interface rather than changing the supplied serial interface -- alex
  virtual wb_if reset_vif;
  int unsigned burst_min = 0;
  // The general range must already include long bursts -- corner profiles can narrow it without extending the defaults -- alex
  // int unsigned burst_max = 20;
  int unsigned burst_max = 255;
  int unsigned data_min = 0;
  int unsigned data_max = 255;
  int unsigned gap_max = 60;
  bit [1:0] wls = 3;
  bit stb;
  bit pen;
  bit eps;
  bit sp;
  bit [15:0] dl = 1;
  // Keep observed LCR and MCR together with an epoch so a monitor can identify a frame interrupted by reconfiguration -- alex
  bit [7:0] lcr = 3;
  bit [4:0] mcr;
  // The external source keeps its last nonzero clock even while the DUT divisor is zero -- alex
  bit [15:0] source_dl = 1;
  int signed source_skew;
  int unsigned source_period;
  bit source_frame_active;
  int unsigned epoch;
  // Make passive reuse explicit instead of always constructing a driver -- alex
  uvm_active_passive_enum active = UVM_ACTIVE;
  function new(string name = "ser_agent_cfg");
    super.new(name);
  endfunction
  function int unsigned n_bits();
    return 5 + int'(wls);
  endfunction
  function int unsigned bit_cycles();
    return 16 * int'(dl);
  endfunction
  function bit parity_bit(bit [7:0] data);
    bit value;
    value = 0;
    for (int i = 0; i < n_bits(); i++) begin
      value ^= data[i];
    end
    case ({eps, sp})
      0: return ~value;
      1: return 1;
      2: return value;
      3: return 0;
    endcase
    return 0;
  endfunction
  function int unsigned stop_cycles();
    if (!stb) begin
      return bit_cycles();
    end
    if (wls == 0) begin
      return bit_cycles() * 3 / 2;
    end
    return bit_cycles() * 2;
  endfunction
  // Update the framing fields from the observed register write -- existing helper functions still use these fields -- alex
  function void set_lcr(bit [7:0] value);
    // Switching only DLAB does not change an in-flight serial format -- alex
    if (lcr[6:0] != value[6:0]) begin
      epoch++;
    end
    lcr = value;
    wls = value[1:0];
    stb = value[2];
    pen = value[3];
    eps = value[4];
    sp = value[5];
  endfunction
endclass
