`timescale 1ns/1ps
`include "uvm_macros.svh"
import uvm_pkg::*;

// Interface
interface uart_if (input bit clk);
  logic        rst;
  logic        wr;
  logic        rd;
  logic [2:0]  addr;
  logic [7:0]  din;
  logic [7:0]  dout;
  logic        tx;
  logic        rx;
endinterface

// Base Transaction
class uart_txn extends uvm_sequence_item;
  rand bit [7:0] data;
  rand bit       tx_start;
  `uvm_object_utils_begin(uart_txn)
    `uvm_field_int(data,     UVM_DEFAULT)
    `uvm_field_int(tx_start, UVM_DEFAULT)
  `uvm_object_utils_end
  function new(string name = "uart_txn");
    super.new(name);
  endfunction
endclass

// Extended Transaction
class uart_reg_txn extends uart_txn;
  rand bit [2:0] addr;
  rand bit [7:0] wdata;
  rand bit       wr;
  rand bit       rd;
  `uvm_object_utils_begin(uart_reg_txn)
    `uvm_field_int(addr,  UVM_DEFAULT)
    `uvm_field_int(wdata, UVM_DEFAULT)
    `uvm_field_int(wr,    UVM_DEFAULT)
    `uvm_field_int(rd,    UVM_DEFAULT)
  `uvm_object_utils_end
  function new(string name = "uart_reg_txn");
    super.new(name);
  endfunction
endclass

// Sequence
class uart_sequence extends uvm_sequence #(uart_txn);
  `uvm_object_utils(uart_sequence)
  function new(string name = "uart_sequence");
    super.new(name);
  endfunction

  task write_reg(bit [2:0] a, bit [7:0] d);
    uart_reg_txn t = uart_reg_txn::type_id::create("t");
    start_item(t);
    t.addr = a; t.wdata = d; t.data = d; t.wr = 1; t.rd = 0;
    finish_item(t);
  endtask

  task body();
    uart_reg_txn t;

    write_reg(3'h3, 8'h83);   // LCR: DLAB=1, 8N1
    write_reg(3'h0, 8'h0A);   // DLL = 10
    write_reg(3'h1, 8'h00);   // DLM = 0
    write_reg(3'h3, 8'h03);   // LCR: DLAB=0, 8N1
    write_reg(3'h2, 8'h01);   // FCR: FIFO enable

    repeat (500) begin
      t = uart_reg_txn::type_id::create("t");
      start_item(t);
      assert(t.randomize() with { addr == 3'h0; wr == 1; rd == 0; });
      t.data = t.wdata;
      finish_item(t);
    end
  endtask
endclass

// Driver
class uart_driver extends uvm_driver #(uart_txn);
  `uvm_component_utils(uart_driver)
  virtual uart_if vif;
  localparam int FRAME_WAIT = 1800;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    if (!uvm_config_db#(virtual uart_if)::get(this, "", "vif", vif))
      `uvm_fatal("DRV", "Virtual interface not set")
  endfunction

  task run_phase(uvm_phase phase);
    uart_txn     base_txn;
    uart_reg_txn reg_txn;

    vif.wr <= 0; vif.rd <= 0; vif.addr <= 0; vif.din <= 0;

    @(negedge vif.rst);
    repeat (5) @(posedge vif.clk);

    forever begin
      seq_item_port.get_next_item(base_txn);

      if ($cast(reg_txn, base_txn)) begin
        @(posedge vif.clk);
        vif.addr <= reg_txn.addr;
        vif.din  <= reg_txn.wdata;
        vif.wr   <= reg_txn.wr;
        vif.rd   <= reg_txn.rd;
        @(posedge vif.clk);
        vif.wr <= 0; vif.rd <= 0;

        if (reg_txn.wr && reg_txn.addr == 3'h0)
          repeat (FRAME_WAIT) @(posedge vif.clk);
        else
          repeat (5) @(posedge vif.clk);
      end else begin
        @(posedge vif.clk);
        vif.addr <= 3'h0; vif.din <= base_txn.data; vif.wr <= 1;
        @(posedge vif.clk);
        vif.wr <= 0;
        repeat (FRAME_WAIT) @(posedge vif.clk);
      end

      seq_item_port.item_done();
    end
  endtask
endclass

// TX Monitor
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
      `uvm_fatal("TX_MON", "Virtual interface not set")
  endfunction

  task run_phase(uvm_phase phase);
    uart_txn txn;
    bit config_done = 0;
    @(negedge vif.rst);
    forever begin
      @(posedge vif.clk);
      if (vif.wr && vif.addr == 3'h2) config_done = 1;
      if (config_done && vif.wr && vif.addr == 3'h0) begin
        txn = uart_txn::type_id::create("txn");
        txn.data = vif.din;
        tx_ap.write(txn);
      end
    end
  endtask
endclass

// RX Monitor
class uart_rx_monitor extends uvm_monitor;
  `uvm_component_utils(uart_rx_monitor)
  virtual uart_if vif;
  uvm_analysis_port #(uart_txn) rx_ap;
  localparam int BIT_CLKS = 176;
  localparam int HALF_BIT = 88;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    rx_ap = new("rx_ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    if (!uvm_config_db#(virtual uart_if)::get(this, "", "vif", vif))
      `uvm_fatal("RX_MON", "Virtual interface not set")
  endfunction

  task run_phase(uvm_phase phase);
    uart_txn txn;
    logic [7:0] rx_byte;
    @(negedge vif.rst);
    forever begin
      @(negedge vif.rx);
      repeat (HALF_BIT) @(posedge vif.clk);
      if (vif.rx !== 1'b0) continue;
      repeat (HALF_BIT) @(posedge vif.clk);
      for (int i = 0; i < 8; i++) begin
        repeat (HALF_BIT) @(posedge vif.clk);
        rx_byte[i] = vif.rx;
        repeat (HALF_BIT) @(posedge vif.clk);
      end
      repeat (BIT_CLKS) @(posedge vif.clk);
      txn = uart_txn::type_id::create("txn");
      txn.data = rx_byte;
      rx_ap.write(txn);
    end
  endtask
endclass

// Scoreboard
`uvm_analysis_imp_decl(_rx)

class uart_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(uart_scoreboard)
  uvm_analysis_imp    #(uart_txn, uart_scoreboard) tx_imp;
  uvm_analysis_imp_rx #(uart_txn, uart_scoreboard) rx_imp;
  mailbox #(uart_txn) exp_q;
  int match_cnt = 0, mismatch_cnt = 0;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    tx_imp = new("tx_imp", this);
    rx_imp = new("rx_imp", this);
    exp_q  = new();
  endfunction

  function void write(uart_txn txn);
    uart_txn c = uart_txn::type_id::create("c");
    c.data = txn.data;
    void'(exp_q.try_put(c));
    `uvm_info("SCO", $sformatf("Expected TX: 0x%0h", txn.data), UVM_MEDIUM)
  endfunction

  function void write_rx(uart_txn txn);
    uart_txn exp;
    if (!exp_q.try_get(exp)) begin
      `uvm_error("SCO", $sformatf("RX 0x%0h — no matching TX", txn.data))
      return;
    end
    if (txn.data !== exp.data) begin
      `uvm_error("SCO", $sformatf("MISMATCH EXP=0x%0h ACT=0x%0h", exp.data, txn.data))
      mismatch_cnt++;
    end else begin
      `uvm_info("SCO", $sformatf("MATCH 0x%0h", txn.data), UVM_LOW)
      match_cnt++;
    end
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info("SCO", $sformatf("========== Matches: %0d  Mismatches: %0d ==========", match_cnt, mismatch_cnt), UVM_LOW)
    if (exp_q.num() > 0)
      `uvm_warning("SCO", $sformatf("%0d TX items never received on RX", exp_q.num()))
  endfunction
endclass

// Agent
class uart_agent extends uvm_agent;
  `uvm_component_utils(uart_agent)
  uart_driver     drv;
  uart_tx_monitor tx_mon;
  uart_rx_monitor rx_mon;
  uvm_sequencer #(uart_txn) seqr;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    drv    = uart_driver     ::type_id::create("drv",    this);
    tx_mon = uart_tx_monitor ::type_id::create("tx_mon", this);
    rx_mon = uart_rx_monitor ::type_id::create("rx_mon", this);
    seqr   = uvm_sequencer#(uart_txn)::type_id::create("seqr", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    drv.seq_item_port.connect(seqr.seq_item_export);
  endfunction
endclass

// Environment
class uart_env extends uvm_env;
  `uvm_component_utils(uart_env)
  uart_agent      agent;
  uart_scoreboard sb;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    agent = uart_agent     ::type_id::create("agent", this);
    sb    = uart_scoreboard::type_id::create("sb",    this);
  endfunction

  function void connect_phase(uvm_phase phase);
    agent.tx_mon.tx_ap.connect(sb.tx_imp);
    agent.rx_mon.rx_ap.connect(sb.rx_imp);
  endfunction
endclass

// Test
class uart_test extends uvm_test;
  `uvm_component_utils(uart_test)
  uart_env env;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    env = uart_env::type_id::create("env", this);
  endfunction

  task run_phase(uvm_phase phase);
    uart_sequence seq;
    phase.raise_objection(this);

    seq = uart_sequence::type_id::create("seq");
    seq.start(env.agent.seqr);

    // Drain: 500 frames × 1800 clk/frame × 10ns = 9 ms + margin
    #10_000_000;

    `uvm_info("TEST", "All frames transmitted — drain complete", UVM_LOW)
    phase.drop_objection(this);
  endtask
endclass

// TB Top
module tb_top;

  bit clk = 0;
  always #5 clk = ~clk;

  uart_if vif(clk);

  all_mod dut (
    .clk  (clk),
    .rst  (vif.rst),
    .wr   (vif.wr),
    .rd   (vif.rd),
    .rx   (vif.rx),
    .addr (vif.addr),
    .din  (vif.din),
    .tx   (vif.tx),
    .dout (vif.dout)
  );

  assign vif.rx = vif.tx;

  initial begin
    vif.rst  = 1;
    vif.wr   = 0;
    vif.rd   = 0;
    vif.addr = 0;
    vif.din  = 0;
    #100 vif.rst = 0;
  end

  initial begin
    uvm_config_db#(virtual uart_if)::set(null, "*", "vif", vif);
    run_test("uart_test");
  end

endmodule
