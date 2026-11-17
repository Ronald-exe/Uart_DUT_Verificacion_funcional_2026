# Comandos para la demo de E2

## 0. Entrar y preparar
```bash
cd <carpeta del repo>/Uart_DUT_Verificacion_funcional_2026
git pull
cd sim
```

## 1. Compilar (una sola vez)
```bash
make comp TEST=uart_base_test
```
Buscar al final: `0 error(s), 0 warning(s)`.

## 2. Una semilla, para mostrar el flujo
```bash
make run TEST=uart_base_test SEED=1 ARGS="-f plusargs.args"
```
Qué enseñar en la salida:
- `[UART_CFG] ... (default)` / `(plusarg)`: cada knob con su origen.
- `[UART_RAL_FRONTDOOR]` y `[UART_RAL_BACKDOOR]`: prueba de reset del RAL.
- `[UART_LINE] LCR=.. DL=..`: formato elegido por la semilla.
- `[SCB_SUMMARY] TX comparados=.. RX comparados=..`
- `[UART_E2_PASS]` y `UVM_ERROR : 0`, `UVM_FATAL : 0`.

## 3. Las 20 semillas
```bash
for s in $(seq 1 20); do make run TEST=uart_base_test SEED=$s ARGS="-f plusargs.args"; done
```

## 4. Resumen de las 20
```bash
grep -l "UVM_ERROR :    0" run_uart_base_test_*.log | wc -l     # debe dar 20
grep -H "UVM_FATAL :" run_uart_base_test_*.log
grep -h "\[SCB_SUMMARY\] TX" run_uart_base_test_*.log
```

## 5. Cobertura (URG)
```bash
make cov
head -25 cov_report/dashboard.txt
firefox cov_report/dashboard.html &
```

## 6. Si preguntan por los knobs o el perfil
```bash
grep -v "^//" plusargs.args | grep -v "^$"
```
Mostrar un plusarg cambiado en vivo:
```bash
make run TEST=uart_base_test SEED=1 ARGS="-f plusargs.args +UART_SW_TX_BURST_MAX=5"
grep "UART_SW_TX_BURST_MAX" run_uart_base_test_1.log    # sale (plusarg)
```
