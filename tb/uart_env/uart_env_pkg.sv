`timescale 1ns/1ps
// Import the existing types and collect our classes here so the top only imports one new package
package uart_env_pkg;
  import uvm_pkg::*;
  import wb_pkg::*;
  import ser_pkg::*;
  import ral_pkg::*;
  `include "uvm_macros.svh"
  // Keep this order because each included class must see the types it uses
  // The sequences need the virtual sequencer -- the test needs the completed environment type
  `include "uart_env_cfg.sv"
  `include "uart_scoreboard.sv"
  `include "uart_vsequencer.sv"
  `include "uart_sequences.sv"
  `include "uart_env.sv"
  `include "uart_base_test.sv"
endpackage : uart_env_pkg
