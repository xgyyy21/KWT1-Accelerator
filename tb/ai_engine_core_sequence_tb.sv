`timescale 1ns/1ps
module ai_engine_core_sequence_tb;
  localparam int R=3,C=5,K=4,DW=8,AW=24;
  logic clk=0; always #5 clk=~clk;
  logic rst_n=0,start=0,tile_load_done=0,writeback_done=0,tile_in_valid=0;
  logic [DW-1:0] a_tile[R],b_tile[C];
  logic [15:0] valid_rows=R,valid_cols=C;
  logic tile_load_start,compute_start,writeback_start,busy,done,error,result_valid,result_last;
  logic [AW-1:0] result_data;
  logic [15:0] result_row,result_col;
  integer r,c,k,job,count,vr,vc;
  ai_engine_core #(.DATA_WIDTH(DW),.ACC_WIDTH(AW),.ROWS(R),.COLS(C),.K(K)) dut(.*);
  initial begin
    for(r=0;r<R;r=r+1) a_tile[r]=0;
    for(c=0;c<C;c=c+1) b_tile[c]=0;
    repeat(2) @(negedge clk); rst_n=1;
    // First abort an invalid job; then run two real tasks without a reset.
    @(negedge clk); valid_rows=0; start=1;
    @(negedge clk); start=0;
    if(!error || busy || tile_load_start) $fatal(1,"invalid job was accepted");
    for(job=0;job<2;job=job+1) begin
      vr=(job==0)?R:2; vc=(job==0)?C:3; count=0;
      @(negedge clk); valid_rows=16'(vr); valid_cols=16'(vc); start=1;
      @(negedge clk); start=0;
      wait(tile_load_start);
      @(negedge clk); tile_load_done=1;
      @(negedge clk); tile_load_done=0;
      // Accepted valid sizes must survive external configuration changes.
      valid_rows=0; valid_cols=0;
      for(k=0;k<K;k=k+1) begin
        @(negedge clk);
        for(r=0;r<R;r=r+1) a_tile[r]=DW'(r+1+job);
        for(c=0;c<C;c=c+1) b_tile[c]=DW'(-c-1);
        tile_in_valid=1;
        @(negedge clk); tile_in_valid=0;
      end
      do begin
        @(negedge clk);
        if(error) $fatal(1,"in-flight config was not latched");
        if(result_valid) begin
          if(result_row!==16'(count/vc) || result_col!==16'(count%vc) ||
             result_data!==AW'(-K*(count/vc+1+job)*(count%vc+1))) $fatal(1,"core sequence numerical/order failure");
          if(result_last!==(count==vr*vc-1)) $fatal(1,"core sequence last failure");
          count=count+1;
        end
      end while(!writeback_start);
      if(count!=vr*vc || done) $fatal(1,"compute/writeback boundary failure count=%0d",count);
      repeat(3) begin @(negedge clk); if(done) $fatal(1,"done before writeback ack"); end
      writeback_done=1;
      @(negedge clk); writeback_done=0;
      if(!done) $fatal(1,"missing task done");
      @(negedge clk);
    end
    $display("ai_engine_core_sequence_tb PASS"); $finish;
  end
  initial begin #30000; $fatal(1,"ai_engine_core_sequence_tb timeout"); end
endmodule
