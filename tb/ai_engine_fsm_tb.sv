`timescale 1ns/1ps
module ai_engine_fsm_tb;
  logic clk=0; always #5 clk=~clk;
  logic rst_n=0,start=0,load_done=0,compute_done=0,write_done=0,error_in=0;
  logic load_start,compute_start,write_start,busy,done,error; logic [2:0] state;
  ai_engine_fsm dut(.*,.dma_load_done(load_done),.writeback_done(write_done),
    .dma_load_start(load_start),.writeback_start(write_start));
  initial begin
    repeat(2) @(negedge clk); rst_n=1;
    @(negedge clk); start=1; @(negedge clk); start=0;
    if (!load_start) $fatal(1,"FSM did not enter load");
    @(negedge clk);
    if(load_start || !busy) $fatal(1,"load start must pulse once while busy remains high");
    @(negedge clk); load_done=1; @(negedge clk); load_done=0;
    if (!compute_start) $fatal(1,"FSM did not enter compute");
    @(negedge clk); compute_done=1; @(negedge clk); compute_done=0;
    if (!write_start) $fatal(1,"FSM did not enter writeback");
    @(negedge clk); write_done=1; @(negedge clk); write_done=0;
    if (!done) $fatal(1,"FSM did not assert done");
    start=1;
    @(negedge clk); start=0;
    if(!load_start || !busy) $fatal(1,"new job at DONE was lost");
    error_in=1;
    @(negedge clk);
    if(!error || busy) $fatal(1,"FSM error transition failed");
    error_in=0; start=1;
    @(negedge clk); start=0;
    if(!load_start || error) $fatal(1,"FSM restart after error failed");
    $display("ai_engine_fsm_tb PASS"); $finish;
  end
  initial begin #10000; $fatal(1,"ai_engine_fsm_tb timeout"); end
endmodule
