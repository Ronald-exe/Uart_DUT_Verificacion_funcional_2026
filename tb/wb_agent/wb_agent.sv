//El agente junta al driver, al monitor y al secuenciador del bus Wishbone
class wb_agent extends uvm_agent;

  `uvm_component_utils(wb_agent) // se guarda en la fabrica

  //handles a los componentes del agente
  wb_driver                 drv; //mueve los cables
  wb_monitor                mon; //mira los cables y publica por ap
  uvm_sequencer #(wb_item)  sqr; //le pasa los items de la secuencia al driver (no hace falta crear una clase propia)

//Se crea el contructor y en esta caso parent funciona para saber en para del archivo se encentra el driver, como un path
  function new(string name = "wb_agent", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  //En la fase de build se crean los componentes, el agente es el parent (this) de cada uno
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    drv = wb_driver::type_id::create("drv", this);  //se crea el objeto llamando a la fac de driver
    mon = wb_monitor::type_id::create("mon", this);//se crea el objeto llamando a la fac de monitor
    sqr = uvm_sequencer#(wb_item)::type_id::create("sqr", this); //se crea el objeto de sqr llamando directame la clase de UVM
  endfunction

  //En la fase de connect se conecta el driver con el secuenciador
  //por esta conexion pasan los items: secuencia -> sqr -> drv
  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase); // fase de conexion entre componentes
    drv.seq_item_port.connect(sqr.seq_item_export); //Conecta el driver con el secuenciador
  endfunction

endclass
