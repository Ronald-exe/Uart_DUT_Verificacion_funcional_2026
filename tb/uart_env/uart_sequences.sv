// Keep one bus access in this helper so TX generation and RX service use the same packing and timeout
// The original driver still handles the pins
class uart_wb_seq extends uvm_sequence #(wb_item);
  `uvm_object_utils(uart_wb_seq)
  uart_env_cfg cfg;
  bit [4:0] reg_index;
  bit write_access;
  bit [7:0] write_data;
  bit [7:0] read_data;

  function new(string name = "uart_wb_seq");
    super.new(name);
  endfunction

  task body();
    wb_item it;
    int unsigned lane;
    it = wb_item::type_id::create("access");
    start_item(it);
    // Pack bytes the same way as the RAL adapter so raw traffic and register accesses agree
    // Register zero uses the top byte lane -- the aligned bus address identifies the group
    lane = 3 - reg_index[1:0];
    it.adr = {reg_index[4:2], 2'b00};
    it.sel = 4'b1000 >> reg_index[1:0];
    it.we = write_access;
    it.data = '0;
    it.data[8 * lane +: 8] = write_data;
    it.delay = $urandom_range(cfg.wb.delay_max, 0);
    it.stb_delay = $urandom_range(cfg.wb.stb_delay_max, 0);
    // The driver can wait forever if ACK never arrives so put a timeout beside finish_item
    // Once either branch finishes cancel the other -- no leftover timeout should kill a later access
    fork
      begin
        finish_item(it);
      end
      begin
        repeat (cfg.bus_timeout_cycles) @(cfg.wb.vif.drv_cb);
        `uvm_fatal("UART_WB_TIMEOUT", "El acceso Wishbone no termino")
      end
    join_any
    disable fork;
    read_data = it.data[8 * lane +: 8];
  endtask
endclass : uart_wb_seq

// Generate characters here and leave bit timing to the existing serial driver
// That keeps the traffic constraints separate from how a UART frame is driven on SRX
class uart_rx_seq extends uvm_sequence #(ser_item);
  `uvm_object_utils(uart_rx_seq)
  uart_env_cfg cfg;
  int unsigned count;

  function new(string name = "uart_rx_seq");
    super.new(name);
  endfunction

  task body();
    ser_item it;
    int unsigned low;
    int unsigned high;
    int unsigned gap_limit;
    // Copy the config limits locally so the inline constraint clearly refers to these bounds
    low = cfg.ser.data_min;
    high = cfg.ser.data_max;
    gap_limit = cfg.ser.gap_max;
    repeat (count) begin
      it = ser_item::type_id::create("rx_character");
      start_item(it);
      if (!it.randomize() with {
        data inside {[local::low:local::high]};
        gap inside {[0:local::gap_limit]};
      }) begin
        `uvm_fatal("UART_RANDOMIZE", "No se pudo aleatorizar el caracter RX")
      end
      finish_item(it);
    end
  endtask
endclass : uart_rx_seq

// Use the standard RAL reset sequence but supply the hardware reset it cannot know how to drive
// Resetting the mirror alone would not test whether the DUT registers actually reset
class uart_hw_reset_seq extends uvm_reg_hw_reset_seq;
  `uvm_object_utils(uart_hw_reset_seq)
  virtual wb_if vif;

  function new(string name = "uart_hw_reset_seq");
    super.new(name);
  endfunction

  // Change reset on falling edges to keep it away from bus sampling on rising edges
  // Only do this before traffic because the existing agents do not recover an interrupted frame
  virtual task reset_blk(uvm_reg_block blk);
    if (vif == null)
      `uvm_fatal("UART_RESET_VIF", "Reset fisico sin wb_if")
    @(negedge vif.clk);
    vif.rst = 1;
    repeat (5) @(negedge vif.clk);
    vif.rst = 0;
    repeat (3) @(vif.drv_cb);
  endtask
endclass : uart_hw_reset_seq

// Coordinate the agents here because neither individual agent should own the full test flow
// Use the same sequence for different ranges -- the plusargs decide what traffic is possible
class uart_main_vseq extends uvm_sequence;
  `uvm_object_utils(uart_main_vseq)
  `uvm_declare_p_sequencer(uart_vsequencer)
  uart_env_cfg cfg;
  bit rx_done;
  bit [7:0] active_lcr;
  bit [15:0] active_dl;
  longint unsigned planned_tx;
  longint unsigned planned_rx;

  function new(string name = "uart_main_vseq");
    super.new(name);
  endfunction

  // Compute character time from the active format so waits follow changes in data width and baud
  // Use the agent helper for stops because 5-bit mode can have one and a half stop bits
  function int unsigned char_cycles();
    return (1 + cfg.ser.n_bits() + int'(cfg.ser.pen)) * cfg.ser.bit_cycles() +
           cfg.ser.stop_cycles();
  endfunction

  // Leave locking to the caller so several transfers can stay inside one DLAB-critical section
  // Wait after the access because the unchanged driver needs its outputs to settle before reuse
  task transfer(bit wr, bit [4:0] index, bit [7:0] value,
                output bit [7:0] result);
    uart_wb_seq seq;
    seq = uart_wb_seq::type_id::create("wb_access");
    seq.cfg = cfg;
    seq.reg_index = index;
    seq.write_access = wr;
    seq.write_data = value;
    seq.start(p_sequencer.wb_sqr);
    result = seq.read_data;
    repeat (2) @(cfg.wb.vif.drv_cb);
  endtask

  // Take the bus token around the whole access including recovery cycles
  // Otherwise TX and RX service could start their next accesses before the bus is ready
  task access(bit wr, bit [4:0] index, bit [7:0] value,
              output bit [7:0] result);
    cfg.bus_lock.get(1);
    transfer(wr, index, value, result);
    cfg.bus_lock.put(1);
  endtask

  // Write something different first -- reading reset values from an untouched DUT would prove very little
  // Read it back so we know the preparation really reached the hardware
  task prepare_reset_register(uvm_reg reg_handle, uvm_reg_data_t value);
    uvm_status_e status;
    uvm_reg_data_t actual;
    reg_handle.write(status, value, UVM_FRONTDOOR, p_sequencer.regm.map_dlab0);
    if (status != UVM_IS_OK)
      `uvm_error("UART_RAL_PREPARE", "Fallo al preparar el registro antes del reset")
    repeat (2) @(cfg.wb.vif.drv_cb);
    reg_handle.read(status, actual, UVM_FRONTDOOR, p_sequencer.regm.map_dlab0);
    repeat (2) @(cfg.wb.vif.drv_cb);
    if ((status != UVM_IS_OK) || (actual !== value))
      `uvm_error("UART_RAL_PREPARE", {reg_handle.get_name(), " no tomo el valor previo al reset"})
  endtask

  // Check reset through Wishbone first and then repeat preparation before the backdoor check
  // The second check needs its own changed state or it would only reread an already-reset register
  task ral_preamble();
    uart_hw_reset_seq seq;
    uvm_status_e status;
    seq = uart_hw_reset_seq::type_id::create("ral_reset");
    seq.vif = cfg.wb.vif;
    seq.model = p_sequencer.regm;
    prepare_reset_register(p_sequencer.regm.LCR, 8'h1b);
    prepare_reset_register(p_sequencer.regm.IER, 8'h0f);
    prepare_reset_register(p_sequencer.regm.SCR, 8'ha5);
    `uvm_info("UART_RAL_FRONTDOOR", "Comprobando reset por Wishbone", UVM_LOW)
    seq.start(null);
    repeat (2) @(cfg.wb.vif.drv_cb);
    prepare_reset_register(p_sequencer.regm.LCR, 8'h1b);
    prepare_reset_register(p_sequencer.regm.IER, 8'h0f);
    prepare_reset_register(p_sequencer.regm.SCR, 8'ha5);
    seq.reset_blk(p_sequencer.regm);
    p_sequencer.regm.reset();
    `uvm_info("UART_RAL_BACKDOOR", "Comprobando reset por rutas HDL", UVM_LOW)
    p_sequencer.regm.LCR.mirror(status, UVM_CHECK, UVM_BACKDOOR);
    if (status != UVM_IS_OK)
      `uvm_error("UART_RAL_STATUS", "Error backdoor en LCR")
    p_sequencer.regm.IER.mirror(status, UVM_CHECK, UVM_BACKDOOR);
    if (status != UVM_IS_OK)
      `uvm_error("UART_RAL_STATUS", "Error backdoor en IER")
    p_sequencer.regm.SCR.mirror(status, UVM_CHECK, UVM_BACKDOOR);
    if (status != UVM_IS_OK)
      `uvm_error("UART_RAL_STATUS", "Error backdoor en SCR")
  endtask

  // Choose one format before traffic and keep it stable for this run
  // Changing it mid-frame needs extra handling in the original driver, monitors and scoreboard
  task program_uart();
    int unsigned mode;
    int unsigned pick;
    bit [7:0] result;
    bit [7:0] fcr;
    bit [7:0] ier;
    bit [7:0] mcr;
    // Build LCR from weighted choices so excluding a format only requires changing its weight
    active_lcr = cfg.choose_weight(cfg.line.wls_w) |
                 (cfg.choose_weight(cfg.line.stb_w) << 2);
    mode = cfg.choose_weight(cfg.line.par_w);
    case (mode)
      1: active_lcr |= 8'h08;
      2: active_lcr |= 8'h18;
      3: active_lcr |= 8'h28;
      4: active_lcr |= 8'h38;
    endcase
    // Choose the region first so the fast range can be common without excluding larger divisors
    // DL zero stays represented in the config but is rejected for this stage
    pick = $urandom_range(99, 0);
    if (pick < cfg.line.dl_zero_pct)
      active_dl = 0;
    else if (pick < cfg.line.dl_zero_pct + cfg.line.dl_tail_pct)
      active_dl = $urandom_range(cfg.line.dl_max, cfg.line.dl_fast_max + 1);
    else
      active_dl = $urandom_range(cfg.line.dl_fast_max, 1);
    // Clear FIFOs only during setup so no expected payload has to be discarded here
    // Choose IER and MCR bits independently because their percentages are not a single distribution
    fcr = (cfg.choose_weight(cfg.ctrl.tl_w) << 6) | 8'h01;
    if ($urandom_range(99, 0) < cfg.ctrl.fcr_clear_pct)
      fcr |= $urandom_range(3, 1) << 1;
    ier = 0;
    mcr = 0;
    for (int i = 0; i < 4; i++) begin
      ier[i] = ($urandom_range(99, 0) < cfg.ctrl.ier_bit_pct[i]);
      mcr[i] = ($urandom_range(99, 0) < cfg.ctrl.mcr_bit_pct[i]);
    end

    // Keep DLAB switching and both divisor bytes under the same lock
    // An unrelated address-zero access in the middle would hit DLL instead of THR or RBR
    // Switch the predictor map too so it interprets the observed addresses using the active bank
    cfg.bus_lock.get(1);
    transfer(1, 3, active_lcr | 8'h80, result);
    p_sequencer.predictor.map = p_sequencer.regm.map_dlab1;
    transfer(1, 0, active_dl[7:0], result);
    transfer(1, 1, active_dl[15:8], result);
    transfer(0, 0, 0, result);
    if (result !== active_dl[7:0])
      `uvm_error("UART_DLL", "DLL no coincide con el divisor solicitado")
    transfer(0, 1, 0, result);
    if (result !== active_dl[15:8])
      `uvm_error("UART_DLM", "DLM no coincide con el divisor solicitado")
    transfer(1, 3, active_lcr, result);
    p_sequencer.predictor.map = p_sequencer.regm.map_dlab0;
    transfer(0, 3, 0, result);
    if (result !== active_lcr)
      `uvm_error("UART_LCR", "LCR no coincide con el formato solicitado")
    transfer(1, 2, fcr, result);
    transfer(1, 1, ier, result);
    transfer(1, 4, mcr, result);
    cfg.bus_lock.put(1);

    // Update the shared serial config after programming and before starting traffic
    // The driver and both monitors need the exact same framing as the DUT or comparisons become meaningless
    cfg.ser.wls = active_lcr[1:0];
    cfg.ser.stb = active_lcr[2];
    cfg.ser.pen = active_lcr[3];
    cfg.ser.eps = active_lcr[4];
    cfg.ser.sp = active_lcr[5];
    cfg.ser.dl = active_dl;
    `uvm_info("UART_LINE", $sformatf("LCR=%02h DL=%0d", active_lcr, active_dl), UVM_LOW)
  endtask

  // Write THR to make the DUT transmit -- the serial driver does not drive STX
  // Wait for THRE here because this stage checks normal data rather than deliberate TX overflow
  task send_tx(int unsigned count);
    bit [7:0] lsr;
    bit [7:0] ignored;
    repeat (count) begin
      do begin
        access(0, 5, 0, lsr);
      end while (!lsr[5]);
      access(1, 0, $urandom_range(cfg.sw.tx_data_max, cfg.sw.tx_data_min), ignored);
    end
  endtask

  // Use the serial sequencer for data entering the DUT through SRX
  // Wait after the last frame before marking the source done so RX service does not stop too early
  task send_rx(int unsigned count);
    uart_rx_seq seq;
    seq = uart_rx_seq::type_id::create("rx_traffic");
    seq.cfg = cfg;
    seq.count = count;
    seq.start(p_sequencer.ser_sqr);
    repeat (2 * cfg.ser.bit_cycles()) @(cfg.ser.vif.mon_cb);
    rx_done = 1;
  endtask

  // Keep draining RBR while the external source runs
  // An empty FIFO is not enough to stop -- another character may still be on the wire
  // Delay and blind-read hooks stay disabled until their checking rules are implemented
  task service_rx();
    bit [7:0] lsr;
    bit [7:0] ignored;
    int unsigned delay_chars;
    forever begin
      delay_chars = $urandom_range(cfg.sw.service_delay_max, cfg.sw.service_delay_min);
      repeat (longint'(delay_chars) * char_cycles()) @(cfg.wb.vif.drv_cb);
      access(0, 5, 0, lsr);
      if (lsr[0]) begin
        access(0, 0, 0, ignored);
      end else begin
        if ($urandom_range(99, 0) < cfg.sw.blind_read_pct)
          access(0, 0, 0, ignored);
        if (rx_done)
          break;
      end
    end
  endtask

  // Do setup before launching the workers so nobody uses the reset divisor or the wrong format
  // Choose both counts for each iteration so MIN equals MAX also works without a special path
  task body();
    bit [7:0] lsr;
    int unsigned tx_count;
    int unsigned rx_count;
    cfg = p_sequencer.cfg;
    wait (cfg.wb.vif.rst === 1'b0);
    repeat (3) @(cfg.wb.vif.drv_cb);
    if (cfg.run_ral_reset)
      ral_preamble();
    program_uart();

    repeat (cfg.sw.n_iter) begin
      tx_count = $urandom_range(cfg.sw.tx_burst_max, cfg.sw.tx_burst_min);
      rx_count = $urandom_range(cfg.ser.burst_max, cfg.ser.burst_min);
      planned_tx += tx_count;
      planned_rx += rx_count;
      rx_done = 0;
      `uvm_info("UART_BURST", $sformatf("Objetivo TX=%0d RX=%0d", tx_count, rx_count), UVM_MEDIUM)
      // Run both directions together because the UART can send and receive at the same time
      // Only serialize shared Wishbone accesses -- serial input can keep running independently
      fork
        send_tx(tx_count);
        send_rx(rx_count);
        service_rx();
      join
      // Wait for TEMT rather than just finishing the last THR write
      // The FIFO can be empty while the shift register is still sending the last character
      do begin
        access(0, 5, 0, lsr);
      end while (!lsr[6]);
      repeat (3) @(cfg.wb.vif.drv_cb);
    end
  endtask
endclass : uart_main_vseq
