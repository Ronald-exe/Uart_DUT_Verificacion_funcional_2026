//Este item representa UN caracter de la linea serie del UART
//Lo usamos en el driver (para mandar el caracter por srx) y en los monitores (para guardar lo que vieron en stx y srx)
//Hereda de uvm_sequence_item porque es una transaccion que viaja de la secuencia al driver
class ser_item extends uvm_sequence_item;

  //Registramos en la fabrica para poder crearlo con create y sustituirlo con un override
  `uvm_object_utils(ser_item)

  //Campos del caracter, son rand para que la secuencia los pueda aleatorizar
  rand bit [7:0] data;     //dato del caracter, de 5 a 8 bits segun el largo (los bits que sobran se ignoran)
  rand int unsigned gap;   //bits de silencio (linea en 1) antes de mandar el caracter, el rango lo pone la secuencia con gap_max

  //Error que el driver tiene que inyectar en este caracter, no es rand porque lo decide la secuencia con los knobs de error
  //  0 = ninguno, 1 = paridad invertida, 2 = bit de parada en 0 (error de trama), 3 = break (linea en 0 mas de un caracter)
  int unsigned err_kind;
  bit glitch; //1 = pulso corto en 0 antes del caracter (AMB-13), lo decide la secuencia

  //Estos no son rand porque los llena el monitor cuando ve algo mal en la linea
  bit parity_err; //la paridad que se vio no coincide con la que deberia ser
  bit frame_err;  //el bit de parada estaba en 0
  bit brk;        //la linea se quedo en 0 un caracter completo (break), el DUT lo guarda como un caracter 0

  //Se crea el constructor, como es un objeto y no un componente no lleva parent
  function new(string name = "ser_item");
    super.new(name);
  endfunction

  //Esta funcion arma un texto para el log, por ejemplo: "data=0x41 gap=3 err=0 pe=0 fe=0 bi=0"
  function string convert2string();
    return $sformatf("data=0x%02h gap=%0d err=%0d glitch=%0b pe=%0b fe=%0b bi=%0b", data, gap, err_kind, glitch, parity_err, frame_err, brk);
  endfunction

endclass
