//El paquete junta todas las clases del agente Wishbone en un solo lugar
//los demas (el ambiente, la prueba) solo hacen "import wb_pkg::*;" y ya ven todas las clases
package wb_pkg;

  import uvm_pkg::*;         //clases de UVM (uvm_driver, uvm_monitor, ...)
  `include "uvm_macros.svh"  //macros de UVM (`uvm_info, `uvm_component_utils, ...)

  //el orden importa: cada clase va despues de las que usa
  `include "wb_item.sv"       //no usa a nadie
  `include "wb_agent_cfg.sv"  //no usa a nadie
  `include "wb_driver.sv"     //usa wb_item y wb_agent_cfg
  `include "wb_monitor.sv"    //usa wb_item y wb_agent_cfg
  `include "wb_agent.sv"      //usa driver y monitor

endpackage
