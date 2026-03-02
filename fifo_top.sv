// FIFO — 16-deep shift-register
module fifo_top (
  input        rst, clk, en, push_in, pop_in,
  input  [7:0] din,
  output [7:0] dout,
  output       empty, full, overrun, underrun,
  input  [3:0] threshold,
  output       thre_trigger
);

  reg [7:0] mem [0:15];
  reg [4:0] waddr;

  logic push, pop;
  assign push = push_in & ~full_t;
  assign pop  = pop_in  & ~empty_t;

  reg empty_t;
  always @(posedge clk or posedge rst) begin
    if (rst)
      empty_t <= 1'b1;
    else case ({push, pop})
      2'b01:   empty_t <= (waddr <= 5'd1) | ~en;
      2'b10:   empty_t <= 1'b0;
      default: ;
    endcase
  end

  reg full_t;
  always @(posedge clk or posedge rst) begin
    if (rst)
      full_t <= 1'b0;
    else case ({push, pop})
      2'b10:   full_t <= (waddr >= 5'd15) | ~en;
      2'b01:   full_t <= 1'b0;
      default: ;
    endcase
  end

  assign dout = mem[0];

  always @(posedge clk or posedge rst) begin
    if (rst)
      waddr <= 5'h0;
    else case ({push, pop})
      2'b10: if (waddr < 5'd16 && !full_t) waddr <= waddr + 1;
      2'b01: if (waddr != 0 && !empty_t)   waddr <= waddr - 1;
      default: ;
    endcase
  end

  always @(posedge clk) begin
    case ({push, pop})
      2'b01: begin
        for (int i = 0; i < 15; i++) mem[i] <= mem[i+1];
        mem[15] <= 8'h00;
      end
      2'b10: begin
        mem[waddr[3:0]] <= din;
      end
      2'b11: begin
        for (int i = 0; i < 15; i++) mem[i] <= mem[i+1];
        mem[15] <= 8'h00;
        if (waddr > 0) mem[waddr[3:0]-1] <= din;
      end
      default: ;
    endcase
  end

  reg overrun_t, underrun_t;
  always @(posedge clk or posedge rst) begin
    if (rst) begin overrun_t <= 0; underrun_t <= 0; end
    else begin
      overrun_t  <= push_in & full_t;
      underrun_t <= pop_in  & empty_t;
    end
  end

  reg thre_t;
  always @(posedge clk or posedge rst) begin
    if (rst) thre_t <= 1'b0;
    else if (push ^ pop)
      thre_t <= (waddr >= {1'b0, threshold});
  end

  assign empty     = empty_t;
  assign full      = full_t;
  assign overrun   = overrun_t;
  assign underrun  = underrun_t;
  assign thre_trigger = thre_t;

endmodule
