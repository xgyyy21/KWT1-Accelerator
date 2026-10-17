`timescale 1ns/1ps
module block_descriptor_tb;
  logic clk=0; always #5 clk=~clk;
  logic rst_n=0,load=0,has_valid_data=0,allow_compute=0,operation_done=0;
  logic [15:0] row_position=0,col_position=0,height=0,width=0;
  logic active,valid,permitted,complete;
  logic [15:0] row,col,block_height,block_width;
  block_descriptor dut(.*);
  initial begin
    repeat(2) @(negedge clk); rst_n=1;
    operation_done=1;
    @(negedge clk); operation_done=0;
    if(complete || active) $fatal(1,"unloaded descriptor completed");
    load=1; row_position=96; col_position=240; height=3; width=16;
    has_valid_data=1; allow_compute=1;
    @(negedge clk); load=0; row_position=0; col_position=0;
    if(!active || !valid || !permitted || complete || row!=96 || col!=240 || block_height!=3 || block_width!=16)
      $fatal(1,"descriptor metadata load failure");
    operation_done=1;
    @(negedge clk); operation_done=0;
    if(active || !complete) $fatal(1,"descriptor completion failure");
    load=1; has_valid_data=0; allow_compute=0;
    @(negedge clk); load=0;
    if(!active || complete || valid || permitted) $fatal(1,"descriptor stale flags on reload");
    $display("block_descriptor_tb PASS"); $finish;
  end
  initial begin #10000; $fatal(1,"block_descriptor_tb timeout"); end
endmodule
