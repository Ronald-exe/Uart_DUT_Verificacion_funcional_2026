
class uart_line_cfg extends uvm_object;
  `uvm_object_utils(uart_line_cfg)
  // Bias most runs toward short bit periods without removing slow divisors from the default space -- alex
  int unsigned dl_zero_pct = 1;
  int unsigned dl_fast_max = 16;
  int unsigned dl_max = 65535;
  int unsigned dl_tail_pct = 2;
  // This is the DUT transmit-break control -- ser_break_pct below asks the external source to hold RX low -- alex
  int unsigned bc_pct = 5;
  // Array position is the encoding used by program_uart -- changing this order changes the chosen format
  // WLS is [5,6,7,8], stops [one,extended], parity [none,odd,even,stick-1,stick-0] -- alex
  int unsigned wls_w[] = '{1,1,1,1};
  int unsigned stb_w[] = '{1,1};
  int unsigned par_w[] = '{1,1,1,1,1};
  function new(string name = "uart_line_cfg");
    super.new(name);
  endfunction
endclass : uart_line_cfg

class uart_ctrl_cfg extends uvm_object;
  `uvm_object_utils(uart_ctrl_cfg)
  // Allow FIFO clears during live traffic too -- the reference model now accounts for the discarded entries -- alex
  int unsigned fcr_clear_pct = 10;
  int unsigned loop_pct = 10;
  // Trigger weights select [1,4,8,14] characters -- alex
  int unsigned tl_w[] = '{1,1,1,1};
  // Each bit has its own probability -- these are not mutually exclusive weights and need not sum to 100 -- alex
  int unsigned ier_bit_pct[] = '{50,50,50,50};
  int unsigned mcr_bit_pct[] = '{50,50,50,50};
  function new(string name = "uart_ctrl_cfg");
    super.new(name);
  endfunction
endclass : uart_ctrl_cfg

class uart_sw_cfg extends uvm_object;
  `uvm_object_utils(uart_sw_cfg)
  int unsigned n_iter = 20;
  // Equal endpoints force a count -- 50/50 requests 50 writes, 0/0 disables this source
  // This does not promise 50 delivered bytes if another enabled action clears or overflows the FIFO -- alex
  int unsigned tx_burst_min = 0;
  int unsigned tx_burst_max = 255;
  int unsigned tx_data_min = 0;
  int unsigned tx_data_max = 255;
  // Character times keep a delayed service comparable at different baud rates -- a fixed clock delay would not -- alex
  int unsigned service_delay_min = 0;
  int unsigned service_delay_max = 20;
  int unsigned blind_read_pct = 5;
  int unsigned rand_access_pct = 5;
  int unsigned recfg_pct = 5;
  int unsigned rst_pct = 1;
  // Order is [interrupt-driven,polling] -- a zero weight removes that mode from this run -- alex
  int unsigned mode_w[] = '{1,1};
  function new(string name = "uart_sw_cfg");
    super.new(name);
  endfunction
endclass : uart_sw_cfg

class uart_env_cfg extends uvm_object;
  `uvm_object_utils(uart_env_cfg)
  uart_line_cfg line;
  uart_ctrl_cfg ctrl;
  uart_sw_cfg sw;
  wb_agent_cfg wb;
  ser_agent_cfg ser;
  virtual modem_if mdm_vif;
  // The scoreboard updates these counters on this shared object -- the final test banner reads the same evidence -- alex
  modem_agent_cfg mdm;
  bit waived[1:5];
  longint unsigned observed_checks;
  longint unsigned known_bug_checks;
  int unsigned known_bug_count[1:5];
  // One token protects a whole bank operation, not just one bus item
  // Otherwise RX service could access RBR while another worker has temporarily selected DLL -- alex
  semaphore bus_lock;
  int unsigned ser_parity_err_pct = 5;
  int unsigned ser_frame_err_pct = 5;
  int unsigned ser_break_pct = 3;
  int unsigned ser_stop2_err_pct = 5;
  int unsigned ser_glitch_pct = 3;
  int unsigned ser_baud_err_pct = 5;
  int unsigned ser_baud_err_max = 8;
  int unsigned mdm_toggle_pct = 20;
  // Keep a run watchdog as well as the driver timeout -- sequences can block without any active bus request -- alex
  int unsigned run_ral_reset = 1;
  int unsigned bus_timeout_cycles = 1000;
  longint unsigned timeout_cycles;
  // An explicitly empty value selects strict checking -- it must not fall back to this default list -- alex
  string waive_bugs = "1,2,3,4,5";
  // The seed cannot reproduce a run without its effective knobs -- record defaults as well as overrides -- alex
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
    // Match physical reset before the first observed write -- the standalone serial config starts with DL one -- alex
    ser.burst_max = 255;
    ser.dl = 0;
    mdm = modem_agent_cfg::type_id::create("mdm");
    bus_lock = new(1);
  endfunction

  function int unsigned decimal(string text, string key);
    longint unsigned number;
    number = 0;
    if ((text.len() == 0) || (text.len() > 10))
      `uvm_fatal_context("UART_ARG", {key, ": entero invalido"}, reporter)
    // Do not let an unsigned conversion turn a negative or malformed knob into a plausible positive value -- alex
    for (int i = 0; i < text.len(); i++) begin
      if ((text.getc(i) < 48) || (text.getc(i) > 57))
        `uvm_fatal_context("UART_ARG", {key, ": se requiere un entero no negativo"}, reporter)
      number = number * 10 + text.getc(i) - 48;
    end
    // Accumulate in 64 bits and reject overflow before narrowing to the 32-bit knob type -- alex
    if (number > 64'hffffffff)
      `uvm_fatal_context("UART_ARG", {key, ": entero fuera de rango"}, reporter)
    return int'(number);
  endfunction

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

  function void read_vector(string key, ref int unsigned values[], input bit percentages = 0);
    string raw;
    string token;
    int index;
    longint unsigned sum;
    if ($value$plusargs({key, "=%s"}, raw)) begin
      token = "";
      index = 0;
      // The extra iteration closes the final token without needing a trailing comma
      // A missing or empty entry must fail instead of shifting the meaning of all following weights -- alex
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
    // All-zero bit probabilities are valid -- all-zero selection weights would leave choose_weight no possible choice -- alex
    if (!percentages && ((sum == 0) || (sum > 32'hffffffff)))
      `uvm_fatal_context("UART_ARG", {key, ": suma de pesos invalida"}, reporter)
    effective[key] = raw;
  endfunction

  function void require(bit condition, string message);
    if (!condition)
      `uvm_fatal_context("UART_CFG", message, reporter)
  endfunction

  function bit [4:0] waiver_mask();
    bit [4:0] mask;
    mask = 0;
    for (int i = 1; i <= 5; i++) begin
      // The user-facing list is numbered 1 through 5 -- the packed model switches are bits 0 through 4 -- alex
      mask[i-1] = waived[i];
    end
    return mask;
  endfunction

  function bit bugs_waived(bit [4:0] causes);
    for (int i = 1; i <= 5; i++) begin
      // A comparison can involve more than one cause -- every contributing cause has to be enabled -- alex
      if (causes[i-1] && !waived[i]) begin
        return 0;
      end
    end
    // An empty cause mask is not a known bug and must not become a waiver -- alex
    return |causes;
  endfunction

  function void report_known_bug(bit [4:0] causes, string details, bit force_error = 0);
    for (int i = 1; i <= 5; i++) begin
      if (causes[i-1]) begin
        known_bug_count[i]++;
      end
    end
    // One observation can increment several per-bug counts -- keep a separate total for the number of affected checks -- alex
    known_bug_checks++;
    // Recognition and permission are different -- force_error preserves a known-but-unwaived failure -- alex
    if (!force_error && bugs_waived(causes)) begin
      `uvm_warning_context("UART_KNOWN_BUG", details, reporter)
    end else begin
      `uvm_error_context("UART_KNOWN_BUG", details, reporter)
    end
  endfunction

  function void parse_plusargs(uvm_report_object context_reporter);
    string args[$];
    string key;
    string raw;
    int equals;
    uvm_cmdline_processor command_line;
    reporter = context_reporter;

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
    read_vector("UART_LCR_WLS_WEIGHTS", line.wls_w, 0);
    read_vector("UART_LCR_STB_WEIGHTS", line.stb_w, 0);
    read_vector("UART_LCR_PAR_WEIGHTS", line.par_w, 0);
    read_vector("UART_FCR_TL_WEIGHTS", ctrl.tl_w, 0);
    read_vector("UART_IER_BIT_PCT", ctrl.ier_bit_pct, 1);
    read_vector("UART_MCR_BIT_PCT", ctrl.mcr_bit_pct, 1);
    read_vector("UART_SW_MODE_WEIGHTS", sw.mode_w, 0);

    // +UART_SCB_WAIVE_BUGS= is intentional strict mode
    // A %s conversion alone can miss the empty value and accidentally retain the default waivers -- alex
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

    // Check relationships too -- individually valid endpoints can still define an empty random range -- alex
    require(sw.n_iter > 0, "UART_SW_ITER debe ser positivo");
    require((sw.tx_burst_min <= sw.tx_burst_max) && (sw.tx_burst_max <= 255), "Rango TX invalido");
    require((ser.burst_min <= ser.burst_max) && (ser.burst_max <= 255), "Rango RX invalido");
    require((sw.tx_data_min <= sw.tx_data_max) && (sw.tx_data_max <= 255), "Rango de datos TX invalido");
    require((ser.data_min <= ser.data_max) && (ser.data_max <= 255), "Rango de datos RX invalido");
    require(sw.service_delay_min <= sw.service_delay_max, "Retraso de servicio invertido");
    require((line.dl_fast_max > 0) && (line.dl_fast_max <= line.dl_max) &&
            (line.dl_max <= 65535), "Rango DL invalido");
    // Zero, fast and tail are branches of one draw -- zero and tail probabilities share the same 100 percent budget
    // If the tail is enabled there must be at least one divisor strictly above the fast range -- alex
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
    // The request timer includes the intentional driver delays -- leave room for those before calling ACK late -- alex
    require(longint'(wb.delay_max) + wb.stb_delay_max + 16 < bus_timeout_cycles,
            "BUS_TIMEOUT_CYCLES debe superar los retardos WB mas el handshake");

    // Without this pass a misspelled +UART_ knob silently leaves the default active -- alex
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
    foreach (effective[name])
      `uvm_info_context("UART_CFG", $sformatf("%s=%s (%s)", name, effective[name], origin[name]), UVM_LOW, reporter)

    // Start strict, then enable only listed bug numbers -- no token may stand for an unclassified discrepancy -- alex
    foreach (waived[i]) begin
      waived[i] = 0;
    end
    if (waive_bugs != "") begin
      string token;
      int unsigned number;
      token = "";
      for (int i = 0; i <= waive_bugs.len(); i++) begin
        if ((i == waive_bugs.len()) || (waive_bugs.getc(i) == 44)) begin
          number = decimal(token, "UART_SCB_WAIVE_BUGS");
          require((number >= 1) && (number <= 5), "Only BUG-01 to BUG-05 can be waived");
          waived[number] = 1;
          token = "";
        end else begin
          token = {token, waive_bugs.substr(i, i)};
        end
      end
    end
    // Propagate the timeout and reset handles after parsing -- use the existing interfaces for all agents -- alex
    wb.timeout_cycles = bus_timeout_cycles;
    ser.reset_vif = wb.vif;
    mdm.vif = mdm_vif;
    mdm.reset_vif = wb.vif;
    mdm.toggle_pct = mdm_toggle_pct;

    // Large divisors and delayed service can make a legal run much longer than a normal burst
    // Raw register writes can also exceed the setup DL_MAX -- budget for 65535 when those accesses are enabled
    // This is a hang guard, not a baud correctness check -- alex
    timeout_cycles = 10000 + 4 * longint'(sw.n_iter) *
      (longint'(sw.tx_burst_max + ser.burst_max + 64) * 12 * 16 * ((sw.rand_access_pct == 0) ? line.dl_max : 65535) +
       longint'(ser.burst_max) * (ser.gap_max + 12 * longint'(sw.service_delay_max)) * 16 * ((sw.rand_access_pct == 0) ? line.dl_max : 65535));
  endfunction

  function int unsigned choose_weight(int unsigned weights[]);
    int unsigned sum;
    int unsigned pick;
    sum = 0;
    foreach (weights[i])
      sum += weights[i];
    // Treat weights as interval sizes, not percentages -- subtracting a zero bucket gives it no chance of selection -- alex
    pick = $urandom_range(sum - 1, 0);
    foreach (weights[i]) begin
      if (pick < weights[i])
        return i;
      pick -= weights[i];
    end
    return 0;
  endfunction
endclass : uart_env_cfg
