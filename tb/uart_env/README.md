# Integración del domingo / E2

Implementación nueva sobre el pull `6d40269`. Antes de crearla se retiró el
banco provisional de pruebas VCS y se restauraron sus archivos al pull.
No se modificaron el RTL, las interfaces, los agentes ni el RAL originales.
El Makefile también conserva su contenido original.

## Componentes y conexiones

```text
uart_base_test
  └─ uart_env
       ├─ vseqr ← uart_main_vseq
       │    ├─ wb_sqr → wb_driver → wb_if → DUT
       │    └─ ser_sqr → ser_driver → srx → DUT
       ├─ wb_monitor ──────────┬─→ predictor → RAL
       │                      └─→ scoreboard.wb_in
       ├─ ser_monitor (stx) ─────→ scoreboard.tx_in
       └─ ser_monitor (srx) ─────→ scoreboard.rx_in
```

Los monitores son los originales. El scoreboard compara las escrituras THR
observadas en Wishbone contra los caracteres observados en STX, y los
caracteres observados en SRX contra las lecturas RBR observadas en Wishbone.
Aplica el ancho de carácter y mantiene colas independientes TX y RX.
Comprueba orden, datos, cantidades totales y colas pendientes. No sustituye
las observaciones con los datos que el generador quiso transmitir.

El modelo de registros usa ambos mapas DLAB, un adaptador y un predictor.
La preparación programa valores distintos del reset en LCR, IER y SCR; la
secuencia estándar `uvm_reg_hw_reset_seq`, extendida para aplicar el reset
físico, comprueba su restauración por Wishbone. Después se vuelve a preparar
el estado y se comprueba el reset de esos tres registros por backdoor.
Los demás registros quedan excluidos únicamente de esta prueba RAL de reset.

## Configuración y tráfico

`uart_env_cfg.sv` centraliza los objetos de configuración y lee los plusargs
una vez. Valida rangos, pesos, porcentajes, opciones desconocidas y controles
que todavía no se implementan; imprime el valor efectivo y su procedencia.
Los mensajes usan reportes UVM con identificadores y verbosidad.

`uart_main_vseq` programa LCR/DLL/DLM/FCR/IER/MCR antes del tráfico y actualiza
la configuración serie compartida. Luego ejecuta por iteración, en paralelo:

- generación de escrituras THR, esperando THRE para evitar overflow;
- generación de caracteres hacia SRX;
- servicio RX por polling de LSR y lectura de RBR.

Al final drena TX y exige que el scoreboard haya comparado las cantidades
previstas. Un semáforo serializa los accesos Wishbone. Hay un timeout del
acceso de tráfico y un watchdog general calculado con los límites de tráfico,
divisor, silencios e iteraciones. El watchdog general también cubre bloqueos
RAL. No se recompila para cambiar los plusargs o la semilla.

| Control | Plusargs | Comportamiento |
|---|---|---|
| Iteraciones | `UART_SW_ITER` | Positivo; default 20 |
| Cantidad TX | `UART_SW_TX_BURST_MIN/MAX` | Default 0..255 por iteración |
| Cantidad RX | `UART_SER_BURST_MIN/MAX` | Default 0..255 por iteración |
| Datos TX | `UART_SW_TX_DATA_MIN/MAX` | Default 0..255; máscara según LCR |
| Datos RX | `UART_SER_DATA_MIN/MAX` | Default 0..255; serialización según LCR |
| Silencio RX | `UART_SER_GAP_MAX` | Aleatorio 0..máximo, en tiempos de bit |
| Formato | `UART_LCR_WLS_WEIGHTS`, `UART_LCR_STB_WEIGHTS`, `UART_LCR_PAR_WEIGHTS` | Pesos de 5/6/7/8 bits; 1 o 1.5/2 stops; ninguna/impar/par/stick-1/stick-0 |
| Divisor | `UART_LCR_DL_FAST_MAX`, `UART_LCR_DL_MAX`, `UART_LCR_DL_TAIL_PCT` | Selección entre región rápida 1..FAST_MAX y cola FAST_MAX+1..MAX |
| Wishbone | `UART_WB_DELAY_MAX`, `UART_WB_STB_DELAY_MAX` | Retardos aleatorios del item |
| Registros | `UART_FCR_TL_WEIGHTS`, `UART_FCR_CLEAR_PCT`, `UART_IER_BIT_PCT`, `UART_MCR_BIT_PCT` | Programación inicial; no implica validación de IRQ/módem |
| Reset RAL | `UART_RAL_HW_RESET` | 1 ejecuta el preámbulo; 0 lo omite |
| Timeout WB | `UART_BUS_TIMEOUT_CYCLES` | Máximo de ciclos del acceso de tráfico |

Los vectores de pesos/porcentajes usan comas. Para una cantidad exacta se
iguala MIN con MAX; ambos en cero deshabilitan ese tráfico. TX y RX conservan
máximos por defecto de 255 sin tocar el default 20 del archivo de Ronald:
se configura el objeto de su agente desde esta integración.

El repositorio incluye `sim/plusargs.args`, un perfil explícito de capacidades E2
con una iteración y divisor entre 1 y 8. Mantiene las ráfagas en 0..255 y
aleatoriza los formatos. Es el mismo test y el mismo generador, configurados
para lo que ya existe; no es CG-01 ni demuestra cierre del plan completo.

## Pendiente de E3

No están implementados el servicio por IRQ, reset/reconfiguración durante
tráfico, errores serie, DL=0, break, loopback, SEL irregular, cambios de módem,
accesos de robustez, lecturas ciegas ni retrasos de servicio con overrun.
Sus controles deben quedar en cero en E2; se rechazan con `UART_E2_CAPABILITY`
si se piden. Los defaults generales conservan opciones pendientes, por lo
que este estado se ejecuta con el perfil E2 explícito.

La limpieza FIFO aleatoria ocurre antes del tráfico: todavía no valida el
descartado de datos activos. TX se sirve con THRE: una ráfaga larga no equivale
a llenar deliberadamente la FIFO. No hay modelo completo LSR/IIR/IRQ/MSR,
cobertura funcional ni nuevas aserciones. No se aplican waivers; E2 requiere
`+UART_SCB_WAIVE_BUGS=` vacío y trata las discrepancias como errores.

El adaptador original funciona con bus de 32 bits; este test rechaza BUS8.
El monitor original convierte señales a dos estados y no tiene recuperación
de reset a mitad de trama. Por eso esta etapa no reclama comprobar X/Z ni
reset durante tráfico. Son limitaciones pendientes de los agentes originales.

Para no modificar esos archivos, los accesos de tráfico agregan dos ciclos
de recuperación después del driver original; una subclase local del adaptador
RAL agrega dos ciclos antes de cada acceso RAL. La traducción de registros
es la original. No son retardos aleatorios ni arreglos a sus fuentes.

## Validación actual y VCS posterior

Se revisó sintaxis y elaboración del top completo con slang y fuentes UVM 1.2:
0 errores, 2 advertencias de bucles vacíos en la biblioteca UVM. No es una
simulación, no valida el comportamiento ni reemplaza VCS. VCS no se ejecutó.

Cuando corresponda probar en el servidor, desde `sim/`:

```bash
make comp
make run TEST=uart_base_test SEED=1 ARGS="-f plusargs.args"
```

Para fijar cantidades, copiar `plusargs.args` a otro `.args` y agregar, por ejemplo,
`+UART_SW_TX_BURST_MIN=50` y `+UART_SW_TX_BURST_MAX=50`. Ejecutar el mismo
binario cambiando únicamente `ARGS` y la semilla. No duplicar la misma clave
con distintos valores entre el archivo y la línea de comandos.

El resultado esperado al probar es `UART_E2_PASS`, cero `UVM_ERROR/FATAL`,
conteos TX/RX coincidentes y ninguna cola pendiente. Revisar también los
warnings; un banner PASS no certifica capacidades de E3 ni cobertura completa.
El ejecutor sigue siendo el Makefile/Bash original; no se agregó runner Python.

## Validación de conexiones antes del tráfico

El ambiente verifica en `end_of_elaboration_phase()` que existan los
componentes, configuraciones e interfaces virtuales requeridos, que cada
puerto alcance sus implementaciones y que sus destinos sean los previstos
También comprueba las referencias del virtual sequencer, los mapas RAL,
el predictor y la selección STX/SRX de los monitores

Una conexión faltante o incorrecta produce `UVM_FATAL` con ID
`UART_CONNECTION` antes de iniciar las secuencias
Esta validación ocurre al arrancar la simulación, después de `connect_phase()`
No demuestra por sí sola actividad real ni el cableado RTL de la interfaz
Los conteos y las comparaciones del scoreboard siguen siendo necesarios
