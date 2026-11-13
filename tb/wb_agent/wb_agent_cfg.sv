class  wb_agent_cfg extends uvm_object;
//Se encarga de guardar los cables que lee el driver el monitor y las secuencias

//Registramos en la fabrica
`uvm_object_utils(wb_agent_cfg)

//Campos de acceso para las senales que se van a leer
virtual wb_if vif; // Son los cables que se guardan en una interfaz virtual para luego utilizarlo como handle el el config_db utilizara para guiar el recorrido

int unsigned delay_max = 5;     //maximo de ciclos libres entre acceso
int unsigned stb_delay_max = 3;  //maximo de cliclos entre cyc = 1 y stb = 1
int unsigned sel_odd_pct = 2;    //porcentaje de acceso con sel raros

function new(string name = "wb_agent_cfg");
    super.new(name);
endfunction

endclass :  wb_agent_cfg