//==============================================================
//== ARCHIVO uart_defines.v (copia de estudio; el original está en rtl/)
//== Macros globales que incluyen todos los archivos del RTL. No tiene lógica:
//== anchos de bus, direcciones de registros y posiciones de bits. Es la base del RAL.
//== Líneas 1-130: licencia e historial.
//==============================================================
//////////////////////////////////////////////////////////////////////
////                                                              ////
////  uart_defines.v                                              ////
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
////  Defines of the Core                                         ////
////                                                              ////
////  Known problems (limits):                                    ////
////  None                                                        ////
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
// Revision 1.13  2003/06/11 16:37:47  gorban
// This fixes errors in some cases when data is being read and put to the FIFO at the same time. Patch is submitted by Scott Furman. Update is very recommended.
//
// Revision 1.12  2002/07/22 23:02:23  gorban
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
// Revision 1.10  2001/12/11 08:55:40  mohor
// Scratch register define added.
//
// Revision 1.9  2001/12/03 21:44:29  gorban
// Updated specification documentation.
// Added full 32-bit data bus interface, now as default.
// Address is 5-bit wide in 32-bit data bus mode.
// Added wb_sel_i input to the core. It's used in the 32-bit mode.
// Added debug interface with two 32-bit read-only registers in 32-bit mode.
// Bits 5 and 6 of LSR are now only cleared on TX FIFO write.
// My small test bench is modified to work with 32-bit mode.
//
// Revision 1.8  2001/11/26 21:38:54  gorban
// Lots of fixes:
// Break condition wasn't handled correctly at all.
// LSR bits could lose their values.
// LSR value after reset was wrong.
// Timing of THRE interrupt signal corrected.
// LSR bit 0 timing corrected.
//
// Revision 1.7  2001/08/24 21:01:12  mohor
// Things connected to parity changed.
// Clock devider changed.
//
// Revision 1.6  2001/08/23 16:05:05  mohor
// Stop bit bug fixed.
// Parity bug fixed.
// WISHBONE read cycle bug fixed,
// OE indicator (Overrun Error) bug fixed.
// PE indicator (Parity Error) bug fixed.
// Register read bug fixed.
//
// Revision 1.5  2001/05/31 20:08:01  gorban
// FIFO changes and other corrections.
//
// Revision 1.4  2001/05/21 19:12:02  gorban
// Corrected some Linter messages.
//
// Revision 1.3  2001/05/17 18:34:18  gorban
// First 'stable' release. Should be sythesizable now. Also added new header.
//
// Revision 1.0  2001-05-17 21:27:11+02  jacob
// Initial revision
//
//

// remove comments to restore to use the new version with 8 data bit interface
// in 32bit-bus mode, the wb_sel_i signal is used to put data in correct place
// also, in 8-bit version there'll be no debugging features included
// CAUTION: doesn't work with current version of OR1200
//==============================================================
//== Selección de ancho de bus (se hace con +define+DATA_BUS_WIDTH_8 en VCS, no editando aquí)
//==============================================================
//`define DATA_BUS_WIDTH_8                                      //> línea comentada: si se descomenta, bus de 8 bits

`ifdef DATA_BUS_WIDTH_8                                         //> ¿bus de 8 bits?
 `define UART_ADDR_WIDTH 3                                      //> dirección de 3 bits (registros 0..7)
 `define UART_DATA_WIDTH 8                                      //> dato de 8 bits
`else                                                           //> si no (modo obligatorio de 32 bits):
 `define UART_ADDR_WIDTH 5                                      //> dirección de 5 bits (0..31; permite Debug en 8 y 12)
 `define UART_DATA_WIDTH 32                                     //> dato de 32 bits (el byte útil lo elige wb_sel_i)
`endif                                                          //> fin del ifdef

// Uncomment this if you want your UART to have
// 16xBaudrate output port.
// If defined, the enable signal will be used to drive baudrate_o signal
// It's frequency is 16xbaudrate

//==============================================================
//== Salida opcional baud_o
//==============================================================
// `define UART_HAS_BAUDRATE_OUTPUT                             //> comentada: se activa con +define+UART_HAS_BAUDRATE_OUTPUT

//==============================================================
//== Direcciones de registros (índice de registro)
//== Varios comparten índice: los distingue lectura/escritura y DLAB = LCR[7]
//==============================================================
// Register addresses
`define UART_REG_RB	`UART_ADDR_WIDTH'd0	// receiver buffer      //> 0, lectura, DLAB=0: RBR (sale de la FIFO RX)
`define UART_REG_TR  `UART_ADDR_WIDTH'd0	// transmitter      //> 0, escritura, DLAB=0: THR (entra a la FIFO TX)
`define UART_REG_IE	`UART_ADDR_WIDTH'd1	// Interrupt enable     //> 1, DLAB=0: IER
`define UART_REG_II  `UART_ADDR_WIDTH'd2	// Interrupt identification  //> 2, lectura: IIR
`define UART_REG_FC  `UART_ADDR_WIDTH'd2	// FIFO control     //> 2, escritura: FCR
`define UART_REG_LC	`UART_ADDR_WIDTH'd3	// Line Control         //> 3: LCR (con cualquier DLAB)
`define UART_REG_MC	`UART_ADDR_WIDTH'd4	// Modem control        //> 4: MCR (se lee 0, no está en el mux de lectura; AMB-02)
`define UART_REG_LS  `UART_ADDR_WIDTH'd5	// Line status      //> 5: LSR, solo lectura
`define UART_REG_MS  `UART_ADDR_WIDTH'd6	// Modem status     //> 6: MSR, solo lectura
`define UART_REG_SR  `UART_ADDR_WIDTH'd7	// Scratch register  //> 7: scratch (existe en el RTL aunque la especificación diga que no; AMB-01)
`define UART_REG_DL1	`UART_ADDR_WIDTH'd0	// Divisor latch bytes (1-2)  //> 0, DLAB=1: DLL (byte bajo del divisor)
`define UART_REG_DL2	`UART_ADDR_WIDTH'd1                     //> 1, DLAB=1: DLM (byte alto del divisor)

//==============================================================
//== Bits de IER
//==============================================================
// Interrupt Enable register bits
`define UART_IE_RDA	0	// Received Data available interrupt    //> IER[0]: dato disponible (RDA) y timeout
`define UART_IE_THRE	1	// Transmitter Holding Register empty interrupt  //> IER[1]: FIFO TX vacía (THRE)
`define UART_IE_RLS	2	// Receiver Line Status Interrupt       //> IER[2]: errores de línea (RLS)
`define UART_IE_MS	3	// Modem Status Interrupt               //> IER[3]: estado de módem (MS)

//==============================================================
//== Campos de IIR
//==============================================================
// Interrupt Identification register bits
`define UART_II_IP	0	// Interrupt pending when 0             //> IIR[0]: 0 = hay interrupción pendiente
`define UART_II_II	3:1	// Interrupt identification             //> IIR[3:1]: código de la interrupción

//==============================================================
//== Códigos de IIR[3:1] (prioridad: RLS > RDA = TI > THRE > MS)
//==============================================================
// Interrupt identification values for bits 3:1
`define UART_II_RLS	3'b011	// Receiver Line Status             //> 011: errores de línea (prioridad 1)
`define UART_II_RDA	3'b010	// Receiver Data available          //> 010: dato disponible (prioridad 2)
`define UART_II_TI	3'b110	// Timeout Indication               //> 110: timeout (prioridad 2; IIR[3:0] = 4'hC)
`define UART_II_THRE	3'b001	// Transmitter Holding Register empty  //> 001: FIFO TX vacía (prioridad 3)
`define UART_II_MS	3'b000	// Modem Status                     //> 000: módem (prioridad 4)

//==============================================================
//== Campo de FCR (uart_regs guarda solo FCR[7:6] en un registro de 2 bits)
//==============================================================
// FIFO Control Register bits
`define UART_FC_TL	1:0	// Trigger level                        //> nivel de disparo en fcr[1:0] (= FCR[7:6] del registro real)

//==============================================================
//== Valores del nivel de disparo de la FIFO RX
//==============================================================
// FIFO trigger level values
`define UART_FC_1		2'b00                                   //> 00 -> 1 byte
`define UART_FC_4		2'b01                                   //> 01 -> 4 bytes
`define UART_FC_8		2'b10                                   //> 10 -> 8 bytes
`define UART_FC_14	2'b11                                       //> 11 -> 14 bytes (valor de reset)

//==============================================================
//== Bits de LCR
//==============================================================
// Line Control register bits
`define UART_LC_BITS	1:0	// bits in character                //> LCR[1:0]: 00=5, 01=6, 10=7, 11=8 bits por carácter
`define UART_LC_SB	2	// stop bits                            //> LCR[2]: 0 = 1 stop; 1 = 1.5 (5 bits) o 2 (6-8 bits)
`define UART_LC_PE	3	// parity enable                        //> LCR[3]: habilita paridad
`define UART_LC_EP	4	// even parity                          //> LCR[4]: 1 = par, 0 = impar
`define UART_LC_SP	5	// stick parity                         //> LCR[5]: paridad stick
`define UART_LC_BC	6	// Break control                        //> LCR[6]: break (stx_pad_o forzada a 0)
`define UART_LC_DL	7	// Divisor Latch access bit             //> LCR[7]: DLAB (direcciones 0 y 1 -> divisor)

//==============================================================
//== Bits de MCR (solo se guardan 5)
//==============================================================
// Modem Control register bits
`define UART_MC_DTR	0                                           //> MCR[0]: DTR -> dtr_pad_o (polaridad: AMB-03)
`define UART_MC_RTS	1                                           //> MCR[1]: RTS -> rts_pad_o
`define UART_MC_OUT1	2                                       //> MCR[2]: OUT1 (en loopback -> RI)
`define UART_MC_OUT2	3                                       //> MCR[3]: OUT2 (en loopback -> DCD)
`define UART_MC_LB	4	// Loopback mode                        //> MCR[4]: loopback

//==============================================================
//== Bits de LSR
//==============================================================
// Line Status Register bits
`define UART_LS_DR	0	// Data ready                           //> LSR[0]: hay dato en la FIFO RX
`define UART_LS_OE	1	// Overrun Error                        //> LSR[1]: overrun
`define UART_LS_PE	2	// Parity Error                         //> LSR[2]: error de paridad (carácter de la cima)
`define UART_LS_FE	3	// Framing Error                        //> LSR[3]: error de trama (carácter de la cima)
`define UART_LS_BI	4	// Break interrupt                      //> LSR[4]: break (carácter de la cima)
`define UART_LS_TFE	5	// Transmit FIFO is empty               //> LSR[5]: FIFO TX vacía (THRE)
`define UART_LS_TE	6	// Transmitter Empty indicator          //> LSR[6]: TX completamente vacío (TEMT)
`define UART_LS_EI	7	// Error indicator                      //> LSR[7]: algún error en cualquier parte de la FIFO RX

//==============================================================
//== Bits de MSR: [3:0] deltas (se limpian al leer), [7:4] estado actual
//==============================================================
// Modem Status Register bits
`define UART_MS_DCTS	0	// Delta signals                    //> MSR[0]: cambió CTS
`define UART_MS_DDSR	1                                       //> MSR[1]: cambió DSR
`define UART_MS_TERI	2                                       //> MSR[2]: TERI, flanco de RI (el RTL marca ambos flancos; AMB-05)
`define UART_MS_DDCD	3                                       //> MSR[3]: cambió DCD
`define UART_MS_CCTS	4	// Complement signals               //> MSR[4]: CTS (polaridad: AMB-04)
`define UART_MS_CDSR	5                                       //> MSR[5]: DSR
`define UART_MS_CRI	6                                           //> MSR[6]: RI
`define UART_MS_CDCD	7                                       //> MSR[7]: DCD

//==============================================================
//== Parámetros de las FIFOs
//==============================================================
// FIFO parameter defines

`define UART_FIFO_WIDTH	8                                       //> ancho de la FIFO TX: 8 bits
`define UART_FIFO_DEPTH	16                                      //> profundidad: 16 posiciones
`define UART_FIFO_POINTER_W	4                                   //> puntero de 4 bits
`define UART_FIFO_COUNTER_W	5                                   //> contador de 5 bits (0..16)
// receiver fifo has width 11 because it has break, parity and framing error bits
`define UART_FIFO_REC_WIDTH  11                                 //> ancho de la FIFO RX: 11 = 8 de dato + break + paridad + trama


//==============================================================
//== Macros del banco de pruebas Verilog original (el RTL no las usa)
//==============================================================
`define VERBOSE_WB  0           // All activity on the WISHBONE is recorded  //> detalle de la actividad Wishbone
`define VERBOSE_LINE_STATUS 0   // Details about the lsr (line status register)  //> detalle del LSR
`define FAST_TEST   1           // 64/1024 packets are sent     //> prueba rápida







