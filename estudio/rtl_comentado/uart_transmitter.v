//==============================================================
//== ARCHIVO uart_transmitter.v (copia de estudio; el original está en rtl/)
//== Transmisor serie: FIFO TX + FSM que envía start(0) -> datos LSB primero -> [paridad] -> stop(1).
//== Avanza solo con enable (16 pulsos por bit). Líneas 1-147: licencia e historial.
//==============================================================
//////////////////////////////////////////////////////////////////////
////                                                              ////
////  uart_transmitter.v                                          ////
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
////  UART core transmitter logic                                 ////
////                                                              ////
////  Known problems (limits):                                    ////
////  None known                                                  ////
////                                                              ////
////  To Do:                                                      ////
////  Thourough testing.                                          ////
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
// Revision 1.16  2002/01/08 11:29:40  mohor
// tf_pop was too wide. Now it is only 1 clk cycle width.
//
// Revision 1.15  2001/12/17 14:46:48  mohor
// overrun signal was moved to separate block because many sequential lsr
// reads were preventing data from being written to rx fifo.
// underrun signal was not used and was removed from the project.
//
// Revision 1.14  2001/12/03 21:44:29  gorban
// Updated specification documentation.
// Added full 32-bit data bus interface, now as default.
// Address is 5-bit wide in 32-bit data bus mode.
// Added wb_sel_i input to the core. It's used in the 32-bit mode.
// Added debug interface with two 32-bit read-only registers in 32-bit mode.
// Bits 5 and 6 of LSR are now only cleared on TX FIFO write.
// My small test bench is modified to work with 32-bit mode.
//
// Revision 1.13  2001/11/08 14:54:23  mohor
// Comments in Slovene language deleted, few small fixes for better work of
// old tools. IRQs need to be fix.
//
// Revision 1.12  2001/11/07 17:51:52  gorban
// Heavily rewritten interrupt and LSR subsystems.
// Many bugs hopefully squashed.
//
// Revision 1.11  2001/10/29 17:00:46  gorban
// fixed parity sending and tx_fifo resets over- and underrun
//
// Revision 1.10  2001/10/20 09:58:40  gorban
// Small synopsis fixes
//
// Revision 1.9  2001/08/24 21:01:12  mohor
// Things connected to parity changed.
// Clock devider changed.
//
// Revision 1.8  2001/08/23 16:05:05  mohor
// Stop bit bug fixed.
// Parity bug fixed.
// WISHBONE read cycle bug fixed,
// OE indicator (Overrun Error) bug fixed.
// PE indicator (Parity Error) bug fixed.
// Register read bug fixed.
//
// Revision 1.6  2001/06/23 11:21:48  gorban
// DL made 16-bit long. Fixed transmission/reception bugs.
//
// Revision 1.5  2001/06/02 14:28:14  gorban
// Fixed receiver and transmitter. Major bug fixed.
//
// Revision 1.4  2001/05/31 20:08:01  gorban
// FIFO changes and other corrections.
//
// Revision 1.3  2001/05/27 17:37:49  gorban
// Fixed many bugs. Updated spec. Changed FIFO files structure. See CHANGES.txt file.
//
// Revision 1.2  2001/05/21 19:12:02  gorban
// Corrected some Linter messages.
//
// Revision 1.1  2001/05/17 18:34:18  gorban
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
module uart_transmitter (clk, wb_rst_i, lcr, tf_push, wb_dat_i, enable,	stx_pad_o, tstate, tf_count, tx_reset, lsr_mask);  //> módulo uart_transmitter y su lista de puertos

input 										clk;                //> reloj
input 										wb_rst_i;           //> reset asíncrono
input [7:0] 								lcr;                //> LCR: formato de línea y break
input 										tf_push;            //> pulso de escritura a THR
input [7:0] 								wb_dat_i;           //> byte a meter a la FIFO
input 										enable;             //> pulso a 16 x baudios
input 										tx_reset;           //> limpieza de FIFO TX (FCR[2])
input 										lsr_mask; //reset of fifo  //> lectura de LSR (solo limpia el overrun de la FIFO)
output 										stx_pad_o;          //> salida serie
output [2:0] 								tstate;             //> estado de la FSM
output [`UART_FIFO_COUNTER_W-1:0] 	tf_count;                   //> ocupación de la FIFO TX

//==============================================================
//== Registros internos
//==============================================================
reg [2:0] 									tstate;             //> estado actual
reg [4:0] 									counter;            //> cuenta los 16 pulsos de cada bit
reg [2:0] 									bit_counter;   // counts the bits to be sent  //> bits de dato que faltan por enviar
reg [6:0] 									shift_out;	// output shift register  //> bits que aún no salen
reg 											stx_o_tmp;      //> valor que se pone en la línea (registrado)
reg 											parity_xor;  // parity of the word  //> XOR de los datos (base de la paridad)
reg 											tf_pop;         //> pulso para sacar un byte de la FIFO
reg 											bit_out;        //> bit que se está enviando

//==============================================================
//== FIFO TX (16 x 8)
//==============================================================
// TX FIFO instance
//
// Transmitter FIFO signals
wire [`UART_FIFO_WIDTH-1:0] 			tf_data_in;             //> dato que entra a la FIFO
wire [`UART_FIFO_WIDTH-1:0] 			tf_data_out;            //> dato que sale de la FIFO
wire 											tf_push;        //> push como cable
wire 											tf_overrun;     //> overrun de la FIFO TX (no llega a ningún registro)
wire [`UART_FIFO_COUNTER_W-1:0] 		tf_count;               //> ocupación como cable

assign 										tf_data_in = wb_dat_i;  //> el dato de entrada es el byte de THR

uart_tfifo fifo_tx(	// error bit signal is not used in transmitter FIFO  //> instancia de uart_tfifo
	.clk(		clk		),                                      //> reloj
	.wb_rst_i(	wb_rst_i	),                                  //> reset
	.data_in(	tf_data_in	),                                  //> dato de entrada
	.data_out(	tf_data_out	),                                  //> dato de salida (el próximo a enviar)
	.push(		tf_push		),                                  //> push
	.pop(		tf_pop		),                                  //> pop
	.overrun(	tf_overrun	),                                  //> overrun
	.count(		tf_count	),                                  //> ocupación
	.fifo_reset(	tx_reset	),                              //> limpieza por FCR[2]
	.reset_status(lsr_mask)                                     //> lectura de LSR
);                                                              //> fin de la instancia

//==============================================================
//== Estados de la FSM (Debug 2[2:0])
//==============================================================
// TRANSMITTER FINAL STATE MACHINE

parameter s_idle        = 3'd0;                                 //> 0: reposo, línea en 1
parameter s_send_start  = 3'd1;                                 //> 1: bit de inicio
parameter s_send_byte   = 3'd2;                                 //> 2: bits de dato
parameter s_send_parity = 3'd3;                                 //> 3: bit de paridad
parameter s_send_stop   = 3'd4;                                 //> 4: bit(s) de parada
parameter s_pop_byte    = 3'd5;                                 //> 5: sacar el byte de la FIFO

//==============================================================
//== FSM del transmisor
//== idle -> pop_byte -> send_start -> send_byte xN -> [send_parity] -> send_stop -> idle
//==============================================================
always @(posedge clk or posedge wb_rst_i)                       //> se actualiza en flanco de reloj o reset
begin                                                           //> inicio
  if (wb_rst_i)                                                 //> en reset:
  begin                                                         //> inicio
	tstate       <= #1 s_idle;                                  //> estado de reposo
	stx_o_tmp       <= #1 1'b1;                                 //> línea en 1
	counter   <= #1 5'b0;                                       //> contador en 0
	shift_out   <= #1 7'b0;                                     //> registro de desplazamiento en 0
	bit_out     <= #1 1'b0;                                     //> bit actual en 0
	parity_xor  <= #1 1'b0;                                     //> paridad en 0
	tf_pop      <= #1 1'b0;                                     //> sin pop
	bit_counter <= #1 3'b0;                                     //> contador de bits en 0
  end                                                           //> fin
  else                                                          //> si no:
  if (enable)                                                   //> solo avanza con enable (con DL = 0 queda congelada)
  begin                                                         //> inicio
	case (tstate)                                               //> según el estado:
	s_idle	 :	if (~|tf_count) // if tf_count==0               //> IDLE: ¿FIFO vacía?
			begin                                               //> inicio
				tstate <= #1 s_idle;                            //> se queda en reposo
				stx_o_tmp <= #1 1'b1;                           //> línea en 1
			end                                                 //> fin
			else                                                //> hay datos:
			begin                                               //> inicio
				tf_pop <= #1 1'b0;                              //> sin pop todavía
				stx_o_tmp  <= #1 1'b1;                          //> línea en 1
				tstate  <= #1 s_pop_byte;                       //> va a sacar el byte
			end                                                 //> fin
	s_pop_byte :	begin                                       //> POP_BYTE: inicio
				tf_pop <= #1 1'b1;                              //> pop (dura 1 ciclo)
				case (lcr[/*`UART_LC_BITS*/1:0])  // number of bits in a word  //> según el número de bits:
				2'b00 : begin                                   //> 5 bits:
					bit_counter <= #1 3'b100;                   //> se cuentan 5 (4..0)
					parity_xor  <= #1 ^tf_data_out[4:0];        //> paridad de los 5 bits
				     end                                        //> fin
				2'b01 : begin                                   //> 6 bits:
					bit_counter <= #1 3'b101;                   //> se cuentan 6
					parity_xor  <= #1 ^tf_data_out[5:0];        //> paridad de los 6 bits
				     end                                        //> fin
				2'b10 : begin                                   //> 7 bits:
					bit_counter <= #1 3'b110;                   //> se cuentan 7
					parity_xor  <= #1 ^tf_data_out[6:0];        //> paridad de los 7 bits
				     end                                        //> fin
				2'b11 : begin                                   //> 8 bits:
					bit_counter <= #1 3'b111;                   //> se cuentan 8
					parity_xor  <= #1 ^tf_data_out[7:0];        //> paridad de los 8 bits
				     end                                        //> fin
				endcase                                         //> fin del case
				{shift_out[6:0], bit_out} <= #1 tf_data_out;    //> carga el byte: bit 0 a bit_out, bits 7:1 al registro
				tstate <= #1 s_send_start;                      //> siguiente: bit de inicio
			end                                                 //> fin
	s_send_start :	begin                                       //> SEND_START: inicio
				tf_pop <= #1 1'b0;                              //> baja el pop
				if (~|counter)                                  //> ¿contador en 0?
					counter <= #1 5'b01111;                     //> carga 15 (16 pulsos en total)
				else                                            //> si no:
				if (counter == 5'b00001)                        //> ¿último pulso del bit?
				begin                                           //> inicio
					counter <= #1 0;                            //> contador en 0
					tstate <= #1 s_send_byte;                   //> pasa a los datos
				end                                             //> fin
				else                                            //> si no:
					counter <= #1 counter - 1'b1;               //> cuenta hacia abajo
				stx_o_tmp <= #1 1'b0;                           //> línea en 0 = bit de inicio
			end                                                 //> fin
	s_send_byte :	begin                                       //> SEND_BYTE: inicio
				if (~|counter)                                  //> ¿contador en 0?
					counter <= #1 5'b01111;                     //> carga 15
				else                                            //> si no:
				if (counter == 5'b00001)                        //> ¿último pulso del bit?
				begin                                           //> inicio
					if (bit_counter > 3'b0)                     //> ¿quedan bits de dato?
					begin                                       //> inicio
						bit_counter <= #1 bit_counter - 1'b1;   //> uno menos
						{shift_out[5:0],bit_out  } <= #1 {shift_out[6:1], shift_out[0]};  //> desplaza: el siguiente bit pasa a bit_out (LSB primero)
						tstate <= #1 s_send_byte;               //> sigue en datos
					end                                         //> fin
					else   // end of byte                       //> si no (fin de los datos):
					if (~lcr[`UART_LC_PE])                      //> ¿sin paridad?
					begin                                       //> inicio
						tstate <= #1 s_send_stop;               //> pasa a parada
					end                                         //> fin
					else                                        //> con paridad:
					begin                                       //> inicio
						case ({lcr[`UART_LC_EP],lcr[`UART_LC_SP]})  //> según {EPS, SP}:
						2'b00:	bit_out <= #1 ~parity_xor;      //> impar: NOT XOR
						2'b01:	bit_out <= #1 1'b1;             //> stick con EPS=0: siempre 1
						2'b10:	bit_out <= #1 parity_xor;       //> par: XOR
						2'b11:	bit_out <= #1 1'b0;             //> stick con EPS=1: siempre 0
						endcase                                 //> fin del case
						tstate <= #1 s_send_parity;             //> pasa a paridad
					end                                         //> fin
					counter <= #1 0;                            //> contador en 0
				end                                             //> fin
				else                                            //> si no:
					counter <= #1 counter - 1'b1;               //> cuenta hacia abajo
				stx_o_tmp <= #1 bit_out; // set output pin      //> la línea toma el bit actual
			end                                                 //> fin
	s_send_parity :	begin                                       //> SEND_PARITY: inicio
				if (~|counter)                                  //> ¿contador en 0?
					counter <= #1 5'b01111;                     //> carga 15
				else                                            //> si no:
				if (counter == 5'b00001)                        //> ¿último pulso?
				begin                                           //> inicio
					counter <= #1 4'b0;                         //> contador en 0
					tstate <= #1 s_send_stop;                   //> pasa a parada
				end                                             //> fin
				else                                            //> si no:
					counter <= #1 counter - 1'b1;               //> cuenta hacia abajo
				stx_o_tmp <= #1 bit_out;                        //> la línea toma el bit de paridad
			end                                                 //> fin
	s_send_stop :  begin                                        //> SEND_STOP: inicio
				if (~|counter)                                  //> ¿contador en 0?
				  begin                                         //> inicio
						casex ({lcr[`UART_LC_SB],lcr[`UART_LC_BITS]})  //> según {STB, WLS}:
  						3'b0xx:	  counter <= #1 5'b01101;     // 1 stop bit ok igor  //> 1 stop: 14 pulsos (+2 de idle y pop = 16)
  						3'b100:	  counter <= #1 5'b10101;     // 1.5 stop bit  //> 1.5 stops con 5 bits: 22 pulsos (+2 = 24)
  						default:	  counter <= #1 5'b11101;     // 2 stop bits  //> 2 stops: 30 pulsos (+2 = 32)
						endcase                                 //> fin del case
					end                                         //> fin
				else                                            //> si no:
				if (counter == 5'b00001)                        //> ¿último pulso?
				begin                                           //> inicio
					counter <= #1 0;                            //> contador en 0
					tstate <= #1 s_idle;                        //> vuelve a reposo
				end                                             //> fin
				else                                            //> si no:
					counter <= #1 counter - 1'b1;               //> cuenta hacia abajo
				stx_o_tmp <= #1 1'b1;                           //> línea en 1 = parada
			end                                                 //> fin

		default : // should never get here                      //> estados 6 y 7: imposibles (rama inalcanzable)
			tstate <= #1 s_idle;                                //> vuelve a reposo
	endcase                                                     //> fin del case
  end // end if enable                                          //> fin del bloque con enable
  else                                                          //> sin enable:
    tf_pop <= #1 1'b0;  // tf_pop must be 1 cycle width         //> baja el pop (dura 1 ciclo de reloj)
end // transmitter logic                                        //> fin del always

//==============================================================
//== Break: LCR[6] = 1 fuerza la línea a 0 en cualquier momento
//==============================================================
assign stx_pad_o = lcr[`UART_LC_BC] ? 1'b0 : stx_o_tmp;    // Break condition  //> salida = 0 con break; si no, el valor de la FSM
	
endmodule                                                       //> fin del módulo
