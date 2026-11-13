//El agente serie se encarga de juntar al driver de srx, a los dos monitores (stx y srx) y al secuenciador
//Hereda de uvm_agent porque es un componente que agrupa a otros componentes
class ser_agent extends uvm_agent;

  //Registramos en la fabrica
  `uvm_component_utils(ser_agent)

  //Handles a los componentes del agente
  ser_driver                 drv;    //manda caracteres por srx
  ser_monitor                mon_tx; //arma los caracteres de stx (lo que transmite el DUT)
  ser_monitor                mon_rx; //arma los caracteres de srx (lo que recibe el DUT)
  uvm_sequencer #(ser_item)  sqr;    //secuenciador de UVM para items ser_item, no hace falta una clase propia

  //Se crea el constructor, parent es el ambiente que contiene al agente
  function new(string name = "ser_agent", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  //En la fase de build se crean los componentes llamando a la fabrica, el agente es el parent (this) de cada uno
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    drv    = ser_driver::type_id::create("drv", this);
    mon_tx = ser_monitor::type_id::create("mon_tx", this);
    mon_rx = ser_monitor::type_id::create("mon_rx", this);
    sqr    = uvm_sequencer#(ser_item)::type_id::create("sqr", this);
    //Usamos la misma clase de monitor dos veces, solo cambiamos que linea mira cada uno
    mon_tx.is_tx = 1;
    mon_rx.is_tx = 0;
  endfunction

  //En la fase de connect conectamos el driver con el secuenciador
  //por esta conexion pasan los items: secuencia -> sqr -> drv
  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    drv.seq_item_port.connect(sqr.seq_item_export);
  endfunction

endclass
