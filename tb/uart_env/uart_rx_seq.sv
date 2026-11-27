//Secuencia de trafico RX: genera los caracteres que entran al DUT por srx
//aqui solo se eligen los caracteres, como se mandan bit por bit lo hace el driver serie
//asi las restricciones del trafico quedan separadas de como se arma la trama
class uart_rx_seq extends uvm_sequence #(ser_item);

  //Registramos en la fabrica
  `uvm_object_utils(uart_rx_seq)

  uart_env_cfg cfg;   //configuracion, de aqui salen los rangos
  int unsigned count; //cuantos caracteres mandar

  //Se crea el constructor
  function new(string name = "uart_rx_seq");
    super.new(name);
  endfunction

  task body();
    ser_item it;
    int unsigned low;
    int unsigned high;
    int unsigned gap_limit;
    int unsigned pick;  //numero al azar para elegir el error
    int unsigned kind;  //error elegido para este caracter
    bit [7:0] mask;     //bits de dato que de verdad se mandan (5 a 8)
    //Copiamos los limites de la configuracion a variables locales, asi en la restriccion queda claro de donde salen
    low = cfg.ser.data_min;
    high = cfg.ser.data_max;
    gap_limit = cfg.ser.gap_max;
    repeat (count) begin
      it = ser_item::type_id::create("rx_character");
      start_item(it);
      //randomize() with {...} sortea el item con restricciones extra
      //local:: indica que low, high y gap_limit son de esta secuencia y no campos del item
      if (!it.randomize() with {
        data inside {[local::low:local::high]};
        gap inside {[0:local::gap_limit]};
      }) begin
        `uvm_fatal("UART_RANDOMIZE", "No se pudo aleatorizar el caracter RX")
      end
      //Elegimos si este caracter lleva un error, a lo sumo uno por caracter
      //se sortea un numero de 0 a 99 y cada error ocupa su porcentaje, ej. con 5, 5 y 3:
      //  0-4 paridad, 5-9 trama, 10-12 break, 13-99 sin error
      pick = $urandom_range(99, 0);
      kind = 0;
      if (pick < cfg.ser_parity_err_pct)
        kind = 1;
      else if (pick < cfg.ser_parity_err_pct + cfg.ser_frame_err_pct)
        kind = 2;
      else if (pick < cfg.ser_parity_err_pct + cfg.ser_frame_err_pct + cfg.ser_break_pct)
        kind = 3;
      //Reglas del plan (seccion 6.2):
      //  sin paridad habilitada no puede haber error de paridad
      //  un error de trama con todos los bits de dato en 0 se veria igual que un break, por eso pedimos algun 1
      mask = 8'hff >> (8 - cfg.ser.n_bits());
      if ((kind == 1) && !cfg.ser.pen)
        kind = 0;
      if ((kind == 2) && ((it.data & mask) == 0))
        kind = 0;
      it.err_kind = kind;
      //Glitch: sorteo aparte de los errores, porque va en el silencio y no en el caracter
      //solo si hay silencio (gap >= 1), si no, no hay donde ponerlo
      it.glitch = ($urandom_range(99, 0) < cfg.ser_glitch_pct) && (it.gap >= 1);
      finish_item(it); //se lo entrega al driver serie y espera a que lo mande
    end
  endtask

endclass : uart_rx_seq
