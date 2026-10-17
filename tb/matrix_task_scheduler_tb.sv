`timescale 1ns/1ps
module matrix_task_scheduler_tb;
  logic clk=0; always #5 clk=~clk;
  logic rst_n=0,start=0,advance=0,busy,done,k_first,k_last;
  logic [15:0] m=99,k=64,n=256,rb,cb,kb,rv,cv,kv;
  matrix_task_scheduler #(.ROW_TILE(8),.COL_TILE(16),.K_TILE(32)) dut(.*,
    .matrix_m(m),.matrix_k(k),.matrix_n(n),.row_base(rb),.col_base(cb),.k_base(kb),
    .rows_valid(rv),.cols_valid(cv),.k_valid(kv));
  integer tiles;
  initial begin
    repeat(2) @(negedge clk); rst_n=1;
    @(negedge clk); start=1; @(negedge clk); start=0;
    tiles=0;
    while(!done && tiles<1000) begin
      if (rv==0 || cv==0 || kv==0) $fatal(1,"invalid tile dimensions");
      tiles=tiles+1; @(negedge clk); advance=1; @(negedge clk); advance=0;
    end
    if (tiles != 2*16*13) $fatal(1,"tile count=%0d expected=416",tiles);
    $display("matrix_task_scheduler_tb PASS"); $finish;
  end
  initial begin #100000; $fatal(1,"matrix_task_scheduler_tb timeout"); end
endmodule
