class wb_driver extends uvm_driver #(wb_item); 

//Guardamos en el fact
`uvm_component_utils(wb_driver)

//utilizamos la interfaz vitual del wb_agente_cfg
wb_agent_cfg cfg;

//Se crea el contructor y en esta caso parent funciona para saber en para del archivo se encentra el driver, como un path
function new(string name = "wb_driver", uvm_component parent = null);
    super.new(name,parent);
endfunction

//Utilizamos la interfaz virtual del wb_agent_cfg
//La parte the build nos funciona para crear los componentes
function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    //vemos si pudo encontrar la interfaz virtul
    //config_db nos permite tomar el handle de la interfaz virtual y conectarlo al driver en caso de que exista o se encuentre
    if (!uvm_config_db#(wb_agent_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("NOCFG", "No se encontro el wb_agent_cfg")
    //UVM fatal detiene la simulacion en caso de que no se encuentre la interfaz
endfunction

//En la fase de run se corre la simulacion, esta termina hasta que todos las objeciones hayan sido solcionados.
// Raise aun no termina y drop significa que ya termino la objecion.
//se usa task porque utiliza tiempo de simulacion

task run_phase(uvm_phase phase);
    wb_item it;      // se crea un handle a la clase de item
    forever begin
        seq_item_port.get_next_item(it); //enviar lel item de la secuencia al secuenciador, esperando al turno
        drive_item(it); // encargado de tranforma el item en senales 
        seq_item_port.item_done(); //le avisa a la secuencia que el item ya llego.
    end
endtask


//Hacemos el acceso al al Wishbone
task drive_item(wb_item it);
    //esperamos el dalay entre ciclos (1)
    repeat (it.delay) @(cfg.vif.drv_cb); //espera los flacos de reloj cb = clocking block
    // 2. subir cyc y poner los datos del acceso
    cfg.vif.drv_cb.cyc     <= 1'b1;
    cfg.vif.drv_cb.adr     <= it.adr;
    cfg.vif.drv_cb.sel     <= it.sel;
    cfg.vif.drv_cb.we      <= it.we;
    cfg.vif.drv_cb.dat_m2s <= it.data;

    // 3. esperar it.stb_delay ciclos y subir stb
    repeat (it.stb_delay) @(cfg.vif.drv_cb);
    cfg.vif.drv_cb.stb <= 1'b1;

    // 4. esperar hasta que ack sea 1 (el DUT tarda unos 2 ciclos)
    //En caso de que este listo ejecuta el while, en caso contario espera
    do @(cfg.vif.drv_cb); while (cfg.vif.drv_cb.ack !== 1'b1);

    // 5. si es lectura: guardar en el item el dato que devolvio el DUT
    if (!it.we) it.data = cfg.vif.drv_cb.dat_s2m;

    // 6. bajar cyc y stb: termina el acceso
    cfg.vif.drv_cb.cyc <= 1'b0;
    cfg.vif.drv_cb.stb <= 1'b0;
endtask


endclass
