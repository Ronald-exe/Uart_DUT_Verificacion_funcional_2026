//El driver de modem se encarga de mover CTS, DSR, RI y DCD hacia el DUT
//Hereda de uvm_driver porque recibe items del secuenciador y los convierte en senales
class modem_driver extends uvm_driver #(modem_item);

  //Registramos en la fabrica
  `uvm_component_utils(modem_driver)

  modem_agent_cfg cfg;

  //Se crea el constructor, parent es el agente que contiene al driver
  function new(string name = "modem_driver", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    //config_db entrega el mismo cfg que el ambiente publico para todos los hijos del agente
    if (!uvm_config_db#(modem_agent_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("NOCFG", "No se encontro el modem_agent_cfg")
  endfunction

  task run_phase(uvm_phase phase);
    modem_item it;

    //1. Dejamos las entradas en reposo, igual que los valores iniciales de tb_top
    cfg.vif.drv_cb.cts <= 1'b1;
    cfg.vif.drv_cb.dsr <= 1'b1;
    cfg.vif.drv_cb.ri <= 1'b1;
    cfg.vif.drv_cb.dcd <= 1'b1;

    forever begin
      //2. get_next_item espera a que el secuenciador entregue el siguiente paso
      seq_item_port.get_next_item(it);

      //3. Solo manejamos entradas del DUT, RTS y DTR las maneja el propio UART
      //drv_cb aplica los cambios con el tiempo de salida definido en la interfaz
      cfg.vif.drv_cb.cts <= it.cts;
      cfg.vif.drv_cb.dsr <= it.dsr;
      cfg.vif.drv_cb.ri <= it.ri;
      cfg.vif.drv_cb.dcd <= it.dcd;

      //4. Sostenemos el paso antes de aceptar otro cambio
      repeat (it.hold) @(cfg.vif.drv_cb);

      //5. item_done le avisa a la secuencia que puede mandar el siguiente item
      seq_item_port.item_done();
    end
  endtask

endclass : modem_driver
