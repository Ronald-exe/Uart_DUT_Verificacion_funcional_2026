//El adaptador se encarga de traducir entre el RAL y el bus Wishbone, es como un traductor
//El RAL habla en registros ("escribe 83h en el registro 3") y el driver habla en cables (adr, sel y data)
//uvm_reg_adapter es la clase de UVM para esto, nosotros solo escribimos las dos traducciones:
//  reg2bus: registro -> wb_item, lo usa el RAL cuando hace write o read por la puerta delantera
//  bus2reg: wb_item -> registro, lo usa el RAL para saber que paso y el predictor para actualizar el espejo
class uart_reg_adapter extends uvm_reg_adapter;

  //Registramos en la fabrica, el adaptador es un objeto y no lleva parent
  `uvm_object_utils(uart_reg_adapter)

  //Se crea el constructor
  function new(string name = "uart_reg_adapter");
    super.new(name);
    supports_byte_enable = 0; //no usamos byte enable del RAL, el sel lo calculamos nosotros
    provides_responses   = 0; //el driver no manda una respuesta aparte, el dato leido queda dentro del mismo item
  endfunction

  //reg2bus: traduce un acceso del RAL a un wb_item para el driver
  //uvm_reg_bus_op es lo que manda el RAL: kind (lectura o escritura), addr (numero de registro) y data (el byte)
  //const ref significa que lo recibimos sin copiarlo y sin poder cambiarlo
  virtual function uvm_sequence_item reg2bus(const ref uvm_reg_bus_op rw);
    wb_item   it = wb_item::type_id::create("it"); //se crea el item llamando a la fabrica
    bit [4:0] r  = rw.addr[4:0];                     //numero del registro (0 a 7)

    it.we  = (rw.kind == UVM_WRITE);                 //1 si el RAL quiere escribir, 0 si quiere leer
    it.adr = {r[4:2], 2'b00};                        //el piso: el grupo de 4 registros (seccion 3.3 del plan)
    it.sel = 4'b1000 >> r[1:0];                      //la puerta: cual registro dentro del grupo, big endian
    it.data = 32'(rw.data[7:0]) << (8 * (3 - r[1:0])); //el byte va en el carril que marca sel, ej. LCR va en [7:0]
    it.delay     = 0;                                //el RAL no usa retardos, los retardos aleatorios son del trafico
    it.stb_delay = 0;
    return it;
  endfunction

  //bus2reg: traduce un wb_item del bus a un acceso del RAL, es la operacion inversa
  //bus_item llega como uvm_sequence_item generico, por eso hay que convertirlo a wb_item con $cast
  //ref significa que lo que escribimos en rw le llega al RAL
  virtual function void bus2reg(uvm_sequence_item bus_item, ref uvm_reg_bus_op rw);
    wb_item   it;
    bit [1:0] b; //cual registro dentro del grupo, sale del sel

    //$cast revisa que el item de verdad sea un wb_item, si no lo es detenemos la simulacion
    if (!$cast(it, bus_item))
      `uvm_fatal("ADAPTER", "bus2reg recibio un item que no es wb_item")

    //De la puerta (sel) sacamos cual registro del grupo fue, igual que el DUT en uart_wb.v lineas 288 a 294
    case (it.sel)
      4'b1000: b = 0;
      4'b0100: b = 1;
      4'b0010: b = 2;
      4'b0001: b = 3;
      default: b = 0; //sel raro: el DUT va al registro 0 del grupo (AMB-06)
    endcase

    rw.kind   = it.we ? UVM_WRITE : UVM_READ;        //si fue escritura o lectura
    rw.addr   = {it.adr[4:2], b};                    //numero del registro = piso + puerta
    rw.data   = it.data[8 * (3 - b) +: 8];           //sacamos el byte del carril que marca sel
    rw.status = UVM_IS_OK;                           //el acceso termino bien (el DUT siempre responde con ack)
  endfunction

endclass
