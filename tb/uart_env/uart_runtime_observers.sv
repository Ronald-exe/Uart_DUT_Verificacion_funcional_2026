typedef class uart_dlab_predictor;

class uart_line_observer extends uvm_subscriber #(wb_item);
  `uvm_component_utils(uart_line_observer)
  uart_env_cfg cfg;
  uart_reg_block regm;
  uvm_reg_predictor #(wb_item) predictor;
  function new(string name = "uart_line_observer", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  function int unsigned reg_index(wb_item it);
`ifdef DATA_BUS_WIDTH_8
    return it.adr;
`else
    case (it.sel)
      8: return {it.adr[4:2], 2'b00};
      4: return {it.adr[4:2], 2'b01};
      2: return {it.adr[4:2], 2'b10};
      1: return {it.adr[4:2], 2'b11};
      default: return {it.adr[4:2], 2'b00};
    endcase
`endif
  endfunction
  function byte unsigned data_byte(wb_item it);
`ifdef DATA_BUS_WIDTH_8
    return it.data[7:0];
`else
    case (it.sel)
      8: return it.data[31:24];
      4: return it.data[23:16];
      2: return it.data[15:8];
      default: return it.data[7:0];
    endcase
`endif
  endfunction
  virtual function void write(wb_item t);
    int unsigned index;
    bit [7:0] value;
    index = reg_index(t);
    value = data_byte(t);
    // Take framing from completed writes, including random raw accesses -- sequence intent can be cancelled by reset -- alex
    if (t.we) begin
      case (index)
        // Offset zero is a divisor write only with DLAB set -- a THR write must not change the serial bit period -- alex
        0: if (cfg.ser.lcr[7]) begin
          if (cfg.ser.dl[7:0] != value) begin
            // Even if a frame is already being decoded, a changed divisor makes that observation partial
            // The epoch lets the monitor cancel it without teaching the monitor which new data should be expected -- alex
            cfg.ser.epoch++;
          end
          cfg.ser.dl[7:0] = value;
        end
        1: if (cfg.ser.lcr[7]) begin
          if (cfg.ser.dl[15:8] != value) begin
            cfg.ser.epoch++;
          end
          cfg.ser.dl[15:8] = value;
        end
        3: cfg.ser.set_lcr(value);
        4: begin
          if (cfg.ser.mcr != value[4:0]) begin
            cfg.ser.epoch++;
          end
          cfg.ser.mcr = value[4:0];
        end
      endcase
      // DL zero stops the DUT, not the remote device -- retain the last usable source period across that write -- alex
      if (cfg.ser.dl != 0) begin
        cfg.ser.source_dl = cfg.ser.dl;
      end
    end
  endfunction
  task run_phase(uvm_phase phase);
    forever begin
      // A reset can arrive with no completed bus transaction -- observing writes alone would miss this change -- alex
      @(posedge cfg.wb.vif.rst);
      cfg.ser.set_lcr(3);
      cfg.ser.dl = 0;
      cfg.ser.mcr = 0;
      cfg.ser.epoch++;
      regm.reset();
      // Reset both the visible map and the predictor bank bit -- resetting only the mirror leaves the next access in the old bank -- alex
      predictor.map = regm.map_dlab0;
      begin
        uart_dlab_predictor typed_predictor;
        if ($cast(typed_predictor,predictor)) begin
          typed_predictor.dlab = 0;
        end
      end
    end
  endtask
endclass

class uart_dlab_predictor extends uvm_reg_predictor #(wb_item);
  `uvm_component_utils(uart_dlab_predictor)
  uart_reg_block regm;
  bit dlab;
  function new(string name = "uart_dlab_predictor", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  virtual function void write(wb_item tr);
    uvm_reg_bus_op access;
    adapter.bus2reg(tr, access);
    map = dlab ? regm.map_dlab1 : regm.map_dlab0;
    // Predict this access using the bank that existed before it
    // Only afterward does an LCR write select the bank for subsequent transactions -- alex
    super.write(tr);
    if (tr.we && (access.addr == 3)) begin
      dlab = access.data[7];
    end
    map = dlab ? regm.map_dlab1 : regm.map_dlab0;
  endfunction
endclass

class uart_irq_sample extends uvm_sequence_item;
  `uvm_object_utils(uart_irq_sample)
  logic irq;
  logic baud;
  logic reset;
  logic srx;
  logic stx;
  logic rts;
  logic dtr;
  logic [3:0] pins;
  // Keep raw bus pins as well as completed transactions -- register strobes precede ACK, so side effects need the earlier timing -- alex
  logic wb_cyc;
  logic wb_stb;
  logic wb_we;
  logic [4:0] wb_adr;
  logic [3:0] wb_sel;
  logic [31:0] wb_data;
  longint unsigned cycle;
  function new(string name = "uart_irq_sample");
    super.new(name);
  endfunction
endclass

class uart_int_monitor extends uvm_monitor;
  `uvm_component_utils(uart_int_monitor)
  uart_env_cfg cfg;
  uvm_analysis_port #(uart_irq_sample) ap;
  function new(string name = "uart_int_monitor", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
  endfunction
  task run_phase(uvm_phase phase);
    uart_irq_sample sample;
    longint unsigned cycles;
    cycles = 0;
    forever begin
      @(cfg.wb.vif.mon_cb);
      // Publish every clock, including idle clocks -- otherwise missing baud ticks or delayed IRQ changes would have no samples to check -- alex
      sample = uart_irq_sample::type_id::create("observed_irq_baud");
      sample.cycle = cycles++;
      sample.irq = cfg.wb.vif.mon_cb.irq;
      sample.baud = cfg.ser.vif.mon_cb.baud;
      sample.reset = cfg.wb.vif.mon_cb.rst;
      sample.wb_cyc = cfg.wb.vif.mon_cb.cyc;
      sample.wb_stb = cfg.wb.vif.mon_cb.stb;
      sample.wb_we = cfg.wb.vif.mon_cb.we;
      sample.wb_adr = cfg.wb.vif.mon_cb.adr;
      sample.wb_sel = cfg.wb.vif.mon_cb.sel;
      sample.wb_data = cfg.wb.vif.mon_cb.dat_m2s;
      sample.srx = cfg.ser.vif.mon_cb.srx;
      sample.stx = cfg.ser.vif.mon_cb.stx;
      sample.rts = cfg.mdm_vif.mon_cb.rts;
      sample.dtr = cfg.mdm_vif.mon_cb.dtr;
      // Use the same DCD, RI, DSR, CTS ordering as the modem item and reference model -- a swapped bit looks like a modem bug -- alex
      sample.pins = {cfg.mdm_vif.mon_cb.dcd, cfg.mdm_vif.mon_cb.ri,
                     cfg.mdm_vif.mon_cb.dsr, cfg.mdm_vif.mon_cb.cts};
      ap.write(sample);
    end
  endtask
endclass
