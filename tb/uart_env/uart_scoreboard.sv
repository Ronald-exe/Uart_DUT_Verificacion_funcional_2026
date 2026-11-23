
//El scoreboard se encarga de comparar lo que el DUT hizo contra lo que deberia hacer
//Arma lo esperado con lo que vieron los monitores, no con lo que pidio la secuencia:
//  TX: cada escritura a THR deberia salir despues por stx
//  RX: cada caracter que entro por srx deberia leerse despues en RBR
//Las cantidades que planeo la secuencia solo se usan al final para revisar que no falto ninguna observacion
//Hereda de uvm_scoreboard porque es el componente que hace las comparaciones
class uart_scoreboard extends uvm_scoreboard;

  //Registramos en la fabrica
  `uvm_component_utils(uart_scoreboard)

  uart_env_cfg cfg; //handle a la configuracion, de ahi sacamos la interfaz para mirar el reloj y el reset

  //Entradas: uvm_tlm_analysis_fifo es como un buzon, el monitor deja el item y el scoreboard lo saca cuando quiere
  //asi el monitor no tiene que esperar a que se compare, y nosotros sacamos todo en un solo lugar en el orden que queremos
  uvm_tlm_analysis_fifo #(wb_item) wb_in;   //accesos del bus Wishbone
  uvm_tlm_analysis_fifo #(ser_item) tx_in;  //caracteres que salieron por stx
  uvm_tlm_analysis_fifo #(ser_item) rx_in;  //caracteres que entraron por srx

  //Colas de lo esperado, TX y RX van separadas porque son caminos independientes
  //son colas porque las FIFOs del UART tambien sacan los datos en orden (el primero que entra es el primero que sale)
  bit [7:0] tx_queue[$]; //bytes escritos en THR que todavia no han salido por stx
  bit [7:0] rx_queue[$]; //caracteres que entraron por srx y todavia no se han leido de RBR
  bit [7:0] lcr = 8'h03; //copia de LCR, la direccion 0 solo es THR/RBR cuando DLAB = 0 (si no es DLL)
  bit last_dr;           //ultimo valor de DR (LSR[0]) que leyo el software

  //Contadores, no basta con comparar cada byte, tambien hay que revisar que no falte ninguno
  longint unsigned tx_writes;     //escrituras a THR vistas
  longint unsigned tx_compared;   //caracteres TX comparados
  longint unsigned rx_characters; //caracteres RX vistos en srx
  longint unsigned rx_compared;   //lecturas de RBR comparadas
  longint unsigned empty_reads;   //lecturas de RBR con la FIFO vacia
  longint unsigned target_tx;     //TX que planeo la secuencia
  longint unsigned target_rx;     //RX que planeo la secuencia
  bit targets_set;                //1 cuando la prueba ya nos dio los totales

  //Se crea el constructor, parent es el ambiente
  function new(string name = "uart_scoreboard", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  //En build tomamos la configuracion y creamos los buzones, asi el ambiente los puede conectar en su connect_phase
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(uart_env_cfg)::get(this, "", "cfg", cfg))
      `uvm_fatal("SCB_NOCFG", "Scoreboard sin configuracion")
    wb_in = new("wb_in", this);
    tx_in = new("tx_in", this);
    rx_in = new("rx_in", this);
  endfunction

  //Saca el numero de registro de un acceso, igual que el adaptador: el piso sale de adr y la puerta de sel
  function int unsigned index_of(wb_item it);
    int unsigned index;
    case (it.sel)
      4'b1000: index = 0;
      4'b0100: index = 1;
      4'b0010: index = 2;
      4'b0001: index = 3;
      default: begin
        //en E2 solo se usan sel con un bit en 1, un sel raro aqui seria un error
        `uvm_error("SCB_SEL", "El modelo E2 requiere un SEL one-hot")
        index = 0;
      end
    endcase
    return {it.adr[4:2], 2'b00} + index; //numero del registro = piso + puerta
  endfunction

  //Saca el byte del carril que marca sel, los otros carriles del bus no son parte de este registro
  function bit [7:0] byte_of(wb_item it);
    int unsigned index;
    index = index_of(it);
    return it.data[8 * (3 - (index % 4)) +: 8];
  endfunction

  //Borra los bits de arriba que no caben en el caracter, ej. con 5 bits de dato los 3 bits altos de THR no se transmiten
  function bit [7:0] character_mask(bit [7:0] data);
    return data & (8'hff >> (3 - int'(lcr[1:0])));
  endfunction

  //Procesa una escritura que vio el monitor Wishbone
  function void observe_write(wb_item it);
    int unsigned index;
    bit [7:0] data;
    index = index_of(it);
    data = byte_of(it);
    if (index == 3)
      lcr = data; //escritura a LCR: guardamos la copia
    //escritura a la direccion 0 con DLAB = 0 es THR: el byte va a la cola TX
    //con DLAB = 1 es DLL, por eso se revisa lcr[7], si no el divisor pareceria un dato TX
    else if ((index == 0) && !lcr[7]) begin
      tx_queue.push_back(character_mask(data));
      tx_writes++;
      //la FIFO TX es de 16 (17 contando el que se esta transmitiendo), en E2 no se modela llenarla
      if (tx_queue.size() > 17)
        `uvm_error("SCB_TX_OVERFLOW", "Trafico fuera del modelo de datos normal E2")
    end else if (index == 2) begin
      //escritura a FCR: si pide limpiar una FIFO, tambien limpiamos su cola
      //solo se usa al configurar, limpiar con trafico necesita un modelo mas completo
      if (data[1])
        rx_queue.delete();
      if (data[2])
        tx_queue.delete();
    end
  endfunction

  //Procesa un caracter que entro por srx
  //lo esperado sale de lo que vio el monitor en la linea y no de lo que se le pidio al driver
  //asi un driver que nunca mando el caracter no puede crear algo esperado falso
  //un caracter con error de paridad o de trama igual entra a la FIFO con su dato, solo se marca en LSR
  //un break entra como un caracter 0 (uart_receiver.v linea 402), el monitor ya lo entrega con data = 0
  function void observe_rx(ser_item it);
    //la FIFO RX es de 16, si se llena es overrun y eso no se modela en E2
    if (rx_queue.size() >= 16) begin
      `uvm_error("SCB_RX_OVERFLOW", "Overrun fuera del alcance de comparacion de datos E2")
      return;
    end
    rx_queue.push_back(character_mask(it.data));
    rx_characters++;
  endfunction

  //Procesa una lectura que vio el monitor Wishbone
  function void observe_read(wb_item it);
    int unsigned index;
    bit [7:0] expected;
    bit [7:0] actual;
    index = index_of(it);
    actual = byte_of(it);
    if (index == 5)
      last_dr = actual[0]; //lectura de LSR: guardamos DR, nos dice si habia dato listo
    //lectura de la direccion 0 con DLAB = 0 es RBR: se compara con el mas viejo de la cola RX
    if ((index == 0) && !lcr[7]) begin //¿este acceso fue a THR/RBR?
      if (rx_queue.size() == 0) begin
        //la cola esta vacia: el valor de RBR no esta definido (AMB-11) asi que no se compara
        //pero si el software vio DR = 1 y no habia nada que leer, algo esta mal
        if (last_dr)
          `uvm_error("SCB_RX_UNEXPECTED", "RBR entrego un dato sin caracter RX observado")
        else
          empty_reads++;
      end else begin
        expected = rx_queue.pop_front(); //pop_front saca el primero de la cola
        rx_compared++;
        if (actual !== expected)
          `uvm_error("SCB_RX_DATA", $sformatf("RBR esperado=%02h observado=%02h", expected, actual))
        else
          `uvm_info("SCB_RX_MATCH", $sformatf("RBR=%02h", actual), UVM_HIGH)
      end
      last_dr = (rx_queue.size() != 0);
    end
  endfunction

  //Procesa un caracter que salio por stx: se compara con el primero de la cola TX
  function void observe_tx(ser_item it);
    bit [7:0] expected;
    if (it.parity_err || it.frame_err) // error de paridad o el bit de parada llego en 0 cuando debia ser 1
      `uvm_error("SCB_TX_LINE", "El DUT transmitio una trama con error de linea") //el DUT nunca deberia transmitir con error
    //si la cola esta vacia el DUT transmitio algo que nadie escribio en THR
    if (tx_queue.size() == 0) begin
      `uvm_error("SCB_TX_UNEXPECTED", "Caracter TX sin escritura THR observada")
      return;
    end
    expected = tx_queue.pop_front();
    tx_compared++;
    if (character_mask(it.data) !== expected)
      `uvm_error("SCB_TX_DATA", $sformatf("TX esperado=%02h observado=%02h", expected, it.data))
    else
      `uvm_info("SCB_TX_MATCH", $sformatf("TX=%02h", it.data), UVM_HIGH)
  endfunction

  //En la fase de run sacamos todo de los buzones en cada ciclo y lo procesamos en un orden fijo
  task run_phase(uvm_phase phase);
    wb_item pending[$]; //accesos Wishbone de este ciclo
    wb_item wb;
    ser_item serial;
    forever begin
      //esperamos un ciclo y un poquito mas (1ps), asi todos los monitores ya publicaron lo de este ciclo
      @(cfg.wb.vif.mon_cb);
      #1ps;
      //Con reset activo botamos todo lo pendiente y volvemos LCR a su valor de reset
      //los totales no se reinician porque en E2 no hay reset en medio del trafico
      if (cfg.wb.vif.rst !== 1'b0) begin
        tx_queue.delete();
        rx_queue.delete();
        wb_in.flush();
        tx_in.flush();
        rx_in.flush();
        lcr = 8'h03;
        last_dr = 0;
        continue;
      end
      //Orden fijo dentro del mismo ciclo, asi no depende de cual monitor publico primero:
      //  1. escrituras (un THR escrito ya esta en la cola antes de comparar lo que sale)
      //  2. caracteres de srx (un caracter que llego ya esta en la cola antes de leer RBR)
      //  3. lecturas
      //  4. caracteres de stx
      pending.delete();
      while (wb_in.try_get(wb)) //try_get saca un item si hay, sin esperar
        pending.push_back(wb);
      foreach (pending[i]) begin
        if (pending[i].we)
          observe_write(pending[i]);
      end
      while (rx_in.try_get(serial))
        observe_rx(serial);
      foreach (pending[i]) begin
        if (!pending[i].we)
          observe_read(pending[i]);
      end
      while (tx_in.try_get(serial))
        observe_tx(serial);
    end
  endtask

  //La prueba llama esta funcion al final para darnos cuantos TX y RX planeo la secuencia
  //solo se usan para contar, lo esperado siempre sale de lo que vieron los monitores
  function void expect_totals(longint unsigned tx, longint unsigned rx);
    target_tx = tx;
    target_rx = rx;
    targets_set = 1;
  endfunction

  //En check_phase revisamos lo que quedo al final, aunque todas las comparaciones hayan salido bien
  //si no, una corrida que termino antes de tiempo podria parecer que paso
  function void check_phase(uvm_phase phase);
    super.check_phase(phase);
    //la secuencia nunca termino
    if (!targets_set)
      `uvm_error("SCB_NO_TARGETS", "La secuencia principal no completo su presupuesto")
    //quedo algo sin comparar en las colas o en los buzones
    if ((tx_queue.size() != 0) || (rx_queue.size() != 0) ||
        (wb_in.used() != 0) || (tx_in.used() != 0) || (rx_in.used() != 0))
      `uvm_error("SCB_PENDING", "Quedaron datos sin comparar al terminar")
    //lo que se vio y comparo tiene que dar justo lo que se planeo
    if (targets_set && ((tx_writes != target_tx) || (tx_compared != target_tx) ||
                        (rx_characters != target_rx) || (rx_compared != target_rx)))
      `uvm_error("SCB_COUNTS", $sformatf("Objetivo TX/RX=%0d/%0d; THR=%0d TX=%0d RX=%0d RBR=%0d", target_tx, target_rx, tx_writes, tx_compared, rx_characters, rx_compared))
  endfunction

  //En report_phase imprimimos el resumen, es el [SCB_SUMMARY] que aparece al final del log
  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("SCB_SUMMARY", $sformatf("TX comparados=%0d RX comparados=%0d lecturas vacias=%0d", tx_compared, rx_compared, empty_reads), UVM_LOW)
  endfunction

endclass : uart_scoreboard
