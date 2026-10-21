`timescale 1ns/1ps
// Formal hand_2x2 handoff: measured RTL events, file-backed operands.
// No golden arithmetic is used to generate any event value.
module fp32_pe_formal_tb;
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
  logic [15:0] x_words[0:7], w_words[0:7], bias_words[0:3];
  string input_dir, output_dir, rtl_revision, manifest_hash, reference_hash;
  integer csv_fd, signals_fd, cycle=0, row_idx=0, col_idx=0;
  integer mac_count=0, bias_count=0, cell_mac=0, cell_bias=0;
  logic capture=0;
  integer accepted_cycle[0:1], mul_ready_cycle[0:1];
  integer add_issue_cycle=0, bias_issue_cycle=0;
  logic [31:0] previous_acc=0;
  integer pre_cycle;
  logic pre_accept, pre_mul, pre_add, pre_add_bias;
  logic [15:0] pre_mul_k, pre_add_k;
  logic [31:0] pre_mul_product, pre_add_before, pre_add_product, pre_add_sum;

  fp32_pe_mac #(.K(2)) dut(.*);

  // Posedge pre-NBA values identify pipeline boundaries; #1 samples registered
  // DUT outputs after NBA. cycle=1 is the first rising edge with rst_n=1.
  always @(posedge clk) begin
    if (!rst_n) cycle=0;
    else begin
      cycle=cycle+1;
      pre_cycle=cycle;
      pre_accept=enable && in_valid;
      pre_mul=dut.mul_valid_pipe[7];
      pre_mul_k=dut.mul_k_pipe[7];
      pre_mul_product=dut.mul_product_pipe[7];
      pre_add=(dut.state==3'd2 || dut.state==3'd3) && !dut.add_busy;
      pre_add_bias=(dut.state==3'd3);
      pre_add_k=dut.add_index;
      pre_add_before=dut.accumulator;
      pre_add_product=pre_add_bias ? dut.bias_reg : dut.product_mem[dut.add_index];
      pre_add_sum=dut.add_sum_pipe[3];
      #1;
      if (capture) begin
        if (pre_accept) begin
          if (task_first) accepted_cycle[0]=pre_cycle;
          else accepted_cycle[1]=pre_cycle;
          $display("INPUT row=%0d column=%0d cycle=%0d first=%0d last=%0d x=%08x w=%08x",row_idx,col_idx,cycle,task_first,task_last,a_in,b_in);
        end
        if (pre_mul) begin
          if (pre_mul_k>1 || pre_cycle-accepted_cycle[pre_mul_k]!=8)
            $fatal(1,"multiplier boundary timing mismatch");
          mul_ready_cycle[pre_mul_k]=pre_cycle;
          $display("MUL_READY row=%0d column=%0d k=%0d cycle=%0d input_cycle=%0d product=%08x",row_idx,col_idx,pre_mul_k,cycle,accepted_cycle[pre_mul_k],pre_mul_product);
        end
        if (pre_add) begin
          if (pre_add_bias) bias_issue_cycle=pre_cycle;
          else begin
            if (pre_add_k>1 || mul_ready_cycle[pre_add_k]==0)
              $fatal(1,"add issued before product boundary");
            add_issue_cycle=pre_cycle;
          end
          $display("ADD_ISSUE row=%0d column=%0d bias=%0d k=%0d cycle=%0d before=%08x operand=%08x",row_idx,col_idx,pre_add_bias,pre_add_k,cycle,pre_add_before,pre_add_product);
        end
        if (trace_valid && trace_bias_valid) $fatal(1,"trace valids overlap");
        if (result_valid !== trace_bias_valid || done !== trace_bias_valid)
          $fatal(1,"result/done/bias valid not aligned");
        if (trace_valid || trace_bias_valid) begin
          if (trace_cycle!==cycle || dut.accumulator!==trace_acc_after_bits ||
              trace_acc_after_bits!==pre_add_sum)
            $fatal(1,"trace cycle/commit value alignment mismatch");
          if (trace_acc_before_bits!==previous_acc) $fatal(1,"accumulator chain mismatch");
          previous_acc=trace_acc_after_bits;
        end
        if (trace_valid) begin
          if (cell_bias!=0 || cell_mac>=2 || trace_k!==cell_mac || cycle-add_issue_cycle!=4)
            $fatal(1,"MAC count/order/add latency mismatch");
          if (trace_x_bits!=={x_words[2*(row_idx*2+cell_mac)+1],x_words[2*(row_idx*2+cell_mac)]} ||
              trace_w_bits!=={w_words[2*(cell_mac*2+col_idx)+1],w_words[2*(cell_mac*2+col_idx)]})
            $fatal(1,"trace input not equal to loaded .mem operand");
          $fdisplay(csv_fd,"rtl_measured,hand_2x2,0,%0d,%0d,mac,%0d,1,%0d,0x%08x,0x%08x,0x%08x,0x%08x,0x%08x,,,%s,%s,%s",
            row_idx,col_idx,trace_cycle,trace_k,trace_x_bits,trace_w_bits,trace_acc_before_bits,trace_product_bits,trace_acc_after_bits,rtl_revision,manifest_hash,reference_hash);
          $display("MAC_COMMIT row=%0d column=%0d k=%0d cycle=%0d add_issue=%0d before=%08x product=%08x after=%08x",row_idx,col_idx,trace_k,cycle,add_issue_cycle,trace_acc_before_bits,trace_product_bits,trace_acc_after_bits);
          cell_mac=cell_mac+1; mac_count=mac_count+1;
        end
        if (trace_bias_valid) begin
          if (cell_mac!=2 || cell_bias!=0 || cycle-bias_issue_cycle!=4 || busy || result!==trace_acc_after_bits)
            $fatal(1,"bias timing/count/result mismatch");
          if (trace_bias_bits!=={bias_words[2*col_idx+1],bias_words[2*col_idx]})
            $fatal(1,"bias not equal to loaded .mem operand");
          $fdisplay(csv_fd,"rtl_measured,hand_2x2,0,%0d,%0d,bias,%0d,1,,,,0x%08x,,0x%08x,0x%08x,0x%08x,%s,%s,%s",
            row_idx,col_idx,trace_cycle,trace_acc_before_bits,trace_acc_after_bits,trace_bias_bits,result,rtl_revision,manifest_hash,reference_hash);
          $display("BIAS_COMMIT row=%0d column=%0d cycle=%0d add_issue=%0d before=%08x bias=%08x result=%08x",row_idx,col_idx,cycle,bias_issue_cycle,trace_acc_before_bits,trace_bias_bits,result);
          cell_bias=cell_bias+1; bias_count=bias_count+1;
        end
        $fdisplay(signals_fd,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,0x%08x,0x%08x,0x%08x,0x%08x,0x%08x,0x%08x,0x%08x",
          cycle,row_idx,col_idx,pre_accept,pre_mul,pre_mul_k,pre_add,pre_add_bias,pre_add_k,trace_valid,trace_bias_valid,result_valid,done,busy,trace_cycle,trace_k,trace_x_bits,trace_w_bits,trace_acc_before_bits,trace_product_bits,trace_acc_after_bits,trace_bias_bits,result);
      end
    end
  end

  initial begin
    input_dir="handoff/pe_hand_2x2_formal_2026-10-20/inputs";
    output_dir="build";
    rtl_revision="unversioned-regression-only";
    manifest_hash="148ac9b305c34dafd033ea33d98b4f0a13edbf1306c66d29c7926ed348941e93";
    reference_hash="a85bb5b7d334841acab94740290933bd3a991b881acf8782615cb8c43f73553b";
    if ($value$plusargs("INPUT_DIR=%s",input_dir)) begin end
    if ($value$plusargs("OUTPUT_DIR=%s",output_dir)) begin end
    if ($value$plusargs("RTL_REVISION=%s",rtl_revision)) begin end
    if ($value$plusargs("MANIFEST_SHA=%s",manifest_hash)) begin end
    if ($value$plusargs("REFERENCE_SHA=%s",reference_hash)) begin end
    $readmemh({input_dir,"/x.mem"},x_words);
    $readmemh({input_dir,"/w.mem"},w_words);
    $readmemh({input_dir,"/bias.mem"},bias_words);
    for(integer i=0;i<8;i=i+1) begin
      if ((^x_words[i])===1'bx || (^w_words[i])===1'bx) $fatal(1,"missing/unknown input word");
    end
    for(integer i=0;i<4;i=i+1)
      if ((^bias_words[i])===1'bx) $fatal(1,"missing/unknown bias word");
    csv_fd=$fopen({output_dir,"/pe_trace.csv"},"w");
    signals_fd=$fopen({output_dir,"/signal_trace.csv"},"w");
    if (!csv_fd || !signals_fd) $fatal(1,"cannot open output files");
    $fdisplay(csv_fd,"source_kind,case_id,tile_id,row,column,event,cycle,valid,k,x_bits,w_bits,acc_before_bits,product_bits,acc_after_bits,bias_bits,result_bits,rtl_commit,input_manifest_sha256,reference_trace_sha256");
    $fdisplay(signals_fd,"cycle,row,column,input_accept,mul_ready,mul_k,add_issue,add_is_bias,add_k,trace_valid,trace_bias_valid,result_valid,done,busy,trace_cycle,trace_k,x_bits,w_bits,acc_before_bits,product_bits,acc_after_bits,bias_bits,result_bits");
    $display("SAMPLING posedge+#1ns after NBA; first posedge out of reset=1; no per-cell reset; clock=10ns simulation only");
    $display("INPUT_FILES %s/x.mem %s/w.mem %s/bias.mem",input_dir,input_dir,input_dir);
    repeat(2) @(negedge clk);
    rst_n=1;
    for(integer r=0;r<2;r=r+1) begin
      for(integer c=0;c<2;c=c+1) begin
        @(negedge clk);
        row_idx=r; col_idx=c; cell_mac=0; cell_bias=0; previous_acc=0;
        accepted_cycle[0]=0; accepted_cycle[1]=0; mul_ready_cycle[0]=0; mul_ready_cycle[1]=0;
        capture=1; bias_in={bias_words[2*c+1],bias_words[2*c]};
        for(integer k=0;k<2;k=k+1) begin
          a_in={x_words[2*(r*2+k)+1],x_words[2*(r*2+k)]};
          b_in={w_words[2*(k*2+c)+1],w_words[2*(k*2+c)]};
          in_valid=1; task_first=(k==0); task_last=(k==1);
          @(negedge clk);
        end
        in_valid=0; task_first=0; task_last=0;
        // Guard observes all cycles, including bubbles after the result.
        repeat(40) @(negedge clk);
        if (cell_mac!=2 || cell_bias!=1) $fatal(1,"cell event count mismatch");
        capture=0;
      end
    end
    if (mac_count!=8 || bias_count!=4) $fatal(1,"total event count mismatch");
    $fclose(csv_fd); $fclose(signals_fd);
    $display("fp32_pe_formal_tb PASS cells=4 mac_events=8 bias_events=4 mul_latency=8 add_latency=4");
    $finish;
  end
  initial begin #200000; $fatal(1,"formal PE timeout"); end
endmodule
