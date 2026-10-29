`timescale 1ns/1ps
module fp32_mac_boundary_tb;
  logic clk=0; always #5 clk=~clk;
  logic rst_n=0,valid=0,clear_acc=0,last=0,result_valid;
  logic [31:0] a=32'h3f800000,b=32'h3f800000,result;
  fp32_mac_boundary dut(.*);
  initial begin
    repeat(2) @(negedge clk); rst_n=1;
    @(negedge clk); clear_acc=1; valid=1;
    @(negedge clk); clear_acc=0; last=1;
    @(negedge clk); valid=0; last=0;
    if(!result_valid || result!==32'h40000000) $fatal(1,"float MAC 1+1 failure");
    clear_acc=1;
    @(negedge clk); clear_acc=0; valid=1; last=1;
    @(negedge clk); valid=0; last=0;
    if(!result_valid || result!==32'h3f800000) $fatal(1,"float idle clear ignored");
    $display("fp32_mac_boundary_tb PASS"); $finish;
  end
  initial begin #10000; $fatal(1,"fp32_mac_boundary_tb timeout"); end
endmodule
