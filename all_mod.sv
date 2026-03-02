// Type definitions
typedef struct packed {
  logic [1:0] rx_trigger;
  logic [1:0] reserved;
  logic dma_mode;
  logic tx_rst;
  logic rx_rst;
  logic ena;
} fcr_t;

typedef struct packed {
  logic dlab;
  logic set_break;
  logic sticky_parity;
  logic eps;
  logic pen;
  logic stb;
  logic [1:0] wls;
} lcr_t;

typedef struct packed {
  logic rx_fifo_error;
  logic temt;
  logic thre;
  logic bi;
  logic fe;
  logic pe;
  logic oe;
  logic dr;
} lsr_t;

typedef struct {
  fcr_t fcr;
  lcr_t lcr;
  lsr_t lsr;
  logic [7:0] scr;
} csr_t;

// Top-level
module all_mod (
  input        clk, rst, wr, rd,
  input        rx,
  input  [2:0] addr,
  input  [7:0] din,
  output       tx,
  output [7:0] dout
);

  csr_t csr;
  wire  baud_pulse;

  wire       tx_fifo_pop, tx_fifo_push;
  wire [7:0] tx_fifo_out;
  wire       tx_fifo_empty;

  wire       rx_fifo_push, rx_fifo_pop;
  wire [7:0] rx_out, rx_fifo_out;
  wire       rx_fifo_empty, rx_fifo_overrun;
  wire       r_pe, r_fe, r_bi;

  wire       tx_rst, rx_rst;
  wire [3:0] rx_fifo_threshold;

  regs_uart uart_regs_inst (
    .clk              (clk),
    .rst              (rst),
    .wr_i             (wr),
    .rd_i             (rd),
    .rx_fifo_empty_i  (rx_fifo_empty),
    .rx_oe            (rx_fifo_overrun),
    .rx_pe            (r_pe),
    .rx_fe            (r_fe),
    .rx_bi            (r_bi),
    .addr_i           (addr),
    .din_i            (din),
    .tx_push_o        (tx_fifo_push),
    .rx_pop_o         (rx_fifo_pop),
    .baud_out         (baud_pulse),
    .tx_rst           (tx_rst),
    .rx_rst           (rx_rst),
    .rx_fifo_threshold(rx_fifo_threshold),
    .dout_o           (dout),
    .csr_o            (csr),
    .rx_fifo_in       (rx_fifo_out)
  );

  uart_tx_top uart_tx_inst (
    .clk           (clk),
    .rst           (rst),
    .baud_pulse    (baud_pulse),
    .pen           (csr.lcr.pen),
    .thre          (tx_fifo_empty),
    .stb           (csr.lcr.stb),
    .sticky_parity (csr.lcr.sticky_parity),
    .eps           (csr.lcr.eps),
    .set_break     (csr.lcr.set_break),
    .din           (tx_fifo_out),
    .wls           (csr.lcr.wls),
    .pop           (tx_fifo_pop),
    .sreg_empty    (),
    .tx            (tx)
  );

  fifo_top tx_fifo_inst (
    .rst         (rst | tx_rst),
    .clk         (clk),
    .en          (csr.fcr.ena),
    .push_in     (tx_fifo_push),
    .pop_in      (tx_fifo_pop),
    .din         (din),
    .dout        (tx_fifo_out),
    .empty       (tx_fifo_empty),
    .full        (),
    .overrun     (),
    .underrun    (),
    .threshold   (4'h0),
    .thre_trigger()
  );

  uart_rx_top uart_rx_inst (
    .clk           (clk),
    .rst           (rst),
    .baud_pulse    (baud_pulse),
    .rx            (rx),
    .sticky_parity (csr.lcr.sticky_parity),
    .eps           (csr.lcr.eps),
    .pen           (csr.lcr.pen),
    .wls           (csr.lcr.wls),
    .push          (rx_fifo_push),
    .pe            (r_pe),
    .fe            (r_fe),
    .bi            (r_bi),
    .dout          (rx_out)
  );

  fifo_top rx_fifo_inst (
    .rst         (rst | rx_rst),
    .clk         (clk),
    .en          (csr.fcr.ena),
    .push_in     (rx_fifo_push),
    .pop_in      (rx_fifo_pop),
    .din         (rx_out),
    .dout        (rx_fifo_out),
    .empty       (rx_fifo_empty),
    .full        (),
    .overrun     (rx_fifo_overrun),
    .underrun    (),
    .threshold   (rx_fifo_threshold),
    .thre_trigger()
  );

endmodule
