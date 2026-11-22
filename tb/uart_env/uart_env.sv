
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
    uvm_sequence_item base_item; //lo que devuelve el adaptador original (tipo generico)
    wb_item item;                //el mismo item ya convertido a wb_item
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
    //Creamos los componentes llamando a la fabrica, el ambiente es el parent (this) de cada uno
    wb_agt = wb_agent::type_id::create("wb_agt", this);
    ser_agt = ser_agent::type_id::create("ser_agt", this);
    //El RAL es un objeto y no tiene build_phase, por eso llamamos su build a mano, si no los mapas y registros quedan vacios
    regm = uart_reg_block::type_id::create("regm");
    regm.build();
    adapter = uart_timed_reg_adapter::type_id::create("adapter");
    predictor = uvm_reg_predictor#(wb_item)::type_id::create("predictor", this);
    scb = uart_scoreboard::type_id::create("scb", this);
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
    //Al secuenciador virtual solo le damos handles, no es otra conexion de driver
    //los secuenciadores reales de cada agente siguen manejando el saludo con su driver
    vseqr.wb_sqr = wb_agt.sqr;
    vseqr.ser_sqr = ser_agt.sqr;
    vseqr.regm = regm;
    vseqr.predictor = predictor;
    vseqr.cfg = cfg;
  endfunction

  //Revisa que un puerto este conectado al destino correcto
  //no basta con contar conexiones, la cantidad puede estar bien y el destino mal, por eso tambien se revisa el nombre y el handle
  //recibe uvm_port_component_base para que sirva con puertos de cualquier tipo de item
  function void check_link(uvm_port_component_base source,
                           uvm_port_component_base destination,
                           int unsigned expected_count);
    uvm_port_list connected;  //lista de destinos conectados al puerto
    string destination_name;
    if ((source == null) || (destination == null)) begin
      `uvm_fatal("UART_CONNECTION", "A required TLM endpoint is null")
      return;
    end
    source.get_connected_to(connected);
    //1. la cantidad de conexiones tiene que ser la esperada
    if (connected.num() != expected_count) begin
      `uvm_fatal("UART_CONNECTION", $sformatf("%s has %0d direct connections -- expected %0d",
                 source.get_full_name(), connected.num(), expected_count))
      return;
    end
    //2. el destino tiene que estar en la lista, buscado por su nombre completo
    destination_name = destination.get_full_name();
    if (!connected.exists(destination_name)) begin
      `uvm_fatal("UART_CONNECTION", $sformatf("Missing connection from %s to %s",
                 source.get_full_name(), destination_name))
      return;
    end
    //3. y tiene que ser el mismo objeto, no otro con el mismo nombre
    if (connected[destination_name] != destination) begin
      `uvm_fatal("UART_CONNECTION", $sformatf("Wrong destination handle for %s", destination_name))
    end
  endfunction

  //En end_of_elaboration UVM ya resolvio todas las conexiones, asi que aqui revisamos que el ambiente quedo bien armado
  //lo hacemos antes del trafico porque en UVM un analysis port sin nadie conectado no da error, y la prueba pasaria sin chequear nada
  function void end_of_elaboration_phase(uvm_phase phase);
    super.end_of_elaboration_phase(phase);

    //1. Primero que existan todos los componentes, asi un null da nuestro mensaje y no un error de puntero nulo
    if ((cfg == null) || (wb_agt == null) || (ser_agt == null) ||
        (regm == null) || (adapter == null) || (predictor == null) ||
        (scb == null) || (vseqr == null)) begin
      `uvm_fatal("UART_CONNECTION", "A required environment component or configuration is missing")
      return;
    end
    if ((cfg.wb == null) || (cfg.ser == null) ||
        (wb_agt.drv == null) || (wb_agt.mon == null) || (wb_agt.sqr == null) ||
        (ser_agt.drv == null) || (ser_agt.mon_tx == null) ||
        (ser_agt.mon_rx == null) || (ser_agt.sqr == null) ||
        (scb.wb_in == null) || (scb.tx_in == null) || (scb.rx_in == null) ||
        (regm.map_dlab0 == null) || (regm.map_dlab1 == null)) begin
      `uvm_fatal("UART_CONNECTION", "A required agent child, scoreboard input, or register map is missing")
      return;
    end

    //2. Que las interfaces virtuales existan, tener el cfg no basta porque su vif puede venir vacia
    if ((cfg.wb.vif == null) || (cfg.ser.vif == null) || (cfg.mdm_vif == null)) begin
      `uvm_fatal("UART_CONNECTION", "A required virtual interface is null")
    end
    //3. Que cada hijo use el MISMO cfg que el ambiente, si usara otro podria tener otra interfaz u otro formato de linea
    if ((wb_agt.drv.cfg != cfg.wb) || (wb_agt.mon.cfg != cfg.wb) ||
        (ser_agt.drv.cfg != cfg.ser) || (ser_agt.mon_tx.cfg != cfg.ser) ||
        (ser_agt.mon_rx.cfg != cfg.ser) || (scb.cfg != cfg)) begin
      `uvm_fatal("UART_CONNECTION", "An agent child or scoreboard is using the wrong configuration")
    end
    //4. Que cada monitor serie mire la linea correcta
    if (!ser_agt.mon_tx.is_tx || ser_agt.mon_rx.is_tx) begin
      `uvm_fatal("UART_CONNECTION", "Serial monitors are assigned to the wrong lines")
    end

    //5. Que cada puerto tenga la cantidad de conexiones esperada (size cuenta los destinos finales)
    //el monitor Wishbone tiene 2: predictor y scoreboard
    if ((wb_agt.drv.seq_item_port.size() != 1) ||
        (ser_agt.drv.seq_item_port.size() != 1) ||
        (wb_agt.mon.ap.size() != 2) ||
        (ser_agt.mon_tx.ap.size() != 1) || (ser_agt.mon_rx.ap.size() != 1)) begin
      `uvm_fatal("UART_CONNECTION", "A required port has an unexpected number of resolved connections")
    end
    //6. Que cada conexion llegue al destino correcto
    check_link(wb_agt.drv.seq_item_port.get_comp(), wb_agt.sqr.seq_item_export.get_comp(), 1);
    check_link(ser_agt.drv.seq_item_port.get_comp(), ser_agt.sqr.seq_item_export.get_comp(), 1);
    check_link(wb_agt.mon.ap.get_comp(), predictor.bus_in.get_comp(), 2);
    check_link(wb_agt.mon.ap.get_comp(), scb.wb_in.analysis_export.get_comp(), 2);
    check_link(ser_agt.mon_tx.ap.get_comp(), scb.tx_in.analysis_export.get_comp(), 1);
    check_link(ser_agt.mon_rx.ap.get_comp(), scb.rx_in.analysis_export.get_comp(), 1);

    //7. El secuenciador virtual usa handles y no puertos TLM, por eso se revisan aparte
    if ((vseqr.wb_sqr != wb_agt.sqr) || (vseqr.ser_sqr != ser_agt.sqr) ||
        (vseqr.regm != regm) || (vseqr.predictor != predictor) || (vseqr.cfg != cfg)) begin
      `uvm_fatal("UART_CONNECTION", "The virtual sequencer has a missing or incorrect reference")
    end

    //8. Que los dos mapas del RAL lleguen al bus real con el mismo adaptador que usa el predictor y sin prediccion automatica
    if ((regm.map_dlab0.get_sequencer() != wb_agt.sqr) ||
        (regm.map_dlab1.get_sequencer() != wb_agt.sqr) ||
        (regm.map_dlab0.get_adapter() != adapter) ||
        (regm.map_dlab1.get_adapter() != adapter) ||
        regm.map_dlab0.get_auto_predict() || regm.map_dlab1.get_auto_predict() ||
        (predictor.adapter != adapter) || (predictor.map != regm.map_dlab0)) begin
      `uvm_fatal("UART_CONNECTION", "RAL maps or predictor are not connected as expected")
    end
    `uvm_info("UART_CONNECTION", "Environment connection checks completed", UVM_LOW)
  endfunction

endclass : uart_env

