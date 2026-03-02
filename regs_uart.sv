// Register File & Baud Rate Generator
module regs_uart (
  input        clk, rst,
  input        wr_i, rd_i,
  input        rx_fifo_empty_i,
  input        rx_oe, rx_pe, rx_fe, rx_bi,
  input  [2:0] addr_i,
  input  [7:0] din_i,
  output       tx_push_o,
  output       rx_pop_o,
  output       baud_out,
  output       tx_rst, rx_rst,
  output [3:0] rx_fifo_threshold,
  output reg [7:0] dout_o,
  output csr_t csr_o,
  input  [7:0] rx_fifo_in
);

  csr_t csr;

  assign tx_push_o = wr_i & (addr_i == 3'b000) & ~csr.lcr.dlab;
  assign rx_pop_o  = rd_i & (addr_i == 3'b000) & ~csr.lcr.dlab;

  reg [7:0] rx_data;
  always @(posedge clk) begin
    if (rx_pop_o) rx_data <= rx_fifo_in;
  end

  // Divisor Latch
  reg [7:0] dl_lsb;
  reg [7:0] dl_msb;
  wire [15:0] divisor = {dl_msb, dl_lsb};

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      dl_lsb <= 8'h00;
      dl_msb <= 8'h00;
    end
    else if (wr_i && csr.lcr.dlab) begin
      if (addr_i == 3'b000) dl_lsb <= din_i;
      if (addr_i == 3'b001) dl_msb <= din_i;
    end
  end

  // Baud Rate Generator
  reg         update_baud;
  reg  [15:0] baud_cnt;
  reg         baud_pulse;

  always @(posedge clk) begin
    update_baud <= wr_i & csr.lcr.dlab & ((addr_i == 3'b000) | (addr_i == 3'b001));
  end

  always @(posedge clk or posedge rst) begin
    if (rst)
      baud_cnt <= 16'h0;
    else if (update_baud || baud_cnt == 16'h0)
      baud_cnt <= divisor;
    else
      baud_cnt <= baud_cnt - 16'h1;
  end

  always @(posedge clk or posedge rst) begin
    if (rst)
      baud_pulse <= 1'b0;
    else
      baud_pulse <= (|divisor) & (baud_cnt == 16'h1);
  end

  assign baud_out = baud_pulse;

  // FCR
  always @(posedge clk or posedge rst) begin
    if (rst)
      csr.fcr <= 8'h00;
    else if (wr_i && addr_i == 3'h2) begin
      csr.fcr.rx_trigger <= din_i[7:6];
      csr.fcr.dma_mode   <= din_i[3];
      csr.fcr.tx_rst     <= din_i[2];
      csr.fcr.rx_rst     <= din_i[1];
      csr.fcr.ena        <= din_i[0];
    end else begin
      csr.fcr.tx_rst <= 1'b0;
      csr.fcr.rx_rst <= 1'b0;
    end
  end
  assign tx_rst = csr.fcr.tx_rst;
  assign rx_rst = csr.fcr.rx_rst;

  reg [3:0] rx_fifo_th_count;
  always_comb begin
    if (!csr.fcr.ena) rx_fifo_th_count = 4'd0;
    else case (csr.fcr.rx_trigger)
      2'b00: rx_fifo_th_count = 4'd1;
      2'b01: rx_fifo_th_count = 4'd4;
      2'b10: rx_fifo_th_count = 4'd8;
      2'b11: rx_fifo_th_count = 4'd14;
    endcase
  end
  assign rx_fifo_threshold = rx_fifo_th_count;

  // LCR
  reg [7:0] lcr_temp;
  always @(posedge clk or posedge rst) begin
    if (rst)      csr.lcr <= 8'h00;
    else if (wr_i && addr_i == 3'h3) csr.lcr <= din_i;
  end
  always @(posedge clk) begin
    if (rd_i && addr_i == 3'h3) lcr_temp <= csr.lcr;
  end

  // LSR
  reg [7:0] lsr_temp;
  always @(posedge clk or posedge rst) begin
    if (rst) csr.lsr <= 8'h60;
    else begin
      csr.lsr.dr <= ~rx_fifo_empty_i;
      csr.lsr.oe <= rx_oe;
      csr.lsr.pe <= rx_pe;
      csr.lsr.fe <= rx_fe;
      csr.lsr.bi <= rx_bi;
    end
  end
  always @(posedge clk) begin
    if (rd_i && addr_i == 3'h5) lsr_temp <= csr.lsr;
  end

  // SCR
  reg [7:0] scr_temp;
  always @(posedge clk or posedge rst) begin
    if (rst)      csr.scr <= 8'h00;
    else if (wr_i && addr_i == 3'h7) csr.scr <= din_i;
  end
  always @(posedge clk) begin
    if (rd_i && addr_i == 3'h7) scr_temp <= csr.scr;
  end

  // Read mux
  always @(posedge clk) begin
    case (addr_i)
      3'd0: dout_o <= csr.lcr.dlab ? dl_lsb : rx_data;
      3'd1: dout_o <= csr.lcr.dlab ? dl_msb  : 8'h00;
      3'd2: dout_o <= 8'h00;
      3'd3: dout_o <= lcr_temp;
      3'd4: dout_o <= 8'h00;
      3'd5: dout_o <= lsr_temp;
      3'd6: dout_o <= 8'h00;
      3'd7: dout_o <= scr_temp;
    endcase
  end
  assign csr_o = csr;

endmodule
