//La prueba base es la unica prueba del proyecto, lo que cambia entre corridas son la semilla y los plusargs
//asi cambiar la cantidad de trafico o la semilla no necesita otra prueba ni recompilar
//Hereda de uvm_test porque es la raiz del arbol de componentes (uvm_test_top)
class uart_base_test extends uvm_test;

  //Registramos en la fabrica, asi run_test() la puede crear con +UVM_TESTNAME=uart_base_test
  `uvm_component_utils(uart_base_test)

  uart_env_cfg cfg; //handle a la configuracion de todo el ambiente
  uart_env env;     //handle al ambiente

  //Se crea el constructor, la prueba no tiene parent porque es la primera del arbol
  function new(string name = "uart_base_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  //En la fase de build creamos la configuracion, la llenamos y despues creamos el ambiente
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    //El adaptador solo sabe traducir el bus de 32 bits, si se compila con el de 8 bits detenemos la simulacion
`ifdef DATA_BUS_WIDTH_8
    `uvm_fatal("UART_BUS_WIDTH", "El adaptador original requiere el bus de 32 bits; BUS8 pendiente")
`endif
    cfg = uart_env_cfg::type_id::create("cfg"); //se crea la configuracion llamando a la fabrica
    //Sacamos del config_db las tres interfaces virtuales que puso tb_top y las guardamos en la configuracion
    if (!uvm_config_db#(virtual wb_if)::get(this, "", "wb_vif", cfg.wb.vif))
      `uvm_fatal("UART_VIF", "No se encontro wb_vif")
    if (!uvm_config_db#(virtual uart_ser_if)::get(this, "", "ser_vif", cfg.ser.vif))
      `uvm_fatal("UART_VIF", "No se encontro ser_vif")
    if (!uvm_config_db#(virtual modem_if)::get(this, "", "mdm_vif", cfg.mdm_vif))
      `uvm_fatal("UART_VIF", "No se encontro mdm_vif")
    //Leemos los plusargs en un solo lugar, le pasamos this para que los mensajes salgan con la ruta de la prueba
    cfg.parse_plusargs(this);
    //Publicamos la configuracion para el ambiente y despues creamos el ambiente, que la va a buscar con get
    uvm_config_db#(uart_env_cfg)::set(this, "env", "cfg", cfg);
    env = uart_env::type_id::create("env", this);
  endfunction

  //En end_of_elaboration ya existe todo el ambiente, aqui elegimos que registros revisa la prueba de reset del RAL
  //solo dejamos LCR, IER y SCR porque tienen un valor de reset estable que se puede leer y tienen puerta trasera
  //a los demas les ponemos NO_REG_HW_RESET_TEST para que esa secuencia los salte, los otros chequeos no cambian
  function void end_of_elaboration_phase(uvm_phase phase);
    uvm_reg registers[$]; //cola con todos los registros del RAL
    super.end_of_elaboration_phase(phase);
    env.regm.get_registers(registers);
    foreach (registers[i]) begin
      if ((registers[i] != env.regm.LCR) &&
          (registers[i] != env.regm.IER) &&
          (registers[i] != env.regm.SCR)) begin
        //uvm_resource_db guarda la marca con el nombre completo del registro, la secuencia de reset la lee y lo salta
        uvm_resource_db#(bit)::set({"REG::", registers[i].get_full_name()},
                                  "NO_REG_HW_RESET_TEST", 1, this);
      end
    end
  endfunction

  //En la fase de run se corre la simulacion, se usa task porque utiliza tiempo de simulacion
  task run_phase(uvm_phase phase);
    uart_main_vseq seq; //handle a la secuencia principal
    bit completed;      //1 si la secuencia termino sola
    //Levantamos la objecion antes de empezar, asi UVM no termina mientras todavia hay trafico
    phase.raise_objection(this);
    seq = uart_main_vseq::type_id::create("main_sequence");
    completed = 0;
    //fork corre dos cosas en paralelo y join_any sigue con la primera que termine:
    //  a) la secuencia principal en el secuenciador virtual
    //  b) un watchdog: si la secuencia se tarda mas de timeout_cycles detenemos la simulacion, si no se quedaria esperando para siempre
    fork
      begin
        seq.start(env.vseqr);
        completed = 1;
      end
      begin
        repeat (cfg.timeout_cycles) @(cfg.wb.vif.drv_cb);
        `uvm_fatal("UART_TIMEOUT", "La secuencia excedio su presupuesto de ciclos")
      end
    join_any
    disable fork; //matamos la rama que sigue esperando
    //Si la secuencia termino, esperamos 3 ciclos para que lo ultimo que vieron los monitores llegue al scoreboard
    //y le pasamos cuantos caracteres TX y RX se planearon, asi revisa que no falte ninguno
    if (completed) begin
      repeat (3) @(cfg.wb.vif.drv_cb);
      env.scb.expect_totals(seq.planned_tx, seq.planned_rx);
    end
    phase.drop_objection(this); //bajamos la objecion, ya podemos terminar
  endtask

  //En la fase de report contamos los errores y decimos si la prueba paso
  //se hace aqui y no antes porque check_phase del scoreboard tambien puede reportar errores al final
  function void report_phase(uvm_phase phase);
    uvm_report_server reports; //el servidor de reportes de UVM lleva la cuenta de cada tipo de mensaje
    super.report_phase(phase);
    reports = uvm_report_server::get_server();
    if ((reports.get_severity_count(UVM_ERROR) == 0) &&
        (reports.get_severity_count(UVM_FATAL) == 0))
      `uvm_info("UART_E2_PASS", "Sin errores en el alcance E2: reset RAL y datos normales TX/RX", UVM_NONE)
    else
      `uvm_info("UART_E2_FAIL", "Hay errores: revisar los reportes UVM anteriores", UVM_NONE)
  endfunction

endclass : uart_base_test
