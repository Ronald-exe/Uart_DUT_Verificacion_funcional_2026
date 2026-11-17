// -----------------------------------------------------------------------------
// wb_item.sv
// Transacción Wishbone: UN acceso al bus (una lectura o una escritura).
//
// El item es "a nivel de bus": guarda adr, sel, we y el dato de 32 bits tal
// cual viajan por los cables. No sabe nada de registros del UART; la
// traducción "registro LCR" -> "adr, sel y carril" la hace el adaptador del RAL.
// -----------------------------------------------------------------------------

// 1) Toda transacción hereda de uvm_sequence_item.
class wb_item extends uvm_sequence_item;

  // 2) Registra la clase en la factory de UVM. Así se puede crear con
  //    wb_item::type_id::create("nombre") y sustituir con un override.
  `uvm_object_utils(wb_item)

  // 3) Campos del acceso. "rand" = la secuencia los puede aleatorizar.
  rand bit [4:0]  adr;        // dirección (wb_adr_i)
  rand bit [3:0]  sel;       // qué bytes se usan (wb_sel_i)
  rand bit        we;         // 1 = escritura, 0 = lectura
  rand bit [31:0] data;       // escritura: dato a enviar; lectura: dato leído

  // 4) Retardos del acceso, en ciclos de reloj. Sus rangos NO se fijan aquí:
  //    los pone la secuencia con los knobs de wb_agent_cfg (delay_max,
  //    stb_delay_max), para cumplir la regla "nada de constantes mágicas".
  rand int unsigned delay;      // ciclos libres antes de empezar el acceso
  rand int unsigned stb_delay;  // ciclos entre subir cyc y subir stb

  // 5) Constructor: siempre con un nombre por defecto.
  function new(string name = "wb_item");
    super.new(name);
  endfunction

  // 6) Texto para el log, por ejemplo: "WR adr=3 sel=0001 data=0x00000083".
  //    Lo usan el driver y el monitor en sus `uvm_info.
  function string convert2string();
    return $sformatf("%s adr=%0d sel=%4b data=0x%08h",
                     we ? "WR" : "RD", adr, sel, data);
  endfunction

endclass : wb_item
