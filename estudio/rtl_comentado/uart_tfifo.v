//==============================================================
//== ARCHIVO uart_tfifo.v (copia de estudio; el original está en rtl/)
//== FIFO de transmisión 16 x 8: una RAM (raminfr) y dos punteros. THR la llena; el TX la vacía.
//== Líneas 1-139: licencia e historial.
//==============================================================
//////////////////////////////////////////////////////////////////////
////                                                              ////
////  uart_tfifo.v                                                ////
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
////  UART core transmitter FIFO                                  ////
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
////  Last Updated:   2002/07/22                                  ////
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
// Revision 1.1  2002/07/22 23:02:23  gorban
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
// Revision 1.16  2001/12/20 13:25:46  mohor
// rx push changed to be only one cycle wide.
//
// Revision 1.15  2001/12/18 09:01:07  mohor
// Bug that was entered in the last update fixed (rx state machine).
//
// Revision 1.14  2001/12/17 14:46:48  mohor
// overrun signal was moved to separate block because many sequential lsr
// reads were preventing data from being written to rx fifo.
// underrun signal was not used and was removed from the project.
//
// Revision 1.13  2001/11/26 21:38:54  gorban
// Lots of fixes:
// Break condition wasn't handled correctly at all.
// LSR bits could lose their values.
// LSR value after reset was wrong.
// Timing of THRE interrupt signal corrected.
// LSR bit 0 timing corrected.
//
// Revision 1.12  2001/11/08 14:54:23  mohor
// Comments in Slovene language deleted, few small fixes for better work of
// old tools. IRQs need to be fix.
//
// Revision 1.11  2001/11/07 17:51:52  gorban
// Heavily rewritten interrupt and LSR subsystems.
// Many bugs hopefully squashed.
//
// Revision 1.10  2001/10/20 09:58:40  gorban
// Small synopsis fixes
//
// Revision 1.9  2001/08/24 21:01:12  mohor
// Things connected to parity changed.
// Clock devider changed.
//
// Revision 1.8  2001/08/24 08:48:10  mohor
// FIFO was not cleared after the data was read bug fixed.
//
// Revision 1.7  2001/08/23 16:05:05  mohor
// Stop bit bug fixed.
// Parity bug fixed.
// WISHBONE read cycle bug fixed,
// OE indicator (Overrun Error) bug fixed.
// PE indicator (Parity Error) bug fixed.
// Register read bug fixed.
//
// Revision 1.3  2001/05/31 20:08:01  gorban
// FIFO changes and other corrections.
//
// Revision 1.3  2001/05/27 17:37:48  gorban
// Fixed many bugs. Updated spec. Changed FIFO files structure. See CHANGES.txt file.
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
// synopsys translate_off
`include "timescale.v"                                          //> unidad de tiempo (solo simulación)
// synopsys translate_on

`include "uart_defines.v"                                       //> macros globales

//==============================================================
//== Puertos
//==============================================================
module uart_tfifo (clk,                                         //> módulo uart_tfifo: reloj,
	wb_rst_i, data_in, data_out,                                //> reset, dato de entrada y de salida
// Control signals
	push, // push strobe, active high                           //> pulso de push (escritura a THR)
	pop,   // pop strobe, active high                           //> pulso de pop (el TX toma un byte)
// status signals
	overrun,                                                    //> overrun (no llega a ningún registro)
	count,                                                      //> ocupación
	fifo_reset,                                                 //> limpieza (FCR[2])
	reset_status                                                //> lectura de LSR
	);                                                          //> fin de la lista


//==============================================================
//== Parámetros
//==============================================================
// FIFO parameters
parameter fifo_width = `UART_FIFO_WIDTH;                        //> 8 bits
parameter fifo_depth = `UART_FIFO_DEPTH;                        //> 16 posiciones
parameter fifo_pointer_w = `UART_FIFO_POINTER_W;                //> puntero de 4 bits
parameter fifo_counter_w = `UART_FIFO_COUNTER_W;                //> contador de 5 bits

input				clk;                                        //> reloj
input				wb_rst_i;                                   //> reset asíncrono
input				push;                                       //> push
input				pop;                                        //> pop
input	[fifo_width-1:0]	data_in;                            //> byte de entrada
input				fifo_reset;                                 //> limpieza
input       reset_status;                                       //> lectura de LSR

output	[fifo_width-1:0]	data_out;                           //> byte de salida
output				overrun;                                    //> overrun
output	[fifo_counter_w-1:0]	count;                          //> ocupación

wire	[fifo_width-1:0]	data_out;                           //> salida como cable

//==============================================================
//== Punteros
//==============================================================
// FIFO pointers
reg	[fifo_pointer_w-1:0]	top;                                //> top: siguiente posición a escribir
reg	[fifo_pointer_w-1:0]	bottom;                             //> bottom: siguiente byte a transmitir

reg	[fifo_counter_w-1:0]	count;                              //> ocupación
reg				overrun;                                        //> overrun como registro
wire [fifo_pointer_w-1:0] top_plus_1 = top + 1'b1;              //> top + 1 (vuelve a 0)

//==============================================================
//== RAM de datos. OJO: se escribe con cada push aunque esté llena: con 16 datos,
//== la escritura 17 sobrescribe el próximo byte a transmitir (posible error del DUT)
//==============================================================
raminfr #(fifo_pointer_w,fifo_width,fifo_depth) tfifo           //> instancia de raminfr: 16 x 8
        (.clk(clk),                                             //> reloj
			.we(push),                                          //> escribe con cada push
			.a(top),                                            //> dirección de escritura = top
			.dpra(bottom),                                      //> dirección de lectura = bottom
			.di(data_in),                                       //> byte de entrada
			.dpo(data_out)                                      //> byte de salida (combinacional)
		);                                                      //> fin de la instancia


//==============================================================
//== Punteros y ocupación
//==============================================================
always @(posedge clk or posedge wb_rst_i) // synchronous FIFO   //> se actualiza en flanco de reloj o reset
begin                                                           //> inicio
	if (wb_rst_i)                                               //> en reset:
	begin                                                       //> inicio
		top		<= #1 0;                                        //> top en 0
		bottom		<= #1 1'b0;                                 //> bottom en 0
		count		<= #1 0;                                    //> vacía
	end                                                         //> fin
	else                                                        //> si no:
	if (fifo_reset) begin                                       //> limpieza por FCR[2] (el carácter en curso sigue saliendo): inicio
		top		<= #1 0;                                        //> top en 0
		bottom		<= #1 1'b0;                                 //> bottom en 0
		count		<= #1 0;                                    //> vacía
	end                                                         //> fin
  else                                                          //> si no:
	begin                                                       //> inicio
		case ({push, pop})                                      //> según {push, pop}:
		2'b10 : if (count<fifo_depth)  // overrun condition     //> solo push: ¿hay espacio?
			begin                                               //> inicio
				top       <= #1 top_plus_1;                     //> avanza top
				count     <= #1 count + 1'b1;                   //> uno más
			end                                                 //> fin
		2'b01 : if(count>0)                                     //> solo pop: ¿hay datos?
			begin                                               //> inicio
				bottom   <= #1 bottom + 1'b1;                   //> avanza bottom
				count	 <= #1 count - 1'b1;                    //> uno menos
			end                                                 //> fin
		2'b11 : begin                                           //> push y pop a la vez: inicio
				bottom   <= #1 bottom + 1'b1;                   //> avanza bottom
				top       <= #1 top_plus_1;                     //> avanza top
		        end                                             //> fin (count no cambia)
    default: ;                                                  //> sin push ni pop: nada
		endcase                                                 //> fin del case
	end                                                         //> fin
end   // always                                                 //> fin del always

//==============================================================
//== Overrun de la FIFO TX (sin efecto observable desde los registros)
//==============================================================
always @(posedge clk or posedge wb_rst_i) // synchronous FIFO   //> se actualiza en flanco de reloj o reset
begin                                                           //> inicio
  if (wb_rst_i)                                                 //> en reset...
    overrun   <= #1 1'b0;                                       //> ...sin overrun
  else                                                          //> si no:
  if(fifo_reset | reset_status)                                 //> con limpieza o lectura de LSR...
    overrun   <= #1 1'b0;                                       //> ...se borra
  else                                                          //> si no:
  if(push & (count==fifo_depth))                                //> push con la FIFO llena...
    overrun   <= #1 1'b1;                                       //> ...overrun
end   // always                                                 //> fin

endmodule                                                       //> fin del módulo
