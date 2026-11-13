//El monitor serie solo es el encargado de mirar UNA linea y armar los caracteres que pasan por ella
//El agente crea dos monitores de esta misma clase: uno mira stx (lo que transmite el DUT) y otro mira srx (lo que recibe)
class ser_monitor extends uvm_monitor;

  //Registramos en la fabrica
  `uvm_component_utils(ser_monitor)

  ser_agent_cfg cfg;                //se crea el handle al ser_agent_cfg para usar la interfaz virtual y el formato de la linea
  uvm_analysis_port #(ser_item) ap; //por aqui publica cada caracter y todos los que estan conectados lo reciben (como un grupo de WhatsApp)
  bit is_tx = 1;                    //1 = mira stx, 0 = mira srx, lo pone el agente al crearlo

  //Se crea el constructor, parent es el agente que lo contiene
  function new(string name = "ser_monitor", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this); //se crea el altavoz, el monitor es el dueno (this)
    if (!uvm_config_db#(ser_agent_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("NOCFG", "No se encontro el ser_agent_cfg")
  endfunction

  //Leemos la linea que le toca a este monitor, mon_cb es el clocking block de solo lectura
  function bit line();
    return is_tx ? cfg.vif.mon_cb.stx : cfg.vif.mon_cb.srx;
  endfunction

  //Esperamos n ciclos de reloj
  task wait_cycles(int unsigned n);
    repeat (n) @(cfg.vif.mon_cb);
  endtask

  //En la fase de run el monitor mira la linea todo el tiempo, se usa task porque utiliza tiempo de simulacion
  task run_phase(uvm_phase phase);
    ser_item     it; //handle al item, el objeto se crea con create en cada caracter
    int unsigned b;  //ciclos que dura cada bit
    bit          p;  //bit de paridad que se leyo

    forever begin
      //1. Esperamos el inicio: la linea baja a 0. Con DL = 0 no hay baudios y no tiene sentido leer
      @(cfg.vif.mon_cb);
      if (line() !== 1'b0 || cfg.dl == 0) continue;
      b = cfg.bit_cycles();

      //2. Vamos a la mitad del bit de inicio y vemos que siga en 0, si volvio a 1 era un glitch (AMB-13)
      //desde aqui leemos siempre a la mitad de cada bit, igual que el receptor del DUT (AMB-12)
      wait_cycles(b / 2);
      if (line() !== 1'b0) continue;

      //3. Creamos el item llamando a la fabrica y leemos los bits de dato, el LSB primero
      it = ser_item::type_id::create("it");
      it.data = '0;
      for (int i = 0; i < cfg.n_bits(); i++) begin
        wait_cycles(b);
        it.data[i] = line();
      end

      //4. Si la paridad esta habilitada la leemos y la comparamos con la que deberia ser
      if (cfg.pen) begin
        wait_cycles(b);
        p = line();
        it.parity_err = (p != cfg.parity_bit(it.data));
      end

      //5. Leemos el bit de parada, si esta en 0 es error de trama (solo se revisa el primero, AMB-08)
      wait_cycles(b);
      it.frame_err = (line() == 1'b0);

      //6. Publicamos el caracter a todos los conectados (scoreboard) y lo imprimimos con UVM_HIGH
      `uvm_info("SER_MON", $sformatf("%s %s", is_tx ? "TX" : "RX", it.convert2string()), UVM_HIGH)
      ap.write(it);

      //7. Si la linea quedo en 0 (break o error de trama) esperamos a que vuelva a 1 antes de buscar otro inicio
      while (line() !== 1'b1) @(cfg.vif.mon_cb);
    end
  endtask

endclass
