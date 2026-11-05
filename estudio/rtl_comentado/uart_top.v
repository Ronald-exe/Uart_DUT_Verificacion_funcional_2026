//==============================================================
//== ARCHIVO uart_top.v (copia de estudio; el original está en rtl/)
//== Módulo superior del DUT: no tiene lógica, solo instancia y conecta
//== wb_interface (uart_wb), regs (uart_regs) y dbg (uart_debug_if).
//== Ruta de puerta trasera del RAL: tb_top.dut.regs.<registro>. Líneas 1-133: licencia e historial.
//==============================================================
//////////////////////////////////////////////////////////////////////
////                                                              ////
////  uart_top.v                                                  ////
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
////  UART core top level.                                        ////
////                                                              ////
////  Known problems (limits):                                    ////
////  Note that transmitter and receiver instances are inside     ////
////  the uart_regs.v file.                                       ////
////                                                              ////
////  To Do:                                                      ////
////  Nothing so far.                                             ////
////                                                              ////
////  Author(s):                                                  ////
////      - gorban@opencores.org                                  ////
////      - Jacob Gorban                                          ////
////      - Igor Mohor (igorm@opencores.org)                      ////
////                                                              ////
////  Created:        2001/05/12                                  ////
////  Last Updated:   2001/05/17                                  ////
////                  (See log for the revision history)          ////
////                                                              ////
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
// Revision 1.18  2002/07/22 23:02:23  gorban
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
// Revision 1.17  2001/12/19 08:40:03  mohor
// Warnings fixed (unused signals removed).
//
// Revision 1.16  2001/12/06 14:51:04  gorban
// Bug in LSR[0] is fixed.
// All WISHBONE signals are now sampled, so another wait-state is introduced on all transfers.
//
// Revision 1.15  2001/12/03 21:44:29  gorban
// Updated specification documentation.
// Added full 32-bit data bus interface, now as default.
// Address is 5-bit wide in 32-bit data bus mode.
// Added wb_sel_i input to the core. It's used in the 32-bit mode.
// Added debug interface with two 32-bit read-only registers in 32-bit mode.
// Bits 5 and 6 of LSR are now only cleared on TX FIFO write.
// My small test bench is modified to work with 32-bit mode.
//
// Revision 1.14  2001/11/07 17:51:52  gorban
// Heavily rewritten interrupt and LSR subsystems.
// Many bugs hopefully squashed.
//
// Revision 1.13  2001/10/20 09:58:40  gorban
// Small synopsis fixes
//
// Revision 1.12  2001/08/25 15:46:19  gorban
// Modified port names again
//
// Revision 1.11  2001/08/24 21:01:12  mohor
// Things connected to parity changed.
// Clock devider changed.
//
// Revision 1.10  2001/08/23 16:05:05  mohor
// Stop bit bug fixed.
// Parity bug fixed.
// WISHBONE read cycle bug fixed,
// OE indicator (Overrun Error) bug fixed.
// PE indicator (Parity Error) bug fixed.
// Register read bug fixed.
//
// Revision 1.4  2001/05/31 20:08:01  gorban
// FIFO changes and other corrections.
//
// Revision 1.3  2001/05/21 19:12:02  gorban
// Corrected some Linter messages.
//
// Revision 1.2  2001/05/17 18:34:18  gorban
// First 'stable' release. Should be sythesizable now. Also added new header.
//
// Revision 1.0  2001-05-17 21:27:12+02  jacob
// Initial revision
//
//
//==============================================================
//== Includes
//==============================================================
// synopsys translate_off                                       //> la síntesis ignora lo que sigue
`include "timescale.v"                                          //> unidad de tiempo 1ns/10ps
// synopsys translate_on                                        //> fin de la zona solo para simulación

`include "uart_defines.v"                                       //> macros globales del UART

//==============================================================
//== Lista de puertos del DUT
//==============================================================
module uart_top	(                                               //> módulo superior uart_top
	wb_clk_i,                                                   //> reloj único del núcleo
	
	// Wishbone signals                                         //> comentario original: señales Wishbone
	wb_rst_i, wb_adr_i, wb_dat_i, wb_dat_o, wb_we_i, wb_stb_i, wb_cyc_i, wb_ack_o, wb_sel_i,  //> reset, dirección, datos, we, stb, cyc, ack y sel
	int_o, // interrupt request                                 //> interrupción hacia el procesador

	// UART	signals                                             //> comentario original: señales UART
	// serial input/output                                      //> comentario original: entrada/salida serie
	stx_pad_o, srx_pad_i,                                       //> TX serie (salida) y RX serie (entrada)

	// modem signals                                            //> comentario original: señales de módem
	rts_pad_o, cts_pad_i, dtr_pad_o, dsr_pad_i, ri_pad_i, dcd_pad_i  //> salidas rts/dtr; entradas cts/dsr/ri/dcd
`ifdef UART_HAS_BAUDRATE_OUTPUT                                 //> solo si se habilita la salida de baudios
	, baud_o                                                    //> puerto baud_o (16 x baudios)
`endif                                                          //> fin del ifdef
	);                                                          //> fin de la lista de puertos

//==============================================================
//== Parámetros de ancho (vienen de las macros; no se cambian en tiempo de ejecución)
//==============================================================
parameter 							 uart_data_width = `UART_DATA_WIDTH;  //> ancho del dato: 32 (u 8 con DATA_BUS_WIDTH_8)
parameter 							 uart_addr_width = `UART_ADDR_WIDTH;  //> ancho de la dirección: 5 (o 3)

//==============================================================
//== Declaración de puertos
//==============================================================
input 								 wb_clk_i;                  //> reloj

// WISHBONE interface                                           //> comentario original: interfaz Wishbone
input 								 wb_rst_i;                  //> reset asíncrono activo en alto
input [uart_addr_width-1:0] 	 wb_adr_i;                      //> dirección (en 32 bits, adr[1:0] se ignora; ver uart_wb.v)
input [uart_data_width-1:0] 	 wb_dat_i;                      //> dato de escritura
output [uart_data_width-1:0] 	 wb_dat_o;                      //> dato de lectura
input 								 wb_we_i;                   //> 1 = escritura
input 								 wb_stb_i;                  //> strobe
input 								 wb_cyc_i;                  //> cycle
input [3:0]							 wb_sel_i;                  //> selección de byte
output 								 wb_ack_o;                  //> ack
output 								 int_o;                     //> interrupción, nivel activo en alto

// UART	signals                                                 //> comentario original: señales UART
input 								 srx_pad_i;                 //> RX serie, reposo en 1
output 								 stx_pad_o;                 //> TX serie, reposo en 1 (en loopback queda fija en 1)
output 								 rts_pad_o;                 //> RTS, sale de MCR[1]
input 								 cts_pad_i;                 //> CTS -> MSR[4] y delta MSR[0]
output 								 dtr_pad_o;                 //> DTR, sale de MCR[0]
input 								 dsr_pad_i;                 //> DSR -> MSR[5] y delta MSR[1]
input 								 ri_pad_i;                  //> RI -> MSR[6] y TERI MSR[2]
input 								 dcd_pad_i;                 //> DCD -> MSR[7] y delta MSR[3]

// optional baudrate output                                     //> comentario original: salida opcional de baudios
`ifdef UART_HAS_BAUDRATE_OUTPUT                                 //> solo con UART_HAS_BAUDRATE_OUTPUT
output	baud_o;                                                 //> salida baud_o
`endif                                                          //> fin del ifdef


//==============================================================
//== Cables internos
//==============================================================
wire 									 stx_pad_o;             //> TX serie como cable
wire 									 rts_pad_o;             //> RTS como cable
wire 									 dtr_pad_o;             //> DTR como cable

wire [uart_addr_width-1:0] 	 wb_adr_i;                          //> dirección como cable
wire [uart_data_width-1:0] 	 wb_dat_i;                          //> dato de escritura como cable
wire [uart_data_width-1:0] 	 wb_dat_o;                          //> dato de lectura como cable

wire [7:0] 							 wb_dat8_i; // 8-bit internal data input  //> byte que se escribe en los registros
wire [7:0] 							 wb_dat8_o; // 8-bit internal data output  //> byte leído de los registros
wire [31:0] 						 wb_dat32_o; // debug interface 32-bit output  //> palabra Debug de 32 bits
wire [3:0] 							 wb_sel_i;  // WISHBONE select signal  //> sel como cable
wire [uart_addr_width-1:0] 	 wb_adr_int;                        //> dirección interna decodificada (no es igual a wb_adr_i)
wire 									 we_o;	// Write enable for registers  //> pulso de escritura de 1 ciclo hacia regs
wire		          	     re_o;	// Read enable for registers  //> pulso de lectura de 1 ciclo hacia regs
//                                                              //> comentario original
// MODULE INSTANCES                                             //> comentario original: instancias
//                                                              //> comentario original

//==============================================================
//== Cables de la interfaz Debug (solo en 32 bits)
//==============================================================
`ifdef DATA_BUS_WIDTH_8                                         //> en 8 bits no se declaran
`else                                                           //> en 32 bits sí:
// debug interface wires                                        //> comentario original
wire	[3:0] ier;                                              //> IER[3:0]
wire	[3:0] iir;                                              //> IIR[3:0]
wire	[1:0] fcr;                                              //> FCR[7:6]
wire	[4:0] mcr;                                              //> MCR[4:0]
wire	[7:0] lcr;                                              //> LCR
wire	[7:0] msr;                                              //> MSR
wire	[7:0] lsr;                                              //> LSR
wire	[`UART_FIFO_COUNTER_W-1:0] rf_count;                    //> ocupación de la FIFO RX (0..16)
wire	[`UART_FIFO_COUNTER_W-1:0] tf_count;                    //> ocupación de la FIFO TX (0..16)
wire	[2:0] tstate;                                           //> estado de la FSM del TX
wire	[3:0] rstate;                                           //> estado de la FSM del RX
`endif                                                          //> fin del ifdef

//==============================================================
//== Instancia Wishbone, versión de 8 bits
//==============================================================
`ifdef DATA_BUS_WIDTH_8                                         //> solo si el bus es de 8 bits
////  WISHBONE interface module                                 //> comentario original
uart_wb		wb_interface(                                       //> instancia wb_interface del módulo uart_wb
		.clk(		wb_clk_i		),                          //> reloj
		.wb_rst_i(	wb_rst_i	),                              //> reset
	.wb_dat_i(wb_dat_i),                                        //> dato de escritura del bus
	.wb_dat_o(wb_dat_o),                                        //> dato de lectura del bus
	.wb_dat8_i(wb_dat8_i),                                      //> byte hacia regs
	.wb_dat8_o(wb_dat8_o),                                      //> byte desde regs
	 .wb_dat32_o(32'b0),								        //> sin Debug en 8 bits: amarrado a 0
	 .wb_sel_i(4'b0),                                           //> sin sel en 8 bits: amarrado a 0
		.wb_we_i(	wb_we_i		),                              //> we
		.wb_stb_i(	wb_stb_i	),                              //> stb
		.wb_cyc_i(	wb_cyc_i	),                              //> cyc
		.wb_ack_o(	wb_ack_o	),                              //> ack
	.wb_adr_i(wb_adr_i),                                        //> dirección del bus
	.wb_adr_int(wb_adr_int),                                    //> dirección interna
		.we_o(		we_o		),                              //> pulso de escritura
		.re_o(re_o)                                             //> pulso de lectura
		);                                                      //> fin de la instancia
//==============================================================
//== Instancia Wishbone, versión de 32 bits (la obligatoria)
//==============================================================
`else                                                           //> si el bus es de 32 bits:
uart_wb		wb_interface(                                       //> instancia wb_interface del módulo uart_wb
		.clk(		wb_clk_i		),                          //> reloj
		.wb_rst_i(	wb_rst_i	),                              //> reset
	.wb_dat_i(wb_dat_i),                                        //> dato de escritura del bus
	.wb_dat_o(wb_dat_o),                                        //> dato de lectura del bus
	.wb_dat8_i(wb_dat8_i),                                      //> byte hacia regs
	.wb_dat8_o(wb_dat8_o),                                      //> byte desde regs
	 .wb_sel_i(wb_sel_i),                                       //> sel real: elige byte y bits bajos de dirección
	 .wb_dat32_o(wb_dat32_o),								    //> palabra Debug que sale con sel = 1111
		.wb_we_i(	wb_we_i		),                              //> we
		.wb_stb_i(	wb_stb_i	),                              //> stb
		.wb_cyc_i(	wb_cyc_i	),                              //> cyc
		.wb_ack_o(	wb_ack_o	),                              //> ack
	.wb_adr_i(wb_adr_i),                                        //> dirección del bus
	.wb_adr_int(wb_adr_int),                                    //> dirección interna decodificada
		.we_o(		we_o		),                              //> pulso de escritura
		.re_o(re_o)                                             //> pulso de lectura
		);                                                      //> fin de la instancia
`endif                                                          //> fin del ifdef

//==============================================================
//== Instancia del núcleo funcional: regs (uart_regs)
//== Su nombre "regs" es la ruta de la puerta trasera del RAL
//==============================================================
// Registers                                                    //> comentario original
uart_regs	regs(                                               //> instancia regs del módulo uart_regs
	.clk(		wb_clk_i		),                              //> reloj
	.wb_rst_i(	wb_rst_i	),                                  //> reset
	.wb_addr_i(	wb_adr_int	),                                  //> dirección interna (no wb_adr_i)
	.wb_dat_i(	wb_dat8_i	),                                  //> byte de escritura
	.wb_dat_o(	wb_dat8_o	),                                  //> byte de lectura
	.wb_we_i(	we_o		),                                  //> pulso de escritura
   .wb_re_i(re_o),                                              //> pulso de lectura
	.modem_inputs(	{cts_pad_i, dsr_pad_i,                      //> entradas de módem empaquetadas: {cts, dsr,
	ri_pad_i,  dcd_pad_i}	),                                  //> ri, dcd}
	.stx_pad_o(		stx_pad_o		),                          //> TX serie
	.srx_pad_i(		srx_pad_i		),                          //> RX serie
`ifdef DATA_BUS_WIDTH_8                                         //> solo en 32 bits:
`else                                                           //> (rama de 32 bits)
// debug interface signals	enabled                             //> comentario original
.ier(ier),                                                      //> IER hacia Debug
.iir(iir),                                                      //> IIR hacia Debug
.fcr(fcr),                                                      //> FCR hacia Debug
.mcr(mcr),                                                      //> MCR hacia Debug
.lcr(lcr),                                                      //> LCR hacia Debug
.msr(msr),                                                      //> MSR hacia Debug
.lsr(lsr),                                                      //> LSR hacia Debug
.rf_count(rf_count),                                            //> ocupación RX hacia Debug
.tf_count(tf_count),                                            //> ocupación TX hacia Debug
.tstate(tstate),                                                //> estado TX hacia Debug
.rstate(rstate),                                                //> estado RX hacia Debug
`endif					                                        //> fin del ifdef
	.rts_pad_o(		rts_pad_o		),                          //> salida RTS
	.dtr_pad_o(		dtr_pad_o		),                          //> salida DTR
	.int_o(		int_o		)                                   //> interrupción
`ifdef UART_HAS_BAUDRATE_OUTPUT                                 //> solo con salida de baudios:
	, .baud_o(baud_o)                                           //> baud_o
`endif                                                          //> fin del ifdef

);                                                              //> fin de la instancia

//==============================================================
//== Instancia Debug: dbg (uart_debug_if), solo en 32 bits
//== Arma Debug 1 (dir. 8) y Debug 2 (dir. 12); leerla no tiene efectos laterales
//==============================================================
`ifdef DATA_BUS_WIDTH_8                                         //> en 8 bits no existe
`else                                                           //> en 32 bits:
uart_debug_if dbg(/*AUTOINST*/                                  //> instancia dbg del módulo uart_debug_if
						// Outputs                              //> comentario original: salidas
						.wb_dat32_o				 (wb_dat32_o[31:0]),  //> palabra Debug de 32 bits
						// Inputs                               //> comentario original: entradas
						.wb_adr_i				 (wb_adr_int[`UART_ADDR_WIDTH-1:0]),  //> misma dirección interna decodificada
						.ier						 (ier[3:0]),  //> IER
						.iir						 (iir[3:0]),  //> IIR
						.fcr						 (fcr[1:0]),  //> FCR
						.mcr						 (mcr[4:0]),  //> MCR
						.lcr						 (lcr[7:0]),  //> LCR
						.msr						 (msr[7:0]),  //> MSR
						.lsr						 (lsr[7:0]),  //> LSR
						.rf_count				 (rf_count[`UART_FIFO_COUNTER_W-1:0]),  //> ocupación RX
						.tf_count				 (tf_count[`UART_FIFO_COUNTER_W-1:0]),  //> ocupación TX
						.tstate					 (tstate[2:0]),  //> estado TX
						.rstate					 (rstate[3:0]));  //> estado RX
`endif                                                          //> fin del ifdef

//==============================================================
//== Mensajes de configuración (solo simulación): los "UART INFO" del log
//==============================================================
initial                                                         //> se ejecuta una vez al inicio de la simulación
begin                                                           //> inicio del bloque
	`ifdef DATA_BUS_WIDTH_8                                     //> si es de 8 bits...
		$display("(%m) UART INFO: Data bus width is 8. No Debug interface.\n");  //> ...imprime "8 bits, sin Debug"
	`else                                                       //> si no...
		$display("(%m) UART INFO: Data bus width is 32. Debug Interface present.\n");  //> ...imprime "32 bits, con Debug"
	`endif                                                      //> fin del ifdef
	`ifdef UART_HAS_BAUDRATE_OUTPUT                             //> si tiene baud_o...
		$display("(%m) UART INFO: Has baudrate output\n");      //> ...lo imprime
	`else                                                       //> si no...
		$display("(%m) UART INFO: Doesn't have baudrate output\n");  //> ...imprime que no tiene baud_o
	`endif                                                      //> fin del ifdef
end                                                             //> fin del bloque

endmodule                                                       //> fin del módulo


