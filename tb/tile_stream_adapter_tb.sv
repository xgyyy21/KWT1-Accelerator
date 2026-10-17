`timescale 1ns/1ps
module tile_stream_adapter_tb;
  localparam int R=2,C=3;
  logic clk=0; always #5 clk=~clk;
  logic rst_n=0,start=0,stop=0,input_valid=0,stream_valid,active;
  logic [15:0] a_mem_data[R],b_mem_data[C];
  wire [15:0] a_left[R],b_top[C];
  integer r,c;
  tile_stream_adapter #(.ROWS(R),.COLS(C)) dut(.*);
  initial begin
    for(r=0;r<R;r=r+1) a_mem_data[r]=16'(10+r);
    for(c=0;c<C;c=c+1) b_mem_data[c]=16'(20+c);
    repeat(2) @(negedge clk); rst_n=1;
    input_valid=1;
    @(negedge clk);
    if(stream_valid || active) $fatal(1,"inactive stream accepted input");
    start=1;
    @(negedge clk); start=0;
    if(!stream_valid || !active) $fatal(1,"first beat on start lost");
    for(r=0;r<R;r=r+1) if(a_left[r]!==a_mem_data[r]) $fatal(1,"A stream mismatch");
    for(c=0;c<C;c=c+1) if(b_top[c]!==b_mem_data[c]) $fatal(1,"B stream mismatch");
    stop=1;
    @(negedge clk); stop=0;
    if(stream_valid || active) $fatal(1,"stop failed to suppress same-edge input");
    $display("tile_stream_adapter_tb PASS"); $finish;
  end
  initial begin #10000; $fatal(1,"tile_stream_adapter_tb timeout"); end
endmodule
