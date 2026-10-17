`timescale 1ns/1ps
module block_counter_tb;
  logic clk=0; always #5 clk=~clk;
  logic rst_n=0,start=0,advance=0,busy,done;
  logic [15:0] row_base,col_base,k_base,row_valid,col_valid,k_valid;
  integer count;
  block_counter #(.M(9),.N(17),.K(65),.K_TILE(32)) dut(.*);
  initial begin
    repeat(2) @(negedge clk); rst_n=1;
    @(negedge clk); start=1;
    @(negedge clk); start=0;
    count=0;
    while(busy) begin
      if(row_base!==16'((count/6)*8) || col_base!==16'(((count/3)%2)*16) || k_base!==16'((count%3)*32) ||
         row_valid!==16'((count/6)==0?8:1) || col_valid!==16'(((count/3)%2)==0?16:1) || k_valid!==16'((count%3)==2?1:32))
        $fatal(1,"block counter tail/order failure at %0d",count);
      count=count+1; advance=1;
      @(negedge clk); advance=0;
    end
    if(!done || count!=12) $fatal(1,"block counter termination failure");
    $display("block_counter_tb PASS"); $finish;
  end
  initial begin #10000; $fatal(1,"block_counter_tb timeout"); end
endmodule
