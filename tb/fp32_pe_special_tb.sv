`timescale 1ns/1ps
// File-backed, measured single-PE tests. K is the actual per-block capacity,
// not the total dot-product depth. No golden arithmetic generates trace data.
module fp32_pe_special_tb #(
  parameter integer ROWS=1, COLS=1, TOTAL_K=2, BLOCK_K=32
);
  logic clk=0;
  always #5 clk=~clk;
  logic rst_n=0, enable=1, clear_acc=0, task_first=0, task_last=0, in_valid=0;
  logic [31:0] a_in=0, b_in=0, bias_in=0;
  logic checkpoint_restore=0;
  logic [31:0] checkpoint_accumulator=0, checkpoint_bias=0;
  wire [31:0] checkpoint_accumulator_out, checkpoint_bias_out;
  wire [2:0] checkpoint_state_out;
  wire result_valid, busy, done, trace_valid, trace_bias_valid;
  wire [31:0] result, trace_cycle, trace_x_bits, trace_w_bits;
  wire [31:0] trace_acc_before_bits, trace_product_bits, trace_acc_after_bits, trace_bias_bits;
  wire [15:0] trace_k;
  logic [15:0] x_words[0:ROWS*TOTAL_K*2-1];
  logic [15:0] w_words[0:TOTAL_K*COLS*2-1], bias_words[0:COLS*2-1];
  string x_file, w_file, bias_file, output_dir, case_id;
  string rtl_revision, manifest_hash, reference_hash;
  integer cycle=0, row_idx=0, col_idx=0, block_base=0;
  integer csv_fd, signals_fd, cell_mac=0, cell_bias=0;
  integer accept_count=0, mul_count=0, issue_count=0;
  integer all_mac=0, all_bias=0, boundary_count=0;
  integer accepted_cycle[0:TOTAL_K-1], mul_cycle[0:TOTAL_K-1];
  integer issue_cycle[0:TOTAL_K-1], bias_issue_cycle=0;
  logic capture=0;
  logic [31:0] previous_acc=0, held_acc=0;
  logic pre_accept, pre_mul, pre_add, pre_bias;
  logic [15:0] pre_mul_k, pre_add_k;
  logic [31:0] pre_sum;
  integer global_k, timeout_count, block_length;

  fp32_pe_mac #(.K(BLOCK_K)) dut(.*);

  // Read pipeline inputs before NBA, registered trace outputs after NBA.
  always @(posedge clk) begin
    if (!rst_n) cycle=0;
    else begin
      cycle=cycle+1;
      pre_accept=enable && in_valid;
      pre_mul=dut.mul_valid_pipe[7];
      pre_mul_k=dut.mul_k_pipe[7];
      pre_add=(dut.state==dut.S_ADD || dut.state==dut.S_BIAS) && !dut.add_busy;
      pre_bias=(dut.state==dut.S_BIAS);
      pre_add_k=dut.add_index;
      pre_sum=dut.add_sum_pipe[3];
      #1;
      if (capture) begin
        if (pre_accept) begin
          if (accept_count>=TOTAL_K || task_first!==(accept_count==0) ||
              task_last!==(accept_count==TOTAL_K-1) || clear_acc)
            $fatal(1,"input control/order mismatch");
          accepted_cycle[accept_count]=cycle;
          $display("INPUT row=%0d column=%0d cycle=%0d global_k=%0d block=%0d first=%0d last=%0d x=%08x w=%08x",
            row_idx,col_idx,cycle,accept_count,block_base/BLOCK_K,task_first,task_last,a_in,b_in);
          accept_count=accept_count+1;
        end
        if (pre_mul) begin
          global_k=block_base+pre_mul_k;
          if (global_k!=mul_count || global_k>=accept_count ||
              cycle-accepted_cycle[global_k]!=8)
            $fatal(1,"multiplier global index/8-cycle boundary mismatch");
          mul_cycle[global_k]=cycle;
          $display("MUL_READY row=%0d column=%0d cycle=%0d global_k=%0d local_k=%0d input_cycle=%0d",
            row_idx,col_idx,cycle,global_k,pre_mul_k,accepted_cycle[global_k]);
          mul_count=mul_count+1;
        end
        if (pre_add) begin
          if (pre_bias) begin
            if (cell_mac!=TOTAL_K || cell_bias!=0) $fatal(1,"early/repeated bias issue");
            bias_issue_cycle=cycle;
          end else begin
            global_k=block_base+pre_add_k;
            if (global_k!=issue_count || mul_cycle[global_k]==0)
              $fatal(1,"add index/order/product readiness mismatch");
            issue_cycle[global_k]=cycle;
            issue_count=issue_count+1;
          end
        end
        if (trace_valid && trace_bias_valid) $fatal(1,"overlapping trace valids");
        if (result_valid!==trace_bias_valid || done!==trace_bias_valid)
          $fatal(1,"result/done/bias misalignment");
        if (trace_valid || trace_bias_valid) begin
          if (trace_cycle!==cycle || dut.accumulator!==trace_acc_after_bits ||
              trace_acc_after_bits!==pre_sum || trace_acc_before_bits!==previous_acc)
            $fatal(1,"trace alignment/accumulator continuity mismatch");
          previous_acc=trace_acc_after_bits;
        end
        if (trace_valid) begin
          global_k=block_base+trace_k;
          if (cell_bias!=0 || global_k!=cell_mac || trace_k>=BLOCK_K ||
              global_k>=TOTAL_K || cycle-issue_cycle[global_k]!=4)
            $fatal(1,"MAC local/global K/order/4-cycle latency mismatch");
          if (trace_x_bits!=={x_words[2*(row_idx*TOTAL_K+global_k)+1],x_words[2*(row_idx*TOTAL_K+global_k)]} ||
              trace_w_bits!=={w_words[2*(global_k*COLS+col_idx)+1],w_words[2*(global_k*COLS+col_idx)]})
            $fatal(1,"trace operands differ from loaded files");
          $fdisplay(csv_fd,"rtl_measured,%s,%0d,%0d,%0d,mac,%0d,1,%0d,0x%08x,0x%08x,0x%08x,0x%08x,0x%08x,,,%s,%s,%s",
            case_id,global_k/32,row_idx,col_idx,trace_cycle,global_k,trace_x_bits,trace_w_bits,
            trace_acc_before_bits,trace_product_bits,trace_acc_after_bits,rtl_revision,manifest_hash,reference_hash);
          $display("MAC_COMMIT row=%0d column=%0d cycle=%0d global_k=%0d local_k=%0d before=%08x product=%08x after=%08x",
            row_idx,col_idx,cycle,global_k,trace_k,trace_acc_before_bits,trace_product_bits,trace_acc_after_bits);
          cell_mac=cell_mac+1; all_mac=all_mac+1;
        end
        if (trace_bias_valid) begin
          if (cell_mac!=TOTAL_K || cell_bias!=0 || cycle-bias_issue_cycle!=4 || busy ||
              result!==trace_acc_after_bits ||
              trace_bias_bits!=={bias_words[2*col_idx+1],bias_words[2*col_idx]})
            $fatal(1,"bias count/timing/value/result mismatch");
          $fdisplay(csv_fd,"rtl_measured,%s,%0d,%0d,%0d,bias,%0d,1,,,,0x%08x,,0x%08x,0x%08x,0x%08x,%s,%s,%s",
            case_id,(TOTAL_K-1)/32,row_idx,col_idx,trace_cycle,trace_acc_before_bits,
            trace_acc_after_bits,trace_bias_bits,result,rtl_revision,manifest_hash,reference_hash);
          $display("BIAS_COMMIT row=%0d column=%0d cycle=%0d before=%08x bias=%08x result=%08x",
            row_idx,col_idx,cycle,trace_acc_before_bits,trace_bias_bits,result);
          cell_bias=cell_bias+1; all_bias=all_bias+1;
        end
        $fdisplay(signals_fd,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,0x%08x,0x%08x,0x%08x,0x%08x,0x%08x,0x%08x,0x%08x,0x%08x",
          cycle,row_idx,col_idx,block_base/BLOCK_K,rst_n,enable,clear_acc,task_first,task_last,
          pre_accept,pre_mul,pre_mul_k,pre_add,pre_bias,pre_add_k,trace_valid,trace_bias_valid,
          result_valid,done,busy,trace_k,trace_acc_before_bits,trace_product_bits,trace_acc_after_bits,
          trace_bias_bits,result,dut.accumulator,trace_x_bits,trace_w_bits);
      end
    end
  end

  initial begin
    case_id="rounding_nonfused";
    x_file="handoff/pe_hand_2x2_formal_2026-10-20/inputs/rounding_x.mem";
    w_file="handoff/pe_hand_2x2_formal_2026-10-20/inputs/rounding_w.mem";
    bias_file="handoff/pe_hand_2x2_formal_2026-10-20/inputs/rounding_bias.mem";
    output_dir="build"; rtl_revision="unversioned-regression-only";
    manifest_hash="148ac9b305c34dafd033ea33d98b4f0a13edbf1306c66d29c7926ed348941e93";
    reference_hash="a85bb5b7d334841acab94740290933bd3a991b881acf8782615cb8c43f73553b";
    if ($value$plusargs("CASE_ID=%s",case_id)) begin end
    if ($value$plusargs("X_FILE=%s",x_file)) begin end
    if ($value$plusargs("W_FILE=%s",w_file)) begin end
    if ($value$plusargs("BIAS_FILE=%s",bias_file)) begin end
    if ($value$plusargs("OUTPUT_DIR=%s",output_dir)) begin end
    if ($value$plusargs("RTL_REVISION=%s",rtl_revision)) begin end
    if ($value$plusargs("MANIFEST_SHA=%s",manifest_hash)) begin end
    if ($value$plusargs("REFERENCE_SHA=%s",reference_hash)) begin end
    if (ROWS<1 || COLS<1 || TOTAL_K<1 || BLOCK_K!=32) $fatal(1,"invalid test parameters");
    $readmemh(x_file,x_words); $readmemh(w_file,w_words); $readmemh(bias_file,bias_words);
    for (integer i=0;i<ROWS*TOTAL_K*2;i=i+1)
      if ((^x_words[i])===1'bx) $fatal(1,"unknown X word");
    for (integer i=0;i<TOTAL_K*COLS*2;i=i+1)
      if ((^w_words[i])===1'bx) $fatal(1,"unknown W word");
    for (integer i=0;i<COLS*2;i=i+1)
      if ((^bias_words[i])===1'bx) $fatal(1,"unknown bias word");
    csv_fd=$fopen({output_dir,"/pe_trace.csv"},"w");
    signals_fd=$fopen({output_dir,"/signal_trace.csv"},"w");
    if (!csv_fd || !signals_fd) $fatal(1,"cannot open output files");
    $fdisplay(csv_fd,"source_kind,case_id,tile_id,row,column,event,cycle,valid,k,x_bits,w_bits,acc_before_bits,product_bits,acc_after_bits,bias_bits,result_bits,rtl_commit,input_manifest_sha256,reference_trace_sha256");
    $fdisplay(signals_fd,"cycle,row,column,block,rst_n,enable,clear_acc,task_first,task_last,input_accept,mul_ready,mul_local_k,add_issue,add_is_bias,add_local_k,trace_valid,trace_bias_valid,result_valid,done,busy,trace_local_k,acc_before_bits,product_bits,acc_after_bits,bias_bits,result_bits,accumulator_bits,x_bits,w_bits");
    $display("SAMPLING posedge+#1ns after NBA; first edge out of reset=1; no inter-block reset; block_K=%0d total_K=%0d",BLOCK_K,TOTAL_K);
    $display("INPUT_FILES %s %s %s",x_file,w_file,bias_file);
    repeat(2) @(negedge clk);
    rst_n=1;
    for (integer r=0;r<ROWS;r=r+1) begin
      for (integer c=0;c<COLS;c=c+1) begin
        @(negedge clk);
        row_idx=r; col_idx=c; block_base=0;
        cell_mac=0; cell_bias=0; accept_count=0; mul_count=0; issue_count=0;
        previous_acc=0; capture=1;
        bias_in={bias_words[2*c+1],bias_words[2*c]};
        for (integer i=0;i<TOTAL_K;i=i+1) begin
          accepted_cycle[i]=0; mul_cycle[i]=0; issue_cycle[i]=0;
        end
        for (integer base=0;base<TOTAL_K;base=base+BLOCK_K) begin
          if (base!=0) begin
            timeout_count=0;
            while (cell_mac!=base || dut.state!=dut.S_WAIT_BLOCK) begin
              @(negedge clk); timeout_count=timeout_count+1;
              if (timeout_count>2000) $fatal(1,"timeout waiting for actual block completion");
            end
            held_acc=dut.accumulator;
            // The controller waits with enable low. Arithmetic pipelines are
            // not globally gated; all previous operations are already drained.
            enable=0;
            repeat(9) begin
              @(negedge clk);
              if (dut.state!=dut.S_WAIT_BLOCK || dut.accumulator!==held_acc ||
                  trace_valid || trace_bias_valid || result_valid || done || !busy)
                $fatal(1,"partial sum changed/early completion during block wait");
            end
            boundary_count=boundary_count+1;
            $display("BLOCK_RESUME row=%0d column=%0d cycle=%0d next_global_k=%0d held_acc=%08x wait_cycles=9 reset=0 clear=0",
              row_idx,col_idx,cycle,base,held_acc);
            enable=1;
          end
          block_base=base;
          block_length=((TOTAL_K-base)>BLOCK_K)?BLOCK_K:(TOTAL_K-base);
          for (integer local_k=0;local_k<block_length;local_k=local_k+1) begin
            // Deliberate input bubbles also verify valid-driven propagation.
            if (local_k!=0 && local_k%7==0) begin
              in_valid=0; task_first=0; task_last=0;
              repeat(2) @(negedge clk);
            end
            a_in={x_words[2*(r*TOTAL_K+base+local_k)+1],x_words[2*(r*TOTAL_K+base+local_k)]};
            b_in={w_words[2*((base+local_k)*COLS+c)+1],w_words[2*((base+local_k)*COLS+c)]};
            task_first=(base+local_k==0); task_last=(base+local_k==TOTAL_K-1); in_valid=1;
            @(negedge clk);
          end
          in_valid=0; task_first=0; task_last=0;
        end
        timeout_count=0;
        while (cell_bias==0) begin
          @(negedge clk); timeout_count=timeout_count+1;
          if (timeout_count>3000) $fatal(1,"timeout waiting for bias");
        end
        repeat(16) @(negedge clk);
        if (cell_mac!=TOTAL_K || cell_bias!=1 || accept_count!=TOTAL_K ||
            mul_count!=TOTAL_K || issue_count!=TOTAL_K)
          $fatal(1,"final stage/event count mismatch");
        capture=0;
      end
    end
    if (all_mac!=ROWS*COLS*TOTAL_K || all_bias!=ROWS*COLS ||
        boundary_count!=ROWS*COLS*((TOTAL_K-1)/BLOCK_K)) $fatal(1,"suite event count mismatch");
    $fclose(csv_fd); $fclose(signals_fd);
    $display("fp32_pe_special_tb PASS case=%s mac=%0d bias=%0d actual_block_boundaries=%0d",case_id,all_mac,all_bias,boundary_count);
    $finish;
  end
  initial begin #10000000; $fatal(1,"special PE test timeout"); end
endmodule
