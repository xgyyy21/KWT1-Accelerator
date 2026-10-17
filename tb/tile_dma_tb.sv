`timescale 1ns/1ps
module tile_dma_tb;
  logic clk=0; always #5 clk=~clk;
  logic rst_n=0,start=0,busy,done,a_valid,b_valid,result_valid,result_ready=0;
  logic [11:0] src_a_base=12'h100,src_b_base=12'h200,dst_base=12'h300;
  logic [11:0] a_addr,b_addr,result_addr;
  integer i,j;
  tile_dma #(.TILE_WORDS(4)) dut(.*);
  initial begin
    repeat(2) @(negedge clk); rst_n=1;
    @(negedge clk); start=1;
    @(negedge clk); start=0; src_a_base=0; src_b_base=0; dst_base=0;
    for(i=0;i<4;i=i+1) begin
      result_ready=0;
      // Stall both ordinary and final beats, including a spurious busy START.
      for(j=0;j<3;j=j+1) begin
        start=(j==0);
        @(negedge clk);
        if(!busy || done || !a_valid || !b_valid || !result_valid ||
           a_addr!==12'(256+i) || b_addr!==12'(512+i) || result_addr!==12'(768+i))
          $fatal(1,"DMA moved/lost beat while stalled i=%0d",i);
      end
      start=0; result_ready=1;
      @(negedge clk);
    end
    result_ready=0;
    if(busy || !done || result_valid) $fatal(1,"DMA final handshake failure");
    $display("tile_dma_tb PASS"); $finish;
  end
  initial begin #10000; $fatal(1,"tile_dma_tb timeout"); end
endmodule
