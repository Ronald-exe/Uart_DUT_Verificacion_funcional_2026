//El monitor solo es el encargado de mirar el bus
class wb_monitor extends uvm_monitor;

  `uvm_component_utils(wb_monitor) // se guarda en la fabrica

  wb_agent_cfg cfg;                  //se crea el handle al wb_agent_cfg para usarla interface virtual y los cables del driver
  uvm_analysis_port #(wb_item) ap;   // por aquí publica cada acceso y todos los que estan conectados lo reciben

  function new(string name = "wb_monitor", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this); //se crea el altavoz, el monitor es el dueno (this) y se llama ap
    if (!uvm_config_db#(wb_agent_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("NOCFG", "No se encontro el wb_agent_cfg")
  endfunction

  //En la fase de run el monitor mira el bus todo el tiempo
  //se usa task porque utiliza tiempo de simulacion
  task run_phase(uvm_phase phase);
    wb_item it; // se crea un handle a la clase de item
    forever begin
      //esperamos un ciclo de reloj (1), mon_cb = clocking block de solo lectura
      @(cfg.vif.mon_cb);

      //vemos si termino un acceso (2): cyc, stb y ack en 1
      // Ignore bus activity during reset because there is no completed transfer to publish -- alex
      // if (cfg.vif.mon_cb.cyc && cfg.vif.mon_cb.stb && cfg.vif.mon_cb.ack) begin
      if ((cfg.vif.mon_cb.rst === 0) && (cfg.vif.mon_cb.cyc === 1) &&
          (cfg.vif.mon_cb.stb === 1) && (cfg.vif.mon_cb.ack === 1)) begin

        //se crea un item nuevo para cada acceso
        it = wb_item::type_id::create("it"); //"créame un wb_item con el nombre "it", llama el constructor y hace que it sea un objeto

        //copiamos lo que se ve en el bus al item
        it.adr = cfg.vif.mon_cb.adr;
        it.sel = cfg.vif.mon_cb.sel;
        it.we  = cfg.vif.mon_cb.we;

        //el dato depende del sentido: escritura = lo que mando el maestro, lectura = lo que devolvio el DUT
        it.data = it.we ? cfg.vif.mon_cb.dat_m2s : cfg.vif.mon_cb.dat_s2m;

        //se imprime en el log (solo con UVM_HIGH) y se publica a todos los conectados
        //Si es escritura, guarda el dato que mandó el maestro (dat_m2s); si no, guarda el que devolvió el DUT (dat_s2m).
        `uvm_info("WB_MON", it.convert2string(), UVM_HIGH)
        // Keep unknown detection before the original two-state item conversion can hide it -- alex
        it.control_unknown = $isunknown({cfg.vif.mon_cb.adr, cfg.vif.mon_cb.sel, cfg.vif.mon_cb.we});
        it.unknown_seen = it.control_unknown;
        if (!it.we) begin
          it.data_unknown = $isunknown(cfg.vif.mon_cb.dat_s2m);
        end else begin
          it.data_unknown = $isunknown(cfg.vif.mon_cb.dat_m2s);
        end
        it.unknown_seen |= it.data_unknown;
        it.completed = 1;
        it.observed_at = $time;
        ap.write(it); //UVM le entrega el item a cada componente conectado
      end
    end
  endtask

endclass
