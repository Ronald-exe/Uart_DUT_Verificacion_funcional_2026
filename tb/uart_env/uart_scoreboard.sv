
// Build expectations from what the monitors actually saw
// A THR write should later appear on STX -- an SRX character should later be read from RBR
// Use sequence counts only as a final cross-check so a missing observation cannot go unnoticed
class uart_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(uart_scoreboard)
  uart_env_cfg cfg;
  // Buffer the monitor outputs so publishing does not have to wait for comparisons
  // Drain everything in one task so callbacks on the same clock do not decide the comparison order
  uvm_tlm_analysis_fifo #(wb_item) wb_in;
  uvm_tlm_analysis_fifo #(ser_item) tx_in;
  uvm_tlm_analysis_fifo #(ser_item) rx_in;
  // Keep TX and RX in separate queues because they are independent data paths
  // Track LCR too -- address zero is only THR or RBR when DLAB is clear
  bit [7:0] tx_queue[$];
  bit [7:0] rx_queue[$];
  bit [7:0] lcr = 8'h03;
  bit last_dr;
  // Check totals as well as payloads because matching every observed byte does not catch a missing byte
  longint unsigned tx_writes;
  longint unsigned tx_compared;
  longint unsigned rx_characters;
  longint unsigned rx_compared;
  longint unsigned empty_reads;
  longint unsigned target_tx;
  longint unsigned target_rx;
  bit targets_set;

  function new(string name = "uart_scoreboard", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  // Create the input FIFOs here so the environment can connect their analysis exports afterward
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(uart_env_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("SCB_NOCFG", "Scoreboard sin configuracion")
    wb_in = new("wb_in", this);
    tx_in = new("tx_in", this);
    rx_in = new("rx_in", this);
  endfunction

  // Use the same byte-lane convention as the adapter
  // The aligned address gives the group -- one-hot SEL picks the byte register inside that group
  function int unsigned index_of(wb_item it);
    int unsigned index;
    case (it.sel)
      4'b1000: index = 0;
      4'b0100: index = 1;
      4'b0010: index = 2;
      4'b0001: index = 3;
      default: begin
        `uvm_error("SCB_SEL", "El modelo E2 requiere un SEL one-hot")
        index = 0;
      end
    endcase
    return {it.adr[4:2], 2'b00} + index;
  endfunction

  // Compare only the selected byte -- the other Wishbone lanes are not part of this register access
  function bit [7:0] byte_of(wb_item it);
    int unsigned index;
    index = index_of(it);
    return it.data[8 * (3 - (index % 4)) +: 8];
  endfunction

  // Mask unused data bits because a 5-bit character cannot carry the upper three bits of a THR write
  function bit [7:0] character_mask(bit [7:0] data);
    return data & (8'hff >> (3 - int'(lcr[1:0])));
  endfunction

  // Only enqueue address-zero writes when DLAB is clear or divisor writes would look like TX data
  // Honor FIFO clears for setup -- clearing active traffic still needs a more complete model
  function void observe_write(wb_item it);
    int unsigned index;
    bit [7:0] data;
    index = index_of(it);
    data = byte_of(it);
    if (index == 3)
      lcr = data;
    else if ((index == 0) && !lcr[7]) begin
      tx_queue.push_back(character_mask(data));
      tx_writes++;
      if (tx_queue.size() > 17)
        `uvm_error("SCB_TX_OVERFLOW", "Trafico fuera del modelo de datos normal E2")
    end else if (index == 2) begin
      if (data[1])
        rx_queue.delete();
      if (data[2])
        tx_queue.delete();
    end
  endfunction

  // Queue the character seen on SRX rather than the item handed to the driver
  // That way a driver that never puts the character on the wire cannot create a valid expectation
  function void observe_rx(ser_item it);
    if (it.parity_err || it.frame_err)
      `uvm_error("SCB_RX_LINE", "El trafico normal RX fue observado con error de linea")
    if (rx_queue.size() >= 16) begin
      `uvm_error("SCB_RX_OVERFLOW", "Overrun fuera del alcance de comparacion de datos E2")
      return;
    end
    rx_queue.push_back(character_mask(it.data));
    rx_characters++;
  endfunction

  // Use DR from LSR to distinguish a valid RBR read from an empty read
  // Consume RX expectations in order because RBR returns the oldest received character
  function void observe_read(wb_item it);
    int unsigned index;
    bit [7:0] expected;
    bit [7:0] actual;
    index = index_of(it);
    actual = byte_of(it);
    if (index == 5)
      last_dr = actual[0];
    if ((index == 0) && !lcr[7]) begin
      // Do not compare the contents of an empty RBR -- that value is not defined by this check
      // If DR was set but there is no observed RX character then something is inconsistent
      if (rx_queue.size() == 0) begin
        if (last_dr)
          `uvm_error("SCB_RX_UNEXPECTED", "RBR entrego un dato sin caracter RX observado")
        else
          empty_reads++;
      end else begin
        expected = rx_queue.pop_front();
        rx_compared++;
        if (actual !== expected)
          `uvm_error("SCB_RX_DATA", $sformatf("RBR esperado=%02h observado=%02h", expected, actual))
        else
          `uvm_info("SCB_RX_MATCH", $sformatf("RBR=%02h", actual), UVM_HIGH)
      end
      last_dr = (rx_queue.size() != 0);
    end
  endfunction

  // Take one expected THR byte per observed STX frame
  // If there is no queued write then the DUT transmitted something we cannot account for
  function void observe_tx(ser_item it);
    bit [7:0] expected;
    if (it.parity_err || it.frame_err)
      `uvm_error("SCB_TX_LINE", "El DUT transmitio una trama con error de linea")
    if (tx_queue.size() == 0) begin
      `uvm_error("SCB_TX_UNEXPECTED", "Caracter TX sin escritura THR observada")
      return;
    end
    expected = tx_queue.pop_front();
    tx_compared++;
    if (character_mask(it.data) !== expected)
      `uvm_error("SCB_TX_DATA", $sformatf("TX esperado=%02h observado=%02h", expected, it.data))
    else
      `uvm_info("SCB_TX_MATCH", $sformatf("TX=%02h", it.data), UVM_HIGH)
  endfunction

  // Wait just past the sampling edge so all monitors can publish for this clock
  // Then drain the FIFOs together instead of depending on which monitor task ran first
  task run_phase(uvm_phase phase);
    wb_item pending[$];
    wb_item wb;
    ser_item serial;
    forever begin
      @(cfg.wb.vif.mon_cb);
      #1ps;
      // Discard stale setup observations when reset is active and restore the tracked LCR value
      // Do not reset totals here -- live reset during traffic is not supported by this model yet
      if (cfg.wb.vif.rst !== 1'b0) begin
        tx_queue.delete();
        rx_queue.delete();
        wb_in.flush();
        tx_in.flush();
        rx_in.flush();
        lcr = 8'h03;
        last_dr = 0;
        continue;
      end
      // Process writes before outgoing frames so a THR write is queued before its comparison
      // Process incoming frames before bus reads so a character observed on this clock is available
      // This ordering only resolves same-clock publications -- it is not a cycle-accurate FIFO model
      pending.delete();
      while (wb_in.try_get(wb))
        pending.push_back(wb);
      foreach (pending[i]) begin
        if (pending[i].we)
          observe_write(pending[i]);
      end
      while (rx_in.try_get(serial))
        observe_rx(serial);
      foreach (pending[i]) begin
        if (!pending[i].we)
          observe_read(pending[i]);
      end
      while (tx_in.try_get(serial))
        observe_tx(serial);
    end
  endtask

  // Use the planned counts to catch traffic that never reached any monitor
  // Do not put planned payloads into the expected queues -- those must come from observations
  function void expect_totals(longint unsigned tx, longint unsigned rx);
    target_tx = tx;
    target_rx = rx;
    targets_set = 1;
  endfunction

  // Look for leftovers and count mismatches even if all completed comparisons passed
  // Otherwise a run could end early and still look successful
  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    if (!targets_set)
      `uvm_error("SCB_NO_TARGETS", "La secuencia principal no completo su presupuesto")
    if ((tx_queue.size() != 0) || (rx_queue.size() != 0) ||
        (wb_in.used() != 0) || (tx_in.used() != 0) || (rx_in.used() != 0))
      `uvm_error("SCB_PENDING", "Quedaron datos sin comparar al terminar")
    if (targets_set && ((tx_writes != target_tx) || (tx_compared != target_tx) ||
                        (rx_characters != target_rx) || (rx_compared != target_rx)))
      `uvm_error("SCB_COUNTS", $sformatf("Objetivo TX/RX=%0d/%0d; THR=%0d TX=%0d RX=%0d RBR=%0d", target_tx, target_rx, tx_writes, tx_compared, rx_characters, rx_compared))
  endfunction

  // Keep totals in a UVM report so they can be filtered with the rest of the log
  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("SCB_SUMMARY", $sformatf("TX comparados=%0d RX comparados=%0d lecturas vacias=%0d", tx_compared, rx_compared, empty_reads), UVM_LOW)
  endfunction
endclass : uart_scoreboard
