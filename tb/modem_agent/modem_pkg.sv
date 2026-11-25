//El paquete de modem junta sus clases para que el ambiente las pueda importar
package modem_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  //Cada clase aparece despues de los tipos que necesita
  `include "modem_item.sv"
  `include "modem_agent_cfg.sv"
  `include "modem_driver.sv"
  `include "modem_monitor.sv"
  `include "modem_agent.sv"
  `include "modem_toggle_seq.sv"

endpackage : modem_pkg
