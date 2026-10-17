`timescale 1ns/1ps
module pe_mac_signed_tb;
  logic clk=0; always #5 clk=~clk;
  logic rst_n=0, enable=1, clear_acc=0, task_first=0, task_last=0, in_valid=0;
  logic [7:0] a_in=0,b_in=0,a_out,b_out;
  logic a_valid_out,b_valid_out,result_valid,busy,done;
  logic [39:0] result;
  pe_mac #(.DATA_WIDTH(8),.ACC_WIDTH(40),.SIGNED_DATA(1)) dut(.*);
  initial begin
    repeat(2) @(negedge clk); rst_n=1;
    @(negedge clk); a_in=-3; b_in=4; task_first=1; in_valid=1;
    @(negedge clk); task_first=0; in_valid=0;
    if(!busy) $fatal(1,"PE not busy during dot product");
    // Invalid first marker must not erase the partial sum.
    task_first=1;
    @(negedge clk); task_first=0; a_in=5; b_in=-2; task_last=1; in_valid=1;
    @(negedge clk); in_valid=0; task_last=0;
    if(!result_valid || !done || busy || $signed(result)!=-22)
      $fatal(1,"signed extension/busy failure: %h",result);
    @(negedge clk); a_in=-128; b_in=-128; task_first=1; task_last=1; in_valid=1;
    @(negedge clk); in_valid=0; task_first=0; task_last=0;
    if(!result_valid || result!=16384 || busy) $fatal(1,"signed extreme failure");
    $display("pe_mac_signed_tb PASS"); $finish;
  end
  initial begin #10000; $fatal(1,"pe_mac_signed_tb timeout"); end
endmodule
