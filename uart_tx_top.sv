module uart_tx_top(
input clk, rst, baud_pulse, pen, thre, stb, sticky_parity, eps, set_break,
input [7:0] din,
input [1:0] wls,
output reg pop, sreg_empty, tx
);

typedef enum logic [1:0] {idle = 0, start = 1, send = 2, parity = 3} state_type;
state_type state = idle;

reg [7:0] shft_reg;
reg tx_data;
reg d_parity;
reg [2:0] bitcnt = 0;
reg [4:0] count = 5'd15;
reg parity_out;

always@(posedge clk, posedge rst)
begin
if(rst)
begin
state <= idle;
count <= 5'd15;
bitcnt <= 0;
shft_reg <= 8'bxxxxxxxx;
pop <= 1'b0;
sreg_empty <= 1'b0;
tx_data <= 1'b1;
end

else if(baud_pulse)
begin
case(state)

idle:
begin
if(thre == 1'b0)
begin
if(count != 0)
begin
count <= count - 1;
state <= idle;
end
else
begin
count <= 5'd15;
state <= start;
bitcnt <= {1'b1,wls};
pop <= 1'b1;
shft_reg <= din;
sreg_empty <= 1'b0;

tx_data <= 1'b0;
end
end
end

start:
begin
if(count != 0)
begin
count <= count - 1;
state <= start;
end
else
begin
count <= 5'd15;
state <= send;

case(wls)
2'b00: d_parity <= ^shft_reg[4:0];
2'b01: d_parity <= ^shft_reg[5:0];
2'b10: d_parity <= ^shft_reg[6:0];
2'b11: d_parity <= ^shft_reg[7:0];
endcase

tx_data <= shft_reg[0];
shft_reg <= shft_reg>>1;
pop <= 1'b0;
end
end

send:
begin
case({sticky_parity, eps})
2'b00: parity_out <= ~d_parity;
2'b01: parity_out <= d_parity;
2'b10: parity_out <= 1'b1;
2'b11: parity_out <= 1'b0;
endcase

if(bitcnt != 0)
begin
if(count != 0)
begin
count <= count - 1;
state <= send;
end
else
begin
count <= 5'd15;
bitcnt <= bitcnt - 1;
tx_data <= shft_reg[0];
shft_reg <= shft_reg>>1;
state <= send;
end
end
else
begin
if(count != 0)
begin
count <= count - 1;
state <= send;
end
else
begin
count <= 5'd15;
sreg_empty <= 1'b1;

if(pen == 1'b1)
begin
state <= parity;
count <= 5'd15;
tx_data <= parity_out;
end

else
begin
tx_data <= 1'b1;
count <= (stb == 1'b0)? 5'd15 :(wls == 2'b00) ? 5'd23 : 5'd31;
state <= idle;
end
end
end
end

parity:
begin
if(count != 0)
begin
count <= count - 1;
state <= parity;
end
else
begin
tx_data <= 1'b1;
count <= (stb == 1'b0)? 5'd15 :(wls == 2'b00) ? 5'd17 : 5'd31;
state <= idle;
end
end

default: ;
endcase
end
end

always@(posedge clk, posedge rst)
begin
if(rst)
tx <= 1'b1;
else
tx <= tx_data & ~set_break;
end

endmodule