//El item de modem guarda un paso de las entradas y las salidas que observa el monitor
//Hereda de uvm_sequence_item porque viaja de la secuencia al driver y del monitor a sus suscriptores
class modem_item extends uvm_sequence_item;

  //Registramos en la fabrica
  `uvm_object_utils(modem_item)

  //La secuencia elige los valores que el driver pone en las entradas del DUT
  rand bit cts;
  rand bit dsr;
  rand bit ri;
  rand bit dcd;
  rand int unsigned hold; //cuantos ciclos se sostienen las cuatro entradas

  //Estas salidas las llena el monitor, la secuencia no las maneja
  bit rts;
  bit dtr;

  //Se crea el constructor, como es un objeto no lleva parent
  function new(string name = "modem_item");
    super.new(name);
  endfunction

  //El texto lo usa el reporte del monitor para mostrar las seis senales juntas
  function string convert2string();
    return $sformatf("cts=%0b dsr=%0b ri=%0b dcd=%0b rts=%0b dtr=%0b hold=%0d",
                     cts, dsr, ri, dcd, rts, dtr, hold);
  endfunction

endclass : modem_item
