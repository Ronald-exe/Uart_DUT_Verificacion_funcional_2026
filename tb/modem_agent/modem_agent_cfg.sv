//La configuracion de modem guarda la interfaz y los ajustes que comparte el agente
//Hereda de uvm_object porque guarda datos y no ejecuta las fases de un componente
class modem_agent_cfg extends uvm_object;

  //Registramos en la fabrica
  `uvm_object_utils(modem_agent_cfg)

  virtual modem_if vif; //handle a los cables de modem que publica tb_top
  int unsigned toggle_pct = 20; //probabilidad de cambiar cada entrada en un paso

  //100 ciclos dejan margen para que el DUT registre el cambio y lo mantenga estable
  //Es una espera fija del agente, no un knob nuevo del plan, por eso no tiene plusarg
  int unsigned step_cycles = 100;

  //Se crea el constructor, como es un objeto no lleva parent
  function new(string name = "modem_agent_cfg");
    super.new(name);
  endfunction

endclass : modem_agent_cfg
