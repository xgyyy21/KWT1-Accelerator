`timescale 1ns/1ps
module matrix_buffer_tb;
  logic clk=0; always #5 clk=~clk;
  logic rst_n=0,a_wr_en=0,b_wr_en=0,result_wr_en=0;
  logic [2:0] a_wr_addr=0,b_wr_addr=0,result_wr_addr=0,a_rd_addr=0,b_rd_addr=0,result_rd_addr=0;
  logic [15:0] a_wr_data=16'h1234,b_wr_data=16'h5678,a_rd_data,b_rd_data;
  logic [31:0] result_wr_data=32'h87654321,result_rd_data;
  matrix_buffer #(.ADDR_WIDTH(3),.DEPTH(5)) dut(.*);
  initial begin
    repeat(2) @(negedge clk); rst_n=1;
    a_wr_en=1; b_wr_en=1; result_wr_en=1;
    @(negedge clk); a_wr_en=0; b_wr_en=0; result_wr_en=0;
    @(negedge clk);
    if(a_rd_data!==16'h1234 || b_rd_data!==16'h5678 || result_rd_data!==32'h87654321)
      $fatal(1,"legacy buffer read failure");
    a_rd_addr=7; b_rd_addr=7; result_rd_addr=7;
    @(negedge clk);
    if(a_rd_data!==0 || b_rd_data!==0 || result_rd_data!==0) $fatal(1,"legacy invalid read failure");
    $display("matrix_buffer_tb PASS"); $finish;
  end
  initial begin #10000; $fatal(1,"matrix_buffer_tb timeout"); end
endmodule
