`timescale 1ns/1ps
module matrix_task_controller_tb;
  logic clk=0; always #5 clk=~clk;
  logic rst_n=0,start=0,block_done=0,block_start,task_busy,task_done,k_first,k_last;
  logic [15:0] matrix_m=9,matrix_k=65,matrix_n=17;
  logic [15:0] row_base,col_base,k_base,rows_valid,cols_valid,k_valid;
  integer count;
  matrix_task_controller dut(.*);
  task run_task(input bit empty); begin
    count=0;
    @(negedge clk); start=1;
    @(negedge clk); start=0;
    // Changing external config must not change the accepted task.
    matrix_m=1; matrix_k=1; matrix_n=1;
    while(!task_done) begin
      @(negedge clk); block_done=0;
      if(block_start) begin
        if(empty) $fatal(1,"empty task launched block");
        if(row_base!==16'((count/6)*8) || col_base!==16'(((count/3)%2)*16) ||
           k_base!==16'((count%3)*32)) $fatal(1,"stale block coordinates count=%0d",count);
        if(rows_valid!==16'((count/6)==0?8:1) || cols_valid!==16'(((count/3)%2)==0?16:1) ||
           k_valid!==16'((count%3)==2?1:32) || k_first!==(count%3==0) || k_last!==(count%3==2))
          $fatal(1,"tail block metadata failure");
        count=count+1;
        repeat(2) @(negedge clk);
        block_done=1;
      end
    end
    if(count!=(empty?0:12) || task_busy) $fatal(1,"controller block count=%0d",count);
    @(negedge clk); block_done=0;
  end endtask
  initial begin
    repeat(2) @(negedge clk); rst_n=1;
    run_task(0);
    matrix_m=9; matrix_k=65; matrix_n=17; run_task(0);
    matrix_m=0; matrix_k=65; matrix_n=17; run_task(1);
    $display("matrix_task_controller_tb PASS"); $finish;
  end
  initial begin #30000; $fatal(1,"matrix_task_controller_tb timeout"); end
endmodule
