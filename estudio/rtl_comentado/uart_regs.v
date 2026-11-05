//==============================================================
//== ARCHIVO uart_regs.v (copia de estudio; el original está en rtl/)
//== Núcleo del UART: registros y mux de lectura, TX y RX, divisor de baudios,
//== LSR, MSR, interrupciones e IIR, loopback y salidas de módem.
//== Ruta de puerta trasera: tb_top.dut.regs.<señal>. Líneas 1-221: licencia e historial.
//==============================================================
//////////////////////////////////////////////////////////////////////
////                                                              ////
////  uart_regs.v                                                 ////
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
////  Registers of the uart 16550 core                            ////
////                                                              ////
////  Known problems (limits):                                    ////
////  Inserts 1 wait state in all WISHBONE transfers              ////
////                                                              ////
////  To Do:                                                      ////
////  Nothing or verification.                                    ////
////                                                              ////
////  Author(s):                                                  ////
////      - gorban@opencores.org                                  ////
////      - Jacob Gorban                                          ////
////      - Igor Mohor (igorm@opencores.org)                      ////
////                                                              ////
////  Created:        2001/05/12                                  ////
////  Last Updated:   (See log for the revision history           ////
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
// Revision 1.41  2004/05/21 11:44:41  tadejm
// Added synchronizer flops for RX input.
//
// Revision 1.40  2003/06/11 16:37:47  gorban
// This fixes errors in some cases when data is being read and put to the FIFO at the same time. Patch is submitted by Scott Furman. Update is very recommended.
//
// Revision 1.39  2002/07/29 21:16:18  gorban
// The uart_defines.v file is included again in sources.
//
// Revision 1.38  2002/07/22 23:02:23  gorban
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
// Revision 1.37  2001/12/27 13:24:09  mohor
// lsr[7] was not showing overrun errors.
//
// Revision 1.36  2001/12/20 13:25:46  mohor
// rx push changed to be only one cycle wide.
//
// Revision 1.35  2001/12/19 08:03:34  mohor
// Warnings cleared.
//
// Revision 1.34  2001/12/19 07:33:54  mohor
// Synplicity was having troubles with the comment.
//
// Revision 1.33  2001/12/17 10:14:43  mohor
// Things related to msr register changed. After THRE IRQ occurs, and one
// character is written to the transmit fifo, the detection of the THRE bit in the
// LSR is delayed for one character time.
//
// Revision 1.32  2001/12/14 13:19:24  mohor
// MSR register fixed.
//
// Revision 1.31  2001/12/14 10:06:58  mohor
// After reset modem status register MSR should be reset.
//
// Revision 1.30  2001/12/13 10:09:13  mohor
// thre irq should be cleared only when being source of interrupt.
//
// Revision 1.29  2001/12/12 09:05:46  mohor
// LSR status bit 0 was not cleared correctly in case of reseting the FCR (rx fifo).
//
// Revision 1.28  2001/12/10 19:52:41  gorban
// Scratch register added
//
// Revision 1.27  2001/12/06 14:51:04  gorban
// Bug in LSR[0] is fixed.
// All WISHBONE signals are now sampled, so another wait-state is introduced on all transfers.
//
// Revision 1.26  2001/12/03 21:44:29  gorban
// Updated specification documentation.
// Added full 32-bit data bus interface, now as default.
// Address is 5-bit wide in 32-bit data bus mode.
// Added wb_sel_i input to the core. It's used in the 32-bit mode.
// Added debug interface with two 32-bit read-only registers in 32-bit mode.
// Bits 5 and 6 of LSR are now only cleared on TX FIFO write.
// My small test bench is modified to work with 32-bit mode.
//
// Revision 1.25  2001/11/28 19:36:39  gorban
// Fixed: timeout and break didn't pay attention to current data format when counting time
//
// Revision 1.24  2001/11/26 21:38:54  gorban
// Lots of fixes:
// Break condition wasn't handled correctly at all.
// LSR bits could lose their values.
// LSR value after reset was wrong.
// Timing of THRE interrupt signal corrected.
// LSR bit 0 timing corrected.
//
// Revision 1.23  2001/11/12 21:57:29  gorban
// fixed more typo bugs
//
// Revision 1.22  2001/11/12 15:02:28  mohor
// lsr1r error fixed.
//
// Revision 1.21  2001/11/12 14:57:27  mohor
// ti_int_pnd error fixed.
//
// Revision 1.20  2001/11/12 14:50:27  mohor
// ti_int_d error fixed.
//
// Revision 1.19  2001/11/10 12:43:21  gorban
// Logic Synthesis bugs fixed. Some other minor changes
//
// Revision 1.18  2001/11/08 14:54:23  mohor
// Comments in Slovene language deleted, few small fixes for better work of
// old tools. IRQs need to be fix.
//
// Revision 1.17  2001/11/07 17:51:52  gorban
// Heavily rewritten interrupt and LSR subsystems.
// Many bugs hopefully squashed.
//
// Revision 1.16  2001/11/02 09:55:16  mohor
// no message
//
// Revision 1.15  2001/10/31 15:19:22  gorban
// Fixes to break and timeout conditions
//
// Revision 1.14  2001/10/29 17:00:46  gorban
// fixed parity sending and tx_fifo resets over- and underrun
//
// Revision 1.13  2001/10/20 09:58:40  gorban
// Small synopsis fixes
//
// Revision 1.12  2001/10/19 16:21:40  gorban
// Changes data_out to be synchronous again as it should have been.
//
// Revision 1.11  2001/10/18 20:35:45  gorban
// small fix
//
// Revision 1.10  2001/08/24 21:01:12  mohor
// Things connected to parity changed.
// Clock devider changed.
//
// Revision 1.9  2001/08/23 16:05:05  mohor
// Stop bit bug fixed.
// Parity bug fixed.
// WISHBONE read cycle bug fixed,
// OE indicator (Overrun Error) bug fixed.
// PE indicator (Parity Error) bug fixed.
// Register read bug fixed.
//
// Revision 1.10  2001/06/23 11:21:48  gorban
// DL made 16-bit long. Fixed transmission/reception bugs.
//
// Revision 1.9  2001/05/31 20:08:01  gorban
// FIFO changes and other corrections.
//
// Revision 1.8  2001/05/29 20:05:04  gorban
// Fixed some bugs and synthesis problems.
//
// Revision 1.7  2001/05/27 17:37:49  gorban
// Fixed many bugs. Updated spec. Changed FIFO files structure. See CHANGES.txt file.
//
// Revision 1.6  2001/05/21 19:12:02  gorban
// Corrected some Linter messages.
//
// Revision 1.5  2001/05/17 18:34:18  gorban
// First 'stable' release. Should be sythesizable now. Also added new header.
//
// Revision 1.0  2001-05-17 21:27:11+02  jacob
// Initial revision
//
//

//==============================================================
//== Includes y macros locales
//==============================================================
// synopsys translate_off
`include "timescale.v"                                          //> unidad de tiempo (solo simulación)
// synopsys translate_on

`include "uart_defines.v"                                       //> macros globales

`define UART_DL1 7:0                                            //> DL1 = byte bajo del divisor (DLL)
`define UART_DL2 15:8                                           //> DL2 = byte alto del divisor (DLM)

//==============================================================
//== Lista de puertos
//==============================================================
module uart_regs (clk,                                          //> módulo uart_regs: reloj
	wb_rst_i, wb_addr_i, wb_dat_i, wb_dat_o, wb_we_i, wb_re_i,   //> reset, dirección interna, datos de 8 bits y pulsos de escritura/lectura

// additional signals
	modem_inputs,                                               //> 4 entradas de módem empaquetadas
	stx_pad_o, srx_pad_i,                                       //> línea serie TX y RX

`ifdef DATA_BUS_WIDTH_8                                         //> en 8 bits no hay salidas Debug
`else                                                           //> en 32 bits sí:
// debug interface signals	enabled
ier, iir, fcr, mcr, lcr, msr, lsr, rf_count, tf_count, tstate, rstate,  //> copias internas para uart_debug_if
`endif				                                            //> fin del ifdef
	rts_pad_o, dtr_pad_o, int_o                                 //> salidas de módem e interrupción
`ifdef UART_HAS_BAUDRATE_OUTPUT                                 //> solo con baud_o:
	, baud_o                                                    //> puerto baud_o
`endif                                                          //> fin del ifdef

	);                                                          //> fin de la lista

//==============================================================
//== Declaración de puertos
//==============================================================
input 									clk;                    //> reloj
input 									wb_rst_i;               //> reset asíncrono activo en alto
input [`UART_ADDR_WIDTH-1:0] 		wb_addr_i;                  //> dirección ya decodificada por uart_wb
input [7:0] 							wb_dat_i;               //> byte de escritura
output [7:0] 							wb_dat_o;               //> byte de lectura (combinacional; uart_wb lo registra)
input 									wb_we_i;                //> pulso de escritura (1 ciclo)
input 									wb_re_i;                //> pulso de lectura (1 ciclo)

output 									stx_pad_o;              //> TX serie
input 									srx_pad_i;              //> RX serie (entrada asíncrona)

input [3:0] 							modem_inputs;           //> {cts, dsr, ri, dcd}
output 									rts_pad_o;              //> RTS
output 									dtr_pad_o;              //> DTR
output 									int_o;                  //> interrupción
`ifdef UART_HAS_BAUDRATE_OUTPUT                                 //> solo con baud_o:
output	baud_o;                                                 //> baud_o
`endif                                                          //> fin del ifdef

//==============================================================
//== Salidas para Debug (solo 32 bits)
//==============================================================
`ifdef DATA_BUS_WIDTH_8                                         //> en 8 bits no existen
`else                                                           //> en 32 bits:
// if 32-bit databus and debug interface are enabled
output [3:0]							ier;                    //> IER[3:0]
output [3:0]							iir;                    //> IIR[3:0]
output [1:0]							fcr;  /// bits 7 and 6 of fcr. Other bits are ignored  //> FCR[7:6] (los demás bits de FCR no se guardan)
output [4:0]							mcr;                    //> MCR[4:0]
output [7:0]							lcr;                    //> LCR
output [7:0]							msr;                    //> MSR
output [7:0] 							lsr;                    //> LSR
output [`UART_FIFO_COUNTER_W-1:0] 	rf_count;                   //> ocupación FIFO RX
output [`UART_FIFO_COUNTER_W-1:0] 	tf_count;                   //> ocupación FIFO TX
output [2:0] 							tstate;                 //> estado FSM TX
output [3:0] 							rstate;                 //> estado FSM RX

`endif                                                          //> fin del ifdef

//==============================================================
//== Señales internas
//==============================================================
wire [3:0] 								modem_inputs;           //> entradas de módem como cable
reg 										enable;             //> pulso a 16 x baudios: TX y RX solo avanzan cuando vale 1
`ifdef UART_HAS_BAUDRATE_OUTPUT                                 //> solo con baud_o:
assign baud_o = enable; // baud_o is actually the enable signal  //> baud_o es la señal enable
`endif                                                          //> fin del ifdef


wire 										stx_pad_o;		// received from transmitter module  //> TX serie (sale del transmisor y del loopback)
wire 										srx_pad_i;          //> RX serie de entrada
wire 										srx_pad;            //> RX ya sincronizada (2 flip-flops)

reg [7:0] 								wb_dat_o;               //> byte de lectura es registro (always combinacional)

wire [`UART_ADDR_WIDTH-1:0] 		wb_addr_i;                  //> dirección como cable
wire [7:0] 								wb_dat_i;               //> dato como cable


reg [3:0] 								ier;                    //> IER: 4 bits (7:4 no existen, se leen 0)
reg [3:0] 								iir;                    //> IIR: 4 bits (se lee como {4'b1100, iir})
reg [1:0] 								fcr;  /// bits 7 and 6 of fcr. Other bits are ignored  //> FCR[7:6]
reg [4:0] 								mcr;                    //> MCR: 5 bits
reg [7:0] 								lcr;                    //> LCR: 8 bits
reg [7:0] 								msr;                    //> MSR: 8 bits
reg [15:0] 								dl;  // 32-bit divisor latch  //> divisor de 16 bits (el comentario dice 32 por error)
reg [7:0] 								scratch; // UART scratch register  //> scratch (existe en el RTL; AMB-01)
reg 										start_dlc; // activate dlc on writing to UART_DL1  //> pulso al escribir DLL: reinicia el contador del divisor
reg 										lsr_mask_d; // delay for lsr_mask condition  //> lsr_mask_condition retrasado (para detectar flanco)
reg 										msi_reset; // reset MSR 4 lower bits indicator  //> pulso que limpia MSR[3:0] después de leer MSR
//reg 										threi_clear; // THRE interrupt clear flag
reg [15:0] 								dlc;  // 32-bit divisor latch counter  //> contador descendente del divisor
reg 										int_o;              //> interrupción como registro

reg [3:0] 								trigger_level; // trigger level of the receiver FIFO  //> nivel de disparo decodificado (1/4/8/14)
reg 										rx_reset;           //> pulso de limpieza de la FIFO RX (FCR[1])
reg 										tx_reset;           //> pulso de limpieza de la FIFO TX (FCR[2])

wire 										dlab;			   // divisor latch access bit  //> DLAB = LCR[7]
wire 										cts_pad_i, dsr_pad_i, ri_pad_i, dcd_pad_i; // modem status bits  //> entradas de módem separadas
wire 										loopback;		   // loopback bit (MCR bit 4)  //> loopback = MCR[4]
wire 										cts, dsr, ri, dcd;	   // effective signals  //> pads invertidos (con estos se calculan los deltas)
wire                    cts_c, dsr_c, ri_c, dcd_c; // Complement effective signals (considering loopback)  //> lo que se muestra en MSR[7:4]
wire 										rts_pad_o, dtr_pad_o;		   // modem control outputs  //> salidas de módem

// LSR bits wires and regs
wire [7:0] 								lsr;                    //> LSR completo
wire 										lsr0, lsr1, lsr2, lsr3, lsr4, lsr5, lsr6, lsr7;  //> condición de activación de cada bit
reg										lsr0r, lsr1r, lsr2r, lsr3r, lsr4r, lsr5r, lsr6r, lsr7r;  //> registro de cada bit
wire 										lsr_mask; // lsr_mask  //> pulso de limpieza de LSR (al leer LSR)

//
// ASSINGS
//

//==============================================================
//== Asignaciones continuas: LSR, módem, DLAB y loopback
//==============================================================
assign 									lsr[7:0] = { lsr7r, lsr6r, lsr5r, lsr4r, lsr3r, lsr2r, lsr1r, lsr0r };  //> LSR = sus 8 registros individuales

assign 									{cts_pad_i, dsr_pad_i, ri_pad_i, dcd_pad_i} = modem_inputs;  //> separa las 4 entradas de módem
assign 									{cts, dsr, ri, dcd} = ~{cts_pad_i,dsr_pad_i,ri_pad_i,dcd_pad_i};  //> versión invertida de los pads

assign                  {cts_c, dsr_c, ri_c, dcd_c} = loopback ? {mcr[`UART_MC_RTS],mcr[`UART_MC_DTR],mcr[`UART_MC_OUT1],mcr[`UART_MC_OUT2]}  //> MSR[7:4]: en loopback = {RTS, DTR, OUT1, OUT2} del MCR...
                                                               : {cts_pad_i,dsr_pad_i,ri_pad_i,dcd_pad_i};  //> ...fuera de loopback = pads sin invertir (la especificación dice complemento; AMB-04)

assign 									dlab = lcr[`UART_LC_DL];  //> DLAB
assign 									loopback = mcr[4];      //> loopback

// assign modem outputs                                         //> comentario original
assign 									rts_pad_o = mcr[`UART_MC_RTS];  //> RTS = MCR[1], sin invertir (AMB-03)
assign 									dtr_pad_o = mcr[`UART_MC_DTR];  //> DTR = MCR[0], sin invertir (AMB-03)

//==============================================================
//== Señales de interrupción y de FIFO
//==============================================================
// Interrupt signals
wire 										rls_int;  // receiver line status interrupt  //> condición de errores de línea
wire 										rda_int;  // receiver data available interrupt  //> condición de dato disponible
wire 										ti_int;   // timeout indicator interrupt  //> condición de timeout
wire										thre_int; // transmitter holding register empty interrupt  //> condición de FIFO TX vacía
wire 										ms_int;   // modem status interrupt  //> condición de módem

// FIFO signals
reg 										tf_push;            //> pulso de push a la FIFO TX (escritura a THR)
reg 										rf_pop;             //> pulso de pop de la FIFO RX (lectura de RBR)
wire [`UART_FIFO_REC_WIDTH-1:0] 	rf_data_out;                //> cima de la FIFO RX: {dato[10:3], break, paridad, trama}
wire 										rf_error_bit; // an error (parity or framing) is inside the fifo  //> hay algún error dentro de la FIFO RX
wire [`UART_FIFO_COUNTER_W-1:0] 	rf_count;                   //> ocupación FIFO RX
wire [`UART_FIFO_COUNTER_W-1:0] 	tf_count;                   //> ocupación FIFO TX
wire [2:0] 								tstate;                 //> estado FSM TX
wire [3:0] 								rstate;                 //> estado FSM RX
wire [9:0] 								counter_t;              //> contador de timeout del receptor

wire                      thre_set_en; // THRE status is delayed one character time when a character is written to fifo.  //> THRE se puede activar (pasó el retardo de un carácter)
reg  [7:0]                block_cnt;   // While counter counts, THRE status is blocked (delayed one character cycle)  //> contador del retardo de THRE
reg  [7:0]                block_value; // One character length minus stop bit  //> duración del retardo (un carácter menos 1 bit)

//==============================================================
//== Instancia del transmisor
//==============================================================
// Transmitter Instance
wire serial_out;                                                //> salida serie del TX, antes del loopback

uart_transmitter transmitter(clk, wb_rst_i, lcr, tf_push, wb_dat_i, enable, serial_out, tstate, tf_count, tx_reset, lsr_mask);  //> uart_transmitter: LCR, push, byte, enable -> salida serie, estado y ocupación

  //==============================================================
  //== Sincronizador de la entrada serie (evita metaestabilidad; agrega 2 ciclos)
  //==============================================================
  // Synchronizing and sampling serial RX input
  uart_sync_flops    i_uart_sync_flops                          //> instancia del sincronizador
  (                                                             //> inicio de la lista de conexiones
    .rst_i           (wb_rst_i),                                //> reset
    .clk_i           (clk),                                     //> reloj
    .stage1_rst_i    (1'b0),                                    //> reset síncrono de la 2.a etapa: no se usa
    .stage1_clk_en_i (1'b1),                                    //> habilitación de la 2.a etapa: siempre activa
    .async_dat_i     (srx_pad_i),                               //> entrada asíncrona
    .sync_dat_o      (srx_pad)                                  //> salida sincronizada
  );                                                            //> fin de la instancia
  defparam i_uart_sync_flops.width      = 1;                    //> 1 bit de ancho
  defparam i_uart_sync_flops.init_value = 1'b1;                 //> valor inicial 1 (línea en reposo)

//==============================================================
//== Loopback
//==============================================================
// handle loopback
wire serial_in = loopback ? serial_out : srx_pad;               //> en loopback el RX recibe la salida del TX
assign stx_pad_o = loopback ? 1'b1 : serial_out;                //> en loopback stx_pad_o queda fija en 1

//==============================================================
//== Instancia del receptor
//==============================================================
// Receiver Instance
uart_receiver receiver(clk, wb_rst_i, lcr, rf_pop, serial_in, enable,   //> uart_receiver: LCR, pop, entrada serie, enable...
	counter_t, rf_count, rf_data_out, rf_error_bit, rf_overrun, rx_reset, lsr_mask, rstate, rf_push_pulse);  //> ...-> timeout, FIFO RX, errores, overrun, estado y pulso de push


//==============================================================
//== Mux de lectura (combinacional): es la tabla que debe reproducir el RAL
//== Falta la dir. 4 (MCR): se lee 0. Debug (8 y 12) sale por uart_debug_if.
//==============================================================
// Asynchronous reading here because the outputs are sampled in uart_wb.v file 
always @(dl or dlab or ier or iir or scratch                    //> se recalcula si cambia cualquiera de estas señales...
			or lcr or lsr or msr or rf_data_out or wb_addr_i or wb_re_i)   // asynchrounous reading  //> ...(lista de sensibilidad)
begin                                                           //> inicio del bloque
	case (wb_addr_i)                                            //> según la dirección interna:
		`UART_REG_RB   : wb_dat_o = dlab ? dl[`UART_DL1] : rf_data_out[10:3];  //> dir. 0: DLL si DLAB=1; si no, el dato de la cima de la FIFO RX
		`UART_REG_IE	: wb_dat_o = dlab ? dl[`UART_DL2] : ier;  //> dir. 1: DLM si DLAB=1; si no, IER
		`UART_REG_II	: wb_dat_o = {4'b1100,iir};             //> dir. 2: IIR completado con 1100 (igual con cualquier DLAB)
		`UART_REG_LC	: wb_dat_o = lcr;                       //> dir. 3: LCR
		`UART_REG_LS	: wb_dat_o = lsr;                       //> dir. 5: LSR
		`UART_REG_MS	: wb_dat_o = msr;                       //> dir. 6: MSR
		`UART_REG_SR	: wb_dat_o = scratch;                   //> dir. 7: scratch
		default:  wb_dat_o = 8'b0; // ??                        //> otra (4 = MCR, 8..31): 0
	endcase // case(wb_addr_i)                                  //> fin del case
end // always @ (dl or dlab or ier or iir or scratch...         //> fin del bloque


//==============================================================
//== rf_pop: pulso de 1 ciclo para sacar un dato de la FIFO RX al leer RBR
//==============================================================
// rf_pop signal handling
always @(posedge clk or posedge wb_rst_i)                       //> registro síncrono con reset asíncrono
begin                                                           //> inicio del bloque
	if (wb_rst_i)                                               //> en reset...
		rf_pop <= #1 0;                                         //> ...no hay pop
	else                                                        //> fuera de reset:
	if (rf_pop)	// restore the signal to 0 after one clock cycle  //> si ya estaba en 1...
		rf_pop <= #1 0;                                         //> ...lo baja (dura un solo ciclo)
	else                                                        //> si no:
	if (wb_re_i && wb_addr_i == `UART_REG_RB && !dlab)          //> ¿lectura de RBR con DLAB=0?
		rf_pop <= #1 1; // advance read pointer                 //> pide sacar el dato (se entrega primero, el puntero avanza después)
end                                                             //> fin del bloque

//==============================================================
//== Detectores de accesos con efectos laterales (todos exigen DLAB=0)
//== Con DLAB=1, leer LSR, IIR o MSR no limpia nada
//==============================================================
wire 	lsr_mask_condition;                                     //> lectura de LSR
wire 	iir_read;                                               //> lectura de IIR
wire  msr_read;                                                 //> lectura de MSR
wire	fifo_read;                                              //> lectura de RBR
wire	fifo_write;                                             //> escritura de THR

assign lsr_mask_condition = (wb_re_i && wb_addr_i == `UART_REG_LS && !dlab);  //> = pulso de lectura en dir. 5 con DLAB=0
assign iir_read = (wb_re_i && wb_addr_i == `UART_REG_II && !dlab);  //> = pulso de lectura en dir. 2 con DLAB=0
assign msr_read = (wb_re_i && wb_addr_i == `UART_REG_MS && !dlab);  //> = pulso de lectura en dir. 6 con DLAB=0
assign fifo_read = (wb_re_i && wb_addr_i == `UART_REG_RB && !dlab);  //> = pulso de lectura en dir. 0 con DLAB=0
assign fifo_write = (wb_we_i && wb_addr_i == `UART_REG_TR && !dlab);  //> = pulso de escritura en dir. 0 con DLAB=0

//==============================================================
//== lsr_mask: flanco de subida de "se está leyendo LSR"
//==============================================================
// lsr_mask_d delayed signal handling
always @(posedge clk or posedge wb_rst_i)                       //> registro síncrono con reset asíncrono
begin                                                           //> inicio
	if (wb_rst_i)                                               //> en reset...
		lsr_mask_d <= #1 0;                                     //> ...en 0
	else // reset bits in the Line Status Register              //> si no:
		lsr_mask_d <= #1 lsr_mask_condition;                    //> guarda la condición del ciclo anterior
end                                                             //> fin

// lsr_mask is rise detected
assign lsr_mask = lsr_mask_condition && ~lsr_mask_d;            //> pulso = condición AND NOT(condición anterior)

//==============================================================
//== msi_reset: pulso que limpia los deltas MSR[3:0]
//==============================================================
// msi_reset signal handling
always @(posedge clk or posedge wb_rst_i)                       //> registro síncrono con reset asíncrono
begin                                                           //> inicio
	if (wb_rst_i)                                               //> en reset...
		msi_reset <= #1 1;                                      //> ...en 1: los deltas arrancan limpios
	else                                                        //> si no:
	if (msi_reset)                                              //> si ya estaba en 1...
		msi_reset <= #1 0;                                      //> ...lo baja (1 ciclo)
	else                                                        //> si no:
	if (msr_read)                                               //> ¿se leyó MSR?
		msi_reset <= #1 1; // reset bits in Modem Status Register  //> limpia los deltas en el ciclo siguiente
end                                                             //> fin


//
//   WRITES AND RESETS   //
//
//==============================================================
//== LCR: registro de control de línea (dir. 3); se escribe con cualquier DLAB
//==============================================================
// Line Control Register
always @(posedge clk or posedge wb_rst_i)                       //> se actualiza en flanco de reloj o reset asíncrono
	if (wb_rst_i)                                               //> si hay reset...
		lcr <= #1 8'b00000011; // 8n1 setting                   //> ...LCR = 0x03: 8 bits, sin paridad, 1 stop
	else                                                        //> si no hay reset:
	if (wb_we_i && wb_addr_i==`UART_REG_LC)                     //> ¿pulso de escritura en la dirección 3?
		lcr <= #1 wb_dat_i;                                     //> guarda el byte completo en LCR

//==============================================================
//== IER o DLM (dir. 1): el destino lo decide DLAB
//==============================================================
// Interrupt Enable Register or UART_DL2
always @(posedge clk or posedge wb_rst_i)                       //> se actualiza en flanco de reloj o reset
	if (wb_rst_i)                                               //> en reset:
	begin                                                       //> inicio
		ier <= #1 4'b0000; // no interrupts after reset         //> IER = 0: sin interrupciones
		dl[`UART_DL2] <= #1 8'b0;                               //> DLM = 0
	end                                                         //> fin
	else                                                        //> si no:
	if (wb_we_i && wb_addr_i==`UART_REG_IE)                     //> ¿escritura en dir. 1?
		if (dlab)                                               //> con DLAB=1:
		begin                                                   //> inicio
			dl[`UART_DL2] <= #1 wb_dat_i;                       //> escribe DLM
		end                                                     //> fin
		else                                                    //> con DLAB=0:
			ier <= #1 wb_dat_i[3:0]; // ier uses only 4 lsb     //> escribe IER, solo los 4 bits bajos


//==============================================================
//== FCR (dir. 2, escritura) y pulsos de limpieza de FIFOs
//==============================================================
// FIFO Control Register and rx_reset, tx_reset signals
always @(posedge clk or posedge wb_rst_i)                       //> se actualiza en flanco de reloj o reset
	if (wb_rst_i) begin                                         //> en reset:
		fcr <= #1 2'b11;                                        //> nivel de disparo 14 (FCR = 0xC0)
		rx_reset <= #1 0;                                       //> sin limpieza de RX
		tx_reset <= #1 0;                                       //> sin limpieza de TX
	end else                                                    //> si no:
	if (wb_we_i && wb_addr_i==`UART_REG_FC) begin               //> ¿escritura en dir. 2 (con cualquier DLAB)?
		fcr <= #1 wb_dat_i[7:6];                                //> guarda el nivel de disparo (FCR[7:6])
		rx_reset <= #1 wb_dat_i[1];                             //> FCR[1]=1 -> limpia la FIFO RX
		tx_reset <= #1 wb_dat_i[2];                             //> FCR[2]=1 -> limpia la FIFO TX
	end else begin                                              //> sin escritura:
		rx_reset <= #1 0;                                       //> baja el pulso de RX (dura 1 ciclo)
		tx_reset <= #1 0;                                       //> baja el pulso de TX
	end                                                         //> fin

//==============================================================
//== MCR (dir. 4): solo escritura; se guardan los bits 4:0
//==============================================================
// Modem Control Register
always @(posedge clk or posedge wb_rst_i)                       //> se actualiza en flanco de reloj o reset
	if (wb_rst_i)                                               //> en reset...
		mcr <= #1 5'b0;                                         //> ...MCR = 0
	else                                                        //> si no:
	if (wb_we_i && wb_addr_i==`UART_REG_MC)                     //> ¿escritura en dir. 4 (con cualquier DLAB)?
			mcr <= #1 wb_dat_i[4:0];                            //> guarda los 5 bits bajos

//==============================================================
//== Scratch (dir. 7): 8 bits RW, sin efecto en el hardware
//==============================================================
// Scratch register
// Line Control Register                                        //> (comentario copiado por error del bloque de LCR)
always @(posedge clk or posedge wb_rst_i)                       //> se actualiza en flanco de reloj o reset
	if (wb_rst_i)                                               //> en reset...
		scratch <= #1 0; // 8n1 setting                         //> ...scratch = 0 (el comentario "8n1" también está copiado por error)
	else                                                        //> si no:
	if (wb_we_i && wb_addr_i==`UART_REG_SR)                     //> ¿escritura en dir. 7?
		scratch <= #1 wb_dat_i;                                 //> guarda el byte

//==============================================================
//== THR o DLL (dir. 0, escritura)
//==============================================================
// TX_FIFO or UART_DL1
always @(posedge clk or posedge wb_rst_i)                       //> se actualiza en flanco de reloj o reset
	if (wb_rst_i)                                               //> en reset:
	begin                                                       //> inicio
		dl[`UART_DL1]  <= #1 8'b0;                              //> DLL = 0 (con DL = 0 no hay transmisión ni recepción)
		tf_push   <= #1 1'b0;                                   //> sin push
		start_dlc <= #1 1'b0;                                   //> sin reinicio del divisor
	end                                                         //> fin
	else                                                        //> si no:
	if (wb_we_i && wb_addr_i==`UART_REG_TR)                     //> ¿escritura en dir. 0?
		if (dlab)                                               //> con DLAB=1:
		begin                                                   //> inicio
			dl[`UART_DL1] <= #1 wb_dat_i;                       //> guarda DLL
			start_dlc <= #1 1'b1; // enable DL counter          //> reinicia el contador del divisor (por eso DLM se escribe primero)
			tf_push <= #1 1'b0;                                 //> no mete nada a la FIFO TX
		end                                                     //> fin
		else                                                    //> con DLAB=0:
		begin                                                   //> inicio
			tf_push   <= #1 1'b1;                               //> pulso de push: el byte entra a la FIFO TX
			start_dlc <= #1 1'b0;                               //> no toca el divisor
		end // else: !if(dlab)                                  //> fin
	else                                                        //> sin escritura en dir. 0:
	begin                                                       //> inicio
		start_dlc <= #1 1'b0;                                   //> baja el pulso del divisor
		tf_push   <= #1 1'b0;                                   //> baja el pulso de push
	end // else: !if(dlab)                                      //> fin

//==============================================================
//== Decodificador del nivel de disparo (mux combinacional)
//==============================================================
// Receiver FIFO trigger level selection logic (asynchronous mux)
always @(fcr)                                                   //> se recalcula si cambia fcr
	case (fcr[`UART_FC_TL])                                     //> según fcr[1:0]:
		2'b00 : trigger_level = 1;                              //> 00 -> 1 byte
		2'b01 : trigger_level = 4;                              //> 01 -> 4 bytes
		2'b10 : trigger_level = 8;                              //> 10 -> 8 bytes
		2'b11 : trigger_level = 14;                             //> 11 -> 14 bytes
	endcase // case(fcr[`UART_FC_TL])                           //> fin del case
	
//
//  STATUS REGISTERS  //
//

//==============================================================
//== MSR: deltas [3:0] y estado [7:4]
//==============================================================
// Modem Status Register
reg [3:0] delayed_modem_signals;                                //> valor de las líneas (invertidas) en el ciclo anterior
always @(posedge clk or posedge wb_rst_i)                       //> se actualiza en flanco de reloj o reset
begin                                                           //> inicio
	if (wb_rst_i)                                               //> en reset:
	  begin                                                     //> inicio
  		msr <= #1 0;                                            //> MSR = 0
	  	delayed_modem_signals[3:0] <= #1 0;                     //> historial en 0
	  end                                                       //> fin
	else begin                                                  //> si no:
		msr[`UART_MS_DDCD:`UART_MS_DCTS] <= #1 msi_reset ? 4'b0 :  //> deltas: se limpian con msi_reset; si no...
			msr[`UART_MS_DDCD:`UART_MS_DCTS] | ({dcd, ri, dsr, cts} ^ delayed_modem_signals[3:0]);  //> ...acumulan (OR) los cambios; XOR = detecta AMBOS flancos (TERI: AMB-05; loopback: AMB-09)
		msr[`UART_MS_CDCD:`UART_MS_CCTS] <= #1 {dcd_c, ri_c, dsr_c, cts_c};  //> estado actual de las líneas (pads o MCR en loopback)
		delayed_modem_signals[3:0] <= #1 {dcd, ri, dsr, cts};   //> guarda el valor actual para el ciclo siguiente
	end                                                         //> fin
end                                                             //> fin


//==============================================================
//== LSR: condiciones de activación de cada bit
//== Cada bit: condición lsrN -> retardo lsrN_d -> registro lsrNr (se pone en el flanco)
//==============================================================
// Line Status Register

// activation conditions
assign lsr0 = (rf_count==0 && rf_push_pulse);  // data in receiver fifo available set condition  //> DR: entra un dato con la FIFO RX vacía
assign lsr1 = rf_overrun;     // Receiver overrun error         //> OE: overrun (viene de la FIFO RX)
assign lsr2 = rf_data_out[1]; // parity error bit               //> PE: paridad del carácter de la cima
assign lsr3 = rf_data_out[0]; // framing error bit              //> FE: trama del carácter de la cima
assign lsr4 = rf_data_out[2]; // break error in the character   //> BI: break del carácter de la cima
assign lsr5 = (tf_count==5'b0 && thre_set_en);  // transmitter fifo is empty  //> THRE: FIFO TX vacía y pasó el retardo de un carácter
assign lsr6 = (tf_count==5'b0 && thre_set_en && (tstate == /*`S_IDLE */ 0)); // transmitter empty  //> TEMT: además, el TX en reposo
assign lsr7 = rf_error_bit | rf_overrun;                        //> LSR[7]: algún error en la FIFO RX, u overrun

//==============================================================
//== LSR[0] DR: dato disponible
//==============================================================
// lsr bit0 (receiver data available)
reg 	 lsr0_d;                                                //> retardo de lsr0

always @(posedge clk or posedge wb_rst_i)                       //> registro con reset
	if (wb_rst_i) lsr0_d <= #1 0;                               //> en reset 0; si no...
	else lsr0_d <= #1 lsr0;                                     //> ...copia lsr0

always @(posedge clk or posedge wb_rst_i)                       //> registro con reset
	if (wb_rst_i) lsr0r <= #1 0;                                //> en reset 0; si no:
	else lsr0r <= #1 (rf_count==1 && rf_pop && !rf_push_pulse || rx_reset) ? 0 : // deassert condition  //> se limpia al sacar el último dato o con FCR[1]...
					  lsr0r || (lsr0 && ~lsr0_d); // set on rise of lsr0 and keep asserted until deasserted   //> ...se pone en el flanco de lsr0 y se mantiene

//==============================================================
//== LSR[1] OE: overrun
//==============================================================
// lsr bit 1 (receiver overrun)
reg lsr1_d; // delayed                                          //> retardo de lsr1

always @(posedge clk or posedge wb_rst_i)                       //> registro con reset
	if (wb_rst_i) lsr1_d <= #1 0;                               //> en reset 0; si no...
	else lsr1_d <= #1 lsr1;                                     //> ...copia lsr1

always @(posedge clk or posedge wb_rst_i)                       //> registro con reset
	if (wb_rst_i) lsr1r <= #1 0;                                //> en reset 0; si no...
	else	lsr1r <= #1	lsr_mask ? 0 : lsr1r || (lsr1 && ~lsr1_d); // set on rise  //> ...se limpia al leer LSR; se pone en el flanco de overrun

//==============================================================
//== LSR[2] PE: error de paridad
//==============================================================
// lsr bit 2 (parity error)
reg lsr2_d; // delayed                                          //> retardo de lsr2

always @(posedge clk or posedge wb_rst_i)                       //> registro con reset
	if (wb_rst_i) lsr2_d <= #1 0;                               //> en reset 0; si no...
	else lsr2_d <= #1 lsr2;                                     //> ...copia lsr2

always @(posedge clk or posedge wb_rst_i)                       //> registro con reset
	if (wb_rst_i) lsr2r <= #1 0;                                //> en reset 0; si no...
	else lsr2r <= #1 lsr_mask ? 0 : lsr2r || (lsr2 && ~lsr2_d); // set on rise  //> ...se limpia al leer LSR; se pone cuando el carácter con error llega a la cima

//==============================================================
//== LSR[3] FE: error de trama
//==============================================================
// lsr bit 3 (framing error)
reg lsr3_d; // delayed                                          //> retardo de lsr3

always @(posedge clk or posedge wb_rst_i)                       //> registro con reset
	if (wb_rst_i) lsr3_d <= #1 0;                               //> en reset 0; si no...
	else lsr3_d <= #1 lsr3;                                     //> ...copia lsr3

always @(posedge clk or posedge wb_rst_i)                       //> registro con reset
	if (wb_rst_i) lsr3r <= #1 0;                                //> en reset 0; si no...
	else lsr3r <= #1 lsr_mask ? 0 : lsr3r || (lsr3 && ~lsr3_d); // set on rise  //> ...se limpia al leer LSR; se pone en el flanco

//==============================================================
//== LSR[4] BI: break
//==============================================================
// lsr bit 4 (break indicator)
reg lsr4_d; // delayed                                          //> retardo de lsr4

always @(posedge clk or posedge wb_rst_i)                       //> registro con reset
	if (wb_rst_i) lsr4_d <= #1 0;                               //> en reset 0; si no...
	else lsr4_d <= #1 lsr4;                                     //> ...copia lsr4

always @(posedge clk or posedge wb_rst_i)                       //> registro con reset
	if (wb_rst_i) lsr4r <= #1 0;                                //> en reset 0; si no...
	else lsr4r <= #1 lsr_mask ? 0 : lsr4r || (lsr4 && ~lsr4_d);  //> ...se limpia al leer LSR; se pone en el flanco

//==============================================================
//== LSR[5] THRE: FIFO TX vacía
//==============================================================
// lsr bit 5 (transmitter fifo is empty)
reg lsr5_d;                                                     //> retardo de lsr5

always @(posedge clk or posedge wb_rst_i)                       //> registro con reset
	if (wb_rst_i) lsr5_d <= #1 1;                               //> en reset 1 (la FIFO arranca vacía); si no...
	else lsr5_d <= #1 lsr5;                                     //> ...copia lsr5

always @(posedge clk or posedge wb_rst_i)                       //> registro con reset
	if (wb_rst_i) lsr5r <= #1 1;                                //> en reset 1; si no...
	else lsr5r <= #1 (fifo_write) ? 0 :  lsr5r || (lsr5 && ~lsr5_d);  //> ...se limpia al escribir THR; se pone en el flanco (leer LSR no lo limpia)

//==============================================================
//== LSR[6] TEMT: transmisor vacío
//==============================================================
// lsr bit 6 (transmitter empty indicator)
reg lsr6_d;                                                     //> retardo de lsr6

always @(posedge clk or posedge wb_rst_i)                       //> registro con reset
	if (wb_rst_i) lsr6_d <= #1 1;                               //> en reset 1; si no...
	else lsr6_d <= #1 lsr6;                                     //> ...copia lsr6

always @(posedge clk or posedge wb_rst_i)                       //> registro con reset
	if (wb_rst_i) lsr6r <= #1 1;                                //> en reset 1; si no...
	else lsr6r <= #1 (fifo_write) ? 0 : lsr6r || (lsr6 && ~lsr6_d);  //> ...se limpia al escribir THR; se pone cuando todo el TX queda vacío

//==============================================================
//== LSR[7]: error en la FIFO RX
//==============================================================
// lsr bit 7 (error in fifo)
reg lsr7_d;                                                     //> retardo de lsr7

always @(posedge clk or posedge wb_rst_i)                       //> registro con reset
	if (wb_rst_i) lsr7_d <= #1 0;                               //> en reset 0; si no...
	else lsr7_d <= #1 lsr7;                                     //> ...copia lsr7

always @(posedge clk or posedge wb_rst_i)                       //> registro con reset
	if (wb_rst_i) lsr7r <= #1 0;                                //> en reset 0; si no...
	else lsr7r <= #1 lsr_mask ? 0 : lsr7r || (lsr7 && ~lsr7_d);  //> ...se limpia al leer LSR; se pone en el flanco (OJO: si quedan errores, ¿vuelve a 1? a verificar)

//==============================================================
//== Divisor de frecuencia: cuenta DL ciclos
//==============================================================
// Frequency divider
always @(posedge clk or posedge wb_rst_i)                       //> se actualiza en flanco de reloj o reset
begin                                                           //> inicio
	if (wb_rst_i)                                               //> en reset...
		dlc <= #1 0;                                            //> ...contador en 0
	else                                                        //> si no:
		if (start_dlc | ~ (|dlc))                               //> si se acaba de escribir DLL o el contador llegó a 0...
  			dlc <= #1 dl - 1;               // preset counter   //> ...recarga con DL-1
		else                                                    //> si no...
			dlc <= #1 dlc - 1;              // decrement counter  //> ...decrementa
end                                                             //> fin

//==============================================================
//== enable: 1 pulso cada DL ciclos (16 por bit -> bit = 16 x DL ciclos)
//==============================================================
// Enable signal generation logic
always @(posedge clk or posedge wb_rst_i)                       //> se actualiza en flanco de reloj o reset
begin                                                           //> inicio
	if (wb_rst_i)                                               //> en reset...
		enable <= #1 1'b0;                                      //> ...sin enable
	else                                                        //> si no:
		if (|dl & ~(|dlc))     // dl>0 & dlc==0                 //> DL != 0 y contador = 0...
			enable <= #1 1'b1;                                  //> ...pulso de enable
		else                                                    //> si no (incluye DL = 0: nunca hay enable)...
			enable <= #1 1'b0;                                  //> ...enable = 0
end                                                             //> fin

//==============================================================
//== Retardo de THRE: duración de un carácter menos 1 bit, en pulsos de enable
//== Índice LCR[3:0] = {PEN, STB, WLS}; valor = 16 x (bits totales - 1) - 1
//==============================================================
// Delaying THRE status for one character cycle after a character is written to an empty fifo.
always @(lcr)                                                   //> se recalcula si cambia LCR
  case (lcr[3:0])                                               //> según {PEN, STB, WLS}:
    4'b0000                             : block_value =  95; // 6 bits  //> 5N1 (7 bits en total)
    4'b0100                             : block_value = 103; // 6.5 bits  //> 5 bits, 1.5 stops
    4'b0001, 4'b1000                    : block_value = 111; // 7 bits  //> 6N1 o 5 bits + paridad
    4'b1100                             : block_value = 119; // 7.5 bits  //> 5 bits + paridad + 1.5 stops
    4'b0010, 4'b0101, 4'b1001           : block_value = 127; // 8 bits  //> 7N1, 6 bits + 2 stops, 6 bits + paridad
    4'b0011, 4'b0110, 4'b1010, 4'b1101  : block_value = 143; // 9 bits  //> 8N1, 7N2, 7 bits + paridad, 6 bits + paridad + 2 stops
    4'b0111, 4'b1011, 4'b1110           : block_value = 159; // 10 bits  //> 8N2, 8 bits + paridad, 7 bits + paridad + 2 stops
    4'b1111                             : block_value = 175; // 11 bits  //> 8 bits + paridad + 2 stops (12 bits, el más largo)
  endcase // case(lcr[3:0])                                     //> fin del case

//==============================================================
//== Contador del retardo de THRE
//==============================================================
// Counting time of one character minus stop bit
always @(posedge clk or posedge wb_rst_i)                       //> se actualiza en flanco de reloj o reset
begin                                                           //> inicio
  if (wb_rst_i)                                                 //> en reset...
    block_cnt <= #1 8'd0;                                       //> ...sin bloqueo
  else                                                          //> si no:
  if(lsr5r & fifo_write)  // THRE bit set & write to fifo occured  //> THRE estaba en 1 y se escribe THR...
    block_cnt <= #1 block_value;                                //> ...carga el tiempo de un carácter
  else                                                          //> si no:
  if (enable & block_cnt != 8'b0)  // only work on enable times  //> con enable y contador != 0...
    block_cnt <= #1 block_cnt - 1;  // decrement break counter  //> ...decrementa
end // always of break condition detection                      //> fin

// Generating THRE status enable signal
assign thre_set_en = ~(|block_cnt);                             //> THRE puede activarse solo con el contador en 0


//==============================================================
//== Lógica de interrupciones
//== Condición (nivel) -> flanco -> pending -> int_o / IIR
//==============================================================
//
//	INTERRUPT LOGIC
//

assign rls_int  = ier[`UART_IE_RLS] && (lsr[`UART_LS_OE] || lsr[`UART_LS_PE] || lsr[`UART_LS_FE] || lsr[`UART_LS_BI]);  //> RLS: habilitada y algún error en LSR
assign rda_int  = ier[`UART_IE_RDA] && (rf_count >= {1'b0,trigger_level});  //> RDA: habilitada y ocupación RX >= nivel de disparo
assign thre_int = ier[`UART_IE_THRE] && lsr[`UART_LS_TFE];      //> THRE: habilitada y LSR[5] = 1
assign ms_int   = ier[`UART_IE_MS] && (| msr[3:0]);             //> MS: habilitada y algún delta en MSR
assign ti_int   = ier[`UART_IE_RDA] && (counter_t == 10'b0) && (|rf_count);  //> timeout: usa IER[0] (igual que RDA), contador en 0 y FIFO RX no vacía

//==============================================================
//== Retardos de 1 ciclo de cada condición
//==============================================================
reg 	 rls_int_d;                                             //> RLS anterior
reg 	 thre_int_d;                                            //> THRE anterior
reg 	 ms_int_d;                                              //> MS anterior
reg 	 ti_int_d;                                              //> timeout anterior
reg 	 rda_int_d;                                             //> RDA anterior

// delay lines
always  @(posedge clk or posedge wb_rst_i)                      //> registro con reset
	if (wb_rst_i) rls_int_d <= #1 0;                            //> en reset 0...
	else rls_int_d <= #1 rls_int;                               //> ...si no, copia RLS

always  @(posedge clk or posedge wb_rst_i)                      //> registro con reset
	if (wb_rst_i) rda_int_d <= #1 0;                            //> en reset 0...
	else rda_int_d <= #1 rda_int;                               //> ...si no, copia RDA

always  @(posedge clk or posedge wb_rst_i)                      //> registro con reset
	if (wb_rst_i) thre_int_d <= #1 0;                           //> en reset 0...
	else thre_int_d <= #1 thre_int;                             //> ...si no, copia THRE

always  @(posedge clk or posedge wb_rst_i)                      //> registro con reset
	if (wb_rst_i) ms_int_d <= #1 0;                             //> en reset 0...
	else ms_int_d <= #1 ms_int;                                 //> ...si no, copia MS

always  @(posedge clk or posedge wb_rst_i)                      //> registro con reset
	if (wb_rst_i) ti_int_d <= #1 0;                             //> en reset 0...
	else ti_int_d <= #1 ti_int;                                 //> ...si no, copia timeout

//==============================================================
//== Flancos de subida de cada condición
//==============================================================
// rise detection signals

wire 	 rls_int_rise;                                          //> flanco RLS
wire 	 thre_int_rise;                                         //> flanco THRE
wire 	 ms_int_rise;                                           //> flanco MS
wire 	 ti_int_rise;                                           //> flanco timeout
wire 	 rda_int_rise;                                          //> flanco RDA

assign rda_int_rise    = rda_int & ~rda_int_d;                  //> RDA ahora y no antes
assign rls_int_rise 	  = rls_int & ~rls_int_d;               //> RLS ahora y no antes
assign thre_int_rise   = thre_int & ~thre_int_d;                //> THRE ahora y no antes
assign ms_int_rise 	  = ms_int & ~ms_int_d;                     //> MS ahora y no antes
assign ti_int_rise 	  = ti_int & ~ti_int_d;                     //> timeout ahora y no antes

//==============================================================
//== Banderas pending: limpieza ? 0 : flanco ? 1 : se mantiene si sigue habilitada
//==============================================================
// interrupt pending flags
reg 	rls_int_pnd;                                            //> RLS pendiente
reg	rda_int_pnd;                                                //> RDA pendiente
reg 	thre_int_pnd;                                           //> THRE pendiente
reg 	ms_int_pnd;                                             //> MS pendiente
reg 	ti_int_pnd;                                             //> timeout pendiente

// interrupt pending flags assignments
always  @(posedge clk or posedge wb_rst_i)                      //> registro con reset
	if (wb_rst_i) rls_int_pnd <= #1 0;                          //> en reset 0
	else                                                        //> si no:
		rls_int_pnd <= #1 lsr_mask ? 0 :  						// reset condition  //> leer LSR la limpia...
							rls_int_rise ? 1 :						// latch condition  //> ...el flanco la pone...
							rls_int_pnd && ier[`UART_IE_RLS];	// default operation: remove if masked  //> ...y se mantiene mientras IER[2] = 1

always  @(posedge clk or posedge wb_rst_i)                      //> registro con reset
	if (wb_rst_i) rda_int_pnd <= #1 0;                          //> en reset 0
	else                                                        //> si no:
		rda_int_pnd <= #1 ((rf_count == {1'b0,trigger_level}) && fifo_read) ? 0 :  	// reset condition  //> leer RBR cuando ocupación = nivel de disparo la limpia...
							rda_int_rise ? 1 :						// latch condition  //> ...el flanco la pone...
							rda_int_pnd && ier[`UART_IE_RDA];	// default operation: remove if masked  //> ...y se mantiene mientras IER[0] = 1

always  @(posedge clk or posedge wb_rst_i)                      //> registro con reset
	if (wb_rst_i) thre_int_pnd <= #1 0;                         //> en reset 0
	else                                                        //> si no:
		thre_int_pnd <= #1 fifo_write || (iir_read & ~iir[`UART_II_IP] & iir[`UART_II_II] == `UART_II_THRE)? 0 :   //> escribir THR, o leer IIR cuando muestra THRE, la limpia...
							thre_int_rise ? 1 :                 //> ...el flanco la pone...
							thre_int_pnd && ier[`UART_IE_THRE];  //> ...y se mantiene mientras IER[1] = 1

always  @(posedge clk or posedge wb_rst_i)                      //> registro con reset
	if (wb_rst_i) ms_int_pnd <= #1 0;                           //> en reset 0
	else                                                        //> si no:
		ms_int_pnd <= #1 msr_read ? 0 :                         //> leer MSR la limpia...
							ms_int_rise ? 1 :                   //> ...el flanco la pone...
							ms_int_pnd && ier[`UART_IE_MS];     //> ...y se mantiene mientras IER[3] = 1

always  @(posedge clk or posedge wb_rst_i)                      //> registro con reset
	if (wb_rst_i) ti_int_pnd <= #1 0;                           //> en reset 0
	else                                                        //> si no:
		ti_int_pnd <= #1 fifo_read ? 0 :                        //> leer RBR la limpia...
							ti_int_rise ? 1 :                   //> ...el flanco la pone...
							ti_int_pnd && ier[`UART_IE_RDA];    //> ...y se mantiene mientras IER[0] = 1
// end of pending flags

//==============================================================
//== int_o: 1 si hay alguna pending; baja en el mismo ciclo del acceso que la limpia
//==============================================================
// INT_O logic
always @(posedge clk or posedge wb_rst_i)                       //> registro con reset
begin                                                           //> inicio
	if (wb_rst_i)	                                            //> en reset...
		int_o <= #1 1'b0;                                       //> ...sin interrupción
	else                                                        //> si no:
		int_o <= #1                                             //> int_o =
					rls_int_pnd		?	~lsr_mask					:  //> RLS pendiente: 1, salvo mientras se lee LSR
					rda_int_pnd		? 1								:  //> RDA pendiente: 1
					ti_int_pnd		? ~fifo_read					:  //> timeout pendiente: 1, salvo mientras se lee RBR
					thre_int_pnd	? !(fifo_write & iir_read) :  //> THRE pendiente: 1 (fifo_write e iir_read nunca coinciden)
					ms_int_pnd		? ~msr_read						:  //> MS pendiente: 1, salvo mientras se lee MSR
					0;	// if no interrupt are pending          //> sin pending: 0
end                                                             //> fin


//==============================================================
//== IIR: código de la interrupción de mayor prioridad
//== Prioridad: RLS > RDA > timeout > THRE > MS
//==============================================================
// Interrupt Identification register
always @(posedge clk or posedge wb_rst_i)                       //> registro con reset
begin                                                           //> inicio
	if (wb_rst_i)                                               //> en reset...
		iir <= #1 1;                                            //> ...iir = 0001 (se lee 0xC1: nada pendiente)
	else                                                        //> si no:
	if (rls_int_pnd)  // interrupt is pending                   //> 1.o: RLS pendiente
	begin                                                       //> inicio
		iir[`UART_II_II] <= #1 `UART_II_RLS;	// set identification register to correct value  //> código 011
		iir[`UART_II_IP] <= #1 1'b0;		// and clear the IIR bit 0 (interrupt pending)  //> IIR[0] = 0: hay interrupción
	end else // the sequence of conditions determines priority of interrupt identification  //> fin; si no:
	if (rda_int)                                                //> 2.o: RDA (usa la condición de nivel, no la pending)
	begin                                                       //> inicio
		iir[`UART_II_II] <= #1 `UART_II_RDA;                    //> código 010
		iir[`UART_II_IP] <= #1 1'b0;                            //> hay interrupción
	end                                                         //> fin
	else if (ti_int_pnd)                                        //> 2.o: timeout pendiente
	begin                                                       //> inicio
		iir[`UART_II_II] <= #1 `UART_II_TI;                     //> código 110 (IIR[3:0] = 4'hC)
		iir[`UART_II_IP] <= #1 1'b0;                            //> hay interrupción
	end                                                         //> fin
	else if (thre_int_pnd)                                      //> 3.o: THRE pendiente
	begin                                                       //> inicio
		iir[`UART_II_II] <= #1 `UART_II_THRE;                   //> código 001
		iir[`UART_II_IP] <= #1 1'b0;                            //> hay interrupción
	end                                                         //> fin
	else if (ms_int_pnd)                                        //> 4.o: MS pendiente
	begin                                                       //> inicio
		iir[`UART_II_II] <= #1 `UART_II_MS;                     //> código 000
		iir[`UART_II_IP] <= #1 1'b0;                            //> hay interrupción
	end else	// no interrupt is pending                      //> fin; si no hay nada:
	begin                                                       //> inicio
		iir[`UART_II_II] <= #1 0;                               //> código 000
		iir[`UART_II_IP] <= #1 1'b1;                            //> IIR[0] = 1: sin interrupción
	end                                                         //> fin
end                                                             //> fin

endmodule                                                       //> fin del módulo
