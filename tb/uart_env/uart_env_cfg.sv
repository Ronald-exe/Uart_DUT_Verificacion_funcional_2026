
// Keep the line settings together so changing a format does not mean hunting through sequences
// These are runtime choices -- the same compiled DUT is used for every seed
// Some plan defaults still enable pending features -- the E2 profile has to turn those off
class uart_line_cfg extends uvm_object;
  `uvm_object_utils(uart_line_cfg)
  // Use a fast region for most runs and a slower tail for the larger divisors
  // That gives slow baud rates a chance without making every seed take the maximum time
  int unsigned dl_zero_pct = 1;
  int unsigned dl_fast_max = 16;
  int unsigned dl_max = 65535;
  int unsigned dl_tail_pct = 2;
  // Keep the break knob here because it belongs to LCR -- enabling it still fails the E2 check
  int unsigned bc_pct = 5;
  // Keep the array order fixed because the chosen index goes straight into the format encoding
  // Data bits are [5,6,7,8] -- stops are [one,extended]
  // Parity is [none,odd,even,stick-1,stick-0] -- weight zero removes that option
  int unsigned wls_w[] = '{1,1,1,1};
  int unsigned stb_w[] = '{1,1};
  int unsigned par_w[] = '{1,1,1,1,1};
  function new(string name = "uart_line_cfg");
    super.new(name);
  endfunction
endclass : uart_line_cfg

// Group the initial register controls here because they are programmed before traffic starts
// Writing IER or MCR alone does not check whether interrupts or modem signals behave correctly
class uart_ctrl_cfg extends uvm_object;
  `uvm_object_utils(uart_ctrl_cfg)
  // Only clear before traffic for now -- clearing an active FIFO would need a discard model
  int unsigned fcr_clear_pct = 10;
  int unsigned loop_pct = 10;
  // Trigger choices follow [1,4,8,14] characters
  // IER and MCR use a percentage per bit -- those values are independent and do not need to add to 100
  int unsigned tl_w[] = '{1,1,1,1};
  int unsigned ier_bit_pct[] = '{50,50,50,50};
  int unsigned mcr_bit_pct[] = '{50,50,50,50};
  function new(string name = "uart_ctrl_cfg");
    super.new(name);
  endfunction
endclass : uart_ctrl_cfg

// These knobs describe the software side -- THR writes and servicing the received characters
// Keep one iteration as a TX and RX pair so either direction can also be disabled with its count
class uart_sw_cfg extends uvm_object;
  `uvm_object_utils(uart_sw_cfg)
  int unsigned n_iter = 20;
  // Use inclusive MIN and MAX so the same generator can do random or fixed traffic
  // For exactly 50 characters set both limits to 50 -- for no traffic set both to zero
  int unsigned tx_burst_min = 0;
  int unsigned tx_burst_max = 255;
  int unsigned tx_data_min = 0;
  int unsigned tx_data_max = 255;
  // Measure service delay in character times so it still makes sense when the baud rate changes
  // Delay, blind reads, random accesses, live reset and reconfiguration are still blocked in E2
  // They need their checking rules before we can enable them
  int unsigned service_delay_min = 0;
  int unsigned service_delay_max = 20;
  int unsigned blind_read_pct = 5;
  int unsigned rand_access_pct = 5;
  int unsigned recfg_pct = 5;
  int unsigned rst_pct = 1;
  // The order is [interrupt-driven,polling] -- leave the first weight at zero until IRQ service exists
  int unsigned mode_w[] = '{1,1};
  function new(string name = "uart_sw_cfg");
    super.new(name);
  endfunction
endclass : uart_sw_cfg

// Pass one shared configuration through the environment instead of parsing arguments in every component
// The original agent configs live here too -- no need to change their source defaults
class uart_env_cfg extends uvm_object;
  `uvm_object_utils(uart_env_cfg)
  // Separate line, register and software settings so each group has a clear place
  // Keep the virtual interfaces inside the agent configs that already use them
  uart_line_cfg line;
  uart_ctrl_cfg ctrl;
  uart_sw_cfg sw;
  wb_agent_cfg wb;
  ser_agent_cfg ser;
  virtual modem_if mdm_vif;
  // TX generation and RX service share one Wishbone master
  // Use one token so they cannot overlap accesses or interrupt the DLAB programming steps
  semaphore bus_lock;
  // Keep the planned error knobs visible -- reject them if enabled until stimulus and checking are ready
  int unsigned ser_parity_err_pct = 5;
  int unsigned ser_frame_err_pct = 5;
  int unsigned ser_break_pct = 3;
  int unsigned ser_stop2_err_pct = 5;
  int unsigned ser_glitch_pct = 3;
  int unsigned ser_baud_err_pct = 5;
  int unsigned ser_baud_err_max = 8;
  int unsigned mdm_toggle_pct = 20;
  // The per-access timeout catches stuck traffic handshakes
  // The overall watchdog is also needed because a RAL access can stall outside that traffic helper
  int unsigned run_ral_reset = 1;
  int unsigned bus_timeout_cycles = 1000;
  longint unsigned timeout_cycles;
  // The plan has a waiver list but the current scoreboard has no waiver handling
  // Require an empty list so we do not accidentally ignore a real mismatch
  string waive_bugs = "1,2,3,4,5";
  // Save the value and where it came from so the log is enough to reconstruct the configuration
  // Use the test as the report context because this config is an object rather than a component
  string effective[string];
  string origin[string];
  uvm_report_object reporter;

  function new(string name = "uart_env_cfg");
    super.new(name);
    line = uart_line_cfg::type_id::create("line");
    ctrl = uart_ctrl_cfg::type_id::create("ctrl");
    sw = uart_sw_cfg::type_id::create("sw");
    wb = wb_agent_cfg::type_id::create("wb");
    ser = ser_agent_cfg::type_id::create("ser");
    // Set the wider range on our instance -- changing the original agent file would affect other users
    ser.burst_max = 255;
    bus_lock = new(1);
  endfunction

  // Parse the digits ourselves because converting directly to unsigned can hide a negative or overflow
  // Check with a wider temporary first -- only narrow the value after it fits
  function int unsigned decimal(string text, string key);
    longint unsigned number;
    number = 0;
    if ((text.len() == 0) || (text.len() > 10))
      `uvm_fatal_context("UART_ARG", {key, ": entero invalido"}, reporter)
    for (int i = 0; i < text.len(); i++) begin
      if ((text.getc(i) < 48) || (text.getc(i) > 57))
        `uvm_fatal_context("UART_ARG", {key, ": se requiere un entero no negativo"}, reporter)
      number = number * 10 + text.getc(i) - 48;
    end
    if (number > 64'hffffffff)
      `uvm_fatal_context("UART_ARG", {key, ": entero fuera de rango"}, reporter)
    return int'(number);
  endfunction

  // Keep the default when the argument is absent
  // Record whether it came from the command line so a default is not mistaken for an explicit choice
  function void read_uint(string key, ref int unsigned value);
    string raw;
    if ($value$plusargs({key, "=%s"}, raw)) begin
      value = decimal(raw, key);
      origin[key] = "plusarg";
    end else begin
      origin[key] = "default";
    end
    effective[key] = $sformatf("%0d", value);
  endfunction

  // Read weights as a fixed-length list so a missing element cannot silently shift the choices
  // Percentages are checked one by one -- weights need a nonzero total for the random pick
  function void read_vector(string key, ref int unsigned values[], input bit percentages = 0);
    string raw;
    string token;
    int index;
    longint unsigned sum;
    if ($value$plusargs({key, "=%s"}, raw)) begin
      token = "";
      index = 0;
      for (int i = 0; i <= raw.len(); i++) begin
        if ((i == raw.len()) || (raw.getc(i) == 44)) begin
          if (index >= values.size())
            `uvm_fatal_context("UART_ARG", {key, ": demasiados elementos"}, reporter)
          values[index] = decimal(token, key);
          index++;
          token = "";
        end else begin
          token = {token, raw.substr(i, i)};
        end
      end
      if (index != values.size())
        `uvm_fatal_context("UART_ARG", {key, ": cantidad de elementos incorrecta"}, reporter)
      origin[key] = "plusarg";
    end else begin
      origin[key] = "default";
    end
    raw = "";
    sum = 0;
    foreach (values[i]) begin
      sum += values[i];
      if (percentages && (values[i] > 100))
        `uvm_fatal_context("UART_ARG", {key, ": porcentaje mayor que 100"}, reporter)
      raw = {raw, (i == 0) ? "" : ",", $sformatf("%0d", values[i])};
    end
    if (!percentages && ((sum == 0) || (sum > 32'hffffffff)))
      `uvm_fatal_context("UART_ARG", {key, ": suma de pesos invalida"}, reporter)
    effective[key] = raw;
  endfunction

  // Keep configuration failures in UVM reporting so the usual report actions still apply
  function void require(bit condition, string message);
    if (!condition)
      `uvm_fatal_context("UART_CFG", message, reporter)
  endfunction

  // Stop at configuration time rather than running with a feature that has no implementation yet
  function void unsupported(int unsigned value, string name);
    if (value != 0)
      `uvm_fatal_context("UART_E2_CAPABILITY", {name, " aun no implementado por los agentes/integracion actuales; usar el perfil plusargs.args"}, reporter)
  endfunction

  // Parse once before creating the environment so every component sees the same validated values
  // Do the capability checks here too -- unsupported settings should fail before traffic starts
  function void parse_plusargs(uvm_report_object context_reporter);
    string args[$];
    string key;
    string raw;
    int equals;
    uvm_cmdline_processor command_line;
    reporter = context_reporter;

    // Read the scalar knobs in groups that match the plan so it is easier to find a setting
    read_uint("UART_LCR_DL_ZERO_PCT", line.dl_zero_pct);
    read_uint("UART_LCR_DL_FAST_MAX", line.dl_fast_max);
    read_uint("UART_LCR_DL_MAX", line.dl_max);
    read_uint("UART_LCR_DL_TAIL_PCT", line.dl_tail_pct);
    read_uint("UART_LCR_BC_PCT", line.bc_pct);
    read_uint("UART_FCR_CLEAR_PCT", ctrl.fcr_clear_pct);
    read_uint("UART_MCR_LOOP_PCT", ctrl.loop_pct);
    read_uint("UART_SW_ITER", sw.n_iter);
    read_uint("UART_SW_TX_BURST_MIN", sw.tx_burst_min);
    read_uint("UART_SW_TX_BURST_MAX", sw.tx_burst_max);
    read_uint("UART_SW_TX_DATA_MIN", sw.tx_data_min);
    read_uint("UART_SW_TX_DATA_MAX", sw.tx_data_max);
    read_uint("UART_SW_SERVICE_DELAY_MIN", sw.service_delay_min);
    read_uint("UART_SW_SERVICE_DELAY_MAX", sw.service_delay_max);
    read_uint("UART_SW_BLIND_READ_PCT", sw.blind_read_pct);
    read_uint("UART_SW_RAND_ACCESS_PCT", sw.rand_access_pct);
    read_uint("UART_SW_RECFG_PCT", sw.recfg_pct);
    read_uint("UART_SW_RST_PCT", sw.rst_pct);
    read_uint("UART_WB_DELAY_MAX", wb.delay_max);
    read_uint("UART_WB_STB_DELAY_MAX", wb.stb_delay_max);
    read_uint("UART_WB_SEL_ODD_PCT", wb.sel_odd_pct);
    read_uint("UART_SER_BURST_MIN", ser.burst_min);
    read_uint("UART_SER_BURST_MAX", ser.burst_max);
    read_uint("UART_SER_DATA_MIN", ser.data_min);
    read_uint("UART_SER_DATA_MAX", ser.data_max);
    read_uint("UART_SER_GAP_MAX", ser.gap_max);
    read_uint("UART_SER_PARITY_ERR_PCT", ser_parity_err_pct);
    read_uint("UART_SER_FRAME_ERR_PCT", ser_frame_err_pct);
    read_uint("UART_SER_BREAK_PCT", ser_break_pct);
    read_uint("UART_SER_STOP2_ERR_PCT", ser_stop2_err_pct);
    read_uint("UART_SER_GLITCH_PCT", ser_glitch_pct);
    read_uint("UART_SER_BAUD_ERR_PCT", ser_baud_err_pct);
    read_uint("UART_SER_BAUD_ERR_MAX", ser_baud_err_max);
    read_uint("UART_MDM_TOGGLE_PCT", mdm_toggle_pct);
    read_uint("UART_RAL_HW_RESET", run_ral_reset);
    read_uint("UART_BUS_TIMEOUT_CYCLES", bus_timeout_cycles);
    // Read the lists separately because they need both length and weight checks
    read_vector("UART_LCR_WLS_WEIGHTS", line.wls_w, 0);
    read_vector("UART_LCR_STB_WEIGHTS", line.stb_w, 0);
    read_vector("UART_LCR_PAR_WEIGHTS", line.par_w, 0);
    read_vector("UART_FCR_TL_WEIGHTS", ctrl.tl_w, 0);
    read_vector("UART_IER_BIT_PCT", ctrl.ier_bit_pct, 1);
    read_vector("UART_MCR_BIT_PCT", ctrl.mcr_bit_pct, 1);
    read_vector("UART_SW_MODE_WEIGHTS", sw.mode_w, 0);

    // An empty waiver value is valid here -- checking only the string conversion can miss it
    // First detect the argument itself and then read whatever follows the equals sign
    key = "UART_SCB_WAIVE_BUGS";
    if ($test$plusargs({key, "="})) begin
      raw = "";
      void'($value$plusargs({key, "=%s"}, raw));
      waive_bugs = raw;
      origin[key] = "plusarg";
    end else begin
      origin[key] = "default";
    end
    effective[key] = waive_bugs;

    // A value can fit its type and still make no sense for the test
    // Check the range pairs, divisor regions and percentages before using them in random picks
    require(sw.n_iter > 0, "UART_SW_ITER debe ser positivo");
    require((sw.tx_burst_min <= sw.tx_burst_max) && (sw.tx_burst_max <= 255), "Rango TX invalido");
    require((ser.burst_min <= ser.burst_max) && (ser.burst_max <= 255), "Rango RX invalido");
    require((sw.tx_data_min <= sw.tx_data_max) && (sw.tx_data_max <= 255), "Rango de datos TX invalido");
    require((ser.data_min <= ser.data_max) && (ser.data_max <= 255), "Rango de datos RX invalido");
    require(sw.service_delay_min <= sw.service_delay_max, "Retraso de servicio invertido");
    require((line.dl_fast_max > 0) && (line.dl_fast_max <= line.dl_max) &&
            (line.dl_max <= 65535), "Rango DL invalido");
    require((line.dl_zero_pct <= 100) && (line.dl_tail_pct <= 100) &&
            (line.dl_zero_pct + line.dl_tail_pct <= 100) &&
            ((line.dl_tail_pct == 0) || (line.dl_fast_max < line.dl_max)), "Distribucion DL invalida");
    require((line.bc_pct <= 100) && (ctrl.fcr_clear_pct <= 100) &&
            (ctrl.loop_pct <= 100) && (sw.blind_read_pct <= 100) &&
            (sw.rand_access_pct <= 100) && (sw.recfg_pct <= 100) &&
            (sw.rst_pct <= 100) && (wb.sel_odd_pct <= 100) &&
            (ser_parity_err_pct <= 100) && (ser_frame_err_pct <= 100) &&
            (ser_break_pct <= 100) && (ser_stop2_err_pct <= 100) &&
            (ser_glitch_pct <= 100) && (ser_baud_err_pct <= 100) &&
            (mdm_toggle_pct <= 100) && (ser_baud_err_max <= 20), "Porcentaje fuera de rango");
    require((run_ral_reset <= 1) && (bus_timeout_cycles > 0), "Control de reset/timeout invalido");

    require(longint'(ser.gap_max) * 16 * line.dl_max <= 32'hffffffff,
            "GAP_MAX por periodo de bit desborda el contador del driver original");
    require(longint'(wb.delay_max) + wb.stb_delay_max + 16 < bus_timeout_cycles,
            "BUS_TIMEOUT_CYCLES debe superar los retardos WB mas el handshake");

    // Catch misspelled UART arguments here -- otherwise a typo could leave a default active unnoticed
    command_line = uvm_cmdline_processor::get_inst();
    void'(command_line.get_plusargs(args));
    foreach (args[i]) begin
      if ((args[i].len() >= 6) && (args[i].substr(0, 5) == "+UART_")) begin
        equals = args[i].len();
        for (int j = 1; j < args[i].len(); j++) begin
          if (args[i].getc(j) == 61) begin
            equals = j;
            break;
          end
        end
        if (equals == args[i].len())
          `uvm_fatal_context("UART_ARG", {"Se requiere NOMBRE=valor: ", args[i]}, reporter)
        key = args[i].substr(1, equals - 1);
        if (!effective.exists(key))
          `uvm_fatal_context("UART_UNKNOWN_ARG", {"Plusarg desconocido: ", key}, reporter)
      end
    end
    // Print defaults too -- the seed by itself is not enough to reproduce a run with different knobs
    foreach (effective[name])
      `uvm_info_context("UART_CFG", $sformatf("%s=%s (%s)", name, effective[name], origin[name]), UVM_LOW, reporter)

    // Keep this list explicit while E2 is incomplete
    // The plusargs file disables these features -- remove a check only when its real support is added
    unsupported(line.bc_pct, "Break TX");
    unsupported(line.dl_zero_pct, "Trafico con DL=0");
    unsupported(ctrl.loop_pct, "Loopback");
    unsupported(sw.mode_w[0], "Servicio por interrupciones");
    unsupported(sw.service_delay_max, "Retraso de servicio con posible overrun");
    unsupported(sw.blind_read_pct, "Lecturas ciegas concurrentes con RX");
    unsupported(sw.rand_access_pct, "Accesos de robustez");
    unsupported(sw.recfg_pct, "Reconfiguracion durante trafico");
    unsupported(sw.rst_pct, "Reset durante trafico");
    unsupported(wb.sel_odd_pct, "Seleccion WB irregular");
    unsupported(ser_parity_err_pct, "Inyeccion PE");
    unsupported(ser_frame_err_pct, "Inyeccion FE");
    unsupported(ser_break_pct, "Break RX");
    unsupported(ser_stop2_err_pct, "Inyeccion STOP2");
    unsupported(ser_glitch_pct, "Glitch RX");
    unsupported(ser_baud_err_pct, "Desajuste de baud");
    unsupported(mdm_toggle_pct, "Estimulo modem");
    require(waive_bugs == "", "En E2 el scoreboard es estricto: usar +UART_SCB_WAIVE_BUGS=");

    // Scale the watchdog with the configured traffic and baud rate
    // A fixed time would kill valid runs with large divisors -- leave extra room for polling and bus work
    // This only bounds a stuck run -- it does not prove that the timing is correct
    timeout_cycles = 10000 + 4 * longint'(sw.n_iter) *
      (longint'(sw.tx_burst_max + ser.burst_max + 64) * 12 * 16 * line.dl_max +
       longint'(ser.burst_max) * (ser.gap_max + 12 * longint'(sw.service_delay_max)) * 16 * line.dl_max);
  endfunction

  // Pick from the total weight and subtract each bucket until the pick falls inside one
  // A zero weight gets no part of the range -- validation already ruled out a zero total
  function int unsigned choose_weight(int unsigned weights[]);
    int unsigned sum;
    int unsigned pick;
    sum = 0;
    foreach (weights[i])
      sum += weights[i];
    pick = $urandom_range(sum - 1, 0);
    foreach (weights[i]) begin
      if (pick < weights[i])
        return i;
      pick -= weights[i];
    end
    return 0;
  endfunction
endclass : uart_env_cfg
