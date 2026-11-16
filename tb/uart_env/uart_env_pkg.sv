`timescale 1ns/1ps
package uart_env_pkg;
  import uvm_pkg::*;
  import wb_pkg::*;
  import ser_pkg::*;
  import ral_pkg::*;
  import modem_pkg::*;
  `include "uvm_macros.svh"
  // This is dependency order -- config needs the agent packages, scoreboard needs the sample and model types
  // Sequences then need the virtual sequencer, and the test needs the completed environment class -- alex
  `include "uart_env_cfg.sv"
  `include "uart_runtime_observers.sv"
  `include "uart_reference_model.sv"
  `include "uart_scoreboard.sv"
  `include "uart_vsequencer.sv"
  `include "uart_sequences.sv"
  `include "uart_env.sv"
  `include "uart_base_test.sv"
endpackage : uart_env_pkg
