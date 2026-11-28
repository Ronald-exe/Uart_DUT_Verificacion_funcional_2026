
//El scoreboard se encarga de comparar lo que el DUT hizo contra lo que deberia hacer
//Arma lo esperado con lo que vieron los monitores, no con lo que pidio la secuencia:
//  TX: cada escritura a THR deberia salir despues por stx
//  RX: cada caracter que entro por srx deberia leerse despues en RBR
//Las cantidades que planeo la secuencia solo se usan al final para revisar que no falto ninguna observacion
//Hereda de uvm_scoreboard porque es el componente que hace las comparaciones
class uart_scoreboard extends uvm_scoreboard;

  //Registramos en la fabrica
  `uvm_component_utils(uart_scoreboard)

  uart_env_cfg cfg; //handle a la configuracion, de ahi sacamos la interfaz para mirar el reloj y el reset

  //Entradas: uvm_tlm_analysis_fifo es como un buzon, el monitor deja el item y el scoreboard lo saca cuando quiere
  //asi el monitor no tiene que esperar a que se compare, y nosotros sacamos todo en un solo lugar en el orden que queremos
  uvm_tlm_analysis_fifo #(wb_item) wb_in;   //accesos del bus Wishbone
  uvm_tlm_analysis_fifo #(ser_item) tx_in;  //caracteres que salieron por stx
  uvm_tlm_analysis_fifo #(ser_item) rx_in;  //caracteres que entraron por srx
  uvm_tlm_analysis_fifo #(modem_item) mdm_in; //cambios en los pines de modem (monitor de modem)

  //Colas de lo esperado, TX y RX van separadas porque son caminos independientes
  //son colas porque las FIFOs del UART tambien sacan los datos en orden (el primero que entra es el primero que sale)
  bit [7:0] tx_queue[$]; //bytes escritos en THR que todavia no han salido por stx
  bit [7:0] rx_queue[$]; //caracteres que entraron por srx y todavia no se han leido de RBR
  bit [7:0] lcr = 8'h03; //copia de LCR, la direccion 0 solo es THR/RBR cuando DLAB = 0 (si no es DLL)
  bit last_dr;           //ultimo valor de DR (LSR[0]) que leyo el software
  bit loop;              //copia de MCR[4]: en loopback lo que se escribe en THR vuelve a RBR y no sale por stx
  bit [1:0] mcr_rts_dtr; //copia de MCR[1:0] = {RTS, DTR}, para revisar los pines RTS y DTR (BUG-01)
  bit [3:0] ier;         //copia de IER: que interrupciones estan habilitadas
  bit [1:0] fcr_tl = 2'b11; //copia de FCR[7:6], el nivel de disparo (reset = 14 caracteres)

  //Modelo de LSR (seccion 10 del plan): errores de cada caracter RX y lo que el DUT puede mostrar
  //los 3 bits van en el mismo orden que LSR[4:2] = {BI, FE, PE}, asi se comparan directo con la lectura
  bit [2:0] rx_flags[$]; //errores de cada caracter de rx_queue, en el mismo orden (el frente es el proximo en leerse)
  bit [2:0] possible;    //errores que LSR puede mostrar en la proxima lectura: los de la FIFO o los que llegaron desde la ultima
  bit [2:0] lsr_seen;    //errores que mostro LSR desde la ultima lectura de RBR
  bit oe_possible;       //1 si hubo overrun desde la ultima lectura de LSR (OE se puede mostrar)

  //Modelo de MSR (seccion 10 del plan): los 4 bits van en el mismo orden que MSR, {DCD, RI, DSR, CTS}
  bit [3:0] pins = 4'b1111;  //valor de los pines de entrada que vio el monitor de modem (en reposo estan en 1)
  bit [3:0] msr_delta;       //deltas esperados {DDCD, TERI, DDSR, DCTS} desde la ultima lectura de MSR
  longint unsigned cycle;           //ciclos desde el inicio, para la ventana de los sincronizadores
  longint unsigned last_pin_change; //ciclo del ultimo cambio en los pines de entrada
  longint unsigned last_overrun;    //ciclo del ultimo overrun que vio el modelo
  bit traffic_seen;      //1 cuando ya hubo trafico (una escritura a THR o un caracter por srx)
  bit cut_by_reset;      //1 si llego un reset despues del trafico: lo que vean los monitores despues es el caracter cortado

  //Contadores, no basta con comparar cada byte, tambien hay que revisar que no falte ninguno
  longint unsigned tx_writes;     //escrituras a THR vistas
  longint unsigned tx_compared;   //caracteres TX comparados
  longint unsigned rx_characters; //caracteres RX vistos en srx
  longint unsigned rx_compared;   //lecturas de RBR comparadas
  longint unsigned empty_reads;   //lecturas de RBR con la FIFO vacia
  longint unsigned lsr_checked;   //lecturas de LSR revisadas
  longint unsigned iir_checked;   //lecturas de IIR revisadas
  longint unsigned overruns;      //caracteres que llegaron con la FIFO RX llena
  longint unsigned rx_lost;       //caracteres RX que se perdieron por overrun (no se van a leer)
  longint unsigned msr_checked;   //lecturas de MSR revisadas
  longint unsigned tx_breaks;     //breaks vistos en stx con LCR[6] = 1
  longint unsigned tx_cut;        //bytes escritos en THR que un reset corto antes de salir completos
  longint unsigned err_chars;     //caracteres RX con error que se leyeron de RBR
  longint unsigned err_missed;    //de esos, cuantos LSR nunca marco (chequeo B)
  longint unsigned err_missed_seq;//de los no marcados, cuantos venian justo despues de otro con el mismo error
  bit [2:0] last_flags;           //errores del ultimo caracter leido de RBR, para el conteo anterior
  longint unsigned target_tx;     //TX que planeo la secuencia
  longint unsigned target_rx;     //RX que planeo la secuencia
  bit targets_set;                //1 cuando la prueba ya nos dio los totales

  //Se crea el constructor, parent es el ambiente
  function new(string name = "uart_scoreboard", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  //En build tomamos la configuracion y creamos los buzones, asi el ambiente los puede conectar en su connect_phase
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(uart_env_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("SCB_NOCFG", "Scoreboard sin configuracion")
    wb_in = new("wb_in", this);
    tx_in = new("tx_in", this);
    rx_in = new("rx_in", this);
    mdm_in = new("mdm_in", this);
  endfunction

  //Saca el numero de registro de un acceso, igual que el adaptador: el piso sale de adr y la puerta de sel
  function int unsigned index_of(wb_item it);
    int unsigned index;
    case (it.sel)
      4'b1000: index = 0;
      4'b0100: index = 1;
      4'b0010: index = 2;
      4'b0001: index = 3;
      4'b1111: index = 0; //registros de debug (direcciones 8 y 12): no se comparan, solo se leen
      default: begin
        //en E2 solo se usan sel con un bit en 1, un sel raro aqui seria un error
        `uvm_error("SCB_SEL", "El modelo E2 requiere un SEL one-hot")
        index = 0;
      end
    endcase
    return {it.adr[4:2], 2'b00} + index; //numero del registro = piso + puerta
  endfunction

  //Saca el byte del carril que marca sel, los otros carriles del bus no son parte de este registro
  function bit [7:0] byte_of(wb_item it);
    int unsigned index;
    index = index_of(it);
    return it.data[8 * (3 - (index % 4)) +: 8];
  endfunction

  //Borra los bits de arriba que no caben en el caracter, ej. con 5 bits de dato los 3 bits altos de THR no se transmiten
  function bit [7:0] character_mask(bit [7:0] data);
    return data & (8'hff >> (3 - int'(lcr[1:0])));
  endfunction

  //Procesa una escritura que vio el monitor Wishbone
  function void observe_write(wb_item it);
    int unsigned index;
    bit [7:0] data;
    index = index_of(it);
    data = byte_of(it);
    if (index == 3)
      lcr = data; //escritura a LCR: guardamos la copia
    //escritura a MCR: guardamos el bit de loopback
    else if (index == 4) begin
      loop = data[4];
      mcr_rts_dtr = data[1:0];
    end
    //escritura a IER (direccion 1 con DLAB = 0): guardamos que interrupciones estan habilitadas
    else if ((index == 1) && !lcr[7])
      ier = data[3:0];
    //Loopback: una escritura a THR (direccion 0 con DLAB = 0) vuelve por adentro a la FIFO RX
    //se espera leerla de RBR igual que un caracter que entro por srx, sin errores de linea
    else if ((index == 0) && !lcr[7] && loop) begin
      traffic_seen = 1;
      rx_queue.push_back(character_mask(data));
      rx_flags.push_back(3'b000);
      rx_characters++;
    end
    //escritura a la direccion 0 con DLAB = 0 es THR: el byte va a la cola TX
    //con DLAB = 1 es DLL, por eso se revisa lcr[7], si no el divisor pareceria un dato TX
    else if ((index == 0) && !lcr[7]) begin
      traffic_seen = 1;
      tx_queue.push_back(character_mask(data));
      tx_writes++;
      //la FIFO TX es de 16 (17 contando el que se esta transmitiendo), en E2 no se modela llenarla
      if (tx_queue.size() > 17)
        `uvm_error("SCB_TX_OVERFLOW", "Trafico fuera del modelo de datos normal E2")
    end else if (index == 2) begin
      //escritura a FCR: guardamos el nivel de disparo y si pide limpiar una FIFO, tambien limpiamos su cola
      //solo se usa al configurar, limpiar con trafico necesita un modelo mas completo
      fcr_tl = data[7:6];
      if (data[1]) begin
        rx_queue.delete();
        rx_flags.delete();
      end
      if (data[2])
        tx_queue.delete();
    end
  endfunction

  //Procesa un caracter que entro por srx
  //lo esperado sale de lo que vio el monitor en la linea y no de lo que se le pidio al driver
  //asi un driver que nunca mando el caracter no puede crear algo esperado falso
  //un caracter con error de paridad o de trama igual entra a la FIFO con su dato, solo se marca en LSR
  //un break entra como un caracter 0 (uart_receiver.v linea 402), el monitor ya lo entrega con data = 0
  function void observe_rx(ser_item it);
    //Un glitch no es un caracter (AMB-13), el DUT lo descarta y nosotros tambien, solo lo cuenta cobertura
    if (it.glitch)
      return;

    //Overrun: la FIFO RX es de 16, si llega otro caracter con la FIFO llena se pierde uno y LSR marca OE
    //BUG-04 (AMB-10): la especificacion dice que se pierde el NUEVO y la FIFO queda igual,
    //pero el DUT escribe el dato nuevo encima del mas viejo (uart_rfifo.v, la memoria se escribe con we(push) aunque este llena)
    //  - si el BUG-04 esta dispensado seguimos al RTL: el dato del frente se cambia por el nuevo (sus errores quedan igual)
    //  - si no, seguimos la especificacion: el nuevo se descarta, y al leer RBR el DUT entrega otro dato -> SCB_RX_DATA
    if (rx_queue.size() >= 16) begin
      overruns++;
      rx_characters++;
      rx_lost++;
      oe_possible = 1;
      last_overrun = cycle;
      if (cfg.scb.waived(4)) begin
        `uvm_warning("SCB_OVERRUN", $sformatf("BUG-04 (dispensado): overrun, el dato %02h pisa al mas viejo %02h", character_mask(it.data), rx_queue[0]))
        rx_queue[0] = character_mask(it.data);
      end else begin
        `uvm_info("SCB_OVERRUN", $sformatf("Overrun: segun la especificacion se pierde el dato nuevo %02h", character_mask(it.data)), UVM_LOW)
      end
      return;
    end
    traffic_seen = 1;
    rx_queue.push_back(character_mask(it.data));
    //guardamos sus errores en el mismo orden, {BI, FE, PE} igual que LSR[4:2]
    rx_flags.push_back({it.brk, it.frame_err, it.parity_err});
    possible |= {it.brk, it.frame_err, it.parity_err};
    rx_characters++;
  endfunction

  //Procesa una lectura que vio el monitor Wishbone
  function void observe_read(wb_item it);
    int unsigned index;
    bit [7:0] expected;
    bit [7:0] actual;
    index = index_of(it);
    actual = byte_of(it);
    if (index == 5) begin
      last_dr = actual[0]; //lectura de LSR: guardamos DR, nos dice si habia dato listo
      check_lsr(actual);
    end
    if (index == 2)
      check_iir(actual); //lectura de IIR: revisamos que la interrupcion que reporta tenga sentido
    if (index == 6)
      check_msr(actual); //lectura de MSR: estado y deltas del modem
    //lectura de la direccion 0 con DLAB = 0 es RBR: se compara con el mas viejo de la cola RX
    if ((index == 0) && !lcr[7]) begin //¿este acceso fue a THR/RBR?
      if (rx_queue.size() == 0) begin
        //la cola esta vacia: el valor de RBR no esta definido (AMB-11) asi que no se compara
        //pero si el software vio DR = 1 y no habia nada que leer, algo esta mal
        //BUG-07: si una lectura ciega cae justo cuando llega un caracter, el DUT deja DR en 1 con la FIFO vacia
        //(uart_rfifo.v linea 266 no cambia la cuenta con push y pop a la vez; uart_regs.v linea 611 solo apaga DR con cuenta 1)
        if (last_dr) begin
          if (cfg.scb.waived(7))
            `uvm_warning("SCB_RX_UNEXPECTED", "BUG-07 (dispensado): LSR dice DR = 1 con la FIFO RX vacia")
          else
            `uvm_error("SCB_RX_UNEXPECTED", "BUG-07: LSR dice DR = 1 pero no hay ningun caracter en la FIFO RX")
        end else begin
          empty_reads++;
        end
      end else begin
        expected = rx_queue.pop_front(); //pop_front saca el primero de la cola
        //Lectura ciega (AMB-11): el software leyo RBR sin que LSR dijera DR = 1
        //igual se compara el dato, pero no se revisa el aviso de error (chequeo B) porque nadie miro LSR antes
        if (last_dr)
          check_missed(rx_flags.pop_front());
        else
          void'(rx_flags.pop_front()); //void'() descarta lo que devuelve la funcion
        rx_compared++;
        if (actual !== expected)
          `uvm_error("SCB_RX_DATA", $sformatf("RBR esperado=%02h observado=%02h", expected, actual))
        else
          `uvm_info("SCB_RX_MATCH", $sformatf("RBR=%02h", actual), UVM_HIGH)
      end
      last_dr = (rx_queue.size() != 0);
    end
  endfunction

  //Chequeo A (falso aviso): revisa una lectura de LSR
  //  - si LSR marca PE, FE o BI tiene que existir un caracter con ese error (en la FIFO o que llego desde la ultima lectura)
  //  - si marca EI (bit 7) tiene que existir algun caracter con error o un overrun
  //  - si marca OE (bit 1) tuvo que haber un overrun desde la ultima lectura de LSR
  //despues, si la lectura fue con DLAB = 0, el DUT borra PE, FE, BI y EI (con DLAB = 1 no borra nada, AMB-14)
  function void check_lsr(bit [7:0] lsr);
    lsr_checked++;
    if ((lsr[4:2] & ~possible) != 0)
      `uvm_error("SCB_LSR_FALSE", $sformatf("LSR=%02h marca {BI,FE,PE}=%03b sin un caracter con ese error (posibles=%03b)", lsr, lsr[4:2], possible))
    if (lsr[7] && (possible == 0) && !oe_possible)
      `uvm_error("SCB_LSR_FALSE", $sformatf("LSR=%02h marca EI sin ningun caracter con error ni overrun", lsr))
    if (lsr[1] && !oe_possible)
      `uvm_error("SCB_LSR_OE", $sformatf("LSR=%02h marca overrun sin que la FIFO RX se llenara", lsr))
    lsr_seen |= lsr[4:2];
    if (!lcr[7]) begin
      //la lectura borra OE, salvo que el overrun haya sido hace menos de un bit:
      //el monitor ve el caracter un poco antes de que el DUT lo meta a la FIFO, asi que el DUT puede marcar OE despues
      if (cycle - last_overrun >= cfg.ser.bit_cycles())
        oe_possible = 0;
      //despues de borrar, solo los caracteres que siguen en la FIFO pueden volver a encender un bit
      possible = 0;
      foreach (rx_flags[i])
        possible |= rx_flags[i];
    end
  endfunction

  //Chequeo B (aviso perdido): al leer de RBR un caracter con error, LSR lo tuvo que haber marcado antes
  //el software siempre lee LSR antes de RBR, asi que basta con revisar las lecturas de LSR desde el RBR anterior
  //BUG-06: en el DUT, si una lectura de LSR empieza en el mismo ciclo en que llega el caracter con error,
  //el borrado gana y el aviso se pierde (uart_regs.v lineas 634, 645 y 656). Se confirmo con el cover c_lsr_lost de uart_sva
  //si el BUG-06 esta dispensado es UVM_WARNING, si no es UVM_ERROR
  function void check_missed(bit [2:0] flags);
    if (flags != 0) begin
      err_chars++;
      if ((flags & ~lsr_seen) != 0) begin
        err_missed++;
        if ((flags & last_flags) != 0)
          err_missed_seq++;
        if (cfg.scb.waived(6))
          `uvm_warning("SCB_LSR_MISS", $sformatf("BUG-06 (dispensado): caracter con {BI,FE,PE}=%03b leido de RBR sin que LSR lo marcara", flags))
        else
          `uvm_error("SCB_LSR_MISS", $sformatf("BUG-06: caracter con {BI,FE,PE}=%03b leido de RBR sin que LSR lo marcara", flags))
      end
    end
    last_flags = flags;
    lsr_seen = 0;
  endfunction

  //Traduce FCR[7:6] a cuantos caracteres tiene que juntar la FIFO RX para la interrupcion de dato disponible
  function int unsigned trigger_chars();
    case (fcr_tl)
      2'b00: return 1;
      2'b01: return 4;
      2'b10: return 8;
      default: return 14;
    endcase
  endfunction

  //Modelo de interrupciones (seccion 10 del plan): revisa una lectura de IIR
  //IIR[0] = 0 significa que hay una interrupcion pendiente y IIR[3:1] dice cual (la de mayor prioridad)
  //predecir el ciclo exacto en que se enciende cada una es muy dificil, por eso revisamos que lo que dice IIR
  //este JUSTIFICADO por el modelo (igual que el chequeo A de LSR):
  //  011 error de linea (RLS) -> IER[2] = 1 y hay algun caracter con error que LSR puede mostrar
  //  010 dato disponible (RDA) -> IER[0] = 1 y la FIFO RX tiene al menos el nivel de disparo
  //  110 timeout (TI)          -> IER[0] = 1 y la FIFO RX tiene algun dato
  //  001 THR vacio (THRE)      -> IER[1] = 1
  //  000 modem (MS)            -> IER[3] = 1
  //ademas IIR[7:4] siempre vale 1100 (el UART siempre trabaja con FIFO, AMB-17)
  function void check_iir(bit [7:0] iir);
    iir_checked++;
    if (iir[7:4] != 4'hC)
      `uvm_error("SCB_IIR", $sformatf("IIR=%02h: los bits 7:4 tienen que ser 1100", iir))
    if (iir[0] == 1'b1)
      return; //no hay interrupcion pendiente, no hay nada que justificar
    case (iir[3:1])
      3'b011: if (!ier[2] || ((possible == 0) && !oe_possible))
                `uvm_error("SCB_IIR", $sformatf("IIR=%02h dice error de linea sin IER[2] o sin caracter con error (IER=%04b)", iir, ier))
      3'b010: if (!ier[0] || (rx_queue.size() < trigger_chars()))
                `uvm_error("SCB_IIR", $sformatf("IIR=%02h dice dato disponible con %0d caracteres y nivel %0d (IER=%04b)", iir, rx_queue.size(), trigger_chars(), ier))
      3'b110: if (!ier[0] || (rx_queue.size() == 0))
                `uvm_error("SCB_IIR", $sformatf("IIR=%02h dice timeout sin datos en la FIFO RX (IER=%04b)", iir, ier))
      3'b001: if (!ier[1])
                `uvm_error("SCB_IIR", $sformatf("IIR=%02h dice THR vacio sin IER[1]", iir))
      3'b000: if (!ier[3])
                `uvm_error("SCB_IIR", $sformatf("IIR=%02h dice modem sin IER[3]", iir))
      default: `uvm_error("SCB_IIR", $sformatf("IIR=%02h tiene un codigo de interrupcion que no existe", iir))
    endcase
  endfunction

  //Procesa un cambio en los pines de modem que vio el monitor de modem
  //guarda los pines nuevos y anota que deltas se tienen que encender en MSR[3:0]
  //  DCTS, DDSR y DDCD: cualquier cambio de su pin
  //  TERI: BUG-03 (AMB-05) la especificacion dice solo cuando RI pasa de 0 a 1, el DUT lo enciende con cualquier cambio
  //        si el BUG-03 esta dispensado seguimos al RTL, si no a la especificacion
  //BUG-05 (AMB-15): en loopback los pines externos no deberian tener efecto, pero el DUT igual enciende los deltas con ellos
  //  si el BUG-05 esta dispensado seguimos al RTL (los pines encienden deltas tambien en loopback), si no, en loopback no se anotan
  function void observe_modem(modem_item it);
    bit [3:0] now;
    bit [3:0] changed;
    bit [1:0] expected_pins;
    //BUG-01 (AMB-03): la especificacion dice bit de MCR en 1 -> pin en 0 (RTS y DTR son activos en bajo)
    //el DUT pone el pin igual al bit (uart_regs.v linea 351). Fuera de loopback revisamos los pines cada vez que el monitor publica
    expected_pins = cfg.scb.waived(1) ? mcr_rts_dtr : ~mcr_rts_dtr;
    if (!loop && ({it.rts, it.dtr} !== expected_pins))
      `uvm_error("SCB_MDM", $sformatf("BUG-01: RTS/DTR=%02b, esperado %02b (MCR[1:0]=%02b; la especificacion dice invertido)", {it.rts, it.dtr}, expected_pins, mcr_rts_dtr))
    now = {it.dcd, it.ri, it.dsr, it.cts};
    changed = now ^ pins; //^ es xor: 1 en cada pin que cambio
    if (changed == 0)
      return; //solo cambiaron RTS o DTR, que son salidas
    last_pin_change = cycle;
    if (!loop || cfg.scb.waived(5)) begin
      msr_delta[0] |= changed[0]; //DCTS
      msr_delta[1] |= changed[1]; //DDSR
      msr_delta[3] |= changed[3]; //DDCD
      if (cfg.scb.waived(3))
        msr_delta[2] |= changed[2];            //TERI como el RTL: cualquier cambio de RI
      else
        msr_delta[2] |= changed[2] && now[2];  //TERI como la especificacion: RI de 0 a 1
    end
    pins = now;
  endfunction

  //Revisa una lectura de MSR
  //  MSR[7:4] (estado): BUG-02 (AMB-04) la especificacion dice que es el INVERSO de los pines, el DUT pone los pines tal cual
  //  MSR[3:0] (deltas): los que anoto observe_modem desde la ultima lectura
  //Ventana (tolerancia de la seccion 10 del plan): un cambio de pin tarda unos ciclos en llegar a MSR,
  //por eso si el ultimo cambio fue hace menos de 8 ciclos no comparamos esta lectura
  //En loopback MSR[7:4] lo revisa la asercion A-LB-02 (sigue al MCR), aqui solo se revisan los deltas (BUG-05)
  function void check_msr(bit [7:0] msr);
    bit [3:0] expected_state;
    if (cycle - last_pin_change >= 8) begin
      msr_checked++;
      expected_state = cfg.scb.waived(2) ? pins : ~pins;
      if (!loop && (msr[7:4] !== expected_state))
        `uvm_error("SCB_MSR", $sformatf("BUG-02: MSR[7:4]=%04b, esperado %04b (pines=%04b; la especificacion dice inverso)", msr[7:4], expected_state, pins))
      if (msr[3:0] !== msr_delta) begin
        if (loop)
          `uvm_error("SCB_MSR", $sformatf("BUG-05: en loopback MSR[3:0]=%04b, esperado %04b (los pines externos no deberian tener efecto)", msr[3:0], msr_delta))
        else
          `uvm_error("SCB_MSR", $sformatf("MSR[3:0]=%04b, deltas esperados %04b (si solo difiere TERI, MSR[2], es el BUG-03)", msr[3:0], msr_delta))
      end
    end
    //la lectura con DLAB = 0 borra los deltas (con DLAB = 1 no, AMB-14)
    if (!lcr[7])
      msr_delta = 0;
  endfunction

  //Procesa un caracter que salio por stx: se compara con el primero de la cola TX
  function void observe_tx(ser_item it);
    bit [7:0] expected;
    //Break TX: con LCR[6] = 1 el DUT pone stx en 0 y el monitor TX lo ve como un break, no es un caracter
    //si llega un break sin LCR[6] es un error del DUT
    if (it.brk) begin
      if (lcr[6])
        tx_breaks++;
      else
        `uvm_error("SCB_TX_BREAK", "stx_pad_o hizo un break sin LCR[6] = 1")
      return;
    end
    if (it.parity_err || it.frame_err) // error de paridad o el bit de parada llego en 0 cuando debia ser 1
      `uvm_error("SCB_TX_LINE", "El DUT transmitio una trama con error de linea") //el DUT nunca deberia transmitir con error
    //si la cola esta vacia el DUT transmitio algo que nadie escribio en THR
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

  //En la fase de run sacamos todo de los buzones en cada ciclo y lo procesamos en un orden fijo
  task run_phase(uvm_phase phase);
    wb_item pending[$]; //accesos Wishbone de este ciclo
    wb_item wb;
    ser_item serial;
    modem_item modem;
    forever begin
      //esperamos un ciclo y un poquito mas (1ps), asi todos los monitores ya publicaron lo de este ciclo
      @(cfg.wb.vif.mon_cb);
      #1ps;
      cycle++;
      //Con reset activo botamos todo lo pendiente y volvemos LCR a su valor de reset
      //los totales no se reinician porque en E2 no hay reset en medio del trafico
      if (cfg.wb.vif.rst !== 1'b0) begin
        //lo que estaba esperando salir por stx lo corta el reset: se cuenta como cortado, no como error
        tx_cut += tx_queue.size();
        //los resets del principio (los del RAL) llegan antes del trafico; un reset despues del trafico es el reset final
        if (traffic_seen)
          cut_by_reset = 1;
        tx_queue.delete();
        rx_queue.delete();
        rx_flags.delete();
        possible = 0;
        oe_possible = 0;
        lsr_seen = 0;
        last_flags = 0;
        wb_in.flush();
        tx_in.flush();
        rx_in.flush();
        mdm_in.flush();
        msr_delta = 0;
        lcr = 8'h03;
        loop = 0;
        mcr_rts_dtr = 0;
        ier = 0;
        fcr_tl = 2'b11;
        last_dr = 0;
        continue;
      end
      //Orden fijo dentro del mismo ciclo, asi no depende de cual monitor publico primero:
      //  1. escrituras (un THR escrito ya esta en la cola antes de comparar lo que sale)
      //  2. caracteres de srx (un caracter que llego ya esta en la cola antes de leer RBR)
      //  3. lecturas
      //  4. caracteres de stx
      pending.delete();
      while (wb_in.try_get(wb)) //try_get saca un item si hay, sin esperar
        pending.push_back(wb);
      foreach (pending[i]) begin
        if (pending[i].we)
          observe_write(pending[i]);
      end
      //Despues del reset final los monitores pueden estar terminando un caracter que el reset corto:
      //ese caracter no es real, se bota sin compararlo (despues del reset final ya no hay trafico)
      while (rx_in.try_get(serial))
        if (!cut_by_reset)
          observe_rx(serial);
      while (mdm_in.try_get(modem))
        observe_modem(modem); //cambios de modem, antes de las lecturas (igual que RX)
      foreach (pending[i]) begin
        if (!pending[i].we)
          observe_read(pending[i]);
      end
      while (tx_in.try_get(serial))
        if (!cut_by_reset)
          observe_tx(serial);
    end
  endtask

  //La prueba llama esta funcion al final para darnos cuantos TX y RX planeo la secuencia
  //solo se usan para contar, lo esperado siempre sale de lo que vieron los monitores
  function void expect_totals(longint unsigned tx, longint unsigned rx);
    target_tx = tx;
    target_rx = rx;
    targets_set = 1;
  endfunction

  //En check_phase revisamos lo que quedo al final, aunque todas las comparaciones hayan salido bien
  //si no, una corrida que termino antes de tiempo podria parecer que paso
  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    //la secuencia nunca termino
    if (!targets_set)
      `uvm_error("SCB_NO_TARGETS", "La secuencia principal no completo su presupuesto")
    //quedo algo sin comparar en las colas o en los buzones
    if ((tx_queue.size() != 0) || (rx_queue.size() != 0) ||
        (wb_in.used() != 0) || (tx_in.used() != 0) || (rx_in.used() != 0) || (mdm_in.used() != 0))
      `uvm_error("SCB_PENDING", "Quedaron datos sin comparar al terminar")
    //lo que se vio y comparo tiene que dar justo lo que se planeo
    //los caracteres perdidos por overrun se vieron en la linea pero nunca se leen de RBR, por eso se restan
    if (targets_set && ((tx_writes - tx_cut != target_tx) || (tx_compared != target_tx) ||
                        (rx_characters != target_rx) || (rx_compared != target_rx - rx_lost)))
      `uvm_error("SCB_COUNTS", $sformatf("Objetivo TX/RX=%0d/%0d; THR=%0d TX=%0d RX=%0d RBR=%0d perdidos=%0d", target_tx, target_rx, tx_writes, tx_compared, rx_characters, rx_compared, rx_lost))
  endfunction

  //En report_phase imprimimos el resumen, es el [SCB_SUMMARY] que aparece al final del log
  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("SCB_SUMMARY", $sformatf("TX comparados=%0d RX comparados=%0d lecturas vacias=%0d breaks TX=%0d", tx_compared, rx_compared, empty_reads, tx_breaks), UVM_LOW)
    `uvm_info("SCB_LSR", $sformatf("LSR revisados=%0d; caracteres con error=%0d, no marcados=%0d (seguidos de otro con el mismo error=%0d)",
              lsr_checked, err_chars, err_missed, err_missed_seq), UVM_LOW)
    `uvm_info("SCB_INT", $sformatf("IIR revisados=%0d; overruns=%0d; MSR revisados=%0d", iir_checked, overruns, msr_checked), UVM_LOW)
  endfunction

endclass : uart_scoreboard
