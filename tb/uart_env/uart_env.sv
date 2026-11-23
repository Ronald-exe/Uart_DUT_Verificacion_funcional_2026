
//Adaptador con pausa: es el mismo adaptador del RAL (uart_reg_adapter) pero le agrega 2 ciclos libres antes de cada acceso
//heredamos de nuestro adaptador en vez de cambiarlo, asi no tocamos el adaptador ni el driver Wishbone originales
class uart_timed_reg_adapter extends uart_reg_adapter;

  //Registramos en la fabrica
  `uvm_object_utils(uart_timed_reg_adapter)

  //Se crea el constructor, es un objeto y no lleva parent
  function new(string name = "uart_timed_reg_adapter");
    super.new(name);
  endfunction

  //reg2bus: dejamos que el adaptador original arme el item (adr, sel y carril) y solo le cambiamos el delay
  //el driver necesita un poco de espacio entre accesos seguidos del RAL
  virtual function uvm_sequence_item reg2bus(const ref uvm_reg_bus_op rw);
    uvm_sequence_item base_item; //handle generico: reg2bus devuelve uvm_sequence_item, pero el objeto adentro es un wb_item
    wb_item item;                //handle de tipo wb_item al MISMO objeto, asi podemos tocar item.delay
    base_item = super.reg2bus(rw); //super llama al reg2bus del adaptador original
    //$cast revisa que de verdad sea un wb_item, si no lo es detenemos la simulacion
    if (!$cast(item, base_item))
      `uvm_fatal("UART_ADAPTER", "El adaptador original no devolvio wb_item")
    item.delay = 2; //2 ciclos libres antes del acceso
    return item;
  endfunction

endclass : uart_timed_reg_adapter

//El ambiente se encarga de crear y conectar todas las piezas, asi la prueba solo tiene que configurarlo y arrancarlo
//el estimulo vive en las secuencias y las comparaciones en el scoreboard
//Hereda de uvm_env porque es el componente que agrupa a los agentes, el RAL y el scoreboard
class uart_env extends uvm_env;

  //Registramos en la fabrica
  `uvm_component_utils(uart_env)

  //Handles a todo lo que vive dentro del ambiente
  uart_env_cfg cfg;                        //configuracion que publico la prueba
  wb_agent wb_agt;                         //agente Wishbone
  ser_agent ser_agt;                       //agente serie
  uart_reg_block regm;                     //modelo de registros (RAL)
  uart_timed_reg_adapter adapter;          //adaptador del RAL con pausa
  uvm_reg_predictor #(wb_item) predictor;  //predictor de UVM, actualiza el espejo del RAL con lo que ve el monitor
  uart_scoreboard scb;                     //scoreboard que compara TX y RX
  uart_coverage cov;                       //cobertura funcional (covergroups)
  uart_vsequencer vseqr;                   //secuenciador virtual donde corre la secuencia principal

  //Se crea el constructor, parent es la prueba que contiene al ambiente
  function new(string name = "uart_env", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  //En la fase de build tomamos la configuracion, se la publicamos a cada hijo y despues creamos los hijos
  //hay que publicar antes de crear porque los drivers y monitores buscan su cfg en su propio build_phase
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(uart_env_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("UART_ENV_CFG", "Ambiente sin configuracion")
    //Le damos a cada agente su propio cfg (el que ya esperan nuestros agentes)
    //el agente serie recibe un solo cfg compartido, asi el driver y los dos monitores usan el mismo formato de linea
    uvm_config_db#(wb_agent_cfg)::set(this, "wb_agt*", "cfg", cfg.wb);
    uvm_config_db#(ser_agent_cfg)::set(this, "ser_agt*", "cfg", cfg.ser);
    uvm_config_db#(uart_env_cfg)::set(this, "scb", "cfg", cfg);
    uvm_config_db#(uart_env_cfg)::set(this, "cov", "cfg", cfg);
    //Creamos los componentes llamando a la fabrica, el ambiente es el parent (this) de cada uno
    wb_agt = wb_agent::type_id::create("wb_agt", this);
    ser_agt = ser_agent::type_id::create("ser_agt", this);
    //El RAL es un objeto y no tiene build_phase, por eso llamamos su build a mano, si no los mapas y registros quedan vacios
    regm = uart_reg_block::type_id::create("regm");
    regm.build();
    adapter = uart_timed_reg_adapter::type_id::create("adapter");
    predictor = uvm_reg_predictor#(wb_item)::type_id::create("predictor", this);
    scb = uart_scoreboard::type_id::create("scb", this);
    cov = uart_coverage::type_id::create("cov", this);
    vseqr = uart_vsequencer::type_id::create("vseqr", this);
  endfunction

  //En la fase de connect conectamos todo, se hace aqui porque en este punto ya existen todos los hijos y sus puertos
  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    //RAL: DLAB cambia que registro hay en cada direccion pero el bus es el mismo
    //por eso los dos mapas usan el mismo secuenciador Wishbone y el mismo adaptador
    regm.map_dlab0.set_sequencer(wb_agt.sqr, adapter);
    regm.map_dlab1.set_sequencer(wb_agt.sqr, adapter);
    //Apagamos la prediccion automatica, el espejo solo se actualiza con lo que ve el monitor (el predictor)
    //si no, cada acceso del RAL se predeciria dos veces
    regm.map_dlab0.set_auto_predict(0);
    regm.map_dlab1.set_auto_predict(0);
    predictor.map = regm.map_dlab0;  //el predictor empieza con el mapa normal (DLAB = 0)
    predictor.adapter = adapter;     //usa bus2reg del adaptador para traducir lo que ve
    //El monitor Wishbone publica cada acceso a dos lugares: el predictor (registros del RAL) y el scoreboard (datos)
    wb_agt.mon.ap.connect(predictor.bus_in);
    wb_agt.mon.ap.connect(scb.wb_in.analysis_export);
    //Los nombres siguen al DUT: stx es lo que el DUT manda y srx lo que recibe
    //cada monitor va a una entrada distinta del scoreboard, asi el scoreboard sabe la direccion por la conexion
    ser_agt.mon_tx.ap.connect(scb.tx_in.analysis_export);
    ser_agt.mon_rx.ap.connect(scb.rx_in.analysis_export);
    //La cobertura escucha a los mismos tres monitores, un analysis port puede tener varios conectados
    wb_agt.mon.ap.connect(cov.wb_in.analysis_export);
    ser_agt.mon_tx.ap.connect(cov.tx_in.analysis_export);
    ser_agt.mon_rx.ap.connect(cov.rx_in.analysis_export);
    //Al secuenciador virtual solo le damos handles, no es otra conexion de driver
    //los secuenciadores reales de cada agente siguen manejando el saludo con su driver
    vseqr.wb_sqr = wb_agt.sqr;
    vseqr.ser_sqr = ser_agt.sqr;
    vseqr.regm = regm;
    vseqr.predictor = predictor;
    vseqr.cfg = cfg;
  endfunction

  //En end_of_elaboration UVM ya creo y conecto todo, asi que imprimimos el arbol de componentes en el log
  //sirve para ver de un vistazo que el ambiente quedo armado como en el diagrama del plan (seccion 9.1)
  //no revisamos las interfaces aqui porque la prueba ya da UVM_FATAL si falta alguna (uart_base_test, build_phase)
  function void end_of_elaboration_phase(uvm_phase phase);
    super.end_of_elaboration_phase(phase);
    uvm_top.print_topology();
  endfunction

endclass : uart_env

