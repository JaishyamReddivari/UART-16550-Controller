`ifndef UART_RAL_PKG_SV
`define UART_RAL_PKG_SV

package uart_ral_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  class uart_reg_rbr extends uvm_reg;
    `uvm_object_utils(uart_reg_rbr)

    rand uvm_reg_field data;

    function new(string name = "uart_reg_rbr");
      super.new(name, 8, UVM_NO_COVERAGE);
    endfunction

    virtual function void build();
      data = uvm_reg_field::type_id::create("data");
      data.configure(this,   8,    0,   "RO",   1,        8'h00, 1,         0,       0);
    endfunction
  endclass

  class uart_reg_thr extends uvm_reg;
    `uvm_object_utils(uart_reg_thr)

    rand uvm_reg_field data;

    function new(string name = "uart_reg_thr");
      super.new(name, 8, UVM_NO_COVERAGE);
    endfunction

    virtual function void build();
      data = uvm_reg_field::type_id::create("data");
      data.configure(this, 8, 0, "WO", 0, 8'h00, 1, 1, 0);
    endfunction
  endclass

  class uart_reg_dll extends uvm_reg;
    `uvm_object_utils(uart_reg_dll)

    rand uvm_reg_field data;

    function new(string name = "uart_reg_dll");
      super.new(name, 8, UVM_NO_COVERAGE);
    endfunction

    virtual function void build();
      data = uvm_reg_field::type_id::create("data");
      data.configure(this, 8, 0, "RW", 0, 8'h00, 1, 1, 0);
    endfunction
  endclass

  class uart_reg_dlm extends uvm_reg;
    `uvm_object_utils(uart_reg_dlm)

    rand uvm_reg_field data;

    function new(string name = "uart_reg_dlm");
      super.new(name, 8, UVM_NO_COVERAGE);
    endfunction

    virtual function void build();
      data = uvm_reg_field::type_id::create("data");
      data.configure(this, 8, 0, "RW", 0, 8'h00, 1, 1, 0);
    endfunction
  endclass

  class uart_reg_fcr extends uvm_reg;
    `uvm_object_utils(uart_reg_fcr)

    rand uvm_reg_field ena;
    rand uvm_reg_field rx_rst;
    rand uvm_reg_field tx_rst;
    rand uvm_reg_field dma_mode;
    rand uvm_reg_field reserved;
    rand uvm_reg_field rx_trigger;

    function new(string name = "uart_reg_fcr");
      super.new(name, 8, UVM_NO_COVERAGE);
    endfunction

    virtual function void build();
      ena        = uvm_reg_field::type_id::create("ena");
      rx_rst     = uvm_reg_field::type_id::create("rx_rst");
      tx_rst     = uvm_reg_field::type_id::create("tx_rst");
      dma_mode   = uvm_reg_field::type_id::create("dma_mode");
      reserved   = uvm_reg_field::type_id::create("reserved");
      rx_trigger = uvm_reg_field::type_id::create("rx_trigger");

      ena       .configure(this,  1,    0,   "WO",   0,        1'b0,  1,         1,    0);
      rx_rst    .configure(this,  1,    1,   "WO",   0,        1'b0,  1,         1,    0);
      tx_rst    .configure(this,  1,    2,   "WO",   0,        1'b0,  1,         1,    0);
      dma_mode  .configure(this,  1,    3,   "WO",   0,        1'b0,  1,         1,    0);
      reserved  .configure(this,  2,    4,   "WO",   0,        2'b00, 1,         0,    0);
      rx_trigger.configure(this,  2,    6,   "WO",   0,        2'b00, 1,         1,    0);
    endfunction
  endclass

  class uart_reg_lcr extends uvm_reg;
    `uvm_object_utils(uart_reg_lcr)

    rand uvm_reg_field wls;
    rand uvm_reg_field stb;
    rand uvm_reg_field pen;
    rand uvm_reg_field eps;
    rand uvm_reg_field sticky_parity;
    rand uvm_reg_field set_break;
    rand uvm_reg_field dlab;

    function new(string name = "uart_reg_lcr");
      super.new(name, 8, UVM_NO_COVERAGE);
    endfunction

    virtual function void build();
      wls           = uvm_reg_field::type_id::create("wls");
      stb           = uvm_reg_field::type_id::create("stb");
      pen           = uvm_reg_field::type_id::create("pen");
      eps           = uvm_reg_field::type_id::create("eps");
      sticky_parity = uvm_reg_field::type_id::create("sticky_parity");
      set_break     = uvm_reg_field::type_id::create("set_break");
      dlab          = uvm_reg_field::type_id::create("dlab");

      wls          .configure(this, 2, 0, "RW", 0, 2'b00, 1, 1, 0);
      stb          .configure(this, 1, 2, "RW", 0, 1'b0,  1, 1, 0);
      pen          .configure(this, 1, 3, "RW", 0, 1'b0,  1, 1, 0);
      eps          .configure(this, 1, 4, "RW", 0, 1'b0,  1, 1, 0);
      sticky_parity.configure(this, 1, 5, "RW", 0, 1'b0,  1, 1, 0);
      set_break    .configure(this, 1, 6, "RW", 0, 1'b0,  1, 1, 0);
      dlab         .configure(this, 1, 7, "RW", 0, 1'b0,  1, 1, 0);
    endfunction
  endclass

  class uart_reg_lsr extends uvm_reg;
    `uvm_object_utils(uart_reg_lsr)
    
    rand uvm_reg_field dr;
    rand uvm_reg_field oe;
    rand uvm_reg_field pe;
    rand uvm_reg_field fe;
    rand uvm_reg_field bi;
    rand uvm_reg_field thre;
    rand uvm_reg_field temt;
    rand uvm_reg_field rx_fifo_error;

    function new(string name = "uart_reg_lsr");
      super.new(name, 8, UVM_NO_COVERAGE);
    endfunction

    virtual function void build();
      dr            = uvm_reg_field::type_id::create("dr");
      oe            = uvm_reg_field::type_id::create("oe");
      pe            = uvm_reg_field::type_id::create("pe");
      fe            = uvm_reg_field::type_id::create("fe");
      bi            = uvm_reg_field::type_id::create("bi");
      thre          = uvm_reg_field::type_id::create("thre");
      temt          = uvm_reg_field::type_id::create("temt");
      rx_fifo_error = uvm_reg_field::type_id::create("rx_fifo_error");

      dr           .configure(this,  1,    0,   "RO",   1,        1'b0,  1,         0,    0);
      oe           .configure(this,  1,    1,   "RO",   1,        1'b0,  1,         0,    0);
      pe           .configure(this,  1,    2,   "RO",   1,        1'b0,  1,         0,    0);
      fe           .configure(this,  1,    3,   "RO",   1,        1'b0,  1,         0,    0);
      bi           .configure(this,  1,    4,   "RO",   1,        1'b0,  1,         0,    0);
      thre         .configure(this,  1,    5,   "RO",   1,        1'b1,  1,         0,    0);
      temt         .configure(this,  1,    6,   "RO",   1,        1'b1,  1,         0,    0);
      rx_fifo_error.configure(this,  1,    7,   "RO",   1,        1'b0,  1,         0,    0);
    endfunction
  endclass

  class uart_reg_scr extends uvm_reg;
    `uvm_object_utils(uart_reg_scr)

    rand uvm_reg_field data;

    function new(string name = "uart_reg_scr");
      super.new(name, 8, UVM_NO_COVERAGE);
    endfunction

    virtual function void build();
      data = uvm_reg_field::type_id::create("data");
      data.configure(this, 8, 0, "RW", 0, 8'h00, 1, 1, 0);
    endfunction
  endclass

  class uart_reg_block extends uvm_reg_block;
    `uvm_object_utils(uart_reg_block)

    uart_reg_rbr  RBR;
    uart_reg_thr  THR;
    uart_reg_dll  DLL;
    uart_reg_dlm  DLM;
    uart_reg_fcr  FCR;
    uart_reg_lcr  LCR;
    uart_reg_lsr  LSR;
    uart_reg_scr  SCR;

    uvm_reg_map   map_dlab0;
    uvm_reg_map   map_dlab1;

    function new(string name = "uart_reg_block");
      super.new(name, UVM_NO_COVERAGE);
    endfunction

    virtual function void build();

      RBR = uart_reg_rbr::type_id::create("RBR");
      RBR.configure(this, null, "");
      RBR.build();

      THR = uart_reg_thr::type_id::create("THR");
      THR.configure(this, null, "");
      THR.build();

      DLL = uart_reg_dll::type_id::create("DLL");
      DLL.configure(this, null, "");
      DLL.build();

      DLM = uart_reg_dlm::type_id::create("DLM");
      DLM.configure(this, null, "");
      DLM.build();

      FCR = uart_reg_fcr::type_id::create("FCR");
      FCR.configure(this, null, "");
      FCR.build();

      LCR = uart_reg_lcr::type_id::create("LCR");
      LCR.configure(this, null, "");
      LCR.build();

      LSR = uart_reg_lsr::type_id::create("LSR");
      LSR.configure(this, null, "");
      LSR.build();

      SCR = uart_reg_scr::type_id::create("SCR");
      SCR.configure(this, null, "");
      SCR.build();

      map_dlab0 = create_map("map_dlab0", 'h0, 1, UVM_LITTLE_ENDIAN);

      map_dlab0.add_reg(THR, 'h0, "WO");
      map_dlab0.add_reg(RBR, 'h0, "RO");
      map_dlab0.add_reg(FCR, 'h2, "WO");
      map_dlab0.add_reg(LCR, 'h3, "RW");
      map_dlab0.add_reg(LSR, 'h5, "RO");
      map_dlab0.add_reg(SCR, 'h7, "RW");

      map_dlab1 = create_map("map_dlab1", 'h0, 1, UVM_LITTLE_ENDIAN);

      map_dlab1.add_reg(DLL, 'h0, "RW");
      map_dlab1.add_reg(DLM, 'h1, "RW");
      map_dlab1.add_reg(FCR, 'h2, "WO");
      map_dlab1.add_reg(LCR, 'h3, "RW");
      map_dlab1.add_reg(LSR, 'h5, "RO");
      map_dlab1.add_reg(SCR, 'h7, "RW");

      lock_model();
    endfunction
    
    function uvm_reg_map get_active_map();
      if (LCR.dlab.get_mirrored_value() == 1)
        return map_dlab1;
      else
        return map_dlab0;
    endfunction

  endclass

endpackage

`endif
