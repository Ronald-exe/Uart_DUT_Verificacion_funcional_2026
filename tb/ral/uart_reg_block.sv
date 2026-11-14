//El bloque se encarga de juntar todos los registros del UART en un solo modelo (seccion 12 del plan)
//uvm_reg_block es la clase de UVM que representa un grupo de registros, como el "mapa de registros" del DUT
//Aqui hacemos tres cosas: crear los registros, armar los mapas (en que direccion esta cada uno) y poner la puerta trasera
class uart_reg_block extends uvm_reg_block;

  //Registramos en la fabrica, el bloque tambien es un objeto y no lleva parent
  `uvm_object_utils(uart_reg_block)

  //Handles a los 12 registros, son rand para que el RAL los pueda aleatorizar si se lo pedimos
  rand uart_rbr RBR;
  rand uart_thr THR;
  rand uart_ier IER;
  rand uart_iir IIR;
  rand uart_fcr FCR;
  rand uart_lcr LCR;
  rand uart_mcr MCR;
  rand uart_lsr LSR;
  rand uart_msr MSR;
  rand uart_scr SCR;
  rand uart_dll DLL;
  rand uart_dlm DLM;

  //uvm_reg_map es la clase de UVM que dice en que direccion esta cada registro
  //Hacemos dos mapas porque las direcciones 0 y 1 cambian segun el bit DLAB de LCR (seccion 12.2 del plan)
  uvm_reg_map map_dlab0; //DLAB = 0: en 0 esta RBR/THR y en 1 esta IER
  uvm_reg_map map_dlab1; //DLAB = 1: en 0 esta DLL y en 1 esta DLM

  //Se crea el constructor, UVM_NO_COVERAGE porque la cobertura de registros la hacemos con cg_reg
  function new(string name = "uart_reg_block");
    super.new(name, UVM_NO_COVERAGE);
  endfunction

  //En build creamos todo el modelo, la llama la prueba o el ambiente despues de crear el bloque
  virtual function void build();

    //1. Creamos cada registro llamando a la fabrica, despues lo configuramos y llamamos a su build para crear sus campos
    //configure(this, null, "") significa: el dueno es este bloque, no tiene archivo de registros y la ruta de puerta trasera se pone en el paso 3
    RBR = uart_rbr::type_id::create("RBR"); RBR.configure(this, null, ""); RBR.build(); //.build() ejecuta esa función del registro en uart_reg_block
    THR = uart_thr::type_id::create("THR"); THR.configure(this, null, ""); THR.build();
    IER = uart_ier::type_id::create("IER"); IER.configure(this, null, ""); IER.build();
    IIR = uart_iir::type_id::create("IIR"); IIR.configure(this, null, ""); IIR.build();
    FCR = uart_fcr::type_id::create("FCR"); FCR.configure(this, null, ""); FCR.build();
    LCR = uart_lcr::type_id::create("LCR"); LCR.configure(this, null, ""); LCR.build();
    MCR = uart_mcr::type_id::create("MCR"); MCR.configure(this, null, ""); MCR.build();
    LSR = uart_lsr::type_id::create("LSR"); LSR.configure(this, null, ""); LSR.build();
    MSR = uart_msr::type_id::create("MSR"); MSR.configure(this, null, ""); MSR.build();
    SCR = uart_scr::type_id::create("SCR"); SCR.configure(this, null, ""); SCR.build();
    DLL = uart_dll::type_id::create("DLL"); DLL.configure(this, null, ""); DLL.build();
    DLM = uart_dlm::type_id::create("DLM"); DLM.configure(this, null, ""); DLM.build();

    //2. Creamos los dos mapas
    //create_map(nombre, direccion base, bytes por direccion, endianness)
    //base 0 y 1 byte por direccion porque cada registro es de 8 bits y su direccion es su numero (0 a 7)
    //la conversion a adr, sel y el carril del bus de 32 bits la hace el adaptador, no el mapa
    map_dlab0 = create_map("map_dlab0", 0, 1, UVM_LITTLE_ENDIAN);
    map_dlab1 = create_map("map_dlab1", 0, 1, UVM_LITTLE_ENDIAN);
    default_map = map_dlab0; //el mapa por defecto es el normal (DLAB = 0), lo usan write, read y las secuencias de UVM

    //add_reg(registro, direccion, acceso) pone un registro en una direccion del mapa
    //RBR y THR comparten la direccion 0, se puede porque uno es solo lectura y el otro solo escritura (igual IIR y FCR en la 2)
    map_dlab0.add_reg(RBR, 0, "RO");
    map_dlab0.add_reg(THR, 0, "WO");
    map_dlab0.add_reg(IER, 1, "RW");
    map_dlab1.add_reg(DLL, 0, "RW");
    map_dlab1.add_reg(DLM, 1, "RW");

    //Las direcciones 2 a 7 son iguales con DLAB = 0 o 1, por eso van en los dos mapas
    map_dlab0.add_reg(IIR, 2, "RO");  map_dlab1.add_reg(IIR, 2, "RO");
    map_dlab0.add_reg(FCR, 2, "WO");  map_dlab1.add_reg(FCR, 2, "WO");
    map_dlab0.add_reg(LCR, 3, "RW");  map_dlab1.add_reg(LCR, 3, "RW");
    map_dlab0.add_reg(MCR, 4, "RW");  map_dlab1.add_reg(MCR, 4, "RW");
    map_dlab0.add_reg(LSR, 5, "RO");  map_dlab1.add_reg(LSR, 5, "RO");
    map_dlab0.add_reg(MSR, 6, "RO");  map_dlab1.add_reg(MSR, 6, "RO");
    map_dlab0.add_reg(SCR, 7, "RW");  map_dlab1.add_reg(SCR, 7, "RW");

    //3. Puerta trasera: le decimos al RAL donde esta cada registro dentro del RTL
    //asi puede leerlo o escribirlo directo, sin pasar por el bus y sin efectos laterales
    //add_hdl_path pone la ruta del modulo uart_regs dentro del DUT, es como la carpeta donde estan los registros
    add_hdl_path("tb_top.dut.regs");
    //add_hdl_path_slice(senal, bit donde empieza dentro del registro, cuantos bits) une cada registro con su senal de uart_regs.v
    IER.add_hdl_path_slice("ier",     0, 4); //reg [3:0] ier
    LCR.add_hdl_path_slice("lcr",     0, 8); //reg [7:0] lcr
    MCR.add_hdl_path_slice("mcr",     0, 5); //reg [4:0] mcr
    MSR.add_hdl_path_slice("msr",     0, 8); //reg [7:0] msr
    SCR.add_hdl_path_slice("scratch", 0, 8); //reg [7:0] scratch
    //DLL y DLM son la mitad de reg [15:0] dl, su puerta trasera queda para E3 porque en E2 no se prueban

    //4. lock_model cierra el modelo: ya no se pueden agregar registros y UVM calcula las direcciones
    lock_model();
  endfunction

endclass
