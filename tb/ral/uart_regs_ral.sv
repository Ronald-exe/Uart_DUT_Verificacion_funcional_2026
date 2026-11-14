//Este archivo se encarga de crear una clase por cada registro del UART para el RAL (seccion 12.1 del plan)
//Asi la prueba puede escribir "LCR = 83h" sin preocuparse por adr, sel y el carril, de eso se encarga el adaptador
//Todos los registros del UART son de 8 bits

//RBR: es donde se lee el dato que llego por la linea serie (direccion 0 con DLAB = 0)
//uvm_reg es la clase de UVM que representa UN registro, por eso heredamos de ella
class uart_rbr extends uvm_reg;

  //Registramos en la fabrica, los registros son objetos y no componentes, por eso usamos uvm_object_utils y no llevan parent
  `uvm_object_utils(uart_rbr)

  //uvm_reg_field es la clase de UVM que representa un campo, o sea un grupo de bits dentro del registro
  //se crea un handle al campo y es rand para que el RAL pueda aleatorizar el valor que se escribe
  //uvm_reg_field ya es parte de UVM y crea el campo y el handle es data
  rand uvm_reg_field data;

  //Se crea el constructor, a super.new le decimos el nombre, que el registro es de 8 bits y que no tiene cobertura propia (UVM_NO_COVERAGE)
  //la cobertura de los registros la hacemos nosotros con covergroups, por eso no usamos la del RAL
  function new(string name = "uart_rbr");
    super.new(name, 8, UVM_NO_COVERAGE); // nombre, tamano del registro y si/no covertura
  endfunction

  //En build creamos y configuramos los campos del registro
  //se llama build y no build_phase porque el registro es un objeto, no tiene fases como los componentes, lo llama el bloque del RAL
  virtual function void build(); // solo usamos buil por ser un objeto
    data = uvm_reg_field::type_id::create("data"); //se crea el objeto del campo llamando a la fabrica
    //configure le dice al RAL como es el campo, sus argumentos en orden son:
    //this = el registro dueno del campo, 8 = cuantos bits tiene, 0 = en que bit empieza,
    //"RO" = solo lectura, 1 = volatil (el DUT lo cambia solo y el RAL no puede adivinar su valor), 8'h00 = valor de reset,
    //1 = si tiene reset, 0 = si se puede aleatorizar, 0 = si se puede acceder al campo solo
    data.configure(this, 8, 0, "RO", 1, 8'h00, 1, 0, 0); //es volatil porque cada lectura saca un dato distinto de la FIFO RX
  endfunction

endclass

//THR: es donde se escribe el dato que se quiere transmitir (direccion 0 con DLAB = 0)
class uart_thr extends uvm_reg;

  //Registramos en la fabrica
  `uvm_object_utils(uart_thr)

  rand uvm_reg_field data; //se crea el handle al campo

  //Se crea el constructor, el registro es de 8 bits
  //nos permite dar caracteristicas  al registro
  function new(string name = "uart_thr");
    super.new(name, 8, UVM_NO_COVERAGE);
  endfunction

  //En build creamos y configuramos el campo
  virtual function void build();
    data = uvm_reg_field::type_id::create("data"); // se crea el objeto/registro del campo con la fabrica
    data.configure(this, 8, 0, "WO", 0, 8'h00, 1, 1, 0); //"WO" = solo escritura, porque el dato entra a la FIFO TX y no se puede leer de vuelta
  endfunction

endclass

//IER: habilita cada interrupcion (direccion 1 con DLAB = 0)
//Tiene dos campos porque en el DUT solo existen los 4 bits de abajo
class uart_ier extends uvm_reg;

  //Registramos en la fabrica
  `uvm_object_utils(uart_ier)

  rand uvm_reg_field ier;  //bits 3:0, un bit por cada interrupcion (RDA, THRE, RLS y MS) se escriben y leen
  uvm_reg_field      rsvd; //bits 7:4, reservados, no es rand porque no se pueden escribir, solo leer simpre 0

  //Se crea el constructor, el registro es de 8 bits
  function new(string name = "uart_ier");
    super.new(name, 8, UVM_NO_COVERAGE);
  endfunction

  //En build creamos y configuramos los dos campos
  virtual function void build();
    ier  = uvm_reg_field::type_id::create("ier");
    rsvd = uvm_reg_field::type_id::create("rsvd");
    ier.configure (this, 4, 0, "RW", 0, 4'h0, 1, 1, 0); //4 bits desde el bit 0, "RW" = lectura y escritura, reset en 0 (sin interrupciones)
    rsvd.configure(this, 4, 4, "RO", 0, 4'h0, 1, 0, 0); //4 bits desde el bit 4, solo lectura y siempre se leen en 0
  endfunction

endclass

//IIR: dice cual interrupcion esta pendiente (direccion 2)
class uart_iir extends uvm_reg;

  //Registramos en la fabrica
  `uvm_object_utils(uart_iir)

  uvm_reg_field data; //se crea el handle al campo, no es rand porque solo se lee

  //Se crea el constructor, el registro es de 8 bits
  function new(string name = "uart_iir");
    super.new(name, 8, UVM_NO_COVERAGE);
  endfunction

  //En build creamos y configuramos el campo
  virtual function void build();
    data = uvm_reg_field::type_id::create("data");
    data.configure(this, 8, 0, "RO", 1, 8'hC1, 1, 0, 0); //solo lectura y volatil porque lo cambia el DUT, el reset C1h significa que no hay interrupcion
  endfunction

endclass

//FCR: controla las FIFOs, sirve para limpiarlas y para elegir el nivel de disparo (direccion 2)
//Comparte la direccion con IIR: al leer la direccion 2 se lee IIR y al escribirla se escribe FCR
class uart_fcr extends uvm_reg;

  //Registramos en la fabrica
  `uvm_object_utils(uart_fcr)

  rand uvm_reg_field data; //se crea el handle al campo

  //Se crea el constructor, el registro es de 8 bits
  function new(string name = "uart_fcr");
    super.new(name, 8, UVM_NO_COVERAGE);
  endfunction

  //En build creamos y configuramos el campo
  virtual function void build();
    data = uvm_reg_field::type_id::create("data");
    data.configure(this, 8, 0, "WO", 0, 8'hC0, 1, 1, 0); //solo escritura, el reset C0h significa nivel de disparo 14
  endfunction

endclass

//LCR: guarda el formato de la linea (largo, paridad, parada y break) y el bit DLAB (direccion 3)
class uart_lcr extends uvm_reg;

  //Registramos en la fabrica
  `uvm_object_utils(uart_lcr)

  rand uvm_reg_field data; //se crea el handle al campo

  //Se crea el constructor, el registro es de 8 bits
  function new(string name = "uart_lcr");
    super.new(name, 8, UVM_NO_COVERAGE);
  endfunction

  //En build creamos y configuramos el campo
  virtual function void build();
    data = uvm_reg_field::type_id::create("data");
    data.configure(this, 8, 0, "RW", 0, 8'h03, 1, 1, 0); //lectura y escritura, el reset 03h significa 8 bits, 1 parada y sin paridad (hoja 0.1 del arbol)
  endfunction

endclass

//MCR: maneja las salidas de modem (DTR, RTS, OUT1 y OUT2) y el bit de loopback (direccion 4)
//Tiene dos campos porque en el DUT solo existen los 5 bits de abajo
class uart_mcr extends uvm_reg;

  //Registramos en la fabrica
  `uvm_object_utils(uart_mcr)

  rand uvm_reg_field mcr;  //bits 4:0
  uvm_reg_field      rsvd; //bits 7:5, reservados, simpre cero no hacen nada, solo lectura

  //Se crea el constructor, el registro es de 8 bits
  function new(string name = "uart_mcr");
    super.new(name, 8, UVM_NO_COVERAGE);
  endfunction

  //En build creamos y configuramos los dos campos
  virtual function void build();
    mcr  = uvm_reg_field::type_id::create("mcr");
    rsvd = uvm_reg_field::type_id::create("rsvd");
    mcr.configure (this, 5, 0, "WO", 0, 5'h00, 1, 1, 0); //5 bits desde el bit 0, solo escritura porque leer la direccion 4 da 0 (AMB-02)
    rsvd.configure(this, 3, 5, "RO", 0, 3'h0,  1, 0, 0); //3 bits desde el bit 5, siempre en 0
  endfunction

endclass

//LSR: dice el estado de la linea, si hay dato listo, si hubo errores y si el TX esta vacio (direccion 5)
class uart_lsr extends uvm_reg;

  //Registramos en la fabrica
  `uvm_object_utils(uart_lsr)

  uvm_reg_field data; //se crea el handle al campo, no es rand porque solo se lee

  //Se crea el constructor, el registro es de 8 bits
  function new(string name = "uart_lsr");
    super.new(name, 8, UVM_NO_COVERAGE);
  endfunction

  //En build creamos y configuramos el campo
  virtual function void build();
    data = uvm_reg_field::type_id::create("data");
    data.configure(this, 8, 0, "RO", 1, 8'h60, 1, 0, 0); //solo lectura y volatil, el reset 60h significa que el TX esta vacio
  endfunction

endclass

//MSR: dice el estado de las entradas de modem (CTS, DSR, RI y DCD) y si cambiaron (direccion 6)
class uart_msr extends uvm_reg;

  //Registramos en la fabrica
  `uvm_object_utils(uart_msr)

  uvm_reg_field data; //se crea el handle al campo, no es rand porque solo se lee

  //Se crea el constructor, el registro es de 8 bits
  function new(string name = "uart_msr");
    super.new(name, 8, UVM_NO_COVERAGE);
  endfunction

  //En build creamos y configuramos el campo
  virtual function void build();
    data = uvm_reg_field::type_id::create("data");
    data.configure(this, 8, 0, "RO", 1, 8'h00, 1, 0, 0); //solo lectura y volatil porque depende de los pines de modem
  endfunction

endclass

//SCR o scratch: es un registro libre que el DUT no usa para nada (direccion 7, AMB-01)
//Como es de lectura y escritura y empieza en 0, nos sirve para probar que el RAL funciona
class uart_scr extends uvm_reg;

  //Registramos en la fabrica
  `uvm_object_utils(uart_scr)

  rand uvm_reg_field data; //se crea el handle al campo

  //Se crea el constructor, el registro es de 8 bits
  function new(string name = "uart_scr");
    super.new(name, 8, UVM_NO_COVERAGE);
  endfunction

  //En build creamos y configuramos el campo
  virtual function void build();
    data = uvm_reg_field::type_id::create("data");
    data.configure(this, 8, 0, "RW", 0, 8'h00, 1, 1, 0); //lectura y escritura, reset en 0
  endfunction

endclass

//DLL: es el byte bajo del divisor de baudios (direccion 0 con DLAB = 1)
class uart_dll extends uvm_reg;

  //Registramos en la fabrica
  `uvm_object_utils(uart_dll)

  rand uvm_reg_field data; //se crea el handle al campo

  //Se crea el constructor, el registro es de 8 bits
  function new(string name = "uart_dll");
    super.new(name, 8, UVM_NO_COVERAGE);
  endfunction

  //En build creamos y configuramos el campo
  virtual function void build();
    data = uvm_reg_field::type_id::create("data");
    data.configure(this, 8, 0, "RW", 0, 8'h00, 1, 1, 0); //lectura y escritura, reset en 0, por eso el UART arranca sin baudios
  endfunction

endclass

//DLM: es el byte alto del divisor de baudios (direccion 1 con DLAB = 1)
class uart_dlm extends uvm_reg;

  //Registramos en la fabrica
  `uvm_object_utils(uart_dlm)

  rand uvm_reg_field data; //se crea el handle al campo

  //Se crea el constructor, el registro es de 8 bits
  function new(string name = "uart_dlm");
    super.new(name, 8, UVM_NO_COVERAGE);
  endfunction

  //En build creamos y configuramos el campo
  virtual function void build();
    data = uvm_reg_field::type_id::create("data");
    data.configure(this, 8, 0, "RW", 0, 8'h00, 1, 1, 0); //lectura y escritura, reset en 0
  endfunction

endclass
