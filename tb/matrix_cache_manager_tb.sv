`timescale 1ns/1ps
module matrix_cache_manager_tb;
  logic clk=0; always #5 clk=~clk;
  logic rst_n=0,a_wr_en=0,b_wr_en=0,result_wr_en=0,a_rd_en=0,b_rd_en=0,result_rd_en=0;
  logic [2:0] a_wr_addr=0,b_wr_addr=0,result_wr_addr=0,a_rd_addr=0,b_rd_addr=0,result_rd_addr=0;
  logic [15:0] a_wr_data=16'h1234,b_wr_data=16'habcd,result_wr_data=16'h8001;
  logic [15:0] a_rd_data,b_rd_data,result_rd_data;
  logic a_rd_valid,b_rd_valid,result_rd_valid;
  matrix_cache_manager #(.ADDR_WIDTH(3),.DEPTH(5)) dut(.*);
  initial begin
    repeat(2) @(negedge clk); rst_n=1;
    @(negedge clk); a_wr_en=1; b_wr_en=1; result_wr_en=1;
    @(negedge clk); a_wr_en=0; b_wr_en=0; result_wr_en=0;
    a_rd_en=1; b_rd_en=1; result_rd_en=1;
    if(a_rd_valid || b_rd_valid || result_rd_valid) $fatal(1,"read responded before clock");
    @(negedge clk);
    if(!a_rd_valid || !b_rd_valid || !result_rd_valid || a_rd_data!==16'h1234 ||
       b_rd_data!==16'habcd || result_rd_data!==16'h8001) $fatal(1,"cache read mismatch");
    a_rd_addr=7; b_rd_addr=7; result_rd_addr=7;
    @(negedge clk);
    if(a_rd_valid || b_rd_valid || result_rd_valid) $fatal(1,"out-of-range read marked valid");
    a_rd_en=0; b_rd_en=0; result_rd_en=0;
    $display("matrix_cache_manager_tb PASS"); $finish;
  end
  initial begin #10000; $fatal(1,"matrix_cache_manager_tb timeout"); end
endmodule
