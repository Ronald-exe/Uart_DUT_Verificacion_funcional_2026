class uart_reg_adapter extends uvm_reg_adapter;
  `uvm_object_utils(uart_reg_adapter)
  function new(string name = "uart_reg_adapter");
    super.new(name);
    supports_byte_enable = 0;
    provides_responses = 0;
  endfunction
  virtual function uvm_sequence_item reg2bus(const ref uvm_reg_bus_op rw);
    wb_item it;
    bit [4:0] index;
    it = wb_item::type_id::create("register_access");
    index = rw.addr[4:0];
    it.we = (rw.kind == UVM_WRITE);
    // Use native byte addresses in the 8-bit build -- the existing big-endian lane packing is only for the 32-bit build -- alex
`ifdef DATA_BUS_WIDTH_8
    it.adr = index;
    it.sel = 1;
    it.data = rw.data[7:0];
`else
    it.adr = {index[4:2], 2'b00};
    it.sel = 4'b1000 >> index[1:0];
    it.data = 32'(rw.data[7:0]) << (8 * (3 - index[1:0]));
`endif
    it.delay = 0;
    it.stb_delay = 0;
    return it;
  endfunction
  virtual function void bus2reg(uvm_sequence_item bus_item, ref uvm_reg_bus_op rw);
    wb_item it;
    bit [1:0] lane;
    if (!$cast(it, bus_item)) begin
      `uvm_fatal("ADAPTER", "RAL adapter requires wb_item")
    end
    rw.kind = it.we ? UVM_WRITE : UVM_READ;
`ifdef DATA_BUS_WIDTH_8
    rw.addr = it.adr;
    rw.data = it.data[7:0];
`else
    // Decode the byte lane for the 32-bit bus -- the 8-bit branch above does not use SEL to select a register -- alex
    case (it.sel)
      8: lane = 0;
      4: lane = 1;
      2: lane = 2;
      1: lane = 3;
      default: lane = 0;
    endcase
    rw.addr = {it.adr[4:2], lane};
    // Only regular SEL values select a data lane -- irregular accesses follow the explicit AMB-06 path below -- alex
    // rw.data = it.data[8 * (3 - b) +: 8];
    if (it.sel inside {1,2,4,8}) begin
      rw.data = it.data[8 * (3 - lane) +: 8];
    end else begin
      // Odd SEL reads return zero but writes still have the low-byte side effect from AMB-06 -- alex
      rw.data = it.we ? it.data[7:0] : 0;
    end
`endif
    // Do not mark an aborted, timed-out or unknown transfer as a successful RAL operation -- alex
    // rw.status = UVM_IS_OK;
    rw.status = (it.aborted || it.timed_out || it.unknown_seen) ? UVM_NOT_OK : UVM_IS_OK;
  endfunction
endclass
