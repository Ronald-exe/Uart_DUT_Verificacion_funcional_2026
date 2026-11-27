//Secuencia de UN acceso al bus Wishbone (una lectura o una escritura a un registro)
//La usan el trafico TX y el servicio RX, asi todos arman el acceso igual
//el driver Wishbone sigue siendo el que mueve los cables
//uvm_sequence #(wb_item) significa que esta secuencia manda items de tipo wb_item
class uart_wb_seq extends uvm_sequence #(wb_item);

  //Registramos en la fabrica
  `uvm_object_utils(uart_wb_seq)

  uart_env_cfg cfg;     //configuracion, de aqui salen los retardos y el tiempo maximo
  bit [4:0] reg_index;  //numero del registro (0 a 7)
  bit write_access;     //1 = escritura, 0 = lectura
  bit [7:0] write_data; //byte que se escribe
  bit [7:0] read_data;  //byte que se leyo, lo llena la secuencia al terminar

  //Se crea el constructor, las secuencias son objetos y no llevan parent
  function new(string name = "uart_wb_seq");
    super.new(name);
  endfunction

  //body es lo que hace la secuencia cuando se arranca con start
  task body();
    wb_item it;        //handle al item que vamos a mandar
    int unsigned lane; //carril del bus donde va el byte
    it = wb_item::type_id::create("access");
    start_item(it); //pide turno al secuenciador, espera hasta que el driver este libre
    //Armamos el acceso igual que el adaptador del RAL, asi los accesos directos y los del RAL coinciden
    //el registro 0 va en el carril de arriba [31:24] y la direccion alineada dice el grupo (piso y puerta)
    lane = 3 - reg_index[1:0];
    it.adr = {reg_index[4:2], 2'b00};
    it.sel = 4'b1000 >> reg_index[1:0];
    //los registros de debug (8 y 12) se leen con sel = 1111 y devuelven los 32 bits (plan, seccion 3.3)
    if (reg_index >= 8)
      it.sel = 4'b1111;
    it.we = write_access;
    it.data = '0;
    it.data[8 * lane +: 8] = write_data;
    it.delay = $urandom_range(cfg.wb.delay_max, 0);         //retardo aleatorio entre accesos, de 0 a delay_max
    it.stb_delay = $urandom_range(cfg.wb.stb_delay_max, 0); //retardo aleatorio entre cyc y stb
    //finish_item le entrega el item al driver y espera a que termine
    //si ack nunca llegara, el watchdog de la prueba (uart_base_test) corta la simulacion
    finish_item(it);
    read_data = it.data[8 * lane +: 8]; //en una lectura el driver dejo el dato en el mismo item, sacamos el byte de su carril
  endtask

endclass : uart_wb_seq
