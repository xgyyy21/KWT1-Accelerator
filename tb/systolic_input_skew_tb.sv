`timescale 1ns/1ps
module systolic_input_skew_tb;
  localparam int R=3,C=4;
  logic clk=0; always #5 clk=~clk;
  logic rst_n=0,enable=1,in_valid=0;
  logic [15:0] a_in[R],b_in[C];
  wire [15:0] a_out[R],b_out[C];
  wire out_valid[R][C];
  integer r,c,t;
  systolic_input_skew #(.ROWS(R),.COLS(C)) dut(.*);
  initial begin
    for(r=0;r<R;r=r+1) a_in[r]=16'(100+r);
    for(c=0;c<C;c=c+1) b_in[c]=16'(200+c);
    repeat(2) @(negedge clk); rst_n=1;
    in_valid=1;
    for(t=0;t<C;t=t+1) begin
      @(negedge clk);
      for(r=0;r<R;r=r+1) if(t>=r && a_out[r]!==16'(100+r)) $fatal(1,"A skew delay failure");
      for(c=0;c<C;c=c+1) if(t>=c && b_out[c]!==16'(200+c)) $fatal(1,"B skew delay failure");
      for(r=0;r<R;r=r+1) for(c=0;c<C;c=c+1)
        if(out_valid[r][c] !== (t>=r && t>=c)) $fatal(1,"boundary valid failure");
      in_valid=0;
      // Subsequent cycles use a continuous stream to fill every skew stage.
      if(t<C-1) in_valid=1;
    end
    enable=0;
    @(negedge clk);
    for(r=0;r<R;r=r+1) for(c=0;c<C;c=c+1)
      if(out_valid[r][c]) $fatal(1,"disabled skew emitted valid");
    $display("systolic_input_skew_tb PASS"); $finish;
  end
  initial begin #10000; $fatal(1,"systolic_input_skew_tb timeout"); end
endmodule
