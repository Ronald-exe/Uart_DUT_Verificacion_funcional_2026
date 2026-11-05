# RTL comentado (solo para estudio)

Copias de `rtl/` con comentarios en español. **No se compilan** (`sim/filelist.f` usa `../rtl`) y `rtl/` no se modificó.

- Cada bloque tiene un encabezado entre líneas `//====` y cada línea de código un comentario al final que empieza con `//>`. Los `//` normales son del autor original.
- Quitar lo agregado devuelve el código original (verificado). Para comprobarlo:
  `grep -v "^[[:space:]]*//==" estudio/rtl_comentado/uart_regs.v | sed -E "s/ +\/\/> .*$//" | diff -w - rtl/uart_regs.v`
- Las notas marcadas con **OJO** o "a verificar" son posibles errores del DUT o ambigüedades que hay que confirmar en simulación.

## Orden de lectura sugerido

1. `uart_defines.v`: mapa de registros y bits
2. `uart_top.v`: cómo se conectan los bloques
3. `uart_wb.v`: Wishbone, ack y `wb_sel_i`
4. `uart_regs.v`: registros, LSR, MSR, interrupciones, divisor y loopback (el más importante)
5. `uart_transmitter.v` y `uart_tfifo.v`
6. `uart_receiver.v` y `uart_rfifo.v`
7. `raminfr.v`, `uart_sync_flops.v`, `uart_debug_if.v`, `timescale.v`
