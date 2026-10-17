`timescale 1ns/1ps
module tile_result_collector_tb;
  localparam int R=8, C=16, W=32;
  logic clk=0; always #5 clk=~clk;
  logic rst_n=0, start=0, pe_result_valid=0;
  logic [W-1:0] pe_result[R][C];
  logic [15:0] valid_rows=3, valid_cols=5;
  logic result_valid, result_last, busy, done;
  logic [W-1:0] result_data; logic [15:0] result_row, result_col;
  integer i,j,count;
  tile_result_collector #(.DATA_WIDTH(W)) dut(.*);
  initial begin
    for(i=0;i<R;i=i+1) for(j=0;j<C;j=j+1) pe_result[i][j]=i*100+j;
    repeat(2) @(negedge clk); rst_n=1;
    @(negedge clk); start=1; @(negedge clk); start=0;
    // Exactly ONE array completion pulse must drain the entire snapshot.
    @(negedge clk); pe_result_valid=1;
    @(negedge clk); pe_result_valid=0;
    valid_rows=1; valid_cols=1; // in-flight configuration is latched
    for(i=0;i<R;i=i+1) for(j=0;j<C;j=j+1) pe_result[i][j]='1;
    count=0;
    do begin
      @(negedge clk);
      if(result_valid) begin
        if(result_row !== 16'(count/5) || result_col !== 16'(count%5) ||
           result_data !== W'((count/5)*100+count%5)) $fatal(1,"collector snapshot/order failure");
        if(result_last !== (count==14)) $fatal(1,"collector last failure");
        count=count+1;
      end
    end while(!done);
    if(count != 15) $fatal(1,"collector count=%0d",count);
    $display("tile_result_collector_tb PASS"); $finish;
  end
  initial begin #10000; $fatal(1,"tile_result_collector_tb timeout"); end
endmodule
