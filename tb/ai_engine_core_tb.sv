`timescale 1ns/1ps
module ai_engine_core_tb;
  localparam int DW=16, AW=32, R=8, C=16, K=4;
  logic clk=0; always #5 clk=~clk;
  logic rst_n=0, start=0, tile_load_done=0, writeback_done=0, tile_in_valid=0;
  logic [DW-1:0] a_tile[R], b_tile[C];
  logic [15:0] valid_rows=R, valid_cols=C;
  logic tile_load_start, compute_start, writeback_start, busy, done, error;
  logic result_valid, result_last; logic [AW-1:0] result_data; logic [15:0] result_row,result_col;
  integer i,j,t,count;
  ai_engine_core #(.DATA_WIDTH(DW),.ACC_WIDTH(AW),.ROWS(R),.COLS(C),.K(K)) dut(.*);
  initial begin
    for(i=0;i<R;i=i+1) a_tile[i]=1;
    for(j=0;j<C;j=j+1) b_tile[j]=1;
    repeat(2) @(negedge clk); rst_n=1;
    @(negedge clk); start=1; @(negedge clk); start=0;
    wait(tile_load_start); @(negedge clk); tile_load_done=1;
    @(negedge clk); tile_load_done=0;
    for(t=0;t<K;t=t+1) begin
      @(negedge clk); tile_in_valid=1;
      @(negedge clk); tile_in_valid=0;
    end
    wait(writeback_start);
    @(negedge clk); writeback_done=1; @(negedge clk); writeback_done=0;
    wait(done);
    if(count!=R*C) $fatal(1,"core result count=%0d",count);
    $display("ai_engine_core_tb PASS"); $finish;
  end
  initial count=0;
  always @(negedge clk) if(rst_n && result_valid) begin
    if(result_data!==AW'(K) || result_row!==16'(count/C) || result_col!==16'(count%C))
      $fatal(1,"core result mismatch at %0d",count);
    if(result_last !== (count==R*C-1)) $fatal(1,"core last mismatch");
    count=count+1;
  end
  initial begin #20000; $fatal(1,"ai_engine_core_tb timeout"); end
endmodule
