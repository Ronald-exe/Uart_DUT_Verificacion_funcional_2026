
//En este archivo esta toda la configuracion del ambiente: los knobs y la funcion que lee los plusargs
//Los knobs se separan en grupos, cada uno en su propia clase, asi cada ajuste tiene un lugar claro:
//  uart_line_cfg: formato de la linea (LCR y DL)
//  uart_ctrl_cfg: registros de control (FCR, IER y MCR)
//  uart_sw_cfg:   lo que hace el software (escribir THR y atender lo que llega)
//  uart_scb_cfg:  lo que necesita el scoreboard (la lista de BUG dispensados)
//  uart_env_cfg:  junta a todos los anteriores y a los cfg de los agentes
//Todos son elecciones al correr, el mismo DUT compilado sirve para todas las semillas

//uart_line_cfg: knobs del formato de la linea
//Hereda de uvm_object porque es configuracion
class uart_line_cfg extends uvm_object;

  //Registramos en la fabrica
  `uvm_object_utils(uart_line_cfg)

  //Divisor DL en tres zonas: casi siempre la zona rapida y a veces la zona lenta (la cola)
  //asi los baudios lentos tienen chance de salir sin que todas las semillas tarden muchisimo
  int unsigned dl_zero_pct = 1;     //porcentaje de DL = 0
  int unsigned dl_fast_max = 16;    //limite de la zona rapida (1 a 16)
  int unsigned dl_max = 65535;      //DL maximo posible
  int unsigned dl_tail_pct = 2;     //porcentaje de la zona lenta (17 a dl_max)
  int unsigned bc_pct = 5;          //porcentaje de break TX, es de LCR por eso va aqui (en E2 da error si se activa)
  //Pesos de cada opcion, el orden del arreglo es fijo porque la posicion elegida va directo a los bits de LCR
  //un peso en 0 quita esa opcion
  int unsigned wls_w[] = '{1,1,1,1};     //largo: 5, 6, 7 y 8 bits
  int unsigned stb_w[] = '{1,1};         //parada: 1 bit, o 1.5/2 bits
  int unsigned par_w[] = '{1,1,1,1,1};   //paridad: ninguna, impar, par, stick 1 y stick 0

  //Se crea el constructor, como es objeto no lleva parent
  function new(string name = "uart_line_cfg");
    super.new(name);
  endfunction

endclass : uart_line_cfg

//uart_ctrl_cfg: knobs de los registros que se programan antes del trafico
//escribir IER o MCR no prueba por si solo que las interrupciones o el modem funcionen, eso lo revisa el scoreboard en E3
class uart_ctrl_cfg extends uvm_object;

  //Registramos en la fabrica
  `uvm_object_utils(uart_ctrl_cfg)

  int unsigned fcr_clear_pct = 10;  //porcentaje de limpiar las FIFOs, por ahora solo antes del trafico
  int unsigned loop_pct = 10;       //porcentaje de loopback
  int unsigned tl_w[] = '{1,1,1,1}; //pesos del nivel de disparo: 1, 4, 8 y 14 caracteres
  //IER y MCR usan un porcentaje por bit, cada bit se sortea solo, por eso no tienen que sumar 100
  int unsigned ier_bit_pct[] = '{50,50,50,50};
  int unsigned mcr_bit_pct[] = '{50,50,50,50};

  //Se crea el constructor
  function new(string name = "uart_ctrl_cfg");
    super.new(name);
  endfunction

endclass : uart_ctrl_cfg

//uart_sw_cfg: knobs del lado del software, escribir THR y atender los caracteres que llegan
//cada iteracion es un par TX y RX, cualquiera de los dos se puede apagar poniendo su cantidad en 0
class uart_sw_cfg extends uvm_object;

  //Registramos en la fabrica
  `uvm_object_utils(uart_sw_cfg)

  int unsigned n_iter = 20; //cuantas iteraciones hace la prueba
  //MIN y MAX incluyen sus extremos, asi el mismo knob sirve para trafico aleatorio o fijo
  //ej. para exactamente 50 caracteres se ponen los dos en 50, para no tener trafico los dos en 0
  int unsigned tx_burst_min = 0;    //minimo de escrituras a THR por iteracion
  int unsigned tx_burst_max = 20;   //maximo de escrituras a THR por iteracion (20 como en la seccion 7 del plan, pasa las 16 de la FIFO)
  int unsigned tx_data_min = 0;     //dato minimo que se escribe en THR
  int unsigned tx_data_max = 255;   //dato maximo que se escribe en THR
  //El retraso de atencion se mide en tiempos de caracter, asi sigue teniendo sentido si cambian los baudios
  //el retraso, las lecturas ciegas, los accesos al azar, el reset y la reconfiguracion con trafico estan bloqueados en E2
  //porque el scoreboard todavia no sabe revisarlos
  int unsigned service_delay_min = 0;
  int unsigned service_delay_max = 20;
  int unsigned blind_read_pct = 5;   //porcentaje de leer RBR sin mirar LSR
  int unsigned rand_access_pct = 5;  //porcentaje de acceso al azar
  int unsigned recfg_pct = 5;        //porcentaje de reconfigurar con trafico
  int unsigned rst_pct = 1;          //porcentaje de reset con trafico
  //pesos del estilo de servicio: [interrupcion, sondeo], el primero va en 0 hasta que exista el servicio por interrupcion
  int unsigned mode_w[] = '{1,1};

  //Se crea el constructor
  function new(string name = "uart_sw_cfg");
    super.new(name);
  endfunction

endclass : uart_sw_cfg

//uart_scb_cfg: knobs del scoreboard, va en su propio objeto como dice la seccion 9.3 del plan
class uart_scb_cfg extends uvm_object;

  //Registramos en la fabrica
  `uvm_object_utils(uart_scb_cfg)

  //Lista de BUG dispensados (BUG-01 a BUG-06), los de la lista se reportan como UVM_WARNING y no como UVM_ERROR
  //asi una regresion puede pasar aunque el DUT tenga errores conocidos, y con la lista vacia se reproduce cada BUG
  string waive_bugs = "1,2,3,4,5,6";

  //Se crea el constructor
  function new(string name = "uart_scb_cfg");
    super.new(name);
  endfunction

  //Dice si el BUG numero n esta en la lista, ej. con "1,6" waived(6) da 1 y waived(2) da 0
  //los BUG van del 1 al 6, asi que basta con buscar el digito letra por letra
  function bit waived(int unsigned n);
    for (int i = 0; i < waive_bugs.len(); i++) begin
      if (waive_bugs.substr(i, i) == $sformatf("%0d", n))
        return 1;
    end
    return 0;
  endfunction

endclass : uart_scb_cfg

//uart_env_cfg: la configuracion de todo el ambiente, un solo objeto compartido
//asi los plusargs se leen en un solo lugar y no en cada componente (regla del enunciado)
//adentro tambien estan los cfg de nuestros agentes, asi no hay que cambiar sus valores por defecto
class uart_env_cfg extends uvm_object;

  //Registramos en la fabrica
  `uvm_object_utils(uart_env_cfg)

  //Handles a los grupos de knobs y a los cfg de los agentes (las interfaces virtuales van dentro de cada cfg de agente)
  uart_line_cfg line;
  uart_ctrl_cfg ctrl;
  uart_sw_cfg sw;
  uart_scb_cfg scb;
  wb_agent_cfg wb;
  ser_agent_cfg ser;
  virtual modem_if mdm_vif; //interfaz del modem, en E2 todavia no hay agente de modem

  //Candado del bus: el trafico TX y el servicio RX usan el mismo maestro Wishbone
  //semaphore es un semaforo de SystemVerilog, con una sola llave (new(1)) solo uno puede usar el bus a la vez
  //tambien evita que alguien se meta en medio mientras se programa DLAB
  semaphore bus_lock;

  //Knobs de errores del plan, se dejan visibles pero si se activan da error hasta que el estimulo y el chequeo esten listos (E3)
  int unsigned ser_parity_err_pct = 5;
  int unsigned ser_frame_err_pct = 5;
  int unsigned ser_break_pct = 3;
  int unsigned ser_stop2_err_pct = 5;
  int unsigned ser_glitch_pct = 3;
  int unsigned ser_baud_err_pct = 5;
  int unsigned ser_baud_err_max = 8;
  int unsigned mdm_toggle_pct = 20;

  //Controles de la prueba
  int unsigned run_ral_reset = 1;              //1 = corre la prueba de reset del RAL al inicio
  int unsigned bus_timeout_cycles = 1000;      //tiempo maximo de cada acceso Wishbone
  int unsigned timeout_cycles = 1000000000;    //watchdog: tiempo maximo de toda la secuencia, solo corta una corrida que se quedo pegada
                                               //con baudios muy lentos (DL grande) hay que subirlo con +UART_TIMEOUT_CYCLES

  //Se crea el constructor y adentro se crean todos los grupos y los cfg de los agentes
  function new(string name = "uart_env_cfg");
    super.new(name);
    line = uart_line_cfg::type_id::create("line");
    ctrl = uart_ctrl_cfg::type_id::create("ctrl");
    sw = uart_sw_cfg::type_id::create("sw");
    scb = uart_scb_cfg::type_id::create("scb");
    wb = wb_agent_cfg::type_id::create("wb");
    ser = ser_agent_cfg::type_id::create("ser");
    bus_lock = new(1); //semaforo con una sola llave
  endfunction

  //Lee un plusarg de un solo numero, si no viene se queda el valor por defecto
  //$value$plusargs busca +key=... en la linea de comandos, %d dice que lo que sigue al = es un numero
  //imprime el valor final y de donde salio, asi la semilla y el log alcanzan para repetir la corrida (regla del enunciado)
  function void read_uint(string key, ref int unsigned value);
    string origin = "default";
    if ($value$plusargs({key, "=%d"}, value))
      origin = "plusarg";
    `uvm_info("UART_CFG", $sformatf("%s=%0d (%s)", key, value, origin), UVM_LOW)
  endfunction

  //Lee un plusarg que es una lista separada por comas (ej. +UART_LCR_WLS_WEIGHTS=0,0,0,1)
  //Pasos:
  //  1. tomamos el texto que sigue al =
  //  2. lo recorremos y cada vez que aparece una coma convertimos el pedazo a numero con atoi
  //  3. tiene que traer exactamente la cantidad de elementos esperada, si falta uno se correrian las opciones
  //  4. si son porcentajes ninguno pasa de 100, si son pesos la suma no puede ser 0
  function void read_vector(string key, ref int unsigned values[], input bit percentages = 0);
    string raw;            //el texto completo, ej. "0,0,0,1"
    string piece = "";     //el numero que vamos armando
    string origin = "default";
    string text = "";      //el valor final para imprimirlo
    int index = 0;         //en que posicion del arreglo vamos
    int unsigned sum = 0;

    //1. si viene el plusarg lo leemos como texto (%s)
    if ($value$plusargs({key, "=%s"}, raw)) begin
      origin = "plusarg";
      //2. recorremos letra por letra, la coma o el final del texto cierran un numero
      for (int i = 0; i <= raw.len(); i++) begin
        if ((i == raw.len()) || (raw.substr(i, i) == ",")) begin
          if (index < values.size())
            values[index] = piece.atoi(); //atoi convierte el texto a numero, ej. "14" -> 14
          index++;
          piece = "";
        end else begin
          piece = {piece, raw.substr(i, i)};
        end
      end
      //3. revisamos la cantidad de elementos
      if (index != values.size())
        `uvm_fatal("UART_ARG", $sformatf("%s: se esperaban %0d elementos y vinieron %0d", key, values.size(), index))
    end

    //4. revisamos los limites y armamos el texto para imprimir
    foreach (values[i]) begin
      sum += values[i];
      if (percentages && (values[i] > 100))
        `uvm_fatal("UART_ARG", {key, ": porcentaje mayor que 100"})
      text = {text, (i == 0) ? "" : ",", $sformatf("%0d", values[i])};
    end
    if (!percentages && (sum == 0))
      `uvm_fatal("UART_ARG", {key, ": la suma de los pesos no puede ser 0"})
    `uvm_info("UART_CFG", $sformatf("%s=%s (%s)", key, text, origin), UVM_LOW)
  endfunction

  //Si no se cumple la condicion detiene la simulacion con un fatal de UVM
  function void require(bit condition, string message);
    if (!condition)
      `uvm_fatal("UART_CFG", message)
  endfunction

  //Si se activa algo que todavia no esta implementado, detiene la simulacion al configurar y no a la mitad de la corrida
  function void unsupported(int unsigned value, string name);
    if (value != 0)
      `uvm_fatal("UART_E2_CAPABILITY", {name, " aun no implementado; usar el caso sim/args/base.args"})
  endfunction

  //parse_plusargs: el UNICO lugar donde se leen los plusargs
  //se llama una vez en la prueba, antes de crear el ambiente, asi todos los componentes ven los mismos valores ya revisados
  function void parse_plusargs();
    //1. Leemos los knobs de un solo numero, en grupos como en la tabla de plusargs del plan (seccion 7)
    read_uint("UART_LCR_DL_ZERO_PCT", line.dl_zero_pct);
    read_uint("UART_LCR_DL_FAST_MAX", line.dl_fast_max);
    read_uint("UART_LCR_DL_MAX", line.dl_max);
    read_uint("UART_LCR_DL_TAIL_PCT", line.dl_tail_pct);
    read_uint("UART_LCR_BC_PCT", line.bc_pct);
    read_uint("UART_FCR_CLEAR_PCT", ctrl.fcr_clear_pct);
    read_uint("UART_MCR_LOOP_PCT", ctrl.loop_pct);
    read_uint("UART_SW_ITER", sw.n_iter);
    read_uint("UART_SW_TX_BURST_MIN", sw.tx_burst_min);
    read_uint("UART_SW_TX_BURST_MAX", sw.tx_burst_max);
    read_uint("UART_SW_TX_DATA_MIN", sw.tx_data_min);
    read_uint("UART_SW_TX_DATA_MAX", sw.tx_data_max);
    read_uint("UART_SW_SERVICE_DELAY_MIN", sw.service_delay_min);
    read_uint("UART_SW_SERVICE_DELAY_MAX", sw.service_delay_max);
    read_uint("UART_SW_BLIND_READ_PCT", sw.blind_read_pct);
    read_uint("UART_SW_RAND_ACCESS_PCT", sw.rand_access_pct);
    read_uint("UART_SW_RECFG_PCT", sw.recfg_pct);
    read_uint("UART_SW_RST_PCT", sw.rst_pct);
    read_uint("UART_WB_DELAY_MAX", wb.delay_max);
    read_uint("UART_WB_STB_DELAY_MAX", wb.stb_delay_max);
    read_uint("UART_WB_SEL_ODD_PCT", wb.sel_odd_pct);
    read_uint("UART_SER_BURST_MIN", ser.burst_min);
    read_uint("UART_SER_BURST_MAX", ser.burst_max);
    read_uint("UART_SER_DATA_MIN", ser.data_min);
    read_uint("UART_SER_DATA_MAX", ser.data_max);
    read_uint("UART_SER_GAP_MAX", ser.gap_max);
    read_uint("UART_SER_PARITY_ERR_PCT", ser_parity_err_pct);
    read_uint("UART_SER_FRAME_ERR_PCT", ser_frame_err_pct);
    read_uint("UART_SER_BREAK_PCT", ser_break_pct);
    read_uint("UART_SER_STOP2_ERR_PCT", ser_stop2_err_pct);
    read_uint("UART_SER_GLITCH_PCT", ser_glitch_pct);
    read_uint("UART_SER_BAUD_ERR_PCT", ser_baud_err_pct);
    read_uint("UART_SER_BAUD_ERR_MAX", ser_baud_err_max);
    read_uint("UART_MDM_TOGGLE_PCT", mdm_toggle_pct);
    read_uint("UART_RAL_HW_RESET", run_ral_reset);
    read_uint("UART_BUS_TIMEOUT_CYCLES", bus_timeout_cycles);
    read_uint("UART_TIMEOUT_CYCLES", timeout_cycles);

    //2. Leemos las listas, el ultimo argumento dice si son porcentajes (1) o pesos (0)
    read_vector("UART_LCR_WLS_WEIGHTS", line.wls_w, 0);
    read_vector("UART_LCR_STB_WEIGHTS", line.stb_w, 0);
    read_vector("UART_LCR_PAR_WEIGHTS", line.par_w, 0);
    read_vector("UART_FCR_TL_WEIGHTS", ctrl.tl_w, 0);
    read_vector("UART_IER_BIT_PCT", ctrl.ier_bit_pct, 1);
    read_vector("UART_MCR_BIT_PCT", ctrl.mcr_bit_pct, 1);
    read_vector("UART_SW_MODE_WEIGHTS", sw.mode_w, 0);

    //3. La lista de BUG dispensados es texto y puede venir vacia (+UART_SCB_WAIVE_BUGS=)
    //con el valor vacio $value$plusargs no cambia la variable, por eso primero revisamos si esta ($test$plusargs),
    //la dejamos vacia y despues leemos lo que sigue al =
    if ($test$plusargs("UART_SCB_WAIVE_BUGS=")) begin
      scb.waive_bugs = "";
      void'($value$plusargs("UART_SCB_WAIVE_BUGS=%s", scb.waive_bugs));
      `uvm_info("UART_CFG", {"UART_SCB_WAIVE_BUGS=", scb.waive_bugs, " (plusarg)"}, UVM_LOW)
    end else begin
      `uvm_info("UART_CFG", {"UART_SCB_WAIVE_BUGS=", scb.waive_bugs, " (default)"}, UVM_LOW)
    end

    //4. Revisamos que los valores tengan sentido antes de usarlos en un sorteo (seccion 7 del plan)
    //pares MIN <= MAX, rangos y porcentajes, si algo esta mal UVM_FATAL
    require(sw.n_iter > 0, "UART_SW_ITER debe ser positivo");
    require((sw.tx_burst_min <= sw.tx_burst_max) && (sw.tx_burst_max <= 255), "Rango TX invalido");
    require((ser.burst_min <= ser.burst_max) && (ser.burst_max <= 255), "Rango RX invalido");
    require((sw.tx_data_min <= sw.tx_data_max) && (sw.tx_data_max <= 255), "Rango de datos TX invalido");
    require((ser.data_min <= ser.data_max) && (ser.data_max <= 255), "Rango de datos RX invalido");
    require(sw.service_delay_min <= sw.service_delay_max, "Retraso de servicio: MIN mayor que MAX");
    require((line.dl_fast_max > 0) && (line.dl_fast_max <= line.dl_max) && (line.dl_max <= 65535), "Rango DL invalido");
    require(line.dl_zero_pct + line.dl_tail_pct <= 100, "Los porcentajes de DL suman mas de 100");
    require((line.bc_pct <= 100) && (ctrl.fcr_clear_pct <= 100) && (ctrl.loop_pct <= 100), "Porcentaje de linea o control mayor que 100");
    require((sw.blind_read_pct <= 100) && (sw.rand_access_pct <= 100) &&
            (sw.recfg_pct <= 100) && (sw.rst_pct <= 100), "Porcentaje de software mayor que 100");
    require((wb.sel_odd_pct <= 100) && (mdm_toggle_pct <= 100), "Porcentaje de bus o modem mayor que 100");
    require((ser_parity_err_pct <= 100) && (ser_frame_err_pct <= 100) && (ser_break_pct <= 100) &&
            (ser_stop2_err_pct <= 100) && (ser_glitch_pct <= 100) && (ser_baud_err_pct <= 100), "Porcentaje de error serie mayor que 100");
    require(ser_baud_err_max <= 20, "UART_SER_BAUD_ERR_MAX va de 0 a 20");
    //a lo sumo un error por caracter, por eso los porcentajes de error juntos no pueden pasar de 100
    require(ser_parity_err_pct + ser_frame_err_pct + ser_break_pct <= 100, "Los porcentajes de error serie suman mas de 100");
    require((bus_timeout_cycles > 0) && (timeout_cycles > 0), "Los timeouts deben ser positivos");

    //5. Lista de lo que todavia no esta implementado, si alguno no esta en 0 la prueba se detiene
    //el caso sim/args/base.args los pone en 0, cada linea se quita cuando su soporte este listo (E3)
    unsupported(line.bc_pct, "Break TX");
    unsupported(line.dl_zero_pct, "Trafico con DL=0");
    unsupported(sw.mode_w[0], "Servicio por interrupciones");
    unsupported(sw.service_delay_max, "Retraso de servicio con posible overrun");
    unsupported(sw.blind_read_pct, "Lecturas ciegas concurrentes con RX");
    unsupported(sw.rand_access_pct, "Accesos de robustez");
    unsupported(sw.recfg_pct, "Reconfiguracion durante trafico");
    unsupported(sw.rst_pct, "Reset durante trafico");
    unsupported(wb.sel_odd_pct, "Seleccion WB irregular");
    unsupported(ser_stop2_err_pct, "Inyeccion STOP2");
    unsupported(ser_glitch_pct, "Glitch RX");
    unsupported(ser_baud_err_pct, "Desajuste de baud");
    unsupported(mdm_toggle_pct, "Estimulo modem");
  endfunction

  //Elige una opcion segun sus pesos, ej. pesos {1,1,2} dan 25 %, 25 % y 50 %
  //se sortea un numero entre 0 y la suma de los pesos y se le va restando cada peso hasta que cae dentro de uno
  //un peso en 0 nunca sale, y la suma nunca es 0 porque ya se reviso en read_vector
  function int unsigned choose_weight(int unsigned weights[]);
    int unsigned sum;
    int unsigned pick;
    sum = 0;
    foreach (weights[i])
      sum += weights[i];
    pick = $urandom_range(sum - 1, 0);
    foreach (weights[i]) begin
      if (pick < weights[i])
        return i;
      pick -= weights[i];
    end
    return 0;
  endfunction

endclass : uart_env_cfg
