`timescale 1ns/1ps
`include "uvm_macros.svh"
import uvm_pkg::*;

//====================================================
// UART Interface
//====================================================
interface uart_if(input bit clk);

  logic rst;

  // TX side
  logic tx_start;
  logic [7:0] tx_data;
  logic tx_busy;
  logic txd;

  // RX side
  logic rxd;
  logic [7:0] rx_data;
  logic rx_valid;

endinterface

//====================================================
// Transaction
//====================================================
class uart_txn extends uvm_sequence_item;

  rand bit [7:0] data;
  rand bit       tx_start;

  `uvm_object_utils_begin(uart_txn)
    `uvm_field_int(data, UVM_DEFAULT)
    `uvm_field_int(tx_start, UVM_DEFAULT)
  `uvm_object_utils_end

  function new(string name="uart_txn");
    super.new(name);
  endfunction

endclass

//====================================================
// Sequence
//====================================================
class uart_sequence extends uvm_sequence #(uart_txn);
  `uvm_object_utils(uart_sequence)

  function new(string name="uart_sequence");
    super.new(name);
  endfunction

  task body();
    uart_txn txn;
    repeat (500) begin
      txn = uart_txn::type_id::create("txn");
      start_item(txn);
      assert(txn.randomize() with { tx_start == 1; });
      finish_item(txn);
    end
  endtask

endclass

//====================================================
// Driver
//====================================================
class uart_driver extends uvm_driver #(uart_txn);
  `uvm_component_utils(uart_driver)

  virtual uart_if vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    if (!uvm_config_db#(virtual uart_if)::get(this, "", "vif", vif))
      `uvm_fatal("DRV", "Virtual interface not set");
  endfunction

  task run_phase(uvm_phase phase);
    uart_txn txn;
    forever begin
      seq_item_port.get_next_item(txn);

      vif.tx_data  <= txn.data;
      vif.tx_start <= 1;
      @(posedge vif.clk);
      vif.tx_start <= 0;

      seq_item_port.item_done();
    end
  endtask

endclass

//====================================================
// TX Monitor (Expected data)
//====================================================
class uart_tx_monitor extends uvm_monitor;
  `uvm_component_utils(uart_tx_monitor)

  virtual uart_if vif;
  uvm_analysis_port #(uart_txn) tx_ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    tx_ap = new("tx_ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    if (!uvm_config_db#(virtual uart_if)::get(this, "", "vif", vif))
      `uvm_fatal("TX_MON", "Virtual interface not set");
  endfunction

  task run_phase(uvm_phase phase);
    uart_txn txn;
    forever begin
      @(posedge vif.clk);
      if (vif.tx_start) begin
        txn = uart_txn::type_id::create("txn");
        txn.data = vif.tx_data;
        tx_ap.write(txn);
      end
    end
  endtask

endclass

//====================================================
// RX Monitor (Actual data)
//====================================================
class uart_rx_monitor extends uvm_monitor;
  `uvm_component_utils(uart_rx_monitor)

  virtual uart_if vif;
  uvm_analysis_port #(uart_txn) rx_ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    rx_ap = new("rx_ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    if (!uvm_config_db#(virtual uart_if)::get(this, "", "vif", vif))
      `uvm_fatal("RX_MON", "Virtual interface not set");
  endfunction

  task run_phase(uvm_phase phase);
    uart_txn txn;
    forever begin
      @(posedge vif.rx_valid);
      txn = uart_txn::type_id::create("txn");
      txn.data = vif.rx_data;
      rx_ap.write(txn);
    end
  endtask

endclass

//====================================================
// Scoreboard
//====================================================
`uvm_analysis_imp_decl(_rx)

class uart_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(uart_scoreboard)

  uvm_analysis_imp #(uart_txn, uart_scoreboard)    tx_imp;
  uvm_analysis_imp_rx #(uart_txn, uart_scoreboard) rx_imp;

  mailbox #(uart_txn) exp_q;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    tx_imp = new("tx_imp", this);
    rx_imp = new("rx_imp", this);
    exp_q  = new();
  endfunction

  function void write(uart_txn txn);
    uart_txn copy;
    copy = uart_txn::type_id::create("copy");
    copy.data = txn.data;
    exp_q.put(copy);
    `uvm_info("SB", $sformatf("Expected TX: 0x%0h", txn.data), UVM_LOW)
  endfunction

  function void write_rx(uart_txn txn);
    uart_txn exp;
    if (!exp_q.try_get(exp)) begin
      `uvm_error("SB", "RX received with no expected TX")
      return;
    end

    if (txn.data !== exp.data)
      `uvm_error("SB",
        $sformatf("MISMATCH! EXP=0x%0h ACT=0x%0h",
                  exp.data, txn.data))
    else
      `uvm_info("SB",
        $sformatf("MATCH 0x%0h", txn.data),
        UVM_LOW)
  endfunction

endclass

//====================================================
// Agent
//====================================================
class uart_agent extends uvm_agent;
  `uvm_component_utils(uart_agent)

  uart_driver      drv;
  uart_tx_monitor  tx_mon;
  uart_rx_monitor  rx_mon;
  uvm_sequencer #(uart_txn) seqr;
  
  function new(string name, uvm_component parent);
  super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    drv    = uart_driver     ::type_id::create("drv", this);
    tx_mon = uart_tx_monitor ::type_id::create("tx_mon", this);
    rx_mon = uart_rx_monitor ::type_id::create("rx_mon", this);
    seqr   = uvm_sequencer#(uart_txn)::type_id::create("seqr", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    drv.seq_item_port.connect(seqr.seq_item_export);
  endfunction

endclass

//====================================================
// Environment
//====================================================
class uart_env extends uvm_env;
  `uvm_component_utils(uart_env)

  uart_agent      agent;
  uart_scoreboard sb;

  function void build_phase(uvm_phase phase);
    agent = uart_agent     ::type_id::create("agent", this);
    sb    = uart_scoreboard::type_id::create("sb", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    agent.tx_mon.tx_ap.connect(sb.tx_imp);
    agent.rx_mon.rx_ap.connect(sb.rx_imp);
  endfunction

endclass

//====================================================
// Test
//====================================================
class uart_test extends uvm_test;
  `uvm_component_utils(uart_test)

  uart_env env;
  uart_sequence seq;
  
  function new(string name, uvm_component parent);
  super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    env = uart_env::type_id::create("env", this);
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);

    seq = uart_sequence::type_id::create("seq");
    seq.start(env.agent.seqr);

    #100000;
    phase.drop_objection(this);
  endtask

endclass

//====================================================
// Top Module
//====================================================
module tb_top;

  bit clk = 0;
  always #5 clk = ~clk;

  uart_if vif(clk);

  // DUT
  all_mod dut (
    .clk      (clk),
    .rst      (vif.rst),
    .tx_data  (vif.tx_data),
    .tx_start (vif.tx_start),
    .txd      (vif.txd),
    .rxd      (vif.rxd),
    .rx_data  (vif.rx_data),
    .rx_valid (vif.rx_valid)
  );

  initial begin
    vif.rst = 1;
    #20 vif.rst = 0;
  end

  initial begin
    uvm_config_db#(virtual uart_if)::set(null, "*", "vif", vif);
    run_test("uart_test");
  end

endmodule