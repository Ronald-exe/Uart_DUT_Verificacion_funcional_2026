
//La cobertura funcional se encarga de contar QUE casos ya pasaron en la simulacion (seccion 13 del plan)
//el scoreboard dice si el DUT hizo bien las cosas, la cobertura dice si ya probamos todas las cosas
//Escucha a los mismos monitores que el scoreboard, asi solo cuenta lo que de verdad paso en el DUT
//y no lo que la secuencia intento hacer
//Por ahora tiene 6 covergroups: cg_reg, cg_line_cfg, cg_tx_char, cg_rx_char, cg_lsr y cg_iir
//cg_fifo, cg_reset y cg_modem se agregan el dia que exista su funcion (overrun, reset, modem)
//Hereda de uvm_component porque vive toda la simulacion dentro del ambiente, igual que el scoreboard
class uart_coverage extends uvm_component;

  //Registramos en la fabrica
  `uvm_component_utils(uart_coverage)

  uart_env_cfg cfg; //handle a la configuracion, de ahi sacamos la interfaz para mirar el reloj, el reset y cyc

  //Buzones, igual que en el scoreboard: el monitor deja el item y nosotros lo sacamos en cada ciclo
  uvm_tlm_analysis_fifo #(wb_item) wb_in;   //accesos del bus Wishbone
  uvm_tlm_analysis_fifo #(ser_item) tx_in;  //caracteres que salieron por stx
  uvm_tlm_analysis_fifo #(ser_item) rx_in;  //caracteres que entraron por srx

  //Copias de los registros de formato, las armamos con las escrituras que ve el monitor Wishbone
  //las necesitamos porque el ser_item solo trae el dato, no con que formato viajo
  bit [7:0] lcr = 8'h03;     //valor de reset de LCR (8 bits, 1 parada, sin paridad)
  bit [7:0] dll = 8'h00;     //parte baja del divisor
  bit [7:0] dlm = 8'h00;     //parte alta del divisor
  bit [1:0] fcr_tl = 2'b11;  //copia de FCR[7:6], el nivel de disparo (reset = 14)
  int unsigned idle_cycles;  //ciclos libres (cyc = 0) desde el ultimo acceso, para cp_gap

  //cg_reg: se muestrea en cada acceso Wishbone
  //"with function sample(...)" dice que valores recibe el covergroup cada vez que lo llamamos con sample()
  covergroup cg_reg with function sample(int unsigned addr, bit we, bit dlab, bit [3:0] sel, int unsigned gap);
    //direccion: los 8 registros y los dos de debug (8 y 12, solo existen en el bus de 32 bits)
    cp_addr: coverpoint addr {
      bins regs[] = {[0:7]};  //los [] crean un bin por cada valor: regs[0], regs[1], ... regs[7]
      bins dbg1   = {8};
      bins dbg2   = {12};
    }
    cp_op: coverpoint we {
      bins lectura   = {0};
      bins escritura = {1};
    }
    cp_dlab: coverpoint dlab; //sin llaves UVM crea solo los bins 0 y 1
    cp_sel: coverpoint sel {
      bins un_byte[] = {4'b1000, 4'b0100, 4'b0010, 4'b0001}; //los 4 sel validos, uno por registro del grupo
      bins todos     = {4'b1111};                            //los 4 bytes, lo usan los registros de debug
      bins raro      = {4'b0000, 4'b0011, 4'b0101, 4'b0110, 4'b0111, 4'b1001,
                        4'b1010, 4'b1011, 4'b1100, 4'b1101, 4'b1110}; //cualquier otro (knob sel_odd_pct)
    }
    cp_gap: coverpoint gap {
      bins pegado = {0};      //accesos uno detras del otro, sin ciclos libres
      bins uno    = {1};
      bins corto  = {[2:5]};
    }
    //Cruces: cada direccion leida y escrita, y cada direccion con DLAB en 0 y en 1
    x_addr_op: cross cp_addr, cp_op {
      //los registros de debug son solo de lectura, escribirlos no es un caso que haya que cubrir
      ignore_bins escribir_dbg1 = binsof(cp_addr.dbg1) && binsof(cp_op.escritura);
      ignore_bins escribir_dbg2 = binsof(cp_addr.dbg2) && binsof(cp_op.escritura);
    }
    x_addr_dlab: cross cp_addr, cp_dlab;
  endgroup

  //cg_line_cfg: se muestrea cuando termina una configuracion de linea (escritura a LCR con DLAB = 0)
  //no se muestrea en cada escritura a DLL o DLM porque a la mitad de la configuracion el divisor esta a medias
  //(ej. ya se escribio DLM pero todavia no DLL) y contariamos un DL que nunca se uso
  covergroup cg_line_cfg with function sample(bit bc, int unsigned dl);
    cp_bc: coverpoint bc;   //break TX (LCR[6])
    cp_dl: coverpoint dl {
      bins cero   = {0};          //sin baudios, el UART queda mudo
      bins rapido = {[1:16]};     //la zona rapida
      bins lento  = {[17:65535]}; //la cola lenta
    }
    //cp_busy (reconfigurar con trafico) se agrega con la reconfiguracion con trafico
  endgroup

  //cg_tx_char: se muestrea con cada caracter que salio por stx
  covergroup cg_tx_char with function sample(bit [1:0] wls, bit stb, int unsigned par);
    cp_wls: coverpoint wls {
      bins cinco = {0};
      bins seis  = {1};
      bins siete = {2};
      bins ocho  = {3};
    }
    cp_stb: coverpoint stb {
      bins una_parada  = {0};
      bins dos_paradas = {1};  //2 bits, o 1.5 si el caracter es de 5 bits
    }
    cp_par: coverpoint par {
      bins ninguna = {0};
      bins impar   = {1};
      bins par     = {2};
      bins fija_1  = {3};
      bins fija_0  = {4};
    }
    x_stb_wls: cross cp_stb, cp_wls; //cada largo con 1 y con 2 paradas
    x_par_wls: cross cp_par, cp_wls; //cada largo con cada paridad
  endgroup

  //cg_rx_char: se muestrea con cada caracter que entro por srx, igual que TX pero ademas con el tipo de error
  covergroup cg_rx_char with function sample(bit [1:0] wls, bit stb, int unsigned par, int unsigned err);
    cp_wls: coverpoint wls {
      bins cinco = {0};
      bins seis  = {1};
      bins siete = {2};
      bins ocho  = {3};
    }
    cp_stb: coverpoint stb {
      bins una_parada  = {0};
      bins dos_paradas = {1};
    }
    cp_par: coverpoint par {
      bins ninguna = {0};
      bins impar   = {1};
      bins par     = {2};
      bins fija_1  = {3};
      bins fija_0  = {4};
    }
    //tipo de error que vio el monitor, STOP2 queda pendiente (el DUT lo toma como un bit de inicio nuevo)
    cp_err: coverpoint err {
      bins ninguno = {0};
      bins paridad = {1};
      bins trama   = {2};
      bins brk     = {3};
    }
    x_par_wls: cross cp_par, cp_wls;
    x_err_stb: cross cp_err, cp_stb;
  endgroup

  //cg_lsr: se muestrea en cada lectura de LSR, cada bit en 0 y en 1
  covergroup cg_lsr with function sample(bit [7:0] lsr, bit dlab);
    cp_dr:   coverpoint lsr[0]; //dato listo
    cp_oe:   coverpoint lsr[1]; //overrun
    cp_pe:   coverpoint lsr[2]; //error de paridad
    cp_fe:   coverpoint lsr[3]; //error de trama
    cp_bi:   coverpoint lsr[4]; //break
    cp_thre: coverpoint lsr[5]; //FIFO TX vacia
    cp_temt: coverpoint lsr[6]; //transmisor vacio
    cp_ei:   coverpoint lsr[7]; //hay algun error en la FIFO RX
    cp_dlab: coverpoint dlab;
    x_ei_dlab: cross cp_ei, cp_dlab; //EI leido con DLAB en 0 y en 1 (AMB-14)
  endgroup

  //cg_iir: se muestrea en cada lectura de IIR, que interrupcion reporto el DUT y con que nivel de disparo
  covergroup cg_iir with function sample(bit [3:0] iir, bit [1:0] tl);
    cp_iir_id: coverpoint iir {
      bins rls     = {4'b0110};  //IIR[3:1] = 011 y IIR[0] = 0: error de linea
      bins rda     = {4'b0100};  //010: dato disponible
      bins timeout = {4'b1100};  //110: timeout
      bins thre    = {4'b0010};  //001: THR vacio
      bins ms      = {4'b0000};  //000: modem
      bins ninguna = {4'b0001};  //IIR[0] = 1: no hay nada pendiente
    }
    cp_tl: coverpoint tl {
      bins uno      = {0};
      bins cuatro   = {1};
      bins ocho     = {2};
      bins catorce  = {3};
    }
    //el nivel de disparo solo cambia cuando salta dato disponible o timeout, por eso el cruce ignora las otras
    x_iir_tl: cross cp_iir_id, cp_tl {
      ignore_bins otras = binsof(cp_iir_id.rls) || binsof(cp_iir_id.thre) ||
                          binsof(cp_iir_id.ms) || binsof(cp_iir_id.ninguna);
    }
  endgroup

  //Se crea el constructor, parent es el ambiente
  //los covergroups se crean aqui con new, si no se crean no cuentan nada
  function new(string name = "uart_coverage", uvm_component parent = null);
    super.new(name, parent);
    cg_reg = new();
    cg_line_cfg = new();
    cg_tx_char = new();
    cg_rx_char = new();
    cg_lsr = new();
    cg_iir = new();
  endfunction

  //En build tomamos la configuracion y creamos los buzones, asi el ambiente los puede conectar en su connect_phase
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(uart_env_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("COV_NOCFG", "Cobertura sin configuracion")
    wb_in = new("wb_in", this);
    tx_in = new("tx_in", this);
    rx_in = new("rx_in", this);
  endfunction

  //Saca el numero de registro de un acceso, igual que el scoreboard: el piso sale de adr y la puerta de sel
  //con un sel raro o con 1111 (debug) no hay una puerta, usamos solo el piso
  function int unsigned reg_number(wb_item it);
    case (it.sel)
      4'b1000: return {it.adr[4:2], 2'b00} + 0;
      4'b0100: return {it.adr[4:2], 2'b00} + 1;
      4'b0010: return {it.adr[4:2], 2'b00} + 2;
      4'b0001: return {it.adr[4:2], 2'b00} + 3;
      default: return {it.adr[4:2], 2'b00};
    endcase
  endfunction

  //Saca el byte del registro, del carril que le toca (igual que el scoreboard)
  function bit [7:0] byte_of(wb_item it, int unsigned addr);
    return it.data[8 * (3 - (addr % 4)) +: 8];
  endfunction

  //Traduce los bits de paridad de LCR a un numero para cp_par, con la misma regla del DUT (uart_transmitter.v)
  //  PEN (LCR[3]) = 0: sin paridad
  //  SP  (LCR[5]) = 0: EPS (LCR[4]) dice si es impar (0) o par (1)
  //  SP  (LCR[5]) = 1: paridad fija, EPS = 0 siempre 1 y EPS = 1 siempre 0
  function int unsigned parity_mode();
    if (!lcr[3])
      return 0;
    if (!lcr[5])
      return lcr[4] ? 2 : 1;
    return lcr[4] ? 4 : 3;
  endfunction

  //Traduce las banderas que puso el monitor serie a un numero para cp_err
  function int unsigned error_of(ser_item ch);
    if (ch.brk)
      return 3;
    if (ch.parity_err)
      return 1;
    if (ch.frame_err)
      return 2;
    return 0;
  endfunction

  //Procesa un acceso Wishbone: muestrea cg_reg y actualiza las copias de LCR, DLL y DLM
  function void observe_wb(wb_item it);
    int unsigned addr;
    bit [7:0] value;
    addr = reg_number(it);
    value = byte_of(it, addr);
    //1. todo acceso cuenta para cg_reg, con el DLAB que habia en ese momento
    cg_reg.sample(addr, it.we, lcr[7], it.sel, idle_cycles);
    idle_cycles = 0;
    //2. escrituras: guardamos las copias del formato
    if (it.we) begin
      if (addr == 3) begin
        lcr = value;
        //LCR con DLAB = 0 cierra la configuracion, ahi el divisor ya esta completo
        if (!lcr[7])
          cg_line_cfg.sample(lcr[6], {dlm, dll});
      end else if ((addr == 0) && lcr[7]) begin
        dll = value; //direccion 0 con DLAB = 1 es DLL
      end else if ((addr == 1) && lcr[7]) begin
        dlm = value; //direccion 1 con DLAB = 1 es DLM
      end else if (addr == 2) begin
        fcr_tl = value[7:6]; //escritura a FCR: guardamos el nivel de disparo
      end
    end
    //3. lecturas de LSR (direccion 5, sirve con DLAB en 0 o en 1)
    else if (addr == 5) begin
      cg_lsr.sample(value, lcr[7]);
    end
    //4. lecturas de IIR (direccion 2)
    else if (addr == 2) begin
      cg_iir.sample(value[3:0], fcr_tl);
    end
  endfunction

  //En la fase de run, en cada ciclo sacamos todo de los buzones y muestreamos, igual que el scoreboard
  task run_phase(uvm_phase phase);
    wb_item wb;
    ser_item ch;
    forever begin
      //esperamos un ciclo y un poquito mas (1ps), asi los monitores ya publicaron lo de este ciclo
      @(cfg.wb.vif.mon_cb);
      #1ps;
      //con reset activo volvemos las copias a su valor de reset y botamos lo pendiente
      if (cfg.wb.vif.rst !== 1'b0) begin
        lcr = 8'h03;
        dll = 8'h00;
        dlm = 8'h00;
        fcr_tl = 2'b11;
        idle_cycles = 0;
        wb_in.flush();
        tx_in.flush();
        rx_in.flush();
        continue;
      end
      //1. accesos Wishbone
      while (wb_in.try_get(wb))
        observe_wb(wb);
      //2. caracteres de stx y de srx, con el formato que tiene LCR en este momento
      while (tx_in.try_get(ch))
        cg_tx_char.sample(lcr[1:0], lcr[2], parity_mode());
      while (rx_in.try_get(ch))
        cg_rx_char.sample(lcr[1:0], lcr[2], parity_mode(), error_of(ch));
      //3. contamos los ciclos libres del bus para el siguiente acceso
      if (!cfg.wb.vif.mon_cb.cyc)
        idle_cycles++;
    end
  endtask

  //En report_phase imprimimos el porcentaje de cada covergroup en esta corrida
  //sirve para ver rapido como va sin abrir URG, el numero oficial es el de URG con todas las semillas juntas
  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("COV_SUMMARY", $sformatf("cg_reg=%0.1f%% cg_line_cfg=%0.1f%% cg_tx_char=%0.1f%% cg_rx_char=%0.1f%% cg_lsr=%0.1f%% cg_iir=%0.1f%%",
              cg_reg.get_coverage(), cg_line_cfg.get_coverage(), cg_tx_char.get_coverage(),
              cg_rx_char.get_coverage(), cg_lsr.get_coverage(), cg_iir.get_coverage()), UVM_LOW)
  endfunction

endclass : uart_coverage
