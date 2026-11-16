// Lista de archivos para VCS. Las rutas son relativas al directorio sim/.
// uart_defines.v y timescale.v no se listan: los incluyen los propios archivos
// (por eso hace falta +incdir+../rtl).

+incdir+../rtl
+incdir+../tb
+incdir+../tb/wb_agent
+incdir+../tb/ser_agent
+incdir+../tb/ral
+incdir+../tb/uart_env
// Add the modem package to the integration without changing the original interfaces -- alex
+incdir+../tb/modem_agent

// ---- RTL del DUT ----
../rtl/raminfr.v
../rtl/uart_sync_flops.v
../rtl/uart_tfifo.v
../rtl/uart_rfifo.v
../rtl/uart_transmitter.v
../rtl/uart_receiver.v
../rtl/uart_regs.v
../rtl/uart_debug_if.v
../rtl/uart_wb.v
../rtl/uart_top.v

// ---- Interfaces y aserciones ----
../tb/wb_if.sv
../tb/uart_ser_if.sv
../tb/modem_if.sv
../tb/uart_wb_sva.sv

// ---- Ambiente UVM ----
../tb/wb_agent/wb_pkg.sv
../tb/ser_agent/ser_pkg.sv
../tb/ral/ral_pkg.sv
// Define modem types before the environment consumes them -- alex
../tb/modem_agent/modem_pkg.sv
../tb/uart_env/uart_env_pkg.sv
../tb/uart_hello_pkg.sv

// ---- Top ----
../tb/tb_top.sv
