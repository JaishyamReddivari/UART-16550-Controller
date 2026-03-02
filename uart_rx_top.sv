// UART TX
module uart_tx_top (
  input        clk, rst, baud_pulse, pen, thre, stb,
  input        sticky_parity, eps, set_break,
  input  [7:0] din,
  input  [1:0] wls,
  output reg   pop, sreg_empty, tx
);

  typedef enum logic [1:0] {IDLE=0, START=1, SEND=2, PARITY=3} state_t;
  state_t state;

  reg [7:0] shft_reg;
  reg       tx_data;
  reg       d_parity;
  reg [2:0] bitcnt;
  reg [4:0] count;
  reg       parity_out;

  always @(posedge clk or posedge rst) begin
    if (rst) begin
      state      <= IDLE;
      count      <= 5'd15;
      bitcnt     <= 3'd0;
      shft_reg   <= 8'h00;
      pop        <= 1'b0;
      sreg_empty <= 1'b1;
      tx_data    <= 1'b1;
      d_parity   <= 1'b0;
      parity_out <= 1'b0;
    end
    else begin
      pop <= 1'b0;

      if (baud_pulse) begin
        case (state)
          IDLE: begin
            if (!thre) begin
              if (count != 5'd0)
                count <= count - 5'd1;
              else begin
                pop        <= 1'b1;
                shft_reg   <= din;
                sreg_empty <= 1'b0;
                tx_data    <= 1'b0;
                bitcnt     <= {1'b1, wls};
                count      <= 5'd15;
                state      <= START;
              end
            end else begin
              sreg_empty <= 1'b1;
              count      <= 5'd15;
            end
          end

          START: begin
            if (count != 5'd0)
              count <= count - 5'd1;
            else begin
              case (wls)
                2'b00: d_parity <= ^shft_reg[4:0];
                2'b01: d_parity <= ^shft_reg[5:0];
                2'b10: d_parity <= ^shft_reg[6:0];
                2'b11: d_parity <= ^shft_reg[7:0];
              endcase
              tx_data  <= shft_reg[0];
              shft_reg <= shft_reg >> 1;
              count    <= 5'd15;
              state    <= SEND;
            end
          end

          SEND: begin
            case ({sticky_parity, eps})
              2'b00: parity_out <= ~d_parity;
              2'b01: parity_out <=  d_parity;
              2'b10: parity_out <= 1'b1;
              2'b11: parity_out <= 1'b0;
            endcase

            if (bitcnt != 3'd0) begin
              if (count != 5'd0)
                count <= count - 5'd1;
              else begin
                tx_data  <= shft_reg[0];
                shft_reg <= shft_reg >> 1;
                bitcnt   <= bitcnt - 3'd1;
                count    <= 5'd15;
              end
            end else begin
              if (count != 5'd0)
                count <= count - 5'd1;
              else begin
                sreg_empty <= 1'b1;
                if (pen) begin
                  tx_data <= parity_out;
                  count   <= 5'd15;
                  state   <= PARITY;
                end else begin
                  tx_data <= 1'b1;
                  count   <= (!stb) ? 5'd15 : (wls == 2'b00) ? 5'd23 : 5'd31;
                  state   <= IDLE;
                end
              end
            end
          end

          PARITY: begin
            if (count != 5'd0)
              count <= count - 5'd1;
            else begin
              tx_data <= 1'b1;
              count   <= (!stb) ? 5'd15 : (wls == 2'b00) ? 5'd23 : 5'd31;
              state   <= IDLE;
            end
          end

          default: state <= IDLE;
        endcase
      end
    end
  end

  always @(posedge clk or posedge rst) begin
    if (rst)
      tx <= 1'b1;
    else
      tx <= tx_data & ~set_break;
  end

endmodule
