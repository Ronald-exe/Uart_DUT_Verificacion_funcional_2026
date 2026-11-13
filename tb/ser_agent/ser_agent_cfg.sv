//Se encarga de guardar todo lo que necesitan el driver, los monitores y la secuencia serie
//Guardamos tres cosas: el handle a los cables, los knobs del trafico y el formato de la linea
//Hereda de uvm_object porque es configuracion, no una transaccion ni un componente
class ser_agent_cfg extends uvm_object;

  //Registramos en la fabrica
  `uvm_object_utils(ser_agent_cfg)

  //Interfaz virtual: es el handle a los cables stx y srx de uart_ser_if
  //La clase no puede tener hardware adentro, por eso guardamos un puntero que lo pone la prueba
  virtual uart_ser_if vif;

  //Knobs del trafico RX, no son rand porque son ajustes (valores por defecto de la seccion 7 del plan)
  int unsigned burst_min = 0;   //minimo de caracteres por rafaga
  int unsigned burst_max = 20;  //maximo de caracteres por rafaga
  int unsigned data_min  = 0;   //dato minimo de cada caracter
  int unsigned data_max  = 255; //dato maximo de cada caracter
  int unsigned gap_max   = 60;  //maximo de bits de silencio entre caracteres

  //si el driver manda con otro formato el DUT recibe basura, por eso la secuencia de configuracion lo actualiza cada vez que escribe LCR o DL
  //Cada uno define como se ve un caracter en la linea (copia de LCR y DL del DUT)
  bit [1:0]  wls = 2'b11; //cuantos bits de dato tiene (5, 6, 7 u 8) - LCR[1:0]
  bit        stb = 0;     //cuantos bits de parada al final (1, o 1.5/2) - LCR[2]
  bit        pen = 0;     //si lleva bit de paridad o no - LCR[3]
  bit        eps = 0;     //si la paridad es par o impar - LCR[4]
  bit        sp  = 0;     //si la paridad es fija (siempre 1 o siempre 0) - LCR[5]
  bit [15:0] dl  = 1;     //que tan rapido va: cada bit dura 16 x dl ciclos de reloj

  //Se crea el constructor, como es objeto no lleva parent
  function new(string name = "ser_agent_cfg");
    super.new(name);
  endfunction

  //Calculamos cuantos bits de dato tiene un caracter (5 a 8)
  function int unsigned n_bits();
    return wls + 5;  //se le suma 5 debido a que el wls toma valores de 0,1,2 y 3 y cuando lo sumas con 5 dan los valorees de bus de 5,6,7 y 8
  endfunction

  //Calculamos cuantos ciclos de reloj dura un bit en la linea
  function int unsigned bit_cycles();
    return 16 * dl;      // esto reprensa la velocidad de los baudios por eso se toma en cuenta el dl a mayor dl mas lento
  endfunction

  //Calculamos el bit de paridad que le toca a un dato
  //Copiamos los mismos 4 casos que usa el DUT en uart_transmitter.v
  function bit parity_bit(bit [7:0] data);
    bit x = 0;
    for (int i = 0; i < n_bits(); i++) x ^= data[i]; //xor de todos los bits de dato, se toma en cuenta el ancho del bus n x = 0 si es par y x = 1 si es impar
    case ({eps, sp})
      2'b00: return ~x;   //paridad impar
      2'b01: return 1'b1; //stick 1: siempre 1
      2'b10: return x;    //paridad par
      2'b11: return 1'b0; //stick 0: siempre 0
    endcase
  endfunction

  //Calculamos cuantos ciclos dura la parada: 1 bit, 1.5 bits (con 5 bits y stb = 1) o 2 bits (AMB-07)
  function int unsigned stop_cycles();
    if (!stb)      return bit_cycles(); //senala el bit de parada
    if (wls == 0)  return bit_cycles() * 3 / 2; //Si el carácter es de 5 bits, devuelve la duración de 1.5 bits de parada
    return 2 * bit_cycles(); //En caso contrario  es el doble de bits para 6,7 y 8
  endfunction

endclass
