//==============================================================
//== ARCHIVO uart_sync_flops.v (copia de estudio; el original está en rtl/)
//== Sincronizador de 2 flip-flops para srx_pad_i (entrada asíncrona): evita metaestabilidad
//== y agrega 2 ciclos de retraso a la entrada serie. Líneas 1-66: licencia e historial.
//==============================================================
//////////////////////////////////////////////////////////////////////
////                                                              ////
////  uart_sync_flops.v                                             ////
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
////      - Andrej Erzen (andreje@flextronics.si)                 ////
////      - Tadej Markovic (tadejm@flextronics.si)                ////
////                                                              ////
////  Created:        2004/05/20                                  ////
////  Last Updated:   2004/05/20                                  ////
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
//


`include "timescale.v"                                          //> unidad de tiempo


//==============================================================
//== Puertos y parámetros
//==============================================================
module uart_sync_flops                                          //> módulo uart_sync_flops
(                                                               //> inicio de la lista
  // internal signals
  rst_i,                                                        //> reset asíncrono
  clk_i,                                                        //> reloj
  stage1_rst_i,                                                 //> reset síncrono de la 2.a etapa (en uart_regs = 0)
  stage1_clk_en_i,                                              //> habilitación de la 2.a etapa (en uart_regs = 1)
  async_dat_i,                                                  //> entrada asíncrona
  sync_dat_o                                                    //> salida sincronizada
);                                                              //> fin de la lista

parameter Tp            = 1;                                    //> retardo de simulación (#1)
parameter width         = 1;                                    //> ancho (uart_regs usa 1)
parameter init_value    = 1'b0;                                 //> valor inicial (uart_regs usa 1 = reposo)

input                           rst_i;                  // reset input  //> reset
input                           clk_i;                  // clock input  //> reloj
input                           stage1_rst_i;           // synchronous reset for stage 1 FF  //> reset síncrono
input                           stage1_clk_en_i;        // synchronous clock enable for stage 1 FF  //> habilitación
input   [width-1:0]             async_dat_i;            // asynchronous data input  //> entrada
output  [width-1:0]             sync_dat_o;             // synchronous data output  //> salida


//
// Interal signal declarations
//

reg     [width-1:0]             sync_dat_o;                     //> salida como registro
reg     [width-1:0]             flop_0;                         //> primera etapa


//==============================================================
//== Primera etapa: captura la entrada (puede quedar metaestable)
//==============================================================
// first stage
always @ (posedge clk_i or posedge rst_i)                       //> se actualiza en flanco de reloj o reset
begin                                                           //> inicio
    if (rst_i)                                                  //> en reset...
        flop_0 <= #Tp {width{init_value}};                      //> ...valor inicial
    else                                                        //> si no...
        flop_0 <= #Tp async_dat_i;                              //> ...copia la entrada
end                                                             //> fin

//==============================================================
//== Segunda etapa: salida estable
//== Las ramas con stage1_rst_i = 1 o stage1_clk_en_i = 0 son inalcanzables (entradas constantes)
//==============================================================
// second stage
always @ (posedge clk_i or posedge rst_i)                       //> se actualiza en flanco de reloj o reset
begin                                                           //> inicio
    if (rst_i)                                                  //> en reset...
        sync_dat_o <= #Tp {width{init_value}};                  //> ...valor inicial
    else if (stage1_rst_i)                                      //> con reset síncrono (nunca ocurre)...
        sync_dat_o <= #Tp {width{init_value}};                  //> ...valor inicial
    else if (stage1_clk_en_i)                                   //> con habilitación (siempre)...
        sync_dat_o <= #Tp flop_0;                               //> ...copia la primera etapa
end                                                             //> fin

endmodule                                                       //> fin del módulo
