`ifndef UART_RAL_SEQUENCE_SV
`define UART_RAL_SEQUENCE_SV

class uart_ral_sequence extends uvm_sequence #(uart_txn);
  `uvm_object_utils(uart_ral_sequence)

  uart_reg_block  reg_block;

  function new(string name = "uart_ral_sequence");
    super.new(name);
  endfunction

  task body();
    uvm_status_e  status;
    uvm_reg_data_t rdata;

    if (!uvm_config_db #(uart_reg_block)::get(null, get_full_name(), "reg_block", reg_block))
      if (!uvm_config_db #(uart_reg_block)::get(null, "*", "reg_block", reg_block))
        `uvm_fatal("RAL_SEQ", "Could not find reg_block in config_db")

    `uvm_info("RAL_SEQ", "=== Starting RAL-based UART configuration ===", UVM_LOW)

    // Phase 1: Set DLAB=1, configure baud divisor using map_dlab1
    `uvm_info("RAL_SEQ", "Setting DLAB=1 for baud rate configuration", UVM_LOW)
    reg_block.LCR.write(status, 8'h83, .map(reg_block.map_dlab0));

    `uvm_info("RAL_SEQ", "Writing DLL=0x0A, DLM=0x00 via map_dlab1", UVM_LOW)
    reg_block.DLL.write(status, 8'h0A, .map(reg_block.map_dlab1));
    reg_block.DLM.write(status, 8'h00, .map(reg_block.map_dlab1));

    reg_block.DLL.read(status, rdata, .map(reg_block.map_dlab1));
    if (rdata != 8'h0A)
      `uvm_error("RAL_SEQ", $sformatf("DLL read-back mismatch: exp=0x0A act=0x%0h", rdata))
    else
      `uvm_info("RAL_SEQ", $sformatf("DLL read-back OK: 0x%0h", rdata), UVM_LOW)

    // Phase 2: Clear DLAB, enable FIFO — switch to map_dlab0
    `uvm_info("RAL_SEQ", "Clearing DLAB, switching to map_dlab0", UVM_LOW)
    reg_block.LCR.write(status, 8'h03, .map(reg_block.map_dlab1));

    reg_block.LCR.read(status, rdata, .map(reg_block.map_dlab0));
    if (rdata != 8'h03)
      `uvm_error("RAL_SEQ", $sformatf("LCR read-back mismatch: exp=0x03 act=0x%0h", rdata))
    else
      `uvm_info("RAL_SEQ", $sformatf("LCR read-back OK: 0x%0h", rdata), UVM_LOW)

    reg_block.FCR.write(status, 8'h01, .map(reg_block.map_dlab0));

    // Phase 3: SCR write/read-back test (simple RW register)
    `uvm_info("RAL_SEQ", "SCR register write/read-back test", UVM_LOW)
    reg_block.SCR.write(status, 8'hA5, .map(reg_block.map_dlab0));
    reg_block.SCR.read(status, rdata, .map(reg_block.map_dlab0));
    if (rdata != 8'hA5)
      `uvm_error("RAL_SEQ", $sformatf("SCR read-back mismatch: exp=0xA5 act=0x%0h", rdata))
    else
      `uvm_info("RAL_SEQ", $sformatf("SCR read-back OK: 0x%0h", rdata), UVM_LOW)

    // Phase 4: Read LSR (volatile, read-only)
    reg_block.LSR.read(status, rdata, .map(reg_block.map_dlab0));
    `uvm_info("RAL_SEQ", $sformatf("LSR = 0x%0h (thre=%0b temt=%0b dr=%0b)",
              rdata, rdata[5], rdata[6], rdata[0]), UVM_LOW)

    // Phase 5: Transmit data via THR using RAL
    `uvm_info("RAL_SEQ", "Transmitting 10 bytes via THR (RAL writes)", UVM_LOW)
    for (int i = 0; i < 10; i++) begin
      reg_block.THR.write(status, i[7:0], .map(reg_block.map_dlab0));
    end

    `uvm_info("RAL_SEQ", "=== RAL sequence complete ===", UVM_LOW)
  endtask

endclass

`endif
