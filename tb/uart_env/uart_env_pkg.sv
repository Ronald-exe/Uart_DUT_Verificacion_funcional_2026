`timescale 1ns/1ps
//El paquete se encarga de juntar todas las clases del ambiente en un solo lugar
//Asi tb_top solo hace "import uart_env_pkg::*;" y ya puede correr la prueba
package uart_env_pkg;
  import uvm_pkg::*;   //importamos las clases de UVM
  import wb_pkg::*;    //importamos el agente Wishbone (wb_item, wb_agent, ...)
  import ser_pkg::*;   //importamos el agente serie (ser_item, ser_agent, ...)
  import modem_pkg::*; //importamos los items, componentes y secuencia de modem
  import ral_pkg::*;   //importamos el RAL (uart_reg_block, uart_reg_adapter)
  `include "uvm_macros.svh" //incluimos las macros de UVM
  //El orden importa: cada clase tiene que ir despues de las clases que usa
  //por ejemplo las secuencias usan el secuenciador virtual y la prueba usa el ambiente completo
  `include "uart_env_cfg.sv"      //configuracion y plusargs, no usa a nadie del ambiente
  `include "uart_scoreboard.sv"   //usa la configuracion
  `include "uart_coverage.sv"     //usa la configuracion, escucha a los mismos monitores que el scoreboard
  `include "uart_vsequencer.sv"   //usa la configuracion y el RAL
  `include "uart_sequences.sv"    //usa el secuenciador virtual
  `include "uart_env.sv"          //usa a todos los anteriores
  `include "uart_base_test.sv"    //usa el ambiente
endpackage : uart_env_pkg
