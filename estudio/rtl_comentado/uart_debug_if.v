//==============================================================
//== ARCHIVO uart_debug_if.v (copia de estudio; el original está en rtl/)
//== Interfaz Debug (solo 32 bits): mux combinacional que arma Debug 1 (dir. 8) y Debug 2 (dir. 12).
//== Se lee con wb_sel_i = 1111 y no tiene efectos laterales. Líneas 1-82: licencia e historial.
//==============================================================
//////////////////////////////////////////////////////////////////////
////                                                              ////
////  uart_debug_if.v                                             ////
////                                                              ////
////                                                              ////
////  This file is part of the "UART 16550 compatible" project    ////
////  http://www.opencores.org/cores/uart16550/                   ////
////                                                              ////
////  Documentation related to this project:                      ////
////  - http://www.opencores.org/cores/uart16550/                 ////
////                                                              ////
////  Projects compatibility:                                     ////
////  - WISHBONE                                                  ////
////  RS232 Protocol                                              ////
////  16550D uart (mostly supported)                              ////
////                                                              ////
////  Overview (main Features):                                   ////
////  UART core debug interface.                                  ////
////                                                              ////
////  Author(s):                                                  ////
////      - gorban@opencores.org                                  ////
////      - Jacob Gorban                                          ////
////                                                              ////
////  Created:        2001/12/02                                  ////
////                  (See log for the revision history)          ////
////                                                              ////
//////////////////////////////////////////////////////////////////////
////                                                              ////
//// Copyright (C) 2000, 2001 Authors                             ////
////                                                              ////
//// This source file may be used and distributed without         ////
//// restriction provided that this copyright statement is not    ////
//// removed from the file and that any derivative work contains  ////
//// the original copyright notice and the associated disclaimer. ////
////                                                              ////
//// This source file is free software; you can redistribute it   ////
//// and/or modify it under the terms of the GNU Lesser General   ////
//// Public License as published by the Free Software Foundation; ////
//// either version 2.1 of the License, or (at your option) any   ////
//// later version.                                               ////
////                                                              ////
//// This source is distributed in the hope that it will be       ////
//// useful, but WITHOUT ANY WARRANTY; without even the implied   ////
//// warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR      ////
//// PURPOSE.  See the GNU Lesser General Public License for more ////
//// details.                                                     ////
////                                                              ////
//// You should have received a copy of the GNU Lesser General    ////
//// Public License along with this source; if not, download it   ////
//// from http://www.opencores.org/lgpl.shtml                     ////
////                                                              ////
//////////////////////////////////////////////////////////////////////
//
// CVS Revision History
//
// $Log: not supported by cvs2svn $
// Revision 1.4  2002/07/22 23:02:23  gorban
// Bug Fixes:
//  * Possible loss of sync and bad reception of stop bit on slow baud rates fixed.
//   Problem reported by Kenny.Tung.
//  * Bad (or lack of ) loopback handling fixed. Reported by Cherry Withers.
//
// Improvements:
//  * Made FIFO's as general inferrable memory where possible.
//  So on FPGA they should be inferred as RAM (Distributed RAM on Xilinx).
//  This saves about 1/3 of the Slice count and reduces P&R and synthesis times.
//
//  * Added optional baudrate output (baud_o).
//  This is identical to BAUDOUT* signal on 16550 chip.
//  It outputs 16xbit_clock_rate - the divided clock.
//  It's disabled by default. Define UART_HAS_BAUDRATE_OUTPUT to use.
//
// Revision 1.3  2001/12/19 08:40:03  mohor
// Warnings fixed (unused signals removed).
//
// Revision 1.2  2001/12/12 22:17:30  gorban
// some synthesis bugs fixed
//
// Revision 1.1  2001/12/04 21:14:16  gorban
// committed the debug interface file
//

//==============================================================
//== Includes
//==============================================================
// synopsys translate_off
`include "timescale.v"                                          //> unidad de tiempo (solo simulación)
// synopsys translate_on

`include "uart_defines.v"                                       //> macros globales

//==============================================================
//== Puertos
//==============================================================
module uart_debug_if (/*AUTOARG*/                               //> módulo uart_debug_if
// Outputs
wb_dat32_o,                                                     //> salida de 32 bits
// Inputs
wb_adr_i, ier, iir, fcr, mcr, lcr, msr,                         //> dirección y registros internos
lsr, rf_count, tf_count, tstate, rstate                         //> ocupaciones y estados
) ;                                                             //> fin de la lista

input [`UART_ADDR_WIDTH-1:0] 		wb_adr_i;                   //> dirección interna decodificada
output [31:0] 							wb_dat32_o;             //> palabra Debug
input [3:0] 							ier;                    //> IER[3:0]
input [3:0] 							iir;                    //> IIR[3:0]
input [1:0] 							fcr;  /// bits 7 and 6 of fcr. Other bits are ignored  //> FCR[7:6]
input [4:0] 							mcr;                    //> MCR[4:0] (única forma de leer el MCR por la puerta delantera)
input [7:0] 							lcr;                    //> LCR
input [7:0] 							msr;                    //> MSR
input [7:0] 							lsr;                    //> LSR
input [`UART_FIFO_COUNTER_W-1:0] rf_count;                      //> ocupación RX
input [`UART_FIFO_COUNTER_W-1:0] tf_count;                      //> ocupación TX
input [2:0] 							tstate;                 //> estado TX
input [3:0] 							rstate;                 //> estado RX


wire [`UART_ADDR_WIDTH-1:0] 		wb_adr_i;                   //> dirección como cable
reg [31:0] 								wb_dat32_o;             //> palabra como registro (always combinacional)

//==============================================================
//== Mux de Debug
//==============================================================
always @(/*AUTOSENSE*/fcr or ier or iir or lcr or lsr or mcr or msr  //> se recalcula si cambia cualquier entrada...
			or rf_count or rstate or tf_count or tstate or wb_adr_i)  //> ...(lista de sensibilidad)
	case (wb_adr_i)                                             //> según la dirección completa:
		                      // 8 + 8 + 4 + 4 + 8
		5'b01000: wb_dat32_o = {msr,lcr,iir,ier,lsr};           //> dir. 8, Debug 1: {MSR, LCR, IIR, IER, LSR} (coincide con la especificación)
		               // 5 + 2 + 5 + 4 + 5 + 3
		5'b01100: wb_dat32_o = {8'b0, fcr,mcr, rf_count, rstate, tf_count, tstate};  //> dir. 12, Debug 2: {0, FCR[23:22], MCR[21:17], rf_count, rstate, tf_count, tstate} (la especificación tiene mal los bits; AMB-10)
		default: wb_dat32_o = 0;                                //> otra dirección: 0
	endcase // case(wb_adr_i)                                   //> fin del case

endmodule // uart_debug_if                                      //> fin del módulo

