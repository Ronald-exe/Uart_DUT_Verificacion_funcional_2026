//==============================================================
//== ARCHIVO uart_wb.v (copia de estudio; el original está en rtl/)
//== Interfaz esclava Wishbone: muestrea el bus, genera ack y pulsos we_o/re_o de 1 ciclo,
//== y en 32 bits elige byte y dirección con wb_sel_i. Líneas 1-135: licencia e historial.
//==============================================================
//////////////////////////////////////////////////////////////////////
////                                                              ////
////  uart_wb.v                                                   ////
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
////  UART core WISHBONE interface.                               ////
////                                                              ////
////  Known problems (limits):                                    ////
////  Inserts one wait state on all transfers.                    ////
////  Note affected signals and the way they are affected.        ////
////                                                              ////
////  To Do:                                                      ////
////  Nothing.                                                    ////
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
// Revision 1.16  2002/07/29 21:16:18  gorban
// The uart_defines.v file is included again in sources.
//
// Revision 1.15  2002/07/22 23:02:23  gorban
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
// Revision 1.12  2001/12/19 08:03:34  mohor
// Warnings cleared.
//
// Revision 1.11  2001/12/06 14:51:04  gorban
// Bug in LSR[0] is fixed.
// All WISHBONE signals are now sampled, so another wait-state is introduced on all transfers.
//
// Revision 1.10  2001/12/03 21:44:29  gorban
// Updated specification documentation.
// Added full 32-bit data bus interface, now as default.
// Address is 5-bit wide in 32-bit data bus mode.
// Added wb_sel_i input to the core. It's used in the 32-bit mode.
// Added debug interface with two 32-bit read-only registers in 32-bit mode.
// Bits 5 and 6 of LSR are now only cleared on TX FIFO write.
// My small test bench is modified to work with 32-bit mode.
//
// Revision 1.9  2001/10/20 09:58:40  gorban
// Small synopsis fixes
//
// Revision 1.8  2001/08/24 21:01:12  mohor
// Things connected to parity changed.
// Clock devider changed.
//
// Revision 1.7  2001/08/23 16:05:05  mohor
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
// Revision 1.3  2001/05/21 19:12:01  gorban
// Corrected some Linter messages.
//
// Revision 1.2  2001/05/17 18:34:18  gorban
// First 'stable' release. Should be sythesizable now. Also added new header.
//
// Revision 1.0  2001-05-17 21:27:13+02  jacob
// Initial revision
//
//

// UART core WISHBONE interface 
//
// Author: Jacob Gorban   (jacob.gorban@flextronicssemi.com)
// Company: Flextronics Semiconductor
//

//==============================================================
//== Includes
//==============================================================
// synopsys translate_off                                       //> la síntesis ignora lo que sigue; el simulador sí lo lee
`include "timescale.v"                                          //> trae `timescale 1ns/10ps
// synopsys translate_on                                        //> fin de la zona solo para simulación
`include "uart_defines.v"                                       //> trae las macros (anchos de bus, direcciones)
 
//==============================================================
//== Declaración del módulo y lista de puertos
//==============================================================
module uart_wb (clk, wb_rst_i,                                  //> módulo uart_wb: reloj y reset
	wb_we_i, wb_stb_i, wb_cyc_i, wb_ack_o, wb_adr_i,            //> entradas de control Wishbone y ack de salida
	wb_adr_int, wb_dat_i, wb_dat_o, wb_dat8_i, wb_dat8_o, wb_dat32_o, wb_sel_i,  //> dirección interna, datos del bus y datos internos de 8/32 bits
	we_o, re_o // Write and read enable output for the core     //> pulsos de escritura/lectura hacia uart_regs
);                                                              //> fin de la lista de puertos

//==============================================================
//== Puertos de entrada del lado Wishbone
//==============================================================
input 		  clk;                                              //> reloj del sistema

// WISHBONE interface	
input 		  wb_rst_i;                                         //> reset asíncrono, activo en alto
input 		  wb_we_i;                                          //> 1 = escritura, 0 = lectura
input 		  wb_stb_i;                                         //> strobe: transferencia válida
input 		  wb_cyc_i;                                         //> cycle: ciclo de bus en curso
input [3:0]   wb_sel_i;                                         //> selección de byte (solo se usa en 32 bits)
input [`UART_ADDR_WIDTH-1:0] 	wb_adr_i; //WISHBONE address line  //> dirección: 5 bits en 32 bits, 3 bits en 8 bits

//==============================================================
//== Ancho del bus de datos según el modo de compilación
//==============================================================
`ifdef DATA_BUS_WIDTH_8                                         //> ¿se compiló con bus de 8 bits?
input [7:0]  wb_dat_i; //input WISHBONE bus                     //> dato de escritura de 8 bits
output [7:0] wb_dat_o;                                          //> dato de lectura de 8 bits
reg [7:0] 	 wb_dat_o;                                          //> wb_dat_o es registro (se asigna en un always)
wire [7:0] 	 wb_dat_i;                                          //> wb_dat_i es cable
reg [7:0] 	 wb_dat_is;                                         //> copia muestreada del dato de escritura
`else // for 32 data bus mode                                   //> si no: modo de 32 bits (el obligatorio)
input [31:0]  wb_dat_i; //input WISHBONE bus                    //> dato de escritura de 32 bits
output [31:0] wb_dat_o;                                         //> dato de lectura de 32 bits
reg [31:0] 	  wb_dat_o;                                         //> wb_dat_o es registro
wire [31:0]   wb_dat_i;                                         //> wb_dat_i es cable
reg [31:0] 	  wb_dat_is;                                        //> copia muestreada del dato (32 bits)
`endif // !`ifdef DATA_BUS_WIDTH_8                              //> fin de la selección de ancho

//==============================================================
//== Puertos del lado interno (hacia uart_regs y uart_debug_if)
//==============================================================
output [`UART_ADDR_WIDTH-1:0]	wb_adr_int; // internal signal for address bus  //> dirección ya decodificada que verá uart_regs
input [7:0]   wb_dat8_o; // internal 8 bit output to be put into wb_dat_o  //> byte leído de uart_regs
output [7:0]  wb_dat8_i;                                        //> byte que se escribirá en uart_regs
input [31:0]  wb_dat32_o; // 32 bit data output (for debug interface)  //> palabra Debug de 32 bits
output 		  wb_ack_o;                                         //> ack hacia el maestro
output 		  we_o;                                             //> pulso de escritura de 1 ciclo
output 		  re_o;                                             //> pulso de lectura de 1 ciclo

//==============================================================
//== Tipos de las señales internas
//==============================================================
wire 			  we_o;                                         //> we_o es combinacional (assign)
reg 			  wb_ack_o;                                     //> ack es registro (lo genera la FSM)
reg [7:0] 	  wb_dat8_i;                                        //> byte de escritura, combinacional en un always
wire [7:0] 	  wb_dat8_o;                                        //> byte leído, cable
wire [`UART_ADDR_WIDTH-1:0]	wb_adr_int; // internal signal for address bus  //> dirección interna, cable
reg [`UART_ADDR_WIDTH-1:0]	wb_adr_is;                          //> dirección muestreada (sufijo _is = input sampled)
reg 								wb_we_is;                   //> we muestreado
reg 								wb_cyc_is;                  //> cyc muestreado
reg 								wb_stb_is;                  //> stb muestreado
reg [3:0] 						wb_sel_is;                      //> sel muestreado
wire [3:0]   wb_sel_i;                                          //> sel de entrada, cable
reg 			 wre ;// timing control signal for write or read enable  //> wre=1 solo en reposo: permite UN pulso we_o/re_o por acceso

//==============================================================
//== FSM de ack
//== Estados: 0 = espera; 1 y 2 = enfriamiento (3 no se usa).
//== stb (E0) -> se muestrea (E1, we_o/re_o=1) -> ack=1 (E2) -> ack=0 (E3).
//== ack llega 2 ciclos después de stb; cada acceso dura al menos 4 ciclos.
//==============================================================
// wb_ack_o FSM
reg [1:0] 	 wbstate;                                           //> estado de la FSM (2 bits)
always  @(posedge clk or posedge wb_rst_i)                      //> se actualiza en flanco de reloj o en reset asíncrono
	if (wb_rst_i) begin                                         //> en reset:
		wb_ack_o <= #1 1'b0;                                    //> sin ack
		wbstate <= #1 0;                                        //> estado de espera
		wre <= #1 1'b1;                                         //> listo para aceptar un acceso
	end else                                                    //> fin del reset; si no hay reset:
		case (wbstate)                                          //> según el estado actual
			0: begin                                            //> estado 0: esperando acceso
				if (wb_stb_is & wb_cyc_is) begin                //> ¿hay stb y cyc (muestreados)?
					wre <= #1 0;                                //> bloquea más pulsos para este acceso
					wbstate <= #1 1;                            //> pasa al estado 1
					wb_ack_o <= #1 1;                           //> da ack (visible en el ciclo siguiente)
				end else begin                                  //> no hay acceso:
					wre <= #1 1;                                //> sigue listo para aceptar
					wb_ack_o <= #1 0;                           //> sin ack
				end                                             //> fin del if
			end                                                 //> fin del estado 0
			1: begin                                            //> estado 1:
			   wb_ack_o <= #1 0;                                //> baja ack (dura 1 ciclo)
				wbstate <= #1 2;                                //> pasa al estado 2
				wre <= #1 0;                                    //> sigue bloqueado
			end                                                 //> fin del estado 1
			2,3: begin                                          //> estados 2 y 3:
				wb_ack_o <= #1 0;                               //> sin ack
				wbstate <= #1 0;                                //> vuelve a espera
				wre <= #1 0;                                    //> bloqueado; OJO: con stb pegado al siguiente acceso, habría ack sin pulso (a verificar)
			end                                                 //> fin de los estados 2 y 3
		endcase                                                 //> fin del case

//==============================================================
//== Pulsos hacia uart_regs
//==============================================================
assign we_o =  wb_we_is & wb_stb_is & wb_cyc_is & wre ; //WE for registers	  //> escritura = we & stb & cyc (muestreados) & wre
assign re_o = ~wb_we_is & wb_stb_is & wb_cyc_is & wre ; //RE for registers	  //> lectura = !we & stb & cyc & wre; aquí ocurren los efectos laterales al leer

//==============================================================
//== Muestreo del bus: todas las entradas se registran 1 ciclo
//==============================================================
// Sample input signals                                         //> comentario original: muestreo de entradas
always  @(posedge clk or posedge wb_rst_i)                      //> se actualiza en flanco de reloj o en reset
	if (wb_rst_i) begin                                         //> en reset:
		wb_adr_is <= #1 0;                                      //> dirección en 0
		wb_we_is <= #1 0;                                       //> we en 0
		wb_cyc_is <= #1 0;                                      //> cyc en 0
		wb_stb_is <= #1 0;                                      //> stb en 0
		wb_dat_is <= #1 0;                                      //> dato en 0
		wb_sel_is <= #1 0;                                      //> sel en 0
	end else begin                                              //> fuera de reset (copia en cada ciclo, haya o no stb):
		wb_adr_is <= #1 wb_adr_i;                               //> copia la dirección
		wb_we_is <= #1 wb_we_i;                                 //> copia we
		wb_cyc_is <= #1 wb_cyc_i;                               //> copia cyc
		wb_stb_is <= #1 wb_stb_i;                               //> copia stb
		wb_dat_is <= #1 wb_dat_i;                               //> copia el dato
		wb_sel_is <= #1 wb_sel_i;                               //> copia sel
	end                                                         //> fin del muestreo

//==============================================================
//== Camino de datos en modo de 8 bits (variante opcional)
//==============================================================
`ifdef DATA_BUS_WIDTH_8 // 8-bit data bus                       //> solo si se compila con bus de 8 bits
always @(posedge clk or posedge wb_rst_i)                       //> registro del dato de lectura
	if (wb_rst_i)                                               //> en reset:
		wb_dat_o <= #1 0;                                       //> dato en 0
	else                                                        //> si no:
		wb_dat_o <= #1 wb_dat8_o;                               //> copia en cada ciclo el byte leído

always @(wb_dat_is)                                             //> se recalcula cuando cambia el dato muestreado
	wb_dat8_i = wb_dat_is;                                      //> byte de escritura = dato tal cual

assign wb_adr_int = wb_adr_is;                                  //> dirección interna = dirección muestreada, sin usar sel

//==============================================================
//== Camino de datos en modo de 32 bits: lectura
//== El byte leído se coloca en el carril que indica sel
//==============================================================
`else // 32-bit bus                                             //> modo de 32 bits
// put output to the correct byte in 32 bits using select line  //> comentario original: colocar el byte según sel
always @(posedge clk or posedge wb_rst_i)                       //> registro del dato de lectura
	if (wb_rst_i)                                               //> en reset:
		wb_dat_o <= #1 0;                                       //> dato en 0
	else if (re_o)                                              //> solo se actualiza con pulso de lectura (si no, conserva el valor)
		case (wb_sel_is)                                        //> según sel muestreado:
			4'b0001: wb_dat_o <= #1 {24'b0, wb_dat8_o};         //> sel=0001 -> byte en [7:0]
			4'b0010: wb_dat_o <= #1 {16'b0, wb_dat8_o, 8'b0};   //> sel=0010 -> byte en [15:8]
			4'b0100: wb_dat_o <= #1 {8'b0, wb_dat8_o, 16'b0};   //> sel=0100 -> byte en [23:16]
			4'b1000: wb_dat_o <= #1 {wb_dat8_o, 24'b0};         //> sel=1000 -> byte en [31:24]
			4'b1111: wb_dat_o <= #1 wb_dat32_o; // debug interface output  //> sel=1111 -> palabra Debug (dir. 8 o 12)
 			default: wb_dat_o <= #1 0;                          //> otro sel -> 0, pero el acceso y sus efectos laterales sí ocurren
		endcase // case(wb_sel_i)                               //> fin del case

//==============================================================
//== Camino de datos en modo de 32 bits: escritura y dirección
//== Los 2 bits bajos de la dirección salen de sel, no de wb_adr_i[1:0]
//==============================================================
reg [1:0] wb_adr_int_lsb;                                       //> desplazamiento dentro de la palabra (0..3)

always @(wb_sel_is or wb_dat_is)                                //> combinacional: depende de sel y del dato
begin                                                           //> inicio del bloque
	case (wb_sel_is)                                            //> elegir el byte que se escribe:
		4'b0001 : wb_dat8_i = wb_dat_is[7:0];                   //> sel=0001 -> dat_i[7:0]
		4'b0010 : wb_dat8_i = wb_dat_is[15:8];                  //> sel=0010 -> dat_i[15:8]
		4'b0100 : wb_dat8_i = wb_dat_is[23:16];                 //> sel=0100 -> dat_i[23:16]
		4'b1000 : wb_dat8_i = wb_dat_is[31:24];                 //> sel=1000 -> dat_i[31:24]
		default : wb_dat8_i = wb_dat_is[7:0];                   //> otro sel (incluido 1111) -> dat_i[7:0]
	endcase // case(wb_sel_i)                                   //> fin del case

  `ifdef LITLE_ENDIAN                                           //> LITTLE ENDIAN: no está definido, esta rama no se compila
	case (wb_sel_is)                                            //> según sel:
		4'b0001 : wb_adr_int_lsb = 2'h0;                        //> 0001 -> +0
		4'b0010 : wb_adr_int_lsb = 2'h1;                        //> 0010 -> +1
		4'b0100 : wb_adr_int_lsb = 2'h2;                        //> 0100 -> +2
		4'b1000 : wb_adr_int_lsb = 2'h3;                        //> 1000 -> +3
		default : wb_adr_int_lsb = 2'h0;                        //> otro -> +0
	endcase // case(wb_sel_i)                                   //> fin del case
  `else                                                         //> BIG ENDIAN: la rama que sí se usa
	case (wb_sel_is)                                            //> según sel:
		4'b0001 : wb_adr_int_lsb = 2'h3;                        //> 0001 -> +3 (p. ej. LCR = 3)
		4'b0010 : wb_adr_int_lsb = 2'h2;                        //> 0010 -> +2 (IIR/FCR = 2)
		4'b0100 : wb_adr_int_lsb = 2'h1;                        //> 0100 -> +1 (IER = 1)
		4'b1000 : wb_adr_int_lsb = 2'h0;                        //> 1000 -> +0 (RBR/THR = 0)
		default : wb_adr_int_lsb = 2'h0;                        //> otro -> +0
	endcase // case(wb_sel_i)                                   //> fin del case
  `endif                                                        //> fin de la selección de endianness
end                                                             //> fin del bloque

assign wb_adr_int = {wb_adr_is[`UART_ADDR_WIDTH-1:2], wb_adr_int_lsb};  //> dirección interna = {adr[4:2], desplazamiento según sel}; adr[1:0] se ignora

`endif // !`ifdef DATA_BUS_WIDTH_8                              //> fin del modo de 32 bits

endmodule                                                       //> fin del módulo










