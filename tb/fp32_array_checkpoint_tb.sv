`timescale 1ns/1ps
// Actual checkpoint flow:
//   first K block -> 128 accumulators saved as 512 SRAM halfwords
//   reset array -> 512 halfwords read back -> restore all PE registers
//   second K block -> final result.
module fp32_array_checkpoint_tb;
  localparam integer ROWS=8, COLS=16, BLOCK_K=32, CELLS=ROWS*COLS;
  reg clk=0; always #5 clk=~clk;
  reg rst_n=0, start=0, stream_valid=0, task_first=0, task_last=0;
  reg checkpoint_save_req=0, checkpoint_restore_req=0;
  reg [31:0] a_left[ROWS], b_top[COLS], bias_in[COLS];
  wire busy,done,result_valid;
  wire [31:0] result[ROWS][COLS];
  wire trace_valid[ROWS][COLS],trace_bias_valid[ROWS][COLS];
  wire [31:0] trace_cycle[ROWS][COLS],trace_acc_after_bits[ROWS][COLS];
  wire checkpoint_busy,checkpoint_done,checkpoint_error,checkpoint_mem_req,checkpoint_mem_we;
  wire [9:0] checkpoint_mem_addr;
  wire [15:0] checkpoint_mem_wdata,checkpoint_mem_rdata;
  wire checkpoint_mem_rvalid;
  fp32_pe_array_8x16 #(.ROWS(ROWS),.COLS(COLS),.K(BLOCK_K)) dut(
    .clk(clk),.rst_n(rst_n),.start(start),.stream_valid(stream_valid),
    .task_first(task_first),.task_last(task_last),.a_left(a_left),.b_top(b_top),.bias_in(bias_in),
    .checkpoint_save_req(checkpoint_save_req),.checkpoint_restore_req(checkpoint_restore_req),
    .checkpoint_busy(checkpoint_busy),.checkpoint_done(checkpoint_done),.checkpoint_error(checkpoint_error),
    .checkpoint_mem_req(checkpoint_mem_req),.checkpoint_mem_we(checkpoint_mem_we),
    .checkpoint_mem_addr(checkpoint_mem_addr),.checkpoint_mem_wdata(checkpoint_mem_wdata),
    .checkpoint_mem_rvalid(checkpoint_mem_rvalid),.checkpoint_mem_rdata(checkpoint_mem_rdata),
    .busy(busy),.done(done),.result_valid(result_valid),.result(result),
    .trace_valid(trace_valid),.trace_bias_valid(trace_bias_valid),.trace_cycle(trace_cycle),
    .trace_acc_after_bits(trace_acc_after_bits));
  matrix_cache_manager #(.ADDR_WIDTH(10),.DEPTH(1024)) checkpoint_mem(
    .clk(clk),.rst_n(rst_n),
    .a_wr_en(1'b0),.a_wr_addr(10'd0),.a_wr_data(16'd0),
    .b_wr_en(1'b0),.b_wr_addr(10'd0),.b_wr_data(16'd0),
    .result_wr_en(checkpoint_mem_req && checkpoint_mem_we),
    .result_wr_addr(checkpoint_mem_addr),.result_wr_data(checkpoint_mem_wdata),
    .a_rd_en(1'b0),.a_rd_addr(10'd0),.b_rd_en(1'b0),.b_rd_addr(10'd0),
    .result_rd_en(checkpoint_mem_req && !checkpoint_mem_we),.result_rd_addr(checkpoint_mem_addr),
    .a_rd_data(),.a_rd_valid(),.b_rd_data(),.b_rd_valid(),
    .result_rd_data(checkpoint_mem_rdata),.result_rd_valid(checkpoint_mem_rvalid));

  integer r,c,k,cycle=0,wait_cycles=0,writes=0,reads=0,restores=0,results=0;
  integer save_seen[0:CELLS*4-1],read_seen[0:CELLS*4-1];
  integer pending_read_valid, pending_read_addr;
  integer fd, result_fd;
  reg [31:0] saved_acc[0:CELLS-1],saved_bias[0:CELLS-1];
  reg [31:0] expected = 32'h42c20000; // 32*1 + 32*2 + bias(1) = 97
  reg saw_reset=0,saw_save=0,saw_restore=0;

  always @(posedge clk) begin
    integer index;
    if(!rst_n) begin
      cycle=0;
      if(saw_save) saw_reset=1;
    end else begin
      cycle=cycle+1;
      if(checkpoint_mem_rvalid) begin
        if(!pending_read_valid) $fatal(1,"unexpected checkpoint SRAM response");
        if(checkpoint_mem_rdata !== checkpoint_mem.result_mem[pending_read_addr])
          $fatal(1,"checkpoint read data mismatch addr=%0d got=%h expected=%h",
                 pending_read_addr,checkpoint_mem_rdata,checkpoint_mem.result_mem[pending_read_addr]);
        case (pending_read_addr%4)
          0,2: if(checkpoint_mem_rdata !== 16'h0000) $fatal(1,"checkpoint low halfword mismatch addr=%0d",pending_read_addr);
          1: if(checkpoint_mem_rdata !== 16'h4200) $fatal(1,"partial sum high halfword mismatch addr=%0d",pending_read_addr);
          3: if(checkpoint_mem_rdata !== 16'h3f80) $fatal(1,"bias high halfword mismatch addr=%0d",pending_read_addr);
        endcase
        pending_read_valid=0;
      end
      if(checkpoint_mem_req) begin
        index=checkpoint_mem_addr;
        if(index>=CELLS*4) $fatal(1,"checkpoint address out of range");
        $fdisplay(fd,"%0d,%s,%0d,%0d,0x%04h,%0d,0x%04h",cycle,
          checkpoint_mem_we?"write":"read_request",index,checkpoint_mem_we,checkpoint_mem_wdata,
          checkpoint_mem_rvalid,checkpoint_mem_rdata);
        if(checkpoint_mem_we) begin
          if(index!=writes || save_seen[index] !== 0) $fatal(1,"bad/duplicate SRAM save address %0d",index);
          if(index%4==0 && checkpoint_mem_wdata !== 16'h0000)
            $fatal(1,"unexpected accumulator checkpoint halfword addr=%0d",index);
          if(index%4==1 && checkpoint_mem_wdata !== 16'h4200)
            $fatal(1,"unexpected accumulator high halfword addr=%0d",index);
          if(index%4==3 && checkpoint_mem_wdata !== 16'h3f80)
            $fatal(1,"unexpected bias high halfword addr=%0d",index);
          save_seen[index]=1; writes=writes+1;
        end else begin
          if(index!=reads || read_seen[index] !== 0) $fatal(1,"bad/duplicate SRAM read address %0d",index);
          pending_read_valid=1; pending_read_addr=index;
          read_seen[index]=1; reads=reads+1;
        end
      end
      if(checkpoint_mem_rvalid) begin
        $fdisplay(fd,"%0d,read_response,%0d,0,0x0000,1,0x%04h",cycle,pending_read_addr,checkpoint_mem_rdata);
      end
      if(dut.checkpoint_state == 3'd4) restores=restores+1;
      if(checkpoint_done) begin
        if(checkpoint_error) $fatal(1,"checkpoint done with error");
        if(!saw_save) begin
          saw_save=1;
          if(writes !== CELLS*4) $fatal(1,"incomplete checkpoint save %0d",writes);
        end else begin
          saw_restore=1;
          if(reads !== CELLS*4) $fatal(1,"incomplete checkpoint read %0d",reads);
        end
      end
      if(result_valid) begin
        results=results+1;
        for(r=0;r<ROWS;r=r+1) for(c=0;c<COLS;c=c+1)
          if(result[r][c]!==expected) $fatal(1,"restored result mismatch r=%0d c=%0d got=%h",r,c,result[r][c]);
        $fdisplay(result_fd,"%0d,all,%0d,0x%08h",cycle,results,expected);
      end
    end
  end

  initial begin
    for(r=0;r<ROWS;r=r+1) a_left[r]=32'h3f800000;
    for(c=0;c<COLS;c=c+1) begin b_top[c]=32'h3f800000; bias_in[c]=32'h3f800000; end
    for(k=0;k<CELLS*4;k=k+1) begin save_seen[k]=0; read_seen[k]=0; end
    for(k=0;k<CELLS;k=k+1) begin saved_acc[k]=0; saved_bias[k]=0; end
    cycle=0; wait_cycles=0; writes=0; reads=0; restores=0; results=0;
    pending_read_valid=0; pending_read_addr=0;
    fd=$fopen("checkpoint_trace.csv","w");
    result_fd=$fopen("checkpoint_result.csv","w");
    $fdisplay(fd,"cycle,kind,address,we,wdata,rvalid,rdata");
    $fdisplay(result_fd,"cycle,scope,count,result_bits");
    repeat(3) @(negedge clk); rst_n=1;
    // Invalid checkpoint requests are reported and do not touch SRAM.
    checkpoint_save_req=1; @(negedge clk); checkpoint_save_req=0; #1;
    if(checkpoint_error!==1'b1 || checkpoint_mem_req) $fatal(1,"invalid save request was not rejected");
    @(negedge clk); #1; if(checkpoint_error!==1'b0) $fatal(1,"checkpoint error pulse did not clear");
    // First block: every product is 1.0, so each partial sum is 32.0.
    for(k=0;k<BLOCK_K;k=k+1) begin
      @(negedge clk); start=(k==0); stream_valid=1; task_first=(k==0); task_last=0;
      for(r=0;r<ROWS;r=r+1) a_left[r]=32'h3f800000;
      for(c=0;c<COLS;c=c+1) b_top[c]=32'h3f800000;
    end
    @(negedge clk); start=0;stream_valid=0;task_first=0;task_last=0;
    wait_cycles=0; while(!dut.all_cells_wait_block) begin @(negedge clk); wait_cycles=wait_cycles+1; if(wait_cycles>2000)$fatal(1,"wait block timeout"); end
    checkpoint_save_req=1; @(negedge clk); checkpoint_save_req=0;
    wait_cycles=0; while(!checkpoint_done) begin @(negedge clk);wait_cycles=wait_cycles+1;if(wait_cycles>2000)$fatal(1,"save timeout");end
    @(posedge clk); #1;
    // Deliberately reset array and control state; the SRAM model does not clear.
    rst_n=0; repeat(3) @(negedge clk);
    if(!saw_reset) $fatal(1,"reset checkpoint not observed");
    for(r=0;r<ROWS;r=r+1) for(c=0;c<COLS;c=c+1)
      if(dut.cell_acc_checkpoint[r][c]!==32'd0 || dut.cell_state[r][c]!==3'd0)
        $fatal(1,"array reset did not clear PE state");
    rst_n=1;
    checkpoint_restore_req=1; @(negedge clk); checkpoint_restore_req=0;
    wait_cycles=0; while(!checkpoint_done) begin @(negedge clk);wait_cycles=wait_cycles+1;if(wait_cycles>5000)$fatal(1,"restore timeout");end
    @(posedge clk); #1;
    for(r=0;r<ROWS;r=r+1) for(c=0;c<COLS;c=c+1)
      if(dut.cell_acc_checkpoint[r][c]!==32'h42000000 || dut.cell_bias_checkpoint[r][c]!==32'h3f800000 ||
         dut.cell_state[r][c]!==3'd4)
        $fatal(1,"restored PE checkpoint mismatch r=%0d c=%0d",r,c);
    // Second block: every product is 2.0, and final bias is 1.0.
    for(k=0;k<BLOCK_K;k=k+1) begin
      @(negedge clk); start=(k==0); stream_valid=1; task_first=0; task_last=(k==BLOCK_K-1);
      for(r=0;r<ROWS;r=r+1) a_left[r]=32'h40000000;
      for(c=0;c<COLS;c=c+1) b_top[c]=32'h3f800000;
    end
    @(negedge clk); start=0;stream_valid=0;task_first=0;task_last=0;
    wait_cycles=0; while(!done) begin @(negedge clk);wait_cycles=wait_cycles+1;if(wait_cycles>5000)$fatal(1,"final compute timeout");end
    repeat(3) @(negedge clk);
    if(!saw_save || !saw_restore || !saw_reset || writes !== CELLS*4 || reads !== CELLS*4 ||
       restores !== CELLS || results !== 1 || checkpoint_error !== 1'b0 || pending_read_valid !== 0)
      $fatal(1,"checkpoint evidence incomplete save=%0d read=%0d reset=%0d writes=%0d reads=%0d results=%0d err=%0d",saw_save,saw_restore,saw_reset,writes,reads,results,checkpoint_error);
    $display("PASS: SRAM checkpoint save=%0d read=%0d restored_cells=%0d result=0x%08h",writes,reads,CELLS,expected);
    $fclose(fd);$fclose(result_fd);$finish;
  end
  initial begin #2000000; $fatal(1,"checkpoint TB timeout"); end
endmodule
