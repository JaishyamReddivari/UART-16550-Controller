`ifndef UART_RAL_DRIVER_SV
`define UART_RAL_DRIVER_SV

class uart_ral_driver extends uart_driver;
  `uvm_component_utils(uart_ral_driver)

  function new(string name, uvm_component parent);
    super.new(name, parent);
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

        // WRITE
        if (reg_txn.wr) begin
          @(posedge vif.clk);
          vif.addr <= reg_txn.addr;
          vif.din  <= reg_txn.wdata;
          vif.wr   <= 1;
          vif.rd   <= 0;
          @(posedge vif.clk);
          vif.wr <= 0;

          if (reg_txn.addr == 3'h0)
            repeat (FRAME_WAIT) @(posedge vif.clk);
          else
            repeat (5) @(posedge vif.clk);
        end

        // READ
        else if (reg_txn.rd) begin
          @(posedge vif.clk);
          vif.addr <= reg_txn.addr;
          vif.rd   <= 1;
          vif.wr   <= 0;

          @(posedge vif.clk);
          vif.rd <= 0;

          @(posedge vif.clk);
          #1;
          reg_txn.data = vif.dout;

          `uvm_info("RAL_DRV", $sformatf("READ addr=0x%0h dout=0x%0h",
                    reg_txn.addr, reg_txn.data), UVM_HIGH)

          repeat (3) @(posedge vif.clk);
        end

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

`endif
