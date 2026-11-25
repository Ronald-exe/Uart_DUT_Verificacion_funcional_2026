//El monitor de modem observa las cuatro entradas y las salidas RTS y DTR
//Hereda de uvm_monitor porque escucha las senales y publica lo que vio, sin manejarlas
class modem_monitor extends uvm_monitor;

  //Registramos en la fabrica
  `uvm_component_utils(modem_monitor)

  modem_agent_cfg cfg;
  //El analysis port publica cada cambio sin esperar respuesta de quien lo escucha
  //Puede quedar sin suscriptores mientras el scoreboard y la cobertura de modem se agregan despues
  uvm_analysis_port #(modem_item) ap;

  //Se crea el constructor, parent es el agente que contiene al monitor
  function new(string name = "modem_monitor", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap = new("ap", this);
    if (!uvm_config_db#(modem_agent_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("NOCFG", "No se encontro el modem_agent_cfg")
  endfunction

  task run_phase(uvm_phase phase);
    modem_item it;
    bit last_cts, last_dsr, last_ri, last_dcd;
    bit last_rts, last_dtr;

    //1. Tomamos la primera muestra del clocking block como referencia, no como un cambio
    @(cfg.vif.mon_cb);
    last_cts = cfg.vif.mon_cb.cts;
    last_dsr = cfg.vif.mon_cb.dsr;
    last_ri = cfg.vif.mon_cb.ri;
    last_dcd = cfg.vif.mon_cb.dcd;
    last_rts = cfg.vif.mon_cb.rts;
    last_dtr = cfg.vif.mon_cb.dtr;

    forever begin
      //2. Esperamos otra muestra, mon_cb solo nos deja leer las senales
      @(cfg.vif.mon_cb);

      //3. Publicamos solo si alguna de las seis senales cambio
      //El monitor no decide si la polaridad o los deltas de MSR estan bien, eso le toca al scoreboard
      if ((cfg.vif.mon_cb.cts != last_cts) ||
          (cfg.vif.mon_cb.dsr != last_dsr) ||
          (cfg.vif.mon_cb.ri != last_ri) ||
          (cfg.vif.mon_cb.dcd != last_dcd) ||
          (cfg.vif.mon_cb.rts != last_rts) ||
          (cfg.vif.mon_cb.dtr != last_dtr)) begin
        it = modem_item::type_id::create("it");
        it.cts = cfg.vif.mon_cb.cts;
        it.dsr = cfg.vif.mon_cb.dsr;
        it.ri = cfg.vif.mon_cb.ri;
        it.dcd = cfg.vif.mon_cb.dcd;
        it.rts = cfg.vif.mon_cb.rts;
        it.dtr = cfg.vif.mon_cb.dtr;
        `uvm_info("MDM_MON", it.convert2string(), UVM_HIGH)
        ap.write(it);

        //Esta muestra queda como referencia para comparar el siguiente ciclo
        last_cts = it.cts;
        last_dsr = it.dsr;
        last_ri = it.ri;
        last_dcd = it.dcd;
        last_rts = it.rts;
        last_dtr = it.dtr;
      end
    end
  endtask

endclass : modem_monitor
