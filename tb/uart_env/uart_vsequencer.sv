//El secuenciador virtual se encarga de guardar en un solo lugar los handles que necesita la secuencia principal
//Se llama virtual porque no tiene un driver propio, cada agente sigue manejando su propio protocolo
//la secuencia principal corre aqui y desde aqui manda secuencias a los secuenciadores reales de cada agente
class uart_vsequencer extends uvm_sequencer;

  //Registramos en la fabrica
  `uvm_component_utils(uart_vsequencer)

  //Handles a los secuenciadores reales de los agentes, asi sus drivers siguen con el saludo normal de UVM (get_next_item / item_done)
  uvm_sequencer #(wb_item) wb_sqr;   //secuenciador del agente Wishbone
  uvm_sequencer #(ser_item) ser_sqr; //secuenciador del agente serie
  uvm_sequencer #(modem_item) mdm_sqr; //secuenciador del agente de modem

  uart_reg_block regm; //handle al RAL, para hacer write y read de registros por nombre
  //handle al predictor, lo necesitamos porque cambiar DLAB cambia como se leen las direcciones del bus (map_dlab0 o map_dlab1)
  uvm_reg_predictor #(wb_item) predictor;
  uart_env_cfg cfg; //handle a la configuracion, de ahi la secuencia saca los knobs

  //Se crea el constructor, parent es el ambiente que lo contiene
  //los handles de arriba no se buscan con config_db, se los asigna el ambiente en su connect_phase
  function new(string name = "uart_vsequencer", uvm_component parent = null);
    super.new(name, parent);
  endfunction

endclass : uart_vsequencer
