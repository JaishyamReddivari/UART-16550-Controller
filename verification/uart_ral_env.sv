`ifndef UART_RAL_ENV_SV
`define UART_RAL_ENV_SV

class uart_ral_env extends uvm_env;
  `uvm_component_utils(uart_ral_env)

  uart_agent        agent;
  uart_scoreboard   sb;

  uart_reg_block    reg_block;
  uart_reg_adapter  reg_adapter;
  uart_reg_monitor  reg_monitor;

  uvm_reg_predictor #(uart_reg_txn) reg_predictor;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    uart_driver::type_id::set_type_override(uart_ral_driver::get_type());

    agent = uart_agent     ::type_id::create("agent", this);
    sb    = uart_scoreboard::type_id::create("sb",    this);

    reg_block = uart_reg_block::type_id::create("reg_block");
    reg_block.build();

    reg_adapter = uart_reg_adapter::type_id::create("reg_adapter");

    reg_monitor = uart_reg_monitor::type_id::create("reg_monitor", this);

    reg_predictor = uvm_reg_predictor #(uart_reg_txn)::type_id::create("reg_predictor", this);

    uvm_config_db #(uart_reg_block)::set(this, "*", "reg_block", reg_block);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);

    agent.tx_mon.tx_ap.connect(sb.tx_imp);
    agent.rx_mon.rx_ap.connect(sb.rx_imp);

    reg_block.map_dlab0.set_sequencer(agent.seqr, reg_adapter);
    reg_block.map_dlab1.set_sequencer(agent.seqr, reg_adapter);

    reg_predictor.map     = reg_block.map_dlab0;
    reg_predictor.adapter = reg_adapter;

    reg_monitor.ap.connect(reg_predictor.bus_in);
  endfunction

endclass

`endif
