//El paquete se encarga de juntar todas las clases del agente serie en un solo lugar
//Asi el ambiente y la prueba solo hacen "import ser_pkg::*;" y ya pueden usar todas las clases
package ser_pkg;

  import uvm_pkg::*;         //importamos las clases de UVM (uvm_driver, uvm_monitor, ...)
  `include "uvm_macros.svh"  //incluimos las macros de UVM (`uvm_info, `uvm_component_utils, ...)

  //El orden importa: cada clase tiene que ir despues de las clases que usa
  `include "ser_item.sv"       //no usa a nadie
  `include "ser_agent_cfg.sv"  //no usa a nadie
  `include "ser_driver.sv"     //usa ser_item y ser_agent_cfg
  `include "ser_monitor.sv"    //usa ser_item y ser_agent_cfg
  `include "ser_agent.sv"      //usa al driver y al monitor

endpackage
