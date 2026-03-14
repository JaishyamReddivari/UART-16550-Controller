// UART RX
module uart_rx_top (
  input        clk, rst, baud_pulse, rx, sticky_parity, eps,
  input        pen,
  input  [1:0] wls,
  output reg   push,
  output reg   pe, fe, bi,
  output reg [7:0] dout
);

  typedef enum logic [2:0] {IDLE=0, START=1, READ=2, PARITY=3, STOP=4} state_t;
  state_t state;

  reg       rx_d1;
  reg       start_detected;
  reg [2:0] bitcnt;
  reg [3:0] count;
  reg       parity_accum;

  always @(posedge clk or posedge rst) begin
    if (rst) rx_d1 <= 1'b1;
    else     rx_d1 <= rx;
  end

  always @(posedge clk or posedge rst) begin
    if (rst)
      start_detected <= 1'b0;
    else if (rx_d1 & ~rx)
      start_detected <= 1'b1;
    else if (state != IDLE)
      start_detected <= 1'b0;
  end

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      state        <= IDLE;
      push         <= 1'b0;
      pe           <= 1'b0;
      fe           <= 1'b0;
      bi           <= 1'b0;
      bitcnt       <= 3'd0;
      count        <= 4'd0;
      parity_accum <= 1'b0;
      dout         <= 8'd0;
    end
    else begin
      push <= 1'b0;

      if (baud_pulse) begin
        case (state)
          IDLE: begin
            if (start_detected) begin
              state <= START;
              count <= 4'd15;
            end
          end

          START: begin
            count <= count - 4'd1;
            if (count == 4'd8) begin
              if (rx) state <= IDLE;
            end
            else if (count == 4'd0) begin
              state        <= READ;
              count        <= 4'd15;
              bitcnt       <= {1'b1, wls};
              parity_accum <= 1'b0;
            end
          end

          READ: begin
            count <= count - 4'd1;
            if (count == 4'd8) begin
              case (wls)
                2'b00: dout <= {3'b000, rx, dout[4:1]};
                2'b01: dout <= {2'b00,  rx, dout[5:1]};
                2'b10: dout <= {1'b0,   rx, dout[6:1]};
                2'b11: dout <= {rx, dout[7:1]};
              endcase
              parity_accum <= parity_accum ^ rx;
            end
            else if (count == 4'd0) begin
              if (bitcnt == 3'd0) begin
                if (pen)  state <= PARITY;
                else      state <= STOP;
                count <= 4'd15;
              end else begin
                bitcnt <= bitcnt - 3'd1;
                count  <= 4'd15;
              end
            end
          end

          PARITY: begin
            count <= count - 4'd1;
            if (count == 4'd8) begin
              case ({sticky_parity, eps})
                2'b00: pe <= (rx != ~parity_accum);
                2'b01: pe <= (rx != parity_accum);
                2'b10: pe <= (rx != 1'b1);
                2'b11: pe <= (rx != 1'b0);
              endcase
            end
            else if (count == 4'd0) begin
              state <= STOP;
              count <= 4'd15;
            end
          end

          STOP: begin
            count <= count - 4'd1;
            if (count == 4'd8) begin
              fe   <= ~rx;
              bi   <= ~rx & ~|dout;
              push <= 1'b1;
            end
            else if (count == 4'd0)
              state <= IDLE;
          end

          default: state <= IDLE;
        endcase
      end
    end
  end

endmodule
