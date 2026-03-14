`ifndef UART_REG_MONITOR_SV
`define UART_REG_MONITOR_SV

class uart_reg_monitor extends uvm_monitor;
  `uvm_component_utils(uart_reg_monitor)

  virtual uart_if vif;
  uvm_analysis_port #(uart_reg_txn) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    if (!uvm_config_db#(virtual uart_if)::get(this, "", "vif", vif))
      `uvm_fatal("REG_MON", "Virtual interface not set")
  endfunction

  task run_phase(uvm_phase phase);
    uart_reg_txn txn;

    @(negedge vif.rst);
    repeat (2) @(posedge vif.clk);

    forever begin
      @(posedge vif.clk);

      if (vif.wr || vif.rd) begin
        txn       = uart_reg_txn::type_id::create("reg_txn");
        txn.addr  = vif.addr;
        txn.wr    = vif.wr;
        txn.rd    = vif.rd;
        txn.wdata = vif.din;
        txn.data  = vif.wr ? vif.din : vif.dout;

        ap.write(txn);

        `uvm_info("REG_MON", $sformatf("%s addr=0x%0h data=0x%0h",
                  vif.wr ? "WR" : "RD", txn.addr, txn.data), UVM_HIGH)
      end
    end
  endtask

endclass

`endif
