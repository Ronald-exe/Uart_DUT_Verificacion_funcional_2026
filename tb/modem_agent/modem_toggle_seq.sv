//La secuencia de modem elige que entradas cambian y cuantos pasos se envian
//Hereda de uvm_sequence porque genera los items, el driver se encarga de mover los cables
class modem_toggle_seq extends uvm_sequence #(modem_item);

  //Registramos en la fabrica
  `uvm_object_utils(modem_toggle_seq)

  modem_agent_cfg cfg;
  int unsigned steps;

  //Se crea el constructor, como es un objeto no lleva parent
  function new(string name = "modem_toggle_seq");
    super.new(name);
  endfunction

  task body();
    modem_item it;
    bit cts, dsr, ri, dcd;

    //1. Empezamos con las cuatro entradas en reposo
    cts = 1;
    dsr = 1;
    ri = 1;
    dcd = 1;

    repeat (steps) begin
      //2. Cada entrada tiene su propio sorteo, cambiar CTS no obliga a cambiar las otras
      //Con 0 ninguna se invierte y con 100 se invierten las cuatro en cada paso
      if ($urandom_range(99, 0) < cfg.toggle_pct)
        cts = !cts;
      if ($urandom_range(99, 0) < cfg.toggle_pct)
        dsr = !dsr;
      if ($urandom_range(99, 0) < cfg.toggle_pct)
        ri = !ri;
      if ($urandom_range(99, 0) < cfg.toggle_pct)
        dcd = !dcd;

      //3. Creamos un item nuevo, asi los cambios siguientes no modifican un item ya publicado
      it = modem_item::type_id::create("modem_step");

      //4. Pedimos turno, llenamos el paso y esperamos a que el driver termine de sostenerlo
      start_item(it);
      it.cts = cts;
      it.dsr = dsr;
      it.ri = ri;
      it.dcd = dcd;
      it.hold = cfg.step_cycles;
      finish_item(it);
    end
  endtask

endclass : modem_toggle_seq
