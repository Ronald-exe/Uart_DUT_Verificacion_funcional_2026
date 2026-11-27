//Prueba de reset del RAL: usamos la secuencia de UVM uvm_reg_hw_reset_seq, que lee cada registro y lo compara con su valor de reset
//el problema es que UVM no sabe como hacer un reset en nuestro DUT, por eso heredamos y escribimos reset_blk
//si solo se reiniciara el espejo nunca se probaria que los registros del DUT de verdad vuelven a su valor de reset
class uart_hw_reset_seq extends uvm_reg_hw_reset_seq;

  //Registramos en la fabrica
  `uvm_object_utils(uart_hw_reset_seq)

  virtual wb_if vif; //interfaz Wishbone, de aqui manejamos rst

  //Se crea el constructor
  function new(string name = "uart_hw_reset_seq");
    super.new(name);
  endfunction

  //reset_blk es la funcion que UVM llama para aplicar el reset, aqui subimos rst 5 ciclos
  //se cambia en el flanco de bajada para no chocar con el muestreo del bus en el flanco de subida
  //solo se usa antes del trafico porque los agentes no se recuperan de un caracter cortado a la mitad
  virtual task reset_blk(uvm_reg_block blk);
    if (vif == null)
      `uvm_fatal("UART_RESET_VIF", "Reset fisico sin wb_if")
    @(negedge vif.clk);
    vif.rst = 1;
    repeat (5) @(negedge vif.clk);
    vif.rst = 0;
    repeat (3) @(vif.drv_cb);
  endtask

endclass : uart_hw_reset_seq
