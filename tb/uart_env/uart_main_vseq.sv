//Secuencia virtual principal: coordina a los agentes, ninguno de ellos sabe el flujo completo de la prueba
//es la misma secuencia para todos los casos, los plusargs deciden que trafico es posible
//Corre en el secuenciador virtual (uart_vsequencer)
class uart_main_vseq extends uvm_sequence;

  //Registramos en la fabrica
  `uvm_object_utils(uart_main_vseq)
  //uvm_declare_p_sequencer crea p_sequencer, un handle al secuenciador virtual donde corre esta secuencia
  //con el sacamos los secuenciadores de los agentes, el RAL, el predictor y la configuracion
  `uvm_declare_p_sequencer(uart_vsequencer)

  uart_env_cfg cfg;             //configuracion
  bit rx_done;                  //1 cuando ya se mandaron todos los caracteres RX de la iteracion
  bit [7:0] active_lcr;         //formato que se escribio en LCR
  bit [15:0] active_dl;         //divisor que se escribio en DLL y DLM
  bit active_loop;              //1 si se activo loopback (MCR[4])
  bit active_irq;               //1 si el software atiende RX por interrupcion, 0 si por sondeo
  bit active_bc;                //1 si en esta corrida se manda un break TX (LCR[6])
  bit [7:0] active_fcr;         //FCR que se escribio (nivel de disparo), para poder limpiar la FIFO RX con el mismo nivel
  longint unsigned planned_tx;  //total de escrituras TX planeadas, se le pasa al scoreboard al final
  longint unsigned planned_rx;  //total de caracteres RX planeados

  //Se crea el constructor
  function new(string name = "uart_main_vseq");
    super.new(name);
  endfunction

  //Calcula cuantos ciclos dura un caracter completo con el formato actual: inicio + datos + paridad + parada
  //asi las esperas se ajustan si cambia el largo o la velocidad
  //para la parada se usa la funcion del agente porque con 5 bits puede ser 1.5 bits
  function int unsigned char_cycles();
    return (1 + cfg.ser.n_bits() + int'(cfg.ser.pen)) * cfg.ser.bit_cycles() +
           cfg.ser.stop_cycles();
  endfunction

  //Hace UN acceso al bus con uart_wb_seq, sin tomar el candado (eso lo hace quien la llama)
  //asi se pueden hacer varios accesos seguidos dentro de la misma zona con DLAB = 1
  //al final espera 2 ciclos porque el driver necesita que sus salidas se acomoden antes del siguiente acceso
  task transfer(bit wr, bit [4:0] index, bit [7:0] value,
                output bit [7:0] result);
    uart_wb_seq seq;
    seq = uart_wb_seq::type_id::create("wb_access");
    seq.cfg = cfg;
    seq.reg_index = index;
    seq.write_access = wr;
    seq.write_data = value;
    seq.start(p_sequencer.wb_sqr); //corre la secuencia en el secuenciador del agente Wishbone
    result = seq.read_data;
    repeat (2) @(cfg.wb.vif.drv_cb);
  endtask

  //Igual que transfer pero tomando el candado del bus (bus_lock, un semaforo)
  //TX, RX y el servicio corren en paralelo y comparten el bus, el candado hace que uno espere a que el otro termine
  task access(bit wr, bit [4:0] index, bit [7:0] value,
              output bit [7:0] result);
    cfg.bus_lock.get(1); //toma el candado, si otro lo tiene espera
    transfer(wr, index, value, result);
    cfg.bus_lock.put(1); //lo devuelve
  endtask

  //Antes del reset escribimos un valor distinto al de reset y lo leemos de vuelta
  //si el DUT ya estuviera en reset, leer el valor de reset no probaria nada
  task prepare_reset_register(uvm_reg reg_handle, uvm_reg_data_t value);
    uvm_status_e status;    //si el acceso del RAL salio bien
    uvm_reg_data_t actual;  //valor que se leyo
    reg_handle.write(status, value, UVM_FRONTDOOR, p_sequencer.regm.map_dlab0); //write del RAL por la puerta delantera
    if (status != UVM_IS_OK)
      `uvm_error("UART_RAL_PREPARE", "Fallo al preparar el registro antes del reset")
    repeat (2) @(cfg.wb.vif.drv_cb);
    reg_handle.read(status, actual, UVM_FRONTDOOR, p_sequencer.regm.map_dlab0);
    repeat (2) @(cfg.wb.vif.drv_cb);
    if ((status != UVM_IS_OK) || (actual !== value))
      `uvm_error("UART_RAL_PREPARE", {reg_handle.get_name(), " no tomo el valor previo al reset"})
  endtask

  //Prueba del RAL, se hace dos veces:
  //  1. puerta delantera: se cambian LCR, IER y SCR, y la secuencia de reset aplica reset y los lee por el bus
  //  2. puerta trasera: se vuelven a cambiar, se aplica otro reset y se leen directo en el RTL
  //la segunda vez se vuelve a cambiar todo, si no solo se releeria un registro que ya estaba en reset
  task ral_preamble();
    uart_hw_reset_seq seq;
    uvm_status_e status;
    seq = uart_hw_reset_seq::type_id::create("ral_reset");
    seq.vif = cfg.wb.vif;
    seq.model = p_sequencer.regm; //le decimos a la secuencia que bloque del RAL revisar
    //1. puerta delantera
    prepare_reset_register(p_sequencer.regm.LCR, 8'h1b);
    prepare_reset_register(p_sequencer.regm.IER, 8'h0f);
    prepare_reset_register(p_sequencer.regm.SCR, 8'ha5);
    `uvm_info("UART_RAL_FRONTDOOR", "Comprobando reset por Wishbone", UVM_LOW)
    seq.start(null); //null porque esta secuencia no usa un secuenciador, usa los mapas del RAL
    repeat (2) @(cfg.wb.vif.drv_cb);
    //2. puerta trasera
    prepare_reset_register(p_sequencer.regm.LCR, 8'h1b);
    prepare_reset_register(p_sequencer.regm.IER, 8'h0f);
    prepare_reset_register(p_sequencer.regm.SCR, 8'ha5);
    seq.reset_blk(p_sequencer.regm); //aplicamos el reset en el DUT
    p_sequencer.regm.reset();        //y ponemos el espejo del RAL en sus valores de reset
    `uvm_info("UART_RAL_BACKDOOR", "Comprobando reset por rutas HDL", UVM_LOW)
    //mirror con UVM_CHECK lee el registro y lo compara con el espejo, UVM_BACKDOOR hace que lea directo en tb_top.dut.regs
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

  //Configura el UART: elige un formato y lo deja fijo toda la corrida
  //cambiarlo a la mitad de un caracter necesita mas manejo en el driver, los monitores y el scoreboard (eso es E3)
  task program_uart();
    int unsigned mode;
    int unsigned pick;
    bit [7:0] result;
    bit [7:0] fcr;
    bit [7:0] ier;
    bit [7:0] mcr;
    //1. LCR: largo y bits de parada se eligen con sus pesos, asi para quitar un formato basta con poner su peso en 0
    active_lcr = cfg.choose_weight(cfg.line.wls_w) |
                 (cfg.choose_weight(cfg.line.stb_w) << 2);
    //paridad: 0 ninguna, 1 impar, 2 par, 3 stick 1, 4 stick 0 (bits PEN, EPS y SP de LCR)
    mode = cfg.choose_weight(cfg.line.par_w);
    case (mode)
      1: active_lcr |= 8'h08;
      2: active_lcr |= 8'h18;
      3: active_lcr |= 8'h28;
      4: active_lcr |= 8'h38;
    endcase
    //2. DL: primero se elige la zona (cero, lenta o rapida) y despues el valor dentro de ella
    //asi la zona rapida sale casi siempre sin quitar los divisores grandes
    pick = $urandom_range(99, 0);
    if (pick < cfg.line.dl_zero_pct)
      active_dl = 0;
    else if (pick < cfg.line.dl_zero_pct + cfg.line.dl_tail_pct)
      active_dl = $urandom_range(cfg.line.dl_max, cfg.line.dl_fast_max + 1);
    else
      active_dl = $urandom_range(cfg.line.dl_fast_max, 1);
    //3. FCR: nivel de disparo con sus pesos, y a veces limpiar las FIFOs (solo aqui, antes del trafico, asi no se pierde nada esperado)
    fcr = (cfg.choose_weight(cfg.ctrl.tl_w) << 6) | 8'h01;
    if ($urandom_range(99, 0) < cfg.ctrl.fcr_clear_pct)
      fcr |= $urandom_range(3, 1) << 1;
    //4. IER y MCR: cada bit se sortea por separado con su propio porcentaje
    ier = 0;
    mcr = 0;
    for (int i = 0; i < 4; i++) begin
      ier[i] = ($urandom_range(99, 0) < cfg.ctrl.ier_bit_pct[i]);
      mcr[i] = ($urandom_range(99, 0) < cfg.ctrl.mcr_bit_pct[i]);
    end
    //loopback (MCR[4]) con su porcentaje: lo que se escribe en THR vuelve por adentro del DUT a RBR
    active_loop = ($urandom_range(99, 0) < cfg.ctrl.loop_pct);
    mcr[4] = active_loop;
    //break TX con su porcentaje: no va en el LCR de la configuracion, se manda aparte con send_break
    active_bc = ($urandom_range(99, 0) < cfg.line.bc_pct);
    //estilo de servicio con sus pesos [interrupcion, sondeo]
    //por interrupcion el software solo lee cuando int_o pide atencion, por eso necesita IER[0] (dato disponible y timeout)
    //si no, los caracteres nunca avisarian y el servicio se quedaria esperando
    active_irq = (cfg.choose_weight(cfg.sw.mode_w) == 0);
    if (active_irq)
      ier[0] = 1;

    //5. Escribimos todo con el candado tomado de principio a fin
    //mientras DLAB = 1 la direccion 0 es DLL, si otro acceso se metiera en medio escribiria DLL en vez de THR o RBR
    //tambien cambiamos el mapa del predictor para que entienda las direcciones con el banco que esta activo
    cfg.bus_lock.get(1);
    transfer(1, 3, active_lcr | 8'h80, result);           //LCR con DLAB = 1
    p_sequencer.predictor.map = p_sequencer.regm.map_dlab1;
    transfer(1, 0, active_dl[7:0], result);               //DLL
    transfer(1, 1, active_dl[15:8], result);              //DLM
    transfer(0, 0, 0, result);                            //leemos DLL para revisar
    if (result !== active_dl[7:0])
      `uvm_error("UART_DLL", "DLL no coincide con el divisor solicitado")
    transfer(0, 1, 0, result);                            //leemos DLM para revisar
    if (result !== active_dl[15:8])
      `uvm_error("UART_DLM", "DLM no coincide con el divisor solicitado")
    transfer(1, 3, active_lcr, result);                   //LCR con DLAB = 0
    p_sequencer.predictor.map = p_sequencer.regm.map_dlab0;
    transfer(0, 3, 0, result);                            //leemos LCR para revisar
    if (result !== active_lcr)
      `uvm_error("UART_LCR", "LCR no coincide con el formato solicitado")
    transfer(1, 2, fcr, result);                          //FCR
    active_fcr = fcr & 8'hc1;                             //guardamos el nivel de disparo (sin los bits de limpiar)
    transfer(1, 1, ier, result);                          //IER
    transfer(1, 4, mcr, result);                          //MCR
    cfg.bus_lock.put(1);

    //6. Copiamos el formato al cfg del agente serie despues de escribirlo y antes del trafico
    //el driver y los dos monitores tienen que usar justo el mismo formato que el DUT, si no las comparaciones no sirven
    cfg.ser.wls = active_lcr[1:0];
    cfg.ser.stb = active_lcr[2];
    cfg.ser.pen = active_lcr[3];
    cfg.ser.eps = active_lcr[4];
    cfg.ser.sp = active_lcr[5];
    cfg.ser.dl = active_dl;
    `uvm_info("UART_LINE", $sformatf("LCR=%02h DL=%0d loopback=%0d interrupcion=%0d IER=%01h", active_lcr, active_dl, active_loop, active_irq, ier[3:0]), UVM_LOW)
  endtask

  //Trafico TX: escribe bytes en THR para que el DUT los transmita (el driver serie no maneja stx)
  //antes de cada escritura espera THRE (LSR[5]), en E2 se prueba trafico normal y no llenar la FIFO TX a proposito
  task send_tx(int unsigned count);
    bit [7:0] lsr;
    bit [7:0] ignored;
    repeat (count) begin
      do begin
        access(0, 5, 0, lsr); //lee LSR
      end while (!lsr[5]);    //hasta que THRE = 1
      access(1, 0, $urandom_range(cfg.sw.tx_data_max, cfg.sw.tx_data_min), ignored); //escribe un dato aleatorio en THR
    end
  endtask

  //Trafico RX: arranca uart_rx_seq en el secuenciador del agente serie para mandar caracteres por srx
  //al final espera 2 bits mas antes de marcar rx_done, asi el servicio no se detiene antes de tiempo
  task send_rx(int unsigned count);
    uart_rx_seq seq;
    seq = uart_rx_seq::type_id::create("rx_traffic");
    seq.cfg = cfg;
    seq.count = count;
    seq.start(p_sequencer.ser_sqr);
    repeat (2 * cfg.ser.bit_cycles()) @(cfg.ser.vif.mon_cb);
    rx_done = 1;
  endtask

  //Vacia la FIFO RX: lee LSR y, mientras haya dato (DR = LSR[0]), lee RBR
  //siempre se lee LSR antes de RBR, asi el scoreboard puede revisar los avisos de error (chequeo B)
  task drain_rx();
    bit [7:0] lsr;
    bit [7:0] ignored;
    do begin
      access(0, 5, 0, lsr);
      if (lsr[0])
        access(0, 0, 0, ignored);
    end while (lsr[0]);
  endtask

  //Servicio por interrupcion: el software no pregunta todo el tiempo, espera a que el DUT suba int_o
  //Pasos:
  //  1. esperamos int_o = 1, o que ya no vengan mas caracteres (rx_done)
  //  2. leemos IIR para saber quien pidio atencion (el scoreboard revisa que tenga sentido)
  //  3. atendemos segun IIR[3:1], cada fuente se limpia con una accion distinta:
  //       011 error de linea -> leer LSR
  //       010 dato disponible o 110 timeout -> vaciar la FIFO RX
  //       001 THR vacio -> leer IIR ya la limpio, no hay que hacer nada mas
  //       000 modem -> leer MSR
  //  4. al terminar vaciamos lo que quedo por debajo del nivel de disparo
  task service_irq();
    bit [7:0] iir;
    bit [7:0] ignored;
    forever begin
      //1. esperamos ciclo por ciclo a que int_o suba o a que termine el trafico RX
      while ((cfg.wb.vif.mon_cb.irq !== 1'b1) && !rx_done)
        @(cfg.wb.vif.mon_cb);
      if (cfg.wb.vif.mon_cb.irq !== 1'b1)
        break; //rx_done y nadie pide atencion: terminamos
      //2. quien pidio atencion
      access(0, 2, 0, iir);
      //3. atendemos (si IIR[0] = 1 la interrupcion ya se habia ido y no hacemos nada)
      if (!iir[0]) begin
        case (iir[3:1])
          3'b011: access(0, 5, 0, ignored);  //error de linea: leer LSR la limpia
          3'b010: drain_rx();                //dato disponible
          3'b110: drain_rx();                //timeout
          3'b000: access(0, 6, 0, ignored);  //modem: leer MSR la limpia
          default: ;                         //THR vacio: ya se limpio al leer IIR
        endcase
      end
    end
    //4. lo que quedo por debajo del nivel de disparo
    drain_rx();
  endtask

  //Servicio por sondeo: mientras llegan caracteres, lee LSR y si hay dato (DR = LSR[0]) lo saca de RBR
  //que la FIFO este vacia no basta para terminar, puede venir otro caracter en camino, por eso tambien se espera rx_done
  //el retraso de atencion (service_delay) sirve para provocar overrun y las lecturas ciegas para leer RBR vacio (AMB-11)
  task service_rx();
    bit [7:0] lsr;
    bit [7:0] ignored;
    int unsigned delay_chars; //retraso de atencion en caracteres
    int unsigned stuck;       //lecturas seguidas con DR = 1 despues de que termino el trafico RX
    //si se eligio servicio por interrupcion, ese servicio se encarga de todo
    if (active_irq) begin
      service_irq();
      return;
    end
    forever begin
      delay_chars = $urandom_range(cfg.sw.service_delay_max, cfg.sw.service_delay_min);
      repeat (longint'(delay_chars) * char_cycles()) @(cfg.wb.vif.drv_cb);
      access(0, 5, 0, lsr);       //lee LSR
      if (lsr[0]) begin
        access(0, 0, 0, ignored); //hay dato: lee RBR (lo compara el scoreboard)
        //BUG-07: el DUT puede dejar DR en 1 con la FIFO vacia, y el software se quedaria leyendo para siempre
        //si ya termino el trafico y la FIFO (16) se tendria que haber vaciado hace rato, la limpiamos con FCR[1]
        //como haria un software real para recuperarse (el scoreboard tambien vacia su cola al ver FCR[1])
        if (rx_done)
          stuck++;
        if (stuck > 20) begin
          `uvm_warning("UART_DR_STUCK", "DR sigue en 1 despues del trafico: se limpia la FIFO RX (BUG-07)")
          access(1, 2, active_fcr | 8'h02, ignored);
          stuck = 0;
        end
      end else begin
        if ($urandom_range(99, 0) < cfg.sw.blind_read_pct)
          access(0, 0, 0, ignored); //lectura ciega: lee RBR sin dato
        if (rx_done)
          break; //ya no viene nada mas, termina el servicio
      end
    end
  endtask

  //Trafico de modem: arranca modem_toggle_seq en el secuenciador del agente de modem
  //Con toggle_pct = 0 no hace nada, asi el caso base queda igual
  task send_modem(int unsigned steps);
    modem_toggle_seq seq;
    if (cfg.mdm.toggle_pct == 0)
      return;
    seq = modem_toggle_seq::type_id::create("modem_traffic");
    seq.cfg = cfg.mdm;
    seq.steps = steps;
    seq.start(p_sequencer.mdm_sqr);
  endtask

  //Break TX (hoja 4.4 del plan): LCR[6] = 1 pone stx en 0 aunque no haya nada que transmitir
  //lo dejamos 2 caracteres (el monitor TX lo ve como break y el scoreboard lo acepta porque LCR[6] = 1)
  //y despues lo apagamos y esperamos 1 caracter con la linea en reposo antes del trafico
  task send_break();
    bit [7:0] ignored;
    access(1, 3, active_lcr | 8'h40, ignored);  //LCR con el bit 6 (break) en 1
    repeat (2 * char_cycles()) @(cfg.wb.vif.drv_cb);
    access(1, 3, active_lcr, ignored);          //LCR sin break
    repeat (char_cycles()) @(cfg.wb.vif.drv_cb);
  endtask

  //Espera TEMT (LSR[6]): la FIFO TX y el registro de corrimiento vacios
  //no basta con la ultima escritura a THR, la FIFO puede estar vacia mientras todavia sale el ultimo caracter
  task wait_temt();
    bit [7:0] lsr;
    do begin
      access(0, 5, 0, lsr);
    end while (!lsr[6]);
  endtask

  //body es el flujo completo de la prueba
  task body();
    int unsigned tx_count;
    int unsigned rx_count;
    cfg = p_sequencer.cfg;
    //1. esperamos a que termine el reset inicial
    wait (cfg.wb.vif.rst === 1'b0);
    repeat (3) @(cfg.wb.vif.drv_cb);
    //2. prueba del RAL (se puede apagar con un plusarg)
    if (cfg.run_ral_reset)
      ral_preamble();
    //3. configuramos el UART antes del trafico, asi nadie usa el divisor de reset (DL = 0) ni otro formato
    program_uart();
    //DL = 0: sin baudios el UART no transmite ni recibe (hoja 0.2 del plan), asi que esta corrida no manda trafico
    //lo que se prueba es que la configuracion con DL = 0 se acepte (cg_line_cfg) y que no salgan pulsos de baudios (A-BAUD-01)
    if (active_dl == 0) begin
      `uvm_info("UART_DL0", "DL = 0: el UART queda mudo, esta corrida no manda trafico", UVM_LOW)
      return;
    end
    //break TX antes del trafico, pero no en loopback: ahi el break volveria por adentro y entraria como un caracter RX
    if (active_bc && !active_loop)
      send_break();

    //4. repetimos n_iter veces
    repeat (cfg.sw.n_iter) begin
      //se sortea cuanto TX y cuanto RX en cada iteracion, asi con MIN = MAX tambien funciona sin un caso especial
      tx_count = $urandom_range(cfg.sw.tx_burst_max, cfg.sw.tx_burst_min);
      rx_count = $urandom_range(cfg.ser.burst_max, cfg.ser.burst_min);
      rx_done = 0;
      if (!active_loop) begin
        //Modo normal: TX, RX y el servicio corren en paralelo porque el UART puede mandar y recibir al mismo tiempo
        //solo los accesos al bus Wishbone se turnan (con el candado), la linea serie corre sola
        //join espera a que terminen las cuatro tareas
        planned_tx += tx_count;
        planned_rx += rx_count;
        `uvm_info("UART_BURST", $sformatf("Objetivo TX=%0d RX=%0d", tx_count, rx_count), UVM_MEDIUM)
        fork
          send_tx(tx_count);
          send_rx(rx_count);
          service_rx();
          send_modem(tx_count + rx_count); //cambios de modem mientras hay trafico
        join
      end else begin
        //Loopback: lo que se escribe en THR vuelve por adentro a RBR, por eso cuenta como RX y no como TX
        //el agente serie no manda nada, en loopback el DUT ignora srx
        //el servicio termina cuando el transmisor quedo vacio (TEMT) y paso el ultimo caracter (2 bits de margen)
        planned_rx += tx_count;
        `uvm_info("UART_BURST", $sformatf("Objetivo loopback=%0d", tx_count), UVM_MEDIUM)
        fork
          begin
            send_tx(tx_count);
            wait_temt();
            repeat (2 * cfg.ser.bit_cycles()) @(cfg.ser.vif.mon_cb);
            rx_done = 1;
          end
          service_rx();
          send_modem(tx_count); //cambios en los pines externos: en loopback no deberian tener efecto (BUG-05)
        join
      end
      wait_temt();
      repeat (3) @(cfg.wb.vif.drv_cb);
    end
  endtask

endclass : uart_main_vseq
