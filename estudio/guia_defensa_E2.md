# Guía para la defensa de E2

Basada en el código que quedó después del rollback de Alex (commit `8c0ab07`). Lo que el profe suele pedir (enunciado 8.2): explicar la arquitectura, seguir una transacción, explicar 2 componentes, hacer un cambio en vivo e interpretar un error.

## 1. El ambiente en un dibujo

```
tb_top ──(interfaces virtuales por config_db)──► uart_base_test
                                                   │ crea uart_env_cfg y llama parse_plusargs()
                                                   ▼
uart_env
 ├─ wb_agt   (tu agente Wishbone: driver, monitor, sqr)   ── bus ──►   DUT
 ├─ ser_agt  (tu agente serie: driver srx, mon_tx, mon_rx, sqr) ── serie ──► DUT
 ├─ regm     (tu RAL: uart_reg_block)
 ├─ adapter  (uart_timed_reg_adapter: tu adaptador + 2 ciclos de delay)
 ├─ predictor (uvm_reg_predictor normal de UVM)
 ├─ scb      (uart_scoreboard: compara TX y RX)
 └─ vseqr    (uart_vsequencer: tiene los 2 sqr, el RAL y la cfg)
```

**Conexiones** (`uart_env.connect_phase`):
- Los 2 mapas del RAL usan el secuenciador Wishbone y el adaptador; `set_auto_predict(0)`.
- `wb_agt.mon.ap` va a **2 lugares**: el predictor (para el espejo del RAL) y el scoreboard (`wb_in`).
- `ser_agt.mon_tx.ap` va a `scb.tx_in` y `ser_agt.mon_rx.ap` a `scb.rx_in`.
- `end_of_elaboration_phase` revisa que todo esté conectado. Si algo falta, da `uvm_fatal` antes de empezar.

## 2. Qué hace la prueba (`uart_base_test`)

1. **`build_phase`:** crea `uart_env_cfg`, saca las 3 interfaces del `config_db`, llama `parse_plusargs()`, publica la cfg y crea el ambiente.
2. **`end_of_elaboration_phase`:** a todos los registros menos LCR, IER y SCR les pone `NO_REG_HW_RESET_TEST`, para que la prueba de reset no los toque.
3. **`run_phase`:** levanta la objeción y corre `uart_main_vseq`. En paralelo corre un **watchdog**: si la secuencia se tarda más de `timeout_cycles`, da `uvm_fatal`. Al final le pasa al scoreboard cuántos TX y RX se planearon y baja la objeción.
4. **`report_phase`:** si no hubo errores, imprime `UART_E2_PASS`.

## 3. La secuencia principal (`uart_main_vseq.body`)

1. Espera a que termine el reset.
2. **`ral_preamble()`:** prueba del RAL.
   - Escribe valores raros en LCR, IER y SCR y aplica reset (`prepare_reset_register`).
   - **Puerta delantera:** corre `uart_hw_reset_seq` (lee por el bus y compara con el reset). Es la `uvm_reg_hw_reset_seq` de UVM, pero con `reset_blk` cambiado para que de verdad suba `rst` 5 ciclos.
   - **Puerta trasera:** otro reset y luego `mirror(…, UVM_CHECK, UVM_BACKDOOR)` en LCR, IER y SCR.
3. **`program_uart()`:** elige un formato con los knobs y configura LCR, DL, FCR e IER. **El formato queda fijo toda la corrida.**
4. Repite `n_iter` veces, con 3 tareas **en paralelo** (`fork … join`):
   - `send_tx`: espera THRE (LSR[5]) y escribe un byte en THR.
   - `send_rx`: manda caracteres por el agente serie (`uart_rx_seq`).
   - `service_rx`: espera un rato, lee LSR y, si DR (LSR[0]) = 1, lee RBR.
5. Espera TEMT (LSR[6]): el último carácter terminó de salir.

`access()` y `transfer()` hacen un acceso al bus con `uart_wb_seq`. Antes, si DLAB está en 1, lo bajan.

## 4. Recorrido de un carácter

**TX:** `send_tx` escribe en THR → tu driver Wishbone mueve los cables → tu monitor Wishbone lo publica → el scoreboard (`observe_write`) mete el byte en `tx_queue` → el DUT lo saca por `stx` → tu `mon_tx` lo arma → el scoreboard (`observe_tx`) saca el primero de `tx_queue` y compara.

**RX:** `send_rx` → tu driver serie lo manda por `srx` → tu `mon_rx` lo arma → el scoreboard (`observe_rx`) lo mete en `rx_queue` → `service_rx` lee RBR → el monitor Wishbone lo publica → el scoreboard (`observe_read`) saca el primero de `rx_queue` y compara.

## 5. El scoreboard (224 líneas)

- **Entradas:** 3 `uvm_tlm_analysis_fifo` (`wb_in`, `tx_in`, `rx_in`). Son como buzones: los monitores dejan items y el scoreboard los saca cuando quiere.
- **Dos colas:** `tx_queue` (lo escrito en THR) y `rx_queue` (lo que entró por `srx`). Se compara en orden, porque las FIFOs del UART también son en orden.
- Lleva una copia de **LCR** para saber si la dirección 0 es THR/RBR (DLAB = 0) o DLL (DLAB = 1).
- `character_mask` borra los bits que sobran, por ejemplo con 5 bits de dato.
- **Orden en cada ciclo:** primero las escrituras, después lo de `srx`, después las lecturas y lo de `stx`. Así un byte escrito o recibido en el mismo ciclo ya está en la cola cuando se compara.
- **Con reset:** vacía las colas.
- **Al final** (`check_phase`): revisa que se compararon todos los planeados y que no quedó nada en las colas.
- **Errores que da:** `SCB_TX_DATA`/`SCB_RX_DATA` (dato distinto), `SCB_TX_UNEXPECTED` (salió algo que nadie escribió), `SCB_RX_LINE` (error de línea en tráfico normal).

**Límite de E2:** no modela overrun, errores de línea, reconfiguración ni reset en medio. Si pasan, da error. Eso es para E3.

## 6. Plusargs y cambio en vivo

Todo se lee en **un solo lugar**: `uart_env_cfg::parse_plusargs()`, con `read_uint("NOMBRE", campo)` y `read_vector` para listas de pesos. `require()` da `uvm_fatal` si un valor no es válido.

**Agregar un knob nuevo** (lo más probable que pidan):
1. Agregar el campo con su valor por defecto en la cfg que corresponde (ej. `uart_sw_cfg`).
2. Agregar `read_uint("UART_SW_MI_KNOB", sw.mi_knob);` en `parse_plusargs()`.
3. Usarlo donde se sortea (ej. `$urandom_range` en `uart_main_vseq`).
4. Correr con `+UART_SW_MI_KNOB=…` y ver en el log que tomó el valor.

## 7. Cómo correr las 20 semillas

```bash
cd sim
make comp TEST=uart_base_test
for s in $(seq 1 20); do make run TEST=uart_base_test SEED=$s ARGS="-f plusargs.args"; done
grep -H "UVM_ERROR :" run_uart_base_test_*.log
make cov
```

## 8. Preguntas probables

| Pregunta | Respuesta corta |
|---|---|
| ¿Por qué interfaz virtual? | La clase no puede tener hardware; guarda un handle a los cables de `tb_top`. |
| ¿Driver vs monitor? | El driver mueve cables; el monitor solo mira y publica por `ap`. |
| ¿Qué es un analysis port? | Un altavoz: el monitor publica y todos los conectados reciben. |
| ¿Para qué el `uvm_tlm_analysis_fifo` del scoreboard? | Es un buzón: guarda lo que publican los monitores para compararlo después y en orden. |
| ¿Por qué dos mapas en el RAL? | Las direcciones 0 y 1 cambian de registro según DLAB. |
| ¿Puerta delantera vs trasera? | Delantera = por el bus Wishbone; trasera = directo a la señal del RTL, sin efectos laterales. |
| ¿Por qué `set_auto_predict(0)`? | Para que el espejo solo cambie por lo que vio el monitor (el predictor), no dos veces. |
| ¿Por qué el adaptador "timed"? | Agrega 2 ciclos entre accesos del RAL; la fórmula de `adr`, `sel` y carril es la tuya. |
| ¿Por qué el watchdog en la prueba? | Si algo se cuelga (por ejemplo, nunca llega `ack`), la simulación termina con error en vez de quedarse para siempre. |
| ¿Cómo termina la prueba? | Con objeciones: la prueba la levanta y la baja cuando termina la secuencia. |
| ¿Qué es un error falso? | Un `UVM_ERROR` por culpa del ambiente, no del DUT. E2 pide 20 semillas sin ellos. |
