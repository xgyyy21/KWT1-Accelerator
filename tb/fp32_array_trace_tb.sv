`timescale 1ns/1ps
// Read-only probes observe the real array. No reference arithmetic is called.
module fp32_array_trace_tb;
  parameter integer ROWS=8, COLS=16, TOTAL_K=64;
  parameter integer VALID_ROWS=ROWS, VALID_COLS=COLS, ROW_BASE=0, COL_BASE=0;
  localparam integer BLOCK_K=32;
  reg clk=0;
  always #5 clk=~clk;
  reg rst_n=0, start=0, stream_valid=0, task_first=0, task_last=0;
  reg [31:0] a_left[ROWS], b_top[COLS], bias_in[COLS];
  reg checkpoint_save_req=0, checkpoint_restore_req=0;
  wire checkpoint_busy, checkpoint_done, checkpoint_error, checkpoint_mem_req, checkpoint_mem_we;
  wire [9:0] checkpoint_mem_addr;
  wire [15:0] checkpoint_mem_wdata, checkpoint_mem_rdata;
  reg checkpoint_mem_rvalid=0;
  wire busy, done, result_valid;
  wire [31:0] result[ROWS][COLS];
  wire trace_valid[ROWS][COLS], trace_bias_valid[ROWS][COLS];
  wire [31:0] trace_cycle[ROWS][COLS], trace_x_bits[ROWS][COLS], trace_w_bits[ROWS][COLS];
  wire [31:0] trace_acc_before_bits[ROWS][COLS], trace_product_bits[ROWS][COLS];
  wire [31:0] trace_acc_after_bits[ROWS][COLS], trace_bias_bits[ROWS][COLS];
  wire [15:0] trace_k[ROWS][COLS];
  fp32_pe_array_8x16 #(.ROWS(ROWS),.COLS(COLS),.K(BLOCK_K)) dut(.*);

  wire write_valid, write_last, collector_busy, collector_done;
  wire [31:0] write_data;
  wire [15:0] write_row, write_col;
  tile_result_collector #(.ROWS(ROWS),.COLS(COLS),.DATA_WIDTH(32)) collector(
    .clk(clk),.rst_n(rst_n),.start(start),.pe_result_valid(result_valid),.pe_result(result),
    .valid_rows(16'(VALID_ROWS)),.valid_cols(16'(VALID_COLS)),
    .result_valid(write_valid),.result_last(write_last),.result_data(write_data),
    .result_row(write_row),.result_col(write_col),.busy(collector_busy),.done(collector_done));

  wire [2:0] pe_state[ROWS][COLS];
  wire [31:0] accumulator[ROWS][COLS];
  wire accept_pair[ROWS][COLS], mul_commit[ROWS][COLS], add_issue[ROWS][COLS];
  genvar gr,gc;
  generate for(gr=0;gr<ROWS;gr=gr+1) begin:G_R
    for(gc=0;gc<COLS;gc=gc+1) begin:G_C
      assign pe_state[gr][gc]=dut.G_CELL_ROW[gr].G_CELL_COL[gc].u_pe.state;
      assign accumulator[gr][gc]=dut.G_CELL_ROW[gr].G_CELL_COL[gc].u_pe.accumulator;
      assign accept_pair[gr][gc]=dut.cell_valid[gr][gc];
      assign mul_commit[gr][gc]=dut.G_CELL_ROW[gr].G_CELL_COL[gc].u_pe.mul_valid_pipe[7];
      assign add_issue[gr][gc]=(pe_state[gr][gc]==2 || pe_state[gr][gc]==3) &&
                                 !dut.G_CELL_ROW[gr].G_CELL_COL[gc].u_pe.add_busy;
    end
  end endgenerate
  reg [15:0] x_words[0:ROWS*TOTAL_K*2-1], w_words[0:TOTAL_K*COLS*2-1], bias_words[0:COLS*2-1];
  integer accepted[ROWS][COLS], multiplied[ROWS][COLS], retired[ROWS][COLS], biased[ROWS][COLS];
  integer accepted_cycle[ROWS][COLS][TOTAL_K], issue_cycle[ROWS][COLS];
  reg [31:0] saved_acc[ROWS][COLS];
  integer cycle=0, writes=0, array_finishes=0, hold_checks=0;
  integer formal_fd,raw_fd,stage_fd,status_fd,write_fd;
  string input_dir,output_dir,case_id,revision,manifest_hash,reference_hash;
  reg capture=0, hold_mode=0;

  function automatic reg all_waiting;
    integer r,c;
    begin
      all_waiting=1;
      for(r=0;r<ROWS;r=r+1) for(c=0;c<COLS;c=c+1)
        if(pe_state[r][c]!==3'd4) all_waiting=0;
    end
  endfunction

  // Pre-NBA probes record acceptance/issue; post-NBA probes record retirement.
  always @(posedge clk) begin:monitor
    integer r,c,n;
    if(!rst_n) begin
      cycle=0; writes=0; array_finishes=0; hold_checks=0;
      for(r=0;r<ROWS;r=r+1) for(c=0;c<COLS;c=c+1) begin
        accepted[r][c]=0; multiplied[r][c]=0; retired[r][c]=0; biased[r][c]=0;
        issue_cycle[r][c]=-1;
      end
    end else begin
      cycle=cycle+1;
      if(capture) for(r=0;r<ROWS;r=r+1) for(c=0;c<COLS;c=c+1) begin
        if(accept_pair[r][c]) begin
          n=accepted[r][c];
          if(n>=TOTAL_K) $fatal(1,"too many inputs r=%0d c=%0d",r,c);
          if(dut.a_pipe[r][c]!=={x_words[(r*TOTAL_K+n)*2+1],x_words[(r*TOTAL_K+n)*2]} ||
             dut.b_pipe[r][c]!=={w_words[(n*COLS+c)*2+1],w_words[(n*COLS+c)*2]})
            $fatal(1,"systolic operand mapping mismatch r=%0d c=%0d k=%0d",r,c,n);
          accepted_cycle[r][c][n]=cycle;
          accepted[r][c]=n+1;
        end
        if(mul_commit[r][c]) begin
          n=multiplied[r][c];
          if(n>=accepted[r][c] || cycle-accepted_cycle[r][c][n]!=8)
            $fatal(1,"multiplier latency not 8 r=%0d c=%0d",r,c);
          multiplied[r][c]=n+1;
        end
        if(add_issue[r][c]) issue_cycle[r][c]=cycle;
        if(accept_pair[r][c] || mul_commit[r][c] || add_issue[r][c])
          $fdisplay(stage_fd,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",cycle,r,c,
                    accept_pair[r][c],mul_commit[r][c],add_issue[r][c],pe_state[r][c],
                    accepted[r][c],multiplied[r][c]);
      end
      #1;
      if(capture) begin
        $fdisplay(status_fd,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",cycle,stream_valid,busy,
                  done,result_valid,collector_busy,collector_done,write_valid);
        if(done!==result_valid) $fatal(1,"array done/result_valid mismatch");
        if(result_valid) begin
          array_finishes=array_finishes+1;
          if(busy) $fatal(1,"array busy at completion");
          for(r=0;r<ROWS;r=r+1) for(c=0;c<COLS;c=c+1)
            if(retired[r][c]!=TOTAL_K || biased[r][c]!=1)
              $fatal(1,"premature array completion");
        end
        for(r=0;r<ROWS;r=r+1) for(c=0;c<COLS;c=c+1) begin
          if(hold_mode) begin
            if(accumulator[r][c]!==saved_acc[r][c] || trace_valid[r][c] || trace_bias_valid[r][c])
              $fatal(1,"partial sum changed while waiting r=%0d c=%0d",r,c);
            hold_checks=hold_checks+1;
          end
          if(trace_valid[r][c] || trace_bias_valid[r][c]) begin
            if(trace_valid[r][c] && trace_bias_valid[r][c]) $fatal(1,"both event valids high");
            if(trace_cycle[r][c]!==cycle || cycle-issue_cycle[r][c]!=4)
              $fatal(1,"commit cycle/add latency mismatch r=%0d c=%0d",r,c);
            if(accumulator[r][c]!==trace_acc_after_bits[r][c]) $fatal(1,"trace/accumulator mismatch");
            if(dut.cell_result_valid[r][c]!==trace_bias_valid[r][c]) $fatal(1,"PE result_valid mismatch");
            $fdisplay(raw_fd,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,0x%08h,0x%08h,0x%08h,0x%08h,0x%08h,0x%08h,0x%08h,0x%08h",
              cycle,r,c,trace_valid[r][c],trace_bias_valid[r][c],dut.cell_result_valid[r][c],trace_k[r][c],
              trace_x_bits[r][c],trace_w_bits[r][c],trace_acc_before_bits[r][c],trace_product_bits[r][c],
              trace_acc_after_bits[r][c],trace_bias_bits[r][c],result[r][c],accumulator[r][c]);
            if(trace_valid[r][c]) begin
              n=retired[r][c];
              if(n>=TOTAL_K || trace_k[r][c]!==16'(n%BLOCK_K) || biased[r][c]!=0)
                $fatal(1,"MAC global/local K order mismatch");
              if(r<VALID_ROWS && c<VALID_COLS)
                $fdisplay(formal_fd,"rtl_measured,%s,%0d,%0d,%0d,mac,%0d,1,%0d,0x%08h,0x%08h,0x%08h,0x%08h,0x%08h,,,%s,%s,%s",
                  case_id,n/BLOCK_K,r+ROW_BASE,c+COL_BASE,cycle,n,trace_x_bits[r][c],trace_w_bits[r][c],
                  trace_acc_before_bits[r][c],trace_product_bits[r][c],trace_acc_after_bits[r][c],revision,manifest_hash,reference_hash);
              retired[r][c]=n+1;
            end else begin
              if(retired[r][c]!=TOTAL_K || biased[r][c]!=0 || result[r][c]!==trace_acc_after_bits[r][c])
                $fatal(1,"bias count/order/result mismatch");
              biased[r][c]=1;
              // Bias broadcasts by column: unused rows still compute bias.
              // They must be excluded by the collector, not mislabelled zero.
              if(c>=VALID_COLS && result[r][c]!==32'd0)
                $fatal(1,"padded column result not positive zero");
              if(r>=VALID_ROWS && c<VALID_COLS && result[r][c]!==bias_in[c])
                $fatal(1,"padded row result must equal broadcast bias");
              if(r<VALID_ROWS && c<VALID_COLS)
                $fdisplay(formal_fd,"rtl_measured,%s,%0d,%0d,%0d,bias,%0d,1,,,,0x%08h,,0x%08h,0x%08h,0x%08h,%s,%s,%s",
                  case_id,(TOTAL_K-1)/BLOCK_K,r+ROW_BASE,c+COL_BASE,cycle,trace_acc_before_bits[r][c],
                  trace_acc_after_bits[r][c],trace_bias_bits[r][c],result[r][c],revision,manifest_hash,reference_hash);
            end
          end
        end
        if(write_valid) begin
          if(write_row!==16'(writes/VALID_COLS) || write_col!==16'(writes%VALID_COLS) ||
             write_data!==result[write_row][write_col] || write_last!==(writes==VALID_ROWS*VALID_COLS-1))
            $fatal(1,"collector coordinate/data/last mismatch");
          $fdisplay(write_fd,"%0d,%0d,%0d,0x%08h,%0d",cycle,write_row+ROW_BASE,write_col+COL_BASE,write_data,write_last);
          writes=writes+1;
        end
      end
    end
  end

  initial begin:driver
    integer r,c,k,wait_cycles;
    if(!$value$plusargs("input=%s",input_dir) || !$value$plusargs("output=%s",output_dir) ||
       !$value$plusargs("case=%s",case_id) || !$value$plusargs("revision=%s",revision) ||
       !$value$plusargs("manifest=%s",manifest_hash) || !$value$plusargs("reference=%s",reference_hash))
      $fatal(1,"missing required plusarg");
    $readmemh({input_dir,"/x.mem"},x_words);
    $readmemh({input_dir,"/w.mem"},w_words);
    $readmemh({input_dir,"/bias.mem"},bias_words);
    formal_fd=$fopen({output_dir,"/pe_trace.csv"},"w");
    raw_fd=$fopen({output_dir,"/signal_trace.csv"},"w");
    stage_fd=$fopen({output_dir,"/stage_trace.csv"},"w");
    status_fd=$fopen({output_dir,"/array_status.csv"},"w");
    write_fd=$fopen({output_dir,"/result_writeout.csv"},"w");
    if(!formal_fd || !raw_fd || !stage_fd || !status_fd || !write_fd) $fatal(1,"cannot open evidence files");
    $fdisplay(formal_fd,"source_kind,case_id,tile_id,row,column,event,cycle,valid,k,x_bits,w_bits,acc_before_bits,product_bits,acc_after_bits,bias_bits,result_bits,rtl_commit,input_manifest_sha256,reference_trace_sha256");
    $fdisplay(raw_fd,"cycle,physical_row,physical_column,trace_valid,trace_bias_valid,result_valid,local_k,x_bits,w_bits,acc_before_bits,product_bits,acc_after_bits,bias_bits,result_bits,accumulator_bits");
    $fdisplay(stage_fd,"cycle,physical_row,physical_column,accept_pair,mul_commit,add_issue,state,accepted_total,multiplied_total");
    $fdisplay(status_fd,"cycle,stream_valid,busy,done,result_valid,collector_busy,collector_done,write_valid");
    $fdisplay(write_fd,"cycle,row,column,result_bits,last");
    for(r=0;r<ROWS;r=r+1) a_left[r]=0;
    for(c=0;c<COLS;c=c+1) begin b_top[c]=0; bias_in[c]={bias_words[2*c+1],bias_words[2*c]}; end
    repeat(3) @(negedge clk);
    // Abort a real in-flight task, then reset all cells before measured work.
    rst_n=1; start=1; stream_valid=1; task_first=1;
    for(r=0;r<ROWS;r=r+1) a_left[r]={x_words[(r*TOTAL_K)*2+1],x_words[(r*TOTAL_K)*2]};
    for(c=0;c<COLS;c=c+1) b_top[c]={w_words[c*2+1],w_words[c*2]};
    @(negedge clk); start=0; stream_valid=0; task_first=0;
    repeat(12) @(negedge clk);
    rst_n=0;
    repeat(3) @(negedge clk);
    for(r=0;r<ROWS;r=r+1) for(c=0;c<COLS;c=c+1)
      if(accumulator[r][c]!==32'd0 || pe_state[r][c]!==3'd0 || trace_valid[r][c] || trace_bias_valid[r][c])
        $fatal(1,"reset failed to clear in-flight task");
    $display("RESET_ABORT_CHECK PASS cells=%0d",ROWS*COLS);
    rst_n=1; capture=1;
    for(k=0;k<TOTAL_K;k=k+1) begin
      if(k!=0 && k%BLOCK_K==0) begin
        wait_cycles=0;
        while(!all_waiting()) begin
          @(negedge clk); wait_cycles=wait_cycles+1;
          if(wait_cycles>2000) $fatal(1,"timeout waiting for K block drain");
        end
        for(r=0;r<ROWS;r=r+1) for(c=0;c<COLS;c=c+1) saved_acc[r][c]=accumulator[r][c];
        hold_mode=1;
        repeat(9) @(negedge clk);
        hold_mode=0;
        $display("BLOCK_HOLD_CHECK PASS next_global_k=%0d hold_cycles=9",k);
      end
      if(k%5==3) repeat(2) @(negedge clk);
      start=(k==0); stream_valid=1; task_first=(k==0); task_last=(k==TOTAL_K-1);
      for(r=0;r<ROWS;r=r+1) a_left[r]={x_words[(r*TOTAL_K+k)*2+1],x_words[(r*TOTAL_K+k)*2]};
      for(c=0;c<COLS;c=c+1) b_top[c]={w_words[(k*COLS+c)*2+1],w_words[(k*COLS+c)*2]};
      @(negedge clk); start=0; stream_valid=0; task_first=0; task_last=0;
    end
    wait_cycles=0;
    while(writes<VALID_ROWS*VALID_COLS) begin
      @(negedge clk); wait_cycles=wait_cycles+1;
      if(wait_cycles>4000) $fatal(1,"timeout waiting for result writeout");
    end
    repeat(10) @(negedge clk);
    if(array_finishes!=1 || writes!=VALID_ROWS*VALID_COLS) $fatal(1,"completion count mismatch");
    for(r=0;r<ROWS;r=r+1) for(c=0;c<COLS;c=c+1)
      if(accepted[r][c]!=TOTAL_K || multiplied[r][c]!=TOTAL_K || retired[r][c]!=TOTAL_K || biased[r][c]!=1)
        $fatal(1,"event coverage mismatch r=%0d c=%0d",r,c);
    if(hold_checks!=((TOTAL_K-1)/BLOCK_K)*9*ROWS*COLS) $fatal(1,"hold coverage mismatch");
    $display("PASS case=%s physical=%0dx%0d valid=%0dx%0d K=%0d writes=%0d hold_checks=%0d cycles=%0d",case_id,ROWS,COLS,VALID_ROWS,VALID_COLS,TOTAL_K,writes,hold_checks,cycle);
    $fclose(formal_fd); $fclose(raw_fd); $fclose(stage_fd); $fclose(status_fd); $fclose(write_fd);
    $finish;
  end
  initial begin #1000000; $fatal(1,"watchdog timeout"); end
endmodule
