`timescale 1ns/1ps
module systolic_array_reference_tb;
  localparam int DW=16, AW=32, R=8, C=16, K=4;
  logic clk=0; always #5 clk=~clk;
  logic rst_n=0, start=0, in_valid=0;
  logic [DW-1:0] a_left[R], b_top[C];
  logic [31:0] bias_data[C];
  logic busy, done, result_valid;
  logic [AW-1:0] result[R][C];
  integer r,c,k,expected;
  systolic_array_8x16 #(.DATA_WIDTH(DW),.ACC_WIDTH(AW),.ROWS(R),.COLS(C),.K(K)) dut(.*);
  initial begin
    for (r=0;r<R;r=r+1) a_left[r]=0;
    for (c=0;c<C;c=c+1) b_top[c]=0;
    for (c=0;c<C;c=c+1) bias_data[c]=0;
    repeat(2) @(negedge clk); rst_n=1;
    @(negedge clk); start=1;
    @(negedge clk); start=0;
    for(k=0;k<K;k=k+1) begin
      for(r=0;r<R;r=r+1) a_left[r]=r+1;
      for(c=0;c<C;c=c+1) b_top[c]=c+2;
      in_valid=1;
      @(negedge clk);
    end
    in_valid=0;
    for(r=0;r<R;r=r+1) a_left[r]=0;
    for(c=0;c<C;c=c+1) b_top[c]=0;
    wait(result_valid);
    @(negedge clk);
    for(r=0;r<R;r=r+1) for(c=0;c<C;c=c+1) begin
      expected = K*(r+1)*(c+2);
      if(result[r][c] !== expected[AW-1:0])
        $fatal(1,"mismatch r=%0d c=%0d got=%0d expected=%0d",r,c,result[r][c],expected);
    end
    $display("systolic_array_reference_tb PASS");
    $finish;
  end
  initial begin #10000; $fatal(1,"systolic_array_reference_tb timeout"); end
endmodule
