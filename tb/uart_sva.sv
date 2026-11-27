
//Modulo de aserciones del UART (seccion 11 del plan)
//Una asercion revisa una regla del protocolo EN CADA CICLO, el scoreboard en cambio revisa transacciones completas
//Se conecta al DUT con bind en tb_top.sv: es como pegarle este modulo por dentro a uart_top sin tocar el RTL
//asi puede mirar los pines y tambien senales internas (lcr, mcr, msr, dl, tstate)
//Cada assert lleva su cover: el assert dice "nunca fallo" y el cover dice "y si paso la situacion", si no seria una prueba vacia
//Si un assert falla da UVM_ERROR, asi cuenta en el resumen de UVM y make regress lo detecta
//Pendiente: A-SER-02 (duracion de cada bit). La polaridad de RTS y DTR (BUG-01) la revisa el scoreboard
`timescale 1ns/1ps
`include "uart_defines.v"

module uart_sva
  import uvm_pkg::*;          //importamos UVM para poder usar `uvm_error desde un modulo
(
  //pines del bus Wishbone
  input logic                         wb_clk_i,
  input logic                         wb_rst_i,
  input logic [`UART_ADDR_WIDTH-1:0]  wb_adr_i,
  input logic [`UART_DATA_WIDTH-1:0]  wb_dat_i,
  input logic [`UART_DATA_WIDTH-1:0]  wb_dat_o,
  input logic [3:0]                   wb_sel_i,
  input logic                         wb_we_i,
  input logic                         wb_stb_i,
  input logic                         wb_cyc_i,
  input logic                         wb_ack_o,
  //otros pines
  input logic                         int_o,
  input logic                         stx_pad_o,
  //senales internas de uart_regs (en el bind se conectan como regs.lcr, regs.mcr, ...)
  input logic [7:0]                   lcr,     //formato de linea, bit 6 = break
  input logic [4:0]                   mcr,     //bit 0 DTR, 1 RTS, 2 OUT1, 3 OUT2, 4 loopback
  input logic [7:0]                   msr,     //estado del modem, bits 7:4 = DCD, RI, DSR, CTS
  input logic [15:0]                  dl,      //divisor
  input logic [2:0]                   tstate,  //estado del transmisor: 0 reposo, 1 bit de inicio, 2 datos...
  input logic                         enable,  //pulso de baudios (es lo mismo que sale por baud_o)
  input logic                         lsr_mask,     //1 en el primer ciclo de una lectura de LSR con DLAB = 0 (borra PE, FE, BI, EI)
  input logic [2:0]                   lsr_err_rise, //{BI, FE, PE}: 1 en el ciclo en que el DUT quiere encender ese bit (flanco)
  input logic                         dr,           //LSR[0], dato listo
  input logic [4:0]                   rf_count,     //cuantos caracteres tiene la FIFO RX
  input logic                         rf_push,      //1 el ciclo en que el receptor mete un caracter a la FIFO RX
  input logic                         rf_pop        //1 el ciclo en que una lectura de RBR saca un caracter
);
  `include "uvm_macros.svh"

  //Todas las propiedades se revisan en el flanco de subida del reloj y se apagan durante el reset
  default clocking cb @(posedge wb_clk_i); endclocking
  default disable iff (wb_rst_i);

  //Nombres para los estados del transmisor, son los mismos parametros de uart_transmitter.v
  localparam logic [2:0] S_IDLE  = 3'd0;
  localparam logic [2:0] S_START = 3'd1;
  localparam logic [2:0] S_BYTE  = 3'd2;

  //A-WB-01: mientras el maestro espera ack, adr, we, sel y el dato de escritura no cambian (ejemplo del profe)
  //|=> significa "en el siguiente ciclo"
  property p_wb_01;
    (wb_cyc_i && wb_stb_i && !wb_ack_o) |=>
      (wb_stb_i && $stable(wb_adr_i) && $stable(wb_we_i) && $stable(wb_sel_i) && (!wb_we_i || $stable(wb_dat_i)));
  endproperty
  a_wb_01: assert property (p_wb_01) else `uvm_error("A-WB-01", "El maestro cambio el acceso antes de recibir ack")
  c_wb_01: cover property (wb_cyc_i && wb_stb_i && !wb_ack_o ##1 wb_ack_o);

  //A-WB-02a: ack llega a lo sumo 4 ciclos despues de cyc y stb
  //##[0:4] significa "en algun ciclo entre 0 y 4 ciclos despues"
  property p_wb_02a;
    (wb_cyc_i && wb_stb_i) |-> ##[0:4] wb_ack_o;
  endproperty
  a_wb_02a: assert property (p_wb_02a) else `uvm_error("A-WB-02", "ack tardo mas de 4 ciclos")
  c_wb_02a: cover property (wb_cyc_i && wb_stb_i ##[1:4] wb_ack_o);

  //A-WB-02b: ack dura un solo ciclo
  property p_wb_02b;
    wb_ack_o |=> !wb_ack_o;
  endproperty
  a_wb_02b: assert property (p_wb_02b) else `uvm_error("A-WB-02", "ack duro mas de un ciclo")
  c_wb_02b: cover property (wb_ack_o ##1 !wb_ack_o);

  //A-WB-03a: fuera de reset ack_o, int_o y stx_pad_o nunca son X ni Z
  //$isunknown da 1 si alguno de los bits es X o Z
  property p_wb_03a;
    !$isunknown({wb_ack_o, int_o, stx_pad_o});
  endproperty
  a_wb_03a: assert property (p_wb_03a) else `uvm_error("A-WB-03", "ack_o, int_o o stx_pad_o tiene X o Z")
  c_wb_03a: cover property (int_o); //que int_o si llego a subir alguna vez

  //A-WB-03b: cuando hay ack en una lectura, el dato que devuelve el DUT no tiene X
  //menos al leer RBR (direccion 0 con DLAB = 0): con la FIFO RX vacia el valor no esta definido (AMB-11)
  //y en simulacion "no definido" es X, porque esa parte de la memoria de la FIFO nunca se escribio
  property p_wb_03b;
    (wb_ack_o && !wb_we_i && !((wb_adr_i[4:2] == 3'b000) && (wb_sel_i == 4'b1000) && !lcr[7])) |-> !$isunknown(wb_dat_o);
  endproperty
  a_wb_03b: assert property (p_wb_03b) else `uvm_error("A-WB-03", "dat_o tiene X o Z en una lectura")
  c_wb_03b: cover property (wb_ack_o && !wb_we_i);

  //A-SER-01: sin caracter en curso (transmisor en reposo) y sin break, stx_pad_o esta en 1
  property p_ser_01;
    (tstate == S_IDLE && !lcr[6]) |-> stx_pad_o;
  endproperty
  a_ser_01: assert property (p_ser_01) else `uvm_error("A-SER-01", "stx_pad_o en 0 con el transmisor en reposo")
  c_ser_01: cover property (tstate == S_IDLE && !lcr[6]);

  //A-SER-01b: justo despues del reset la linea esta en reposo (1)
  //$fell(wb_rst_i) es el ciclo en que el reset bajo, por eso esta no usa el disable iff
  a_ser_01b: assert property (disable iff (1'b0) $fell(wb_rst_i) |-> stx_pad_o)
    else `uvm_error("A-SER-01", "stx_pad_o no esta en 1 despues del reset")
  c_ser_01b: cover property (disable iff (1'b0) $fell(wb_rst_i));

  //A-SER-03: con break (LCR[6] = 1) y sin loopback, stx_pad_o esta en 0
  //sin loopback porque en loopback el DUT fuerza stx_pad_o a 1 (A-LB-01)
  property p_ser_03;
    (lcr[6] && !mcr[4]) |-> !stx_pad_o;
  endproperty
  a_ser_03: assert property (p_ser_03) else `uvm_error("A-SER-03", "Break activo pero stx_pad_o no esta en 0")
  c_ser_03: cover property (lcr[6] && !mcr[4]);

  //A-SER-04: cada caracter empieza con un bit de inicio en 0
  //lo revisamos cuando el transmisor pasa del bit de inicio (S_START) a los datos (S_BYTE):
  //en el ciclo anterior la linea tenia que estar en 0. $past(x) es el valor de x un ciclo antes
  property p_ser_04;
    (tstate == S_BYTE && $past(tstate) == S_START && !mcr[4] && !lcr[6]) |-> ($past(stx_pad_o) == 1'b0);
  endproperty
  a_ser_04: assert property (p_ser_04) else `uvm_error("A-SER-04", "El caracter no empezo con un bit de inicio en 0")
  c_ser_04: cover property (tstate == S_BYTE && $past(tstate) == S_START && !mcr[4]);

  //A-LB-01: con loopback (MCR[4] = 1) stx_pad_o esta en 1, el caracter se queda adentro del DUT
  property p_lb_01;
    mcr[4] |-> stx_pad_o;
  endproperty
  a_lb_01: assert property (p_lb_01) else `uvm_error("A-LB-01", "Loopback activo pero stx_pad_o no esta en 1")
  c_lb_01: cover property (mcr[4]);

  //A-LB-02: con loopback, MSR[7:4] sigue al MCR un ciclo despues (el MSR es un registro)
  //RTS -> CTS (bit 4), DTR -> DSR (bit 5), OUT1 -> RI (bit 6), OUT2 -> DCD (bit 7)
  property p_lb_02;
    mcr[4] |=> (msr[7:4] == {$past(mcr[3]), $past(mcr[2]), $past(mcr[0]), $past(mcr[1])});
  endproperty
  a_lb_02: assert property (p_lb_02) else `uvm_error("A-LB-02", "En loopback MSR[7:4] no sigue al MCR")
  c_lb_02: cover property (mcr[4] ##1 mcr[4]);

  //A-BAUD-01 (extra): con DL mayor que 1 el pulso de baudios dura un solo ciclo, y con DL = 0 no hay pulsos
  property p_baud_01a;
    (dl > 1 && enable) |=> !enable;
  endproperty
  a_baud_01a: assert property (p_baud_01a) else `uvm_error("A-BAUD-01", "El pulso de baudios duro mas de un ciclo")
  c_baud_01a: cover property (dl > 1 && enable);

  //se usa |=> porque enable es un registro: se calcula con el DL de este ciclo y aparece en el siguiente
  property p_baud_01b;
    (dl == 0) |=> !enable;
  endproperty
  a_baud_01b: assert property (p_baud_01b) else `uvm_error("A-BAUD-01", "Hay pulsos de baudios con DL = 0")
  c_baud_01b: cover property (dl == 0);

  //C-MDM-01 (cover): MCR cambio RTS o DTR fuera de loopback
  //la polaridad de RTS y DTR (BUG-01) la revisa el scoreboard con el monitor de modem, igual que los demas BUG
  c_mdm_01: cover property ($changed(mcr[1:0]) && !mcr[4]);

  //C-LSR-01 (solo cover, para investigar): el DUT quiere encender PE, FE o BI en el mismo ciclo en que una lectura de LSR los borra
  //en uart_regs.v el borrado gana (lsr2r <= lsr_mask ? 0 : ...), asi que ese aviso de error se pierde
  //este numero se compara con los avisos perdidos que cuenta el scoreboard (SCB_LSR_MISS)
  c_lsr_lost: cover property (lsr_mask && (lsr_err_rise != 3'b000));

  //C-RX-01 y C-RX-02 (solo cover, para investigar el BUG-07)
  //C-RX-01: push y pop al mismo tiempo con la FIFO RX vacia (una lectura ciega justo cuando llega un caracter)
  //en uart_rfifo.v ese caso mueve los dos punteros pero deja la cuenta en 0
  c_rx_push_pop_empty: cover property (rf_push && rf_pop && (rf_count == 0));
  //C-RX-02: DR en 1 con la FIFO RX vacia durante 20 ciclos seguidos ([*20] = se repite 20 ciclos)
  //la especificacion dice DR = 0 si no hay caracteres (seccion 4.7), asi que esto es el BUG-07
  c_dr_stuck: cover property ((dr && (rf_count == 0)) [*20]);

endmodule : uart_sva
