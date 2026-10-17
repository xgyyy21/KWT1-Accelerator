`timescale 1ns/1ps
module systolic_array_stress_tb;
  localparam int R=3,C=5,K=7,DW=8,AW=24;
  logic clk=0; always #5 clk=~clk;
  logic rst_n=0,start=0,in_valid=0,busy,done,result_valid;
  logic [DW-1:0] a_left[R],b_top[C];
  logic [31:0] bias_data[C];
  wire [AW-1:0] result[R][C];
  integer r,c,k,job,expected[R][C];
  systolic_array_8x16 #(.DATA_WIDTH(DW),.ACC_WIDTH(AW),.ROWS(R),.COLS(C),.K(K)) dut(.*);
  initial begin
    for(r=0;r<R;r=r+1) a_left[r]=0;
    for(c=0;c<C;c=c+1) begin b_top[c]=0; bias_data[c]=0; end
    repeat(2) @(negedge clk); rst_n=1;
    for(job=0;job<3;job=job+1) begin
      for(r=0;r<R;r=r+1) for(c=0;c<C;c=c+1) expected[r][c]=0;
      @(negedge clk); start=1;
      @(negedge clk); start=0;
      for(k=0;k<K;k=k+1) begin
        for(r=0;r<R;r=r+1) a_left[r]=DW'(r*3-k-job);
        for(c=0;c<C;c=c+1) b_top[c]=DW'(k-c*2+job);
        for(r=0;r<R;r=r+1) for(c=0;c<C;c=c+1)
          expected[r][c]=expected[r][c]+(r*3-k-job)*(k-c*2+job);
        in_valid=1;
        // A spurious start while busy must not erase the active dot products.
        start=(k==2);
        @(negedge clk); in_valid=0; start=0;
        if(k%2==0) repeat(2) @(negedge clk);
      end
      // Excess input beats after the Kth must not corrupt any PE.
      for(r=0;r<R;r=r+1) a_left[r]=127;
      for(c=0;c<C;c=c+1) b_top[c]=127;
      in_valid=1;
      wait(result_valid); @(negedge clk); in_valid=0;
      for(r=0;r<R;r=r+1) for(c=0;c<C;c=c+1)
        if(result[r][c]!==AW'(expected[r][c]))
          $fatal(1,"stress job=%0d r=%0d c=%0d got=%h expected=%0d",job,r,c,result[r][c],expected[r][c]);
      @(negedge clk);
    end
    $display("systolic_array_stress_tb PASS"); $finish;
  end
  initial begin #30000; $fatal(1,"systolic_array_stress_tb timeout"); end
endmodule
