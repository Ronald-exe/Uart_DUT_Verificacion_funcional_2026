//El paquete se encarga de juntar todas las clases del RAL en un solo lugar
//Asi el ambiente y la prueba solo hacen "import ral_pkg::*;" y ya pueden usar el bloque y el adaptador
package ral_pkg;

  import uvm_pkg::*;         //importamos las clases de UVM (uvm_reg, uvm_reg_block, uvm_reg_adapter, ...)
  `include "uvm_macros.svh"  //incluimos las macros de UVM (`uvm_object_utils, `uvm_fatal, ...)
  import wb_pkg::*;          //importamos el agente Wishbone porque el adaptador usa wb_item

  //El orden importa: cada clase tiene que ir despues de las clases que usa
  `include "uart_regs_ral.sv"     //los 12 registros, no usan a nadie
  `include "uart_reg_block.sv"    //usa a los registros
  `include "uart_reg_adapter.sv"  //usa wb_item del wb_pkg

endpackage
