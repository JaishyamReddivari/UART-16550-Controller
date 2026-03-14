`ifndef UART_RAL_TEST_SV
`define UART_RAL_TEST_SV

class uart_ral_test extends uvm_test;
  `uvm_component_utils(uart_ral_test)

  uart_ral_env env;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = uart_ral_env::type_id::create("env", this);
  endfunction

  task run_phase(uvm_phase phase);
    uart_ral_sequence ral_seq;

    phase.raise_objection(this);

    ral_seq = uart_ral_sequence::type_id::create("ral_seq");
    ral_seq.start(env.agent.seqr);

    #5_000_000;

    `uvm_info("RAL_TEST", "Drain complete — dropping objection", UVM_LOW)
    phase.drop_objection(this);
  endtask

endclass

`endif
