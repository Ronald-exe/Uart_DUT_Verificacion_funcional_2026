class uart_wb_seq extends uvm_sequence #(wb_item);
  `uvm_object_utils(uart_wb_seq)
  uart_env_cfg cfg;
  bit [4:0] reg_index;
  bit write_access;
  bit [7:0] write_data;
  bit [31:0] read_word;
  bit [7:0] read_data;
  bit allow_odd;
  bit aborted;
  function new(string name = "uart_wb_seq");
    super.new(name);
  endfunction
  task body();
    wb_item it;
    int unsigned lane;
    bit [3:0] odd_select[12] = '{0,3,5,6,7,9,10,11,12,13,14,15};
    it = wb_item::type_id::create("access");
    start_item(it);
`ifdef DATA_BUS_WIDTH_8
    it.adr = reg_index;
    it.sel = 1;
    it.data = write_data;
`else
    // The 32-bit bus packs registers big-endian -- LCR at offset 3 uses the low byte, not the high byte -- alex
    lane = 3 - reg_index[1:0];
    it.adr = {reg_index[4:2], 2'b00};
    it.sel = 4'b1000 >> reg_index[1:0];
    it.data = 32'(write_data) << (8 * lane);
    // Debug registers are whole words -- a regular one-byte SEL would select a different decode path -- alex
    if (reg_index inside {8,12}) begin
      it.adr = reg_index;
      it.sel = 15;
    end else if (allow_odd && ($urandom_range(99,0) < cfg.wb.sel_odd_pct)) begin
      it.sel = odd_select[$urandom_range(11,0)];
    end
`endif
    it.we = write_access;
    it.delay = $urandom_range(cfg.wb.delay_max,0);
    it.stb_delay = $urandom_range(cfg.wb.stb_delay_max,0);
    finish_item(it);
    aborted = it.aborted;
    // Reset cancellation is a valid return from the driver, but silence without completion or cancellation is not -- alex
    if (!it.completed && !it.aborted) begin
      `uvm_error("UART_WB_INCOMPLETE", "Bus item returned without completion or reset cancellation")
    end
    read_word = it.data;
`ifdef DATA_BUS_WIDTH_8
    read_data = it.data[7:0];
`else
    case (it.sel)
      8: read_data = it.data[31:24];
      4: read_data = it.data[23:16];
      2: read_data = it.data[15:8];
      default: read_data = it.data[7:0];
    endcase
`endif
  endtask
endclass

class uart_rx_seq extends uvm_sequence #(ser_item);
  `uvm_object_utils(uart_rx_seq)
  uart_env_cfg cfg;
  int unsigned count;
  function new(string name = "uart_rx_seq");
    super.new(name);
  endfunction
  task body();
    ser_item it;
    int unsigned data_low, data_high, gap_high, glitch_high;
    int unsigned pe, fe, bi, stop2, glitch;
    int signed skew_limit;
    bit parity_enabled, two_stops, skew_enabled;
    repeat (count) begin
      data_low = cfg.ser.data_min;
      data_high = cfg.ser.data_max;
      gap_high = cfg.ser.gap_max;
      // Four source clocks per divisor are one quarter of a bit -- keep short glitches inside that planned bound -- alex
      glitch_high = 4 * int'(cfg.ser.source_dl);
      pe = cfg.ser_parity_err_pct;
      fe = cfg.ser_frame_err_pct;
      bi = cfg.ser_break_pct;
      stop2 = cfg.ser_stop2_err_pct;
      glitch = cfg.ser_glitch_pct;
      skew_limit = int'(cfg.ser_baud_err_max);
      parity_enabled = cfg.ser.pen;
      two_stops = cfg.ser.stb && (cfg.ser.wls != 0);
      skew_enabled = ($urandom_range(99,0) < cfg.ser_baud_err_pct);
      it = ser_item::type_id::create("rx_character");
      start_item(it);
      // local:: refers to the sampled knob, not a field of the item being randomized -- alex
      if (!it.randomize() with {
        data inside {[local::data_low:local::data_high]};
        gap inside {[0:local::gap_high]};
        inject_break dist {1 := local::bi, 0 := (100-local::bi)};
        inject_glitch dist {1 := local::glitch, 0 := (100-local::glitch)};
        if (inject_glitch) {
          glitch_cycles inside {[1:local::glitch_high]};
        } else {
          glitch_cycles == 0;
        }
        // There is no parity bit to corrupt when parity is disabled -- a break also takes over the whole waveform -- alex
        if (inject_break || !local::parity_enabled) {
          inject_parity_error == 0;
        } else {
          inject_parity_error dist {1 := local::pe, 0 := (100-local::pe)};
        }
        if (inject_break) {
          inject_frame_error == 0;
        } else {
          inject_frame_error dist {1 := local::fe, 0 := (100-local::fe)};
        }
        // Keep second-stop corruption separate from first-stop errors
        // It only makes sense for 6 to 8 data bits with the extended stop enabled -- alex
        if (inject_break || inject_frame_error || !local::two_stops) {
          inject_stop2_error == 0;
        } else {
          inject_stop2_error dist {1 := local::stop2, 0 := (100-local::stop2)};
        }
        // First choose whether to vary baud, then choose a signed offset
        // Zero is still allowed in this branch -- selecting variation does not force an erroneous frame -- alex
        if (local::skew_enabled) {
          baud_error_pct inside {[-local::skew_limit:local::skew_limit]};
        } else {
          baud_error_pct == 0;
        }
      }) begin
        `uvm_fatal("UART_RANDOMIZE","Serial constraints are inconsistent")
      end
      finish_item(it);
    end
  endtask
endclass

class uart_hw_reset_seq extends uvm_reg_hw_reset_seq;
  `uvm_object_utils(uart_hw_reset_seq)
  virtual wb_if vif;
  function new(string name = "uart_hw_reset_seq");
    super.new(name);
  endfunction
  virtual task reset_blk(uvm_reg_block blk);
    if (vif == null) begin
      `uvm_fatal("UART_RESET_VIF", "Physical reset requires wb_if")
    end
    // Drive reset away from the sampling edge so the DUT and monitors do not race its assertion -- alex
    @(negedge vif.clk);
    vif.rst = 1;
    repeat (5) @(negedge vif.clk);
    vif.rst = 0;
    repeat (3) @(vif.drv_cb);
  endtask
endclass

class uart_modem_seq extends uvm_sequence #(modem_item);
  `uvm_object_utils(uart_modem_seq)
  bit [3:0] pins;
  int unsigned hold_cycles;
  function new(string name = "uart_modem_seq");
    super.new(name);
  endfunction
  task body();
    modem_item it;
    it = modem_item::type_id::create("modem_change");
    start_item(it);
    it.pins = pins;
    it.hold_cycles = hold_cycles;
    finish_item(it);
  endtask
endclass

class uart_main_vseq extends uvm_sequence;
  `uvm_object_utils(uart_main_vseq)
  `uvm_declare_p_sequencer(uart_vsequencer)
  uart_env_cfg cfg;
  bit tx_done, rx_done, control_done, workers_stop;
  bit irq_service;
  bit [7:0] active_lcr;
  bit [15:0] active_dl;
  longint unsigned planned_tx, planned_rx;
  function new(string name = "uart_main_vseq");
    super.new(name);
  endfunction
  function int unsigned char_cycles();
    // Use the source clock retained across DL zero -- service timing must stay finite when the DUT divider is stopped -- alex
    return (1 + cfg.ser.n_bits() + int'(cfg.ser.pen)) * 16 * int'(cfg.ser.source_dl) +
           (!cfg.ser.stb ? 16 : ((cfg.ser.wls == 0) ? 24 : 32)) * int'(cfg.ser.source_dl);
  endfunction
  task transfer(bit wr, bit [4:0] index, bit [7:0] value,
                output bit [7:0] result, input bit allow_odd = 0);
    uart_wb_seq seq;
    seq = uart_wb_seq::type_id::create("wb_access");
    seq.cfg = cfg;
    seq.reg_index = index;
    seq.write_access = wr;
    seq.write_data = value;
    seq.allow_odd = allow_odd;
    seq.start(p_sequencer.wb_sqr);
    result = seq.read_data;
  endtask
  task access(bit wr, bit [4:0] index, bit [7:0] value,
              output bit [7:0] result, input bit allow_odd = 0);
    bit [7:0] ignored;
    cfg.bus_lock.get(1);
    // This helper means normal software service -- force bank zero before touching THR or RBR
    // A deliberate bank operation instead holds the lock and calls transfer directly to avoid locking it twice -- alex
    if (cfg.ser.lcr[7]) begin
      transfer(1,3,cfg.ser.lcr & 'h7f,ignored);
    end
    transfer(wr,index,value,result,allow_odd);
    cfg.bus_lock.put(1);
  endtask
  task prepare_reset_register(uvm_reg reg_handle, uvm_reg_data_t value);
    uvm_status_e status;
    uvm_reg_data_t actual;
    // Change and read back the registers before reset -- otherwise reset values left from startup could give a false pass -- alex
    reg_handle.write(status, value, UVM_FRONTDOOR, p_sequencer.regm.map_dlab0);
    if (status != UVM_IS_OK)
      `uvm_error("UART_RAL_PREPARE", "Fallo al preparar el registro antes del reset")
    repeat (2) @(cfg.wb.vif.drv_cb);
    reg_handle.read(status, actual, UVM_FRONTDOOR, p_sequencer.regm.map_dlab0);
    repeat (2) @(cfg.wb.vif.drv_cb);
    if ((status != UVM_IS_OK) || (actual !== value))
      `uvm_error("UART_RAL_PREPARE", {reg_handle.get_name(), " no tomo el valor previo al reset"})
  endtask

  task ral_preamble();
    uart_hw_reset_seq seq;
    uvm_reg_bit_bash_seq bit_bash;
    uvm_reg_mem_hdl_paths_seq paths;
    uvm_status_e status;
    seq = uart_hw_reset_seq::type_id::create("ral_reset");
    seq.vif = cfg.wb.vif;
    seq.model = p_sequencer.regm;
    prepare_reset_register(p_sequencer.regm.LCR, 8'h1b);
    prepare_reset_register(p_sequencer.regm.IER, 8'h0f);
    prepare_reset_register(p_sequencer.regm.SCR, 8'ha5);
    `uvm_info("UART_RAL_FRONTDOOR", "Comprobando reset por Wishbone", UVM_LOW)
    seq.start(null);
    // Prepare a second non-reset state -- the backdoor check needs its own reset event, not just a reread of the first result -- alex
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
    if (status != UVM_IS_OK) begin
      `uvm_error("UART_RAL_STATUS", "Error backdoor en SCR")
    end
    // Check the registered HDL paths here -- later divisor peeks exercise their custom backdoors separately -- alex
    paths = uvm_reg_mem_hdl_paths_seq::type_id::create("ral_paths");
    paths.model = p_sequencer.regm;
    paths.start(null);
    bit_bash = uvm_reg_bit_bash_seq::type_id::create("ral_bit_bash");
    bit_bash.model = p_sequencer.regm;
    // The resource exclusions in uart_base_test limit this generic bit test to LCR, IER and SCR -- alex
    bit_bash.start(null);
    // Restore reset state after bit-bash -- its last write is test stimulus, not the starting UART configuration -- alex
    seq.reset_blk(p_sequencer.regm);
    p_sequencer.regm.reset();
  endtask


  task program_register(uvm_reg register_handle, bit [7:0] value, uvm_reg_map selected_map);
    uvm_status_e status;
    register_handle.write(status,value,UVM_FRONTDOOR,selected_map);
    if (status != UVM_IS_OK) begin
      `uvm_error("UART_RAL_WRITE",{"Programming failed for ",register_handle.get_name()})
    end
  endtask

  task program_uart();
    int unsigned parity_mode;
    int unsigned pick;
    bit [7:0] ignored;
    bit [7:0] fcr_value;
    bit [7:0] ier_value;
    bit [7:0] mcr_value;
    uvm_status_e backdoor_status;
    uvm_reg_data_t backdoor_value;
    // The weight helper returns an array index -- WLS and stop indices map directly into LCR, parity needs the translation below -- alex
    active_lcr = cfg.choose_weight(cfg.line.wls_w) | (cfg.choose_weight(cfg.line.stb_w) << 2);
    parity_mode = cfg.choose_weight(cfg.line.par_w);
    case (parity_mode)
      1: active_lcr |= 'h08;
      2: active_lcr |= 'h18;
      3: active_lcr |= 'h28;
      4: active_lcr |= 'h38;
    endcase
    if ($urandom_range(99,0) < cfg.line.bc_pct) begin
      active_lcr[6] = 1;
    end
    // Use one draw for zero, fast and tail regions so their probabilities do not overlap -- alex
    pick = $urandom_range(99,0);
    if (pick < cfg.line.dl_zero_pct) begin
      active_dl = 0;
    end else if (pick < cfg.line.dl_zero_pct + cfg.line.dl_tail_pct) begin
      active_dl = $urandom_range(cfg.line.dl_max,cfg.line.dl_fast_max+1);
    end else begin
      active_dl = $urandom_range(cfg.line.dl_fast_max,1);
    end
    fcr_value = (cfg.choose_weight(cfg.ctrl.tl_w) << 6) | 1;
    if ($urandom_range(99,0) < cfg.ctrl.fcr_clear_pct) begin
      // The clear event chooses RX, TX or both -- selecting neither is already covered by not taking this branch -- alex
      fcr_value |= $urandom_range(3,1) << 1;
    end
    ier_value = 0;
    mcr_value = 0;
    for (int i = 0; i < 4; i++) begin
      ier_value[i] = ($urandom_range(99,0) < cfg.ctrl.ier_bit_pct[i]);
      mcr_value[i] = ($urandom_range(99,0) < cfg.ctrl.mcr_bit_pct[i]);
    end
    mcr_value[4] = ($urandom_range(99,0) < cfg.ctrl.loop_pct);
    cfg.bus_lock.get(1);
    // Keep DLAB set across both divisor bytes and restore it before normal control writes
    // The bus lock spans this whole group so service cannot mistake a divisor access for RBR or THR -- alex
    program_register(p_sequencer.regm.LCR,active_lcr | 'h80,p_sequencer.regm.map_dlab0);
    program_register(p_sequencer.regm.DLL,active_dl[7:0],p_sequencer.regm.map_dlab1);
    program_register(p_sequencer.regm.DLM,active_dl[15:8],p_sequencer.regm.map_dlab1);
    program_register(p_sequencer.regm.LCR,active_lcr,p_sequencer.regm.map_dlab0);
    program_register(p_sequencer.regm.FCR,fcr_value,p_sequencer.regm.map_dlab0);
    program_register(p_sequencer.regm.IER,ier_value,p_sequencer.regm.map_dlab0);
    program_register(p_sequencer.regm.MCR,mcr_value,p_sequencer.regm.map_dlab0);
    // ACK proves the bus transaction completed -- peek checks that the requested divisor actually reached storage -- alex
    p_sequencer.regm.DLL.peek(backdoor_status,backdoor_value);
    if ((backdoor_status != UVM_IS_OK) || (backdoor_value[7:0] !== active_dl[7:0])) begin
      `uvm_error("UART_DLL_BACKDOOR","DLL frontdoor programming did not match its HDL value")
    end
    p_sequencer.regm.DLM.peek(backdoor_status,backdoor_value);
    if ((backdoor_status != UVM_IS_OK) || (backdoor_value[7:0] !== active_dl[15:8])) begin
      `uvm_error("UART_DLM_BACKDOOR","DLM frontdoor programming did not match its HDL value")
    end
    cfg.bus_lock.put(1);
    `uvm_info("UART_LINE", $sformatf("LCR=%02h DL=%0d FCR=%02h IER=%02h MCR=%02h",active_lcr,active_dl,fcr_value,ier_value,mcr_value),UVM_LOW)
  endtask

  task send_tx(int unsigned count);
    bit [7:0] ignored;
    repeat (count) begin
      // Do not wait for THRE between these writes -- throttling here would prevent the full-FIFO scenarios -- alex
      access(1,0,$urandom_range(cfg.sw.tx_data_max,cfg.sw.tx_data_min),ignored,1);
    end
    tx_done = 1;
  endtask
  task send_rx(int unsigned count);
    uart_rx_seq seq;
    seq = uart_rx_seq::type_id::create("rx_traffic");
    seq.cfg = cfg;
    seq.count = count;
    seq.start(p_sequencer.ser_sqr);
    rx_done = 1;
  endtask

  task random_register_access();
    bit [7:0] ignored;
    bit [7:0] saved_control;
    bit bank;
    bit wr;
    int unsigned index;
    cfg.bus_lock.get(1);
    // Keep other LCR bits when selecting the temporary bank -- this access is testing registers, not requesting a new format -- alex
    saved_control = cfg.ser.lcr;
    bank = $urandom_range(1,0);
    transfer(1,3,{bank,saved_control[6:0]},ignored);
`ifdef DATA_BUS_WIDTH_8
    index = $urandom_range(7,0);
`else
    index = $urandom_range(9,0);
    if (index == 9) begin
      index = 12;
    end
`endif
    wr = $urandom_range(1,0);
    transfer(wr,5'(index),$urandom_range(255,0),ignored,1);
    // The random write may itself have changed LCR -- clear its current DLAB bit instead of restoring a stale format -- alex
    transfer(1,3,cfg.ser.lcr & 'h7f,ignored);
    cfg.bus_lock.put(1);
  endtask

  task service_rx();
    bit [7:0] lsr;
    bit [7:0] iir;
    bit [7:0] ignored;
    int unsigned delay_chars;
    forever begin
      if (workers_stop) begin
        return;
      end
      // IRQ mode waits without polling registers -- those reads could acknowledge the source before we service it -- alex
      if (irq_service && (cfg.wb.vif.irq !== 1)) begin
        @(cfg.wb.vif.drv_cb);
        continue;
      end
      // Deliberately leave received data unserviced -- immediate reads would hide timeout and overrun behavior -- alex
      delay_chars = $urandom_range(cfg.sw.service_delay_max,cfg.sw.service_delay_min);
      repeat (longint'(delay_chars) * char_cycles()) @(cfg.wb.vif.drv_cb);
      access(0,2,0,iir);
      access(0,5,0,lsr);
      access(0,6,0,ignored);
      // A blind read is allowed even with DR clear -- its unspecified payload is handled by the scoreboard, not filtered here -- alex
      if (lsr[0] || ($urandom_range(99,0) < cfg.sw.blind_read_pct)) begin
        access(0,0,0,ignored);
      end
      if ($urandom_range(99,0) < cfg.sw.rand_access_pct) begin
        random_register_access();
      end
    end
  endtask
  task modem_traffic();
    uart_modem_seq seq;
    bit [3:0] pins;
    pins = {cfg.mdm_vif.dcd,cfg.mdm_vif.ri,cfg.mdm_vif.dsr,cfg.mdm_vif.cts};
    while (!workers_stop) begin
      for (int i = 0; i < 4; i++) begin
        if ($urandom_range(99,0) < cfg.mdm.toggle_pct) begin
          pins[i] = ~pins[i];
        end
      end
      seq = uart_modem_seq::type_id::create("modem_traffic");
      seq.pins = pins;
      // Leave time between pin changes -- changing every clock would collapse unrelated modem events into the same service window -- alex
      seq.hold_cycles = $urandom_range(char_cycles(),1);
      seq.start(p_sequencer.mdm_sqr);
    end
  endtask
  task live_control(int unsigned span);
    bit do_reset;
    bit do_reconfigure;
    // These are independent events -- a single iteration may reconfigure and later reset, rather than choosing only one -- alex
    do_reset = ($urandom_range(99,0) < cfg.sw.rst_pct);
    do_reconfigure = ($urandom_range(99,0) < cfg.sw.recfg_pct);
    if (do_reconfigure) begin
      repeat ($urandom_range(span,0)) @(cfg.wb.vif.drv_cb);
      program_uart();
    end
    if (do_reset) begin
      repeat ($urandom_range(span,0)) @(cfg.wb.vif.drv_cb);
      // Reset must be able to interrupt an access -- taking the bus lock first would prevent that scenario -- alex
      @(negedge cfg.wb.vif.clk);
      cfg.wb.vif.rst = 1;
      repeat ($urandom_range(8,2)) @(negedge cfg.wb.vif.clk);
      // Release reset before program_uart takes the bus lock
      // An interrupted bus owner must be able to finish cancellation and release that lock first -- alex
      cfg.wb.vif.rst = 0;
      program_uart();
    end
    control_done = 1;
  endtask
  task stop_after_sources();
    wait (tx_done && rx_done && control_done);
    // Keep servicing long enough to expose a receive timeout even after a short burst finishes -- alex
    repeat (longint'(4 + cfg.sw.service_delay_max) * char_cycles()) @(cfg.wb.vif.drv_cb);
    workers_stop = 1;
  endtask
  task drain();
    bit [7:0] lsr;
    bit [7:0] ignored;
    bit [7:0] control;
    control = cfg.ser.lcr;
    if (cfg.ser.dl == 0) begin
      // A stopped baud generator cannot drain TX -- exercise and account for an explicit FIFO clear instead -- alex
      access(1,2,7,ignored);
      repeat (8) @(cfg.wb.vif.drv_cb);
      return;
    end
    // Wait for TEMT, not only THRE -- an empty FIFO can still have a character in the serializer -- alex
    do begin
      access(0,5,0,lsr);
    end while (!lsr[6]);
    if (control[6]) begin
      // Release transmit break before the final RX drain -- a looped-back low line can still be holding the receiver in break -- alex
      access(1,3,control & 'hbf,ignored);
    end
    // Allow the receiver path to settle after the transmitter and break control finish before deciding RBR is drained -- alex
    repeat (2 * 16 * int'(cfg.ser.source_dl)) @(cfg.wb.vif.drv_cb);
    do begin
      access(0,5,0,lsr);
      if (lsr[0]) begin
        access(0,0,0,ignored);
      end
    end while (lsr[0]);
    access(0,2,0,ignored);
    access(0,6,0,ignored);
    repeat (32) @(cfg.wb.vif.drv_cb);
  endtask
  task body();
    int unsigned tx_count;
    int unsigned rx_count;
    int unsigned span;
    cfg = p_sequencer.cfg;
    wait (cfg.wb.vif.rst === 0);
    repeat (3) @(cfg.wb.vif.drv_cb);
    if (cfg.run_ral_reset) begin
      ral_preamble();
    end
    repeat (cfg.sw.n_iter) begin
      program_uart();
      irq_service = (cfg.choose_weight(cfg.sw.mode_w) == 0);
      tx_count = $urandom_range(cfg.sw.tx_burst_max,cfg.sw.tx_burst_min);
      rx_count = $urandom_range(cfg.ser.burst_max,cfg.ser.burst_min);
      // Count requested traffic separately from delivered bytes -- reset, overflow and FIFO clear can legally discard requests -- alex
      planned_tx += tx_count;
      planned_rx += rx_count;
      tx_done = 0;
      rx_done = 0;
      control_done = 0;
      workers_stop = 0;
      span = char_cycles() * ((tx_count > rx_count) ? tx_count+1 : rx_count+1);
      `uvm_info("UART_BURST",$sformatf("TX requests=%0d RX requests=%0d service=%s",tx_count,rx_count,irq_service ? "IRQ" : "polling"),UVM_LOW)
      // Service stays alive after the sources finish -- stop_after_sources supplies the timeout tail and stops both background workers
      // join waits for those workers too, so the next iteration cannot reconfigure underneath traffic from this one -- alex
      fork
        send_tx(tx_count);
        send_rx(rx_count);
        service_rx();
        modem_traffic();
        live_control(span);
        stop_after_sources();
      join
      drain();
    end
  endtask
endclass
