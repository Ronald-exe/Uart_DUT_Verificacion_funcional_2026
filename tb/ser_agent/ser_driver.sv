//El driver serie se encarga de mandar cada caracter al DUT por srx, bit por bit
//El orden en la linea es: silencio (1) -> inicio (0) -> datos (LSB primero) -> paridad -> parada (1)
//uvm_driver #(ser_item) significa que este driver recibe items de tipo ser_item
class ser_driver extends uvm_driver #(ser_item);

  //Registramos en la fabrica
  `uvm_component_utils(ser_driver)

  //Utilizamos el ser_agent_cfg, de ahi sacamos la interfaz virtual y el formato de la linea
  ser_agent_cfg cfg;

  //Se crea el constructor, parent funciona para saber en que parte del arbol se encuentra el driver, como un path
  function new(string name = "ser_driver", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  //La fase de build nos funciona para crear y conseguir lo que necesita el componente
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    //config_db nos permite tomar el cfg que publico la prueba, si no lo encuentra UVM fatal detiene la simulacion
    if (!uvm_config_db#(ser_agent_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("NOCFG", "No se encontro el ser_agent_cfg")
  endfunction

  //En la fase de run se corre la simulacion, se usa task porque utiliza tiempo de simulacion
  task run_phase(uvm_phase phase);
    ser_item it; //se crea un handle a la clase de item, el objeto lo crea la secuencia
    cfg.vif.drv_cb.srx <= 1'b1; //al inicio dejamos la linea en reposo , es la entrada al dut
    forever begin
      seq_item_port.get_next_item(it); //espera hasta que la secuencia mande el siguiente caracter
      drive_char(it);                  //lo transforma en bits en la linea,toma ese carácter y mándalo bit por bit por srx y es un task que definiemos.
      seq_item_port.item_done();       //le avisa a la secuencia que ya termino y puede mandar otro
    end
  endtask

  //Pone un valor en srx y lo sostiene n ciclos de reloj
  //drv_cb es el clocking block del driver, @(drv_cb) espera un flanco de subida del reloj
  task put_bit(bit value, int unsigned n);
    cfg.vif.drv_cb.srx <= value;//se encarga de poner valur en el srx y lo deja por cierta cantidad de ciclos
    repeat (n) @(cfg.vif.drv_cb); //esta es la cantidad de ciclos
  endtask

  //Hacemos el envio de UN caracter completo
  task drive_char(ser_item it);
    int unsigned b = cfg.bit_cycles(); //ciclos que dura cada bit y la fucnion se hizo en el ser_agent_cfg

    //Con DL = 0 el DUT no tiene baudios, asi que no mandamos nada, el valor de 0 no da baudios de velocidad, no se envia nada
    if (cfg.dl == 0) begin
      `uvm_warning("SER_DRV", "DL = 0: no se manda el caracter")
      return;
    end

    //Imprimimos el caracter en el log (solo sale con UVM_HIGH)
    //covert2string: Convierte el item en texto
    `uvm_info("SER_DRV", it.convert2string(), UVM_HIGH) //Sirve para ver qué carácter mandó el driver justo antes de mandarlo

    put_bit(1'b1, it.gap * b);              //1. silencio: gap bits con la linea en 1
    put_bit(1'b0, b);                       //2. bit de inicio en 0, le avisa al DUT que viene un caracter
    for (int i = 0; i < cfg.n_bits(); i++)  //3. bits de dato, el LSB primero
      put_bit(it.data[i], b);
    if (cfg.pen)                            //4. bit de paridad, solo si esta habilitada
      put_bit(cfg.parity_bit(it.data), b);
    put_bit(1'b1, cfg.stop_cycles());       //5. bit(s) de parada en 1
  endtask

endclass
