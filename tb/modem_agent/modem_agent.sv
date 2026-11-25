//El agente de modem junta al driver, al monitor y al secuenciador
//Hereda de uvm_agent porque agrupa los componentes que trabajan con la misma interfaz
class modem_agent extends uvm_agent;

  //Registramos en la fabrica
  `uvm_component_utils(modem_agent)

  modem_driver drv;
  modem_monitor mon;
  //El secuenciador de UVM entrega modem_item al driver, no hace falta otra clase propia
  uvm_sequencer #(modem_item) sqr;

  //Se crea el constructor, parent es el ambiente que contiene al agente
  function new(string name = "modem_agent", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    drv = modem_driver::type_id::create("drv", this);
    mon = modem_monitor::type_id::create("mon", this);
    sqr = uvm_sequencer#(modem_item)::type_id::create("sqr", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    //Por esta conexion la secuencia entrega sus items al driver a traves del secuenciador
    drv.seq_item_port.connect(sqr.seq_item_export);
  endfunction

endclass : modem_agent
