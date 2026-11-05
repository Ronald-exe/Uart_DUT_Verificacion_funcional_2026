//==============================================================
//== ARCHIVO uart_receiver.v (copia de estudio; el original está en rtl/)
//== Receptor serie: FSM que muestrea cada bit a la mitad (pulso 7 de 16), FIFO RX de 11 bits,
//== detector de break y contador de timeout. Líneas 1-191: licencia e historial.
//==============================================================
//////////////////////////////////////////////////////////////////////
////                                                              ////
////  uart_receiver.v                                             ////
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
////  UART core receiver logic                                    ////
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
// Revision 1.29  2002/07/29 21:16:18  gorban
// The uart_defines.v file is included again in sources.
//
// Revision 1.28  2002/07/22 23:02:23  gorban
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
// Revision 1.27  2001/12/30 20:39:13  mohor
// More than one character was stored in case of break. End of the break
// was not detected correctly.
//
// Revision 1.26  2001/12/20 13:28:27  mohor
// Missing declaration of rf_push_q fixed.
//
// Revision 1.25  2001/12/20 13:25:46  mohor
// rx push changed to be only one cycle wide.
//
// Revision 1.24  2001/12/19 08:03:34  mohor
// Warnings cleared.
//
// Revision 1.23  2001/12/19 07:33:54  mohor
// Synplicity was having troubles with the comment.
//
// Revision 1.22  2001/12/17 14:46:48  mohor
// overrun signal was moved to separate block because many sequential lsr
// reads were preventing data from being written to rx fifo.
// underrun signal was not used and was removed from the project.
//
// Revision 1.21  2001/12/13 10:31:16  mohor
// timeout irq must be set regardless of the rda irq (rda irq does not reset the
// timeout counter).
//
// Revision 1.20  2001/12/10 19:52:05  gorban
// Igor fixed break condition bugs
//
// Revision 1.19  2001/12/06 14:51:04  gorban
// Bug in LSR[0] is fixed.
// All WISHBONE signals are now sampled, so another wait-state is introduced on all transfers.
//
// Revision 1.18  2001/12/03 21:44:29  gorban
// Updated specification documentation.
// Added full 32-bit data bus interface, now as default.
// Address is 5-bit wide in 32-bit data bus mode.
// Added wb_sel_i input to the core. It's used in the 32-bit mode.
// Added debug interface with two 32-bit read-only registers in 32-bit mode.
// Bits 5 and 6 of LSR are now only cleared on TX FIFO write.
// My small test bench is modified to work with 32-bit mode.
//
// Revision 1.17  2001/11/28 19:36:39  gorban
// Fixed: timeout and break didn't pay attention to current data format when counting time
//
// Revision 1.16  2001/11/27 22:17:09  gorban
// Fixed bug that prevented synthesis in uart_receiver.v
//
// Revision 1.15  2001/11/26 21:38:54  gorban
// Lots of fixes:
// Break condition wasn't handled correctly at all.
// LSR bits could lose their values.
// LSR value after reset was wrong.
// Timing of THRE interrupt signal corrected.
// LSR bit 0 timing corrected.
//
// Revision 1.14  2001/11/10 12:43:21  gorban
// Logic Synthesis bugs fixed. Some other minor changes
//
// Revision 1.13  2001/11/08 14:54:23  mohor
// Comments in Slovene language deleted, few small fixes for better work of
// old tools. IRQs need to be fix.
//
// Revision 1.12  2001/11/07 17:51:52  gorban
// Heavily rewritten interrupt and LSR subsystems.
// Many bugs hopefully squashed.
//
// Revision 1.11  2001/10/31 15:19:22  gorban
// Fixes to break and timeout conditions
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
// Revision 1.0  2001-05-17 21:27:11+02  jacob
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
module uart_receiver (clk, wb_rst_i, lcr, rf_pop, srx_pad_i, enable,   //> módulo uart_receiver: reloj, reset, LCR, pop, entrada serie, enable,
	counter_t, rf_count, rf_data_out, rf_error_bit, rf_overrun, rx_reset, lsr_mask, rstate, rf_push_pulse);  //> timeout, ocupación, cima, error, overrun, limpieza, lectura de LSR, estado, push

input				clk;                                        //> reloj
input				wb_rst_i;                                   //> reset asíncrono
input	[7:0]	lcr;                                            //> LCR (no mira LCR[2]: solo revisa 1 bit de parada)
input				rf_pop;                                     //> pulso de lectura de RBR
input				srx_pad_i;                                  //> entrada serie (sincronizada, o la salida del TX en loopback)
input				enable;                                     //> pulso a 16 x baudios
input				rx_reset;                                   //> limpieza de FIFO RX (FCR[1])
input       lsr_mask;                                           //> lectura de LSR (limpia overrun)

output	[9:0]			counter_t;                              //> contador de timeout
output	[`UART_FIFO_COUNTER_W-1:0]	rf_count;                   //> ocupación de la FIFO RX
output	[`UART_FIFO_REC_WIDTH-1:0]	rf_data_out;                //> cima de la FIFO RX (11 bits)
output				rf_overrun;                                 //> overrun
output				rf_error_bit;                               //> hay algún error en la FIFO
output [3:0] 		rstate;                                     //> estado de la FSM
output 				rf_push_pulse;                              //> pulso de 1 ciclo al meter un carácter

//==============================================================
//== Registros internos
//==============================================================
reg	[3:0]	rstate;                                             //> estado actual
reg	[3:0]	rcounter16;                                         //> contador de pulsos dentro del bit (hacia abajo)
reg	[2:0]	rbit_counter;                                       //> bits de dato que faltan
reg	[7:0]	rshift;			// receiver shift register          //> datos recibidos
reg		rparity;		// received parity                      //> bit de paridad recibido
reg		rparity_error;                                          //> resultado de la revisión de paridad
reg		rframing_error;		// framing error flag               //> resultado de la revisión del bit de parada
reg		rbit_in;                                                //> (no se usa)
reg		rparity_xor;                                            //> XOR de datos + paridad
reg	[7:0]	counter_b;	// counts the 0 (low) signals           //> pulsos que lleva la línea en 0 (para break)
reg   rf_push_q;                                                //> rf_push retrasado

//==============================================================
//== Señales de la FIFO RX
//==============================================================
// RX FIFO signals
reg	[`UART_FIFO_REC_WIDTH-1:0]	rf_data_in;                     //> carácter a meter: {dato, break, paridad, trama}
wire	[`UART_FIFO_REC_WIDTH-1:0]	rf_data_out;                //> cima de la FIFO
wire      rf_push_pulse;                                        //> pulso de push
reg				rf_push;                                        //> push "largo" (dura un pulso de enable)
wire				rf_pop;                                     //> pop como cable
wire				rf_overrun;                                 //> overrun como cable
wire	[`UART_FIFO_COUNTER_W-1:0]	rf_count;                   //> ocupación como cable
wire				rf_error_bit; // an error (parity or framing) is inside the fifo  //> error en la FIFO como cable
wire 				break_error = (counter_b == 0);             //> break: la línea estuvo en 0 un carácter completo

//==============================================================
//== FIFO RX (16 x 11)
//==============================================================
// RX FIFO instance
uart_rfifo #(`UART_FIFO_REC_WIDTH) fifo_rx(                     //> instancia de uart_rfifo con ancho 11
	.clk(		clk		),                                      //> reloj
	.wb_rst_i(	wb_rst_i	),                                  //> reset
	.data_in(	rf_data_in	),                                  //> carácter de entrada
	.data_out(	rf_data_out	),                                  //> cima
	.push(		rf_push_pulse		),                          //> push de 1 ciclo
	.pop(		rf_pop		),                                  //> pop
	.overrun(	rf_overrun	),                                  //> overrun
	.count(		rf_count	),                                  //> ocupación
	.error_bit(	rf_error_bit	),                              //> error en la FIFO
	.fifo_reset(	rx_reset	),                              //> limpieza por FCR[1]
	.reset_status(lsr_mask)                                     //> lectura de LSR
);                                                              //> fin de la instancia

//==============================================================
//== Comparadores del contador
//==============================================================
wire 		rcounter16_eq_7 = (rcounter16 == 4'd7);             //> contador = 7: mitad del bit (momento de muestrear)
wire		rcounter16_eq_0 = (rcounter16 == 4'd0);             //> contador = 0: fin del bit
wire		rcounter16_eq_1 = (rcounter16 == 4'd1);             //> contador = 1 (no se usa)

wire [3:0] rcounter16_minus_1 = rcounter16 - 1'b1;              //> contador - 1 (con vuelta de 0 a 15)

//==============================================================
//== Estados de la FSM (Debug 2[11:8]; la cobertura FSM espera los 11)
//==============================================================
parameter  sr_idle 					= 4'd0;                     //> 0: reposo
parameter  sr_rec_start 			= 4'd1;                     //> 1: verificando el bit de inicio
parameter  sr_rec_bit 				= 4'd2;                     //> 2: recibiendo un bit de dato
parameter  sr_rec_parity			= 4'd3;                     //> 3: recibiendo la paridad
parameter  sr_rec_stop 				= 4'd4;                     //> 4: recibiendo la parada
parameter  sr_check_parity 		= 4'd5;                         //> 5: comparando la paridad
parameter  sr_rec_prepare 			= 4'd6;                     //> 6: esperando el final del bit de inicio
parameter  sr_end_bit				= 4'd7;                     //> 7: fin de un bit de dato
parameter  sr_ca_lc_parity	      = 4'd8;                       //> 8: calculando el XOR de paridad
parameter  sr_wait1 					= 4'd9;                 //> 9: esperando el final del bit de paridad
parameter  sr_push 					= 4'd10;                    //> 10: metiendo el carácter en la FIFO


//==============================================================
//== FSM del receptor
//== idle -> rec_start -> rec_prepare -> (rec_bit -> end_bit) xN
//== -> [rec_parity -> ca_lc_parity -> check_parity -> wait1] -> rec_stop -> push -> idle
//==============================================================
always @(posedge clk or posedge wb_rst_i)                       //> se actualiza en flanco de reloj o reset
begin                                                           //> inicio
  if (wb_rst_i)                                                 //> en reset:
  begin                                                         //> inicio
     rstate 			<= #1 sr_idle;                          //> reposo
	  rbit_in 				<= #1 1'b0;                         //> bit de entrada en 0
	  rcounter16 			<= #1 0;                            //> contador en 0
	  rbit_counter 		<= #1 0;                                //> contador de bits en 0
	  rparity_xor 		<= #1 1'b0;                             //> XOR en 0
	  rframing_error 	<= #1 1'b0;                             //> sin error de trama
	  rparity_error 		<= #1 1'b0;                         //> sin error de paridad
	  rparity 				<= #1 1'b0;                         //> paridad en 0
	  rshift 				<= #1 0;                            //> datos en 0
	  rf_push 				<= #1 1'b0;                         //> sin push
	  rf_data_in 			<= #1 0;                            //> carácter en 0
  end                                                           //> fin
  else                                                          //> si no:
  if (enable)                                                   //> solo avanza con enable
  begin                                                         //> inicio
	case (rstate)                                               //> según el estado:
	sr_idle : begin                                             //> IDLE: inicio
			rf_push 			  <= #1 1'b0;                   //> sin push
			rf_data_in 	  <= #1 0;                              //> carácter en 0
			rcounter16 	  <= #1 4'b1110;                        //> precarga el contador en 14
			if (srx_pad_i==1'b0 & ~break_error)   // detected a pulse (start bit?)  //> ¿línea en 0 y sin break en curso?
			begin                                               //> inicio
				rstate 		  <= #1 sr_rec_start;               //> posible bit de inicio
			end                                                 //> fin
		end                                                     //> fin
	sr_rec_start :	begin                                       //> REC_START: inicio
  			rf_push 			  <= #1 1'b0;                   //> sin push
				if (rcounter16_eq_7)    // check the pulse      //> ¿mitad del bit de inicio?
					if (srx_pad_i==1'b1)   // no start bit      //> ¿la línea volvió a 1? -> era un glitch...
						rstate <= #1 sr_idle;                   //> ...se descarta
					else            // start bit detected       //> si sigue en 0: inicio válido
						rstate <= #1 sr_rec_prepare;            //> ...espera el final del bit de inicio
				rcounter16 <= #1 rcounter16_minus_1;            //> cuenta hacia abajo
			end                                                 //> fin
	sr_rec_prepare:begin                                        //> REC_PREPARE: inicio
				case (lcr[/*`UART_LC_BITS*/1:0])  // number of bits in a word  //> según el número de bits:
				2'b00 : rbit_counter <= #1 3'b100;              //> 5 bits (cuenta 4..0)
				2'b01 : rbit_counter <= #1 3'b101;              //> 6 bits
				2'b10 : rbit_counter <= #1 3'b110;              //> 7 bits
				2'b11 : rbit_counter <= #1 3'b111;              //> 8 bits
				endcase                                         //> fin del case
				if (rcounter16_eq_0)                            //> ¿terminó el bit de inicio?
				begin                                           //> inicio
					rstate		<= #1 sr_rec_bit;               //> pasa a recibir datos
					rcounter16	<= #1 4'b1110;                  //> (anulada por la línea 328: el contador queda en 15)
					rshift		<= #1 0;                        //> limpia los datos
				end                                             //> fin
				else                                            //> si no:
					rstate <= #1 sr_rec_prepare;                //> sigue esperando
				rcounter16 <= #1 rcounter16_minus_1;            //> cuenta hacia abajo (esta asignación gana)
			end                                                 //> fin
	sr_rec_bit :	begin                                       //> REC_BIT: inicio
				if (rcounter16_eq_0)                            //> ¿fin del bit?
					rstate <= #1 sr_end_bit;                    //> pasa a end_bit
				if (rcounter16_eq_7) // read the bit            //> ¿mitad del bit? muestrea:
					case (lcr[/*`UART_LC_BITS*/1:0])  // number of bits in a word  //> según el número de bits:
					2'b00 : rshift[4:0]  <= #1 {srx_pad_i, rshift[4:1]};  //> 5 bits: entra por arriba y desplaza (LSB primero)
					2'b01 : rshift[5:0]  <= #1 {srx_pad_i, rshift[5:1]};  //> 6 bits
					2'b10 : rshift[6:0]  <= #1 {srx_pad_i, rshift[6:1]};  //> 7 bits
					2'b11 : rshift[7:0]  <= #1 {srx_pad_i, rshift[7:1]};  //> 8 bits
					endcase                                     //> fin del case
				rcounter16 <= #1 rcounter16_minus_1;            //> cuenta hacia abajo
			end                                                 //> fin
	sr_end_bit :   begin                                        //> END_BIT: inicio
				if (rbit_counter==3'b0) // no more bits in word  //> ¿no quedan bits?
					if (lcr[`UART_LC_PE]) // choose state based on parity  //> con paridad:
						rstate <= #1 sr_rec_parity;             //> recibir la paridad
					else                                        //> sin paridad:
					begin                                       //> inicio
						rstate <= #1 sr_rec_stop;               //> recibir la parada
						rparity_error <= #1 1'b0;  // no parity - no error :)  //> y no hay error de paridad
					end                                         //> fin
				else		// else we have more bits to read   //> quedan bits:
				begin                                           //> inicio
					rstate <= #1 sr_rec_bit;                    //> siguiente bit
					rbit_counter <= #1 rbit_counter - 1'b1;     //> uno menos
				end                                             //> fin
				rcounter16 <= #1 4'b1110;                       //> recarga el contador en 14
			end                                                 //> fin
	sr_rec_parity: begin                                        //> REC_PARITY: inicio
				if (rcounter16_eq_7)	// read the parity      //> ¿mitad del bit de paridad?
				begin                                           //> inicio
					rparity <= #1 srx_pad_i;                    //> guarda el bit de paridad
					rstate <= #1 sr_ca_lc_parity;               //> pasa a calcular
				end                                             //> fin
				rcounter16 <= #1 rcounter16_minus_1;            //> cuenta hacia abajo
			end                                                 //> fin
	sr_ca_lc_parity : begin    // rcounter equals 6             //> CA_LC_PARITY: inicio
				rcounter16  <= #1 rcounter16_minus_1;           //> cuenta hacia abajo
				rparity_xor <= #1 ^{rshift,rparity}; // calculate parity on all incoming data  //> XOR de todos los datos + paridad recibida
				rstate      <= #1 sr_check_parity;              //> pasa a comparar
			  end                                               //> fin
	sr_check_parity: begin	  // rcounter equals 5              //> CHECK_PARITY: inicio
				case ({lcr[`UART_LC_EP],lcr[`UART_LC_SP]})      //> según {EPS, SP}:
					2'b00: rparity_error <= #1  rparity_xor == 0;  // no error if parity 1  //> impar: error si el XOR total es 0
					2'b01: rparity_error <= #1 ~rparity;      // parity should sticked to 1  //> stick 1: error si la paridad no es 1
					2'b10: rparity_error <= #1  rparity_xor == 1;   // error if parity is odd  //> par: error si el XOR total es 1
					2'b11: rparity_error <= #1  rparity;	  // parity should be sticked to 0  //> stick 0: error si la paridad no es 0
				endcase                                         //> fin del case
				rcounter16 <= #1 rcounter16_minus_1;            //> cuenta hacia abajo
				rstate <= #1 sr_wait1;                          //> pasa a esperar
			  end                                               //> fin
	sr_wait1 :	if (rcounter16_eq_0)                            //> WAIT1: ¿fin del bit de paridad?
			begin                                               //> inicio
				rstate <= #1 sr_rec_stop;                       //> pasa a la parada
				rcounter16 <= #1 4'b1110;                       //> recarga el contador en 14
			end                                                 //> fin
			else                                                //> si no:
				rcounter16 <= #1 rcounter16_minus_1;            //> cuenta hacia abajo
	sr_rec_stop :	begin                                       //> REC_STOP: inicio
				if (rcounter16_eq_7)	// read the parity      //> ¿mitad del PRIMER bit de parada?
				begin                                           //> inicio
					rframing_error <= #1 !srx_pad_i; // no framing error if input is 1 (stop bit)  //> error de trama si la línea está en 0 (no revisa un 2.o bit de parada)
					rstate <= #1 sr_push;                       //> pasa a push
				end                                             //> fin
				rcounter16 <= #1 rcounter16_minus_1;            //> cuenta hacia abajo
			end                                                 //> fin
	sr_push :	begin                                           //> PUSH: inicio
///////////////////////////////////////
//				$display($time, ": received: %b", rf_data_in);
        if(srx_pad_i | break_error)                             //> ¿línea en 1 o break detectado?
          begin                                                 //> inicio
            if(break_error)                                     //> con break:
        		  rf_data_in 	<= #1 {8'b0, 3'b100}; // break input (empty character) to receiver FIFO  //> entra un carácter de ceros con BI = 1 (reemplaza al de error de trama)
            else                                                //> sin break:
        			rf_data_in  <= #1 {rshift, 1'b0, rparity_error, rframing_error};  //> entra {dato, 0, error de paridad, error de trama}
      		  rf_push 		  <= #1 1'b1;                       //> pide el push
    				rstate        <= #1 sr_idle;                //> vuelve a reposo
          end                                                   //> fin
        else if(~rframing_error)  // There's always a framing before break_error -> wait for break or srx_pad_i  //> la línea sigue en 0 pero la parada estuvo bien (ya empezó otro carácter):
          begin                                                 //> inicio
       			rf_data_in  <= #1 {rshift, 1'b0, rparity_error, rframing_error};  //> entra el carácter
      		  rf_push 		  <= #1 1'b1;                       //> pide el push
      			rcounter16 	  <= #1 4'b1110;                    //> recarga el contador
    				rstate 		  <= #1 sr_rec_start;           //> salta directo a verificar el nuevo inicio
          end                                                   //> fin
                      
			end                                                 //> fin (con error de trama y línea en 0: se queda esperando)
	default : rstate <= #1 sr_idle;                             //> estados 11..15: imposibles (rama inalcanzable)
	endcase                                                     //> fin del case
  end  // if (enable)                                           //> fin del bloque con enable
end // always of receiver                                       //> fin del always

//==============================================================
//== Pulso de push de 1 ciclo de reloj (rf_push puede durar DL ciclos)
//==============================================================
always @ (posedge clk or posedge wb_rst_i)                      //> se actualiza en flanco de reloj o reset
begin                                                           //> inicio
  if(wb_rst_i)                                                  //> en reset...
    rf_push_q <= 0;                                             //> ...en 0
  else                                                          //> si no...
    rf_push_q <= #1 rf_push;                                    //> ...guarda rf_push del ciclo anterior
end                                                             //> fin

assign rf_push_pulse = rf_push & ~rf_push_q;                    //> pulso = rf_push ahora y no antes

  
//
// Break condition detection.
// Works in conjuction with the receiver state machine

//==============================================================
//== Tiempos de carácter según LCR[3:0] = {PEN, STB, WLS}
//== toc_value = 4 caracteres - 1 (en pulsos de enable). Ej.: 8N1 = 10 x 16 x 4 - 1 = 639
//==============================================================
reg 	[9:0]	toc_value; // value to be set to timeout counter  //> valor de recarga del contador de timeout

always @(lcr)                                                   //> se recalcula si cambia LCR
	case (lcr[3:0])                                             //> según {PEN, STB, WLS}:
		4'b0000										: toc_value = 447; // 7 bits  //> 5N1 (7 bits)
		4'b0100										: toc_value = 479; // 7.5 bits  //> 5 bits, 1.5 stops
		4'b0001,	4'b1000							: toc_value = 511; // 8 bits  //> 6N1 o 5 bits + paridad
		4'b1100										: toc_value = 543; // 8.5 bits  //> 5 bits + paridad + 1.5 stops
		4'b0010, 4'b0101, 4'b1001				: toc_value = 575; // 9 bits  //> 7N1, 6N2, 6 bits + paridad
		4'b0011, 4'b0110, 4'b1010, 4'b1101	: toc_value = 639; // 10 bits  //> 8N1, 7N2, 7 bits + paridad, 6 bits + paridad + 2 stops
		4'b0111, 4'b1011, 4'b1110				: toc_value = 703; // 11 bits  //> 8N2, 8 bits + paridad, 7 bits + paridad + 2 stops
		4'b1111										: toc_value = 767; // 12 bits  //> 8 bits + paridad + 2 stops (12 bits)
	endcase // case(lcr[3:0])                                   //> fin del case

wire [7:0] 	brc_value; // value to be set to break counter      //> valor del contador de break
assign 		brc_value = toc_value[9:2]; // the same as timeout but 1 insead of 4 character times  //> = toc_value / 4 = 1 tiempo de carácter

//==============================================================
//== Contador de break: cuánto tiempo lleva la línea en 0
//==============================================================
always @(posedge clk or posedge wb_rst_i)                       //> se actualiza en flanco de reloj o reset
begin                                                           //> inicio
	if (wb_rst_i)                                               //> en reset...
		counter_b <= #1 8'd159;                                 //> ...159 = 1 carácter 8N1
	else                                                        //> si no:
	if (srx_pad_i)                                              //> ¿línea en 1?
		counter_b <= #1 brc_value; // character time length - 1  //> recarga (se reinicia el conteo)
	else                                                        //> línea en 0:
	if(enable & counter_b != 8'b0)            // only work on enable times  break not reached.  //> con enable y sin llegar a 0...
		counter_b <= #1 counter_b - 1;  // decrement break counter  //> ...cuenta hacia abajo (0 = break)
end // always of break condition detection                      //> fin

//==============================================================
//== Contador de timeout: 4 tiempos de carácter sin actividad con datos en la FIFO
//==============================================================
///
/// Timeout condition detection
reg	[9:0]	counter_t;	// counts the timeout condition clocks  //> contador de timeout

always @(posedge clk or posedge wb_rst_i)                       //> se actualiza en flanco de reloj o reset
begin                                                           //> inicio
	if (wb_rst_i)                                               //> en reset...
		counter_t <= #1 10'd639; // 10 bits for the default 8N1  //> ...639 = 4 caracteres 8N1
	else                                                        //> si no:
		if(rf_push_pulse || rf_pop || rf_count == 0) // counter is reset when RX FIFO is empty, accessed or above trigger level  //> entra un dato, se lee uno o la FIFO está vacía (no revisa el nivel de disparo)...
			counter_t <= #1 toc_value;                          //> ...recarga
		else                                                    //> si no:
		if (enable && counter_t != 10'b0)  // we don't want to underflow  //> con enable y sin llegar a 0...
			counter_t <= #1 counter_t - 1;		                //> ...cuenta hacia abajo (0 + FIFO no vacía = interrupción de timeout)
end                                                             //> fin
	
endmodule                                                       //> fin del módulo
