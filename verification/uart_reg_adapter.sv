`ifndef UART_REG_ADAPTER_SV
`define UART_REG_ADAPTER_SV

class uart_reg_adapter extends uvm_reg_adapter;
  `uvm_object_utils(uart_reg_adapter)

  function new(string name = "uart_reg_adapter");
    super.new(name);

    supports_byte_enable = 0;
    provides_responses   = 0;
  endfunction

  virtual function uvm_sequence_item reg2bus(const ref uvm_reg_bus_op rw);
    uart_reg_txn txn = uart_reg_txn::type_id::create("txn");

    txn.addr  = rw.addr[2:0];
    txn.wdata = rw.data[7:0];
    txn.data  = rw.data[7:0];

    if (rw.kind == UVM_WRITE) begin
      txn.wr = 1;
      txn.rd = 0;
    end else begin
      txn.wr = 0;
      txn.rd = 1;
    end

    return txn;
  endfunction

  virtual function void bus2reg(uvm_sequence_item bus_item,
                                ref uvm_reg_bus_op rw);
    uart_reg_txn txn;

    if (!$cast(txn, bus_item)) begin
      `uvm_fatal("ADAPTER", "bus2reg cast failed — expected uart_reg_txn")
      return;
    end

    rw.addr   = {13'b0, txn.addr};
    rw.kind   = txn.wr ? UVM_WRITE : UVM_READ;
    rw.status = UVM_IS_OK;

    if (txn.wr)
      rw.data = {24'b0, txn.wdata};
    else
      rw.data = {24'b0, txn.data};
  endfunction

endclass

`endif
