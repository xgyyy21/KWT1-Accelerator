`timescale 1ns/1ps
// Cycle-level regression against a4e810d before idle payload enables.
// Baseline source is supplied separately by the evidence runner.
module fp32_idle_equivalence_tb;
  parameter integer ROWS=3, COLS=5, K=32;
  logic clk=0; always #5 clk=~clk;
  logic rst_n=0,start=0,stream_valid=0,task_first=0,task_last=0;
  logic [31:0] a_left[ROWS],b_top[COLS],bias_in[COLS];
  wire busy,done,result_valid,old_busy,old_done,old_result_valid;
  wire [31:0] result[ROWS][COLS],old_result[ROWS][COLS];
  wire tv[ROWS][COLS],bv[ROWS][COLS],otv[ROWS][COLS],obv[ROWS][COLS];
  wire [31:0] tc[ROWS][COLS],otc[ROWS][COLS];
  wire [15:0] tk[ROWS][COLS],otk[ROWS][COLS];
  wire [31:0] tx[ROWS][COLS],tw[ROWS][COLS],ta[ROWS][COLS],tp[ROWS][COLS],tz[ROWS][COLS],tbias[ROWS][COLS];
  wire [31:0] ox[ROWS][COLS],ow[ROWS][COLS],oa[ROWS][COLS],op[ROWS][COLS],oz[ROWS][COLS],obias[ROWS][COLS];
  integer cycle=0,mac_count=0,bias_count=0,outputs=0;
  integer r,c,t,k,g,block_idx,guard;
  logic [31:0] rng=32'h61021001;

  fp32_pe_array_8x16 #(.ROWS(ROWS),.COLS(COLS),.K(K)) dut(
    .clk(clk),.rst_n(rst_n),.start(start),.stream_valid(stream_valid),
    .task_first(task_first),.task_last(task_last),.a_left(a_left),.b_top(b_top),.bias_in(bias_in),
    .checkpoint_save_req(1'b0),.checkpoint_restore_req(1'b0),
    .checkpoint_mem_rvalid(1'b0),.checkpoint_mem_rdata(16'd0),
    .busy(busy),.done(done),.result_valid(result_valid),.result(result),
    .trace_valid(tv),.trace_bias_valid(bv),.trace_cycle(tc),.trace_k(tk),
    .trace_x_bits(tx),.trace_w_bits(tw),.trace_acc_before_bits(ta),
    .trace_product_bits(tp),.trace_acc_after_bits(tz),.trace_bias_bits(tbias));
  baseline_fp32_pe_array_8x16 #(.ROWS(ROWS),.COLS(COLS),.K(K)) reference_dut(
    .clk(clk),.rst_n(rst_n),.start(start),.stream_valid(stream_valid),
    .task_first(task_first),.task_last(task_last),.a_left(a_left),.b_top(b_top),.bias_in(bias_in),
    .checkpoint_save_req(1'b0),.checkpoint_restore_req(1'b0),
    .checkpoint_mem_rvalid(1'b0),.checkpoint_mem_rdata(16'd0),
    .busy(old_busy),.done(old_done),.result_valid(old_result_valid),.result(old_result),
    .trace_valid(otv),.trace_bias_valid(obv),.trace_cycle(otc),.trace_k(otk),
    .trace_x_bits(ox),.trace_w_bits(ow),.trace_acc_before_bits(oa),
    .trace_product_bits(op),.trace_acc_after_bits(oz),.trace_bias_bits(obias));

  function automatic [31:0] next_number();
    begin
      rng=rng ^ (rng<<13); rng=rng ^ (rng>>17); rng=rng ^ (rng<<5);
      next_number={rng[31],8'd126,rng[22:0]};
    end
  endfunction

  always @(posedge clk) begin: compare_outputs
    integer rr,cc;
    #1;
    cycle=cycle+1;
    if(rst_n) begin
      if({busy,done,result_valid} !== {old_busy,old_done,old_result_valid})
        $fatal(1,"control timing differs cycle=%0d",cycle);
      for(rr=0;rr<ROWS;rr=rr+1) for(cc=0;cc<COLS;cc=cc+1) begin
        if({tv[rr][cc],bv[rr][cc]} !== {otv[rr][cc],obv[rr][cc]})
          $fatal(1,"trace validity differs cycle=%0d r=%0d c=%0d",cycle,rr,cc);
        if(tv[rr][cc]) begin
          if({tc[rr][cc],tk[rr][cc],tx[rr][cc],tw[rr][cc],ta[rr][cc],tp[rr][cc],tz[rr][cc]} !==
             {otc[rr][cc],otk[rr][cc],ox[rr][cc],ow[rr][cc],oa[rr][cc],op[rr][cc],oz[rr][cc]})
            $fatal(1,"MAC event differs cycle=%0d r=%0d c=%0d",cycle,rr,cc);
          mac_count=mac_count+1;
        end
        if(bv[rr][cc]) begin
          if({tc[rr][cc],ta[rr][cc],tz[rr][cc],tbias[rr][cc]} !==
             {otc[rr][cc],oa[rr][cc],oz[rr][cc],obias[rr][cc]})
            $fatal(1,"bias event differs cycle=%0d r=%0d c=%0d",cycle,rr,cc);
          bias_count=bias_count+1;
        end
        if(result_valid && result[rr][cc] !== old_result[rr][cc])
          $fatal(1,"result differs cycle=%0d r=%0d c=%0d",cycle,rr,cc);
      end
      if(result_valid) outputs=outputs+1;
    end
  end

  initial begin
    for(r=0;r<ROWS;r=r+1) a_left[r]=0;
    for(c=0;c<COLS;c=c+1) begin b_top[c]=0;bias_in[c]=0;end
    repeat(3) @(negedge clk);rst_n=1;
    // Four consecutive tasks, sparse valid tokens, and long empty gaps.
    for(t=0;t<4;t=t+1) begin
      repeat(70) @(negedge clk);
      for(c=0;c<COLS;c=c+1) bias_in[c]=next_number();
      start=1;@(negedge clk);start=0;
      for(block_idx=0;block_idx<2;block_idx=block_idx+1) begin
        for(k=0;k<K;k=k+1) begin
          if((k+t)%3==0) begin
            stream_valid=0;task_first=0;task_last=0;
            repeat((k%4)+1) @(negedge clk);
          end
          for(r=0;r<ROWS;r=r+1) a_left[r]=next_number();
          for(c=0;c<COLS;c=c+1) b_top[c]=next_number();
          stream_valid=1;task_first=(block_idx==0 && k==0);
          task_last=(block_idx==1 && k==K-1);
          @(negedge clk);
        end
        stream_valid=0;task_first=0;task_last=0;
        if(block_idx==0) repeat(K*8+ROWS+COLS+100) @(negedge clk);
      end
      guard=0;
      while(!result_valid && guard<2000) begin @(negedge clk);guard=guard+1;end
      if(!result_valid) $fatal(1,"equivalence task timeout t=%0d",t);
    end
    repeat(80) @(negedge clk);
    // Reset with a token in flight, then compare both sides after clearing.
    start=1;stream_valid=1;task_first=1;
    @(negedge clk);start=0;task_first=0;
    repeat(3) @(negedge clk);
    rst_n=0;stream_valid=0;repeat(3) @(negedge clk);rst_n=1;
    repeat(80) @(negedge clk);
    if(mac_count != ROWS*COLS*K*2*4 || bias_count != ROWS*COLS*4 || outputs != 4)
      $fatal(1,"equivalence coverage incomplete mac=%0d bias=%0d outputs=%0d",mac_count,bias_count,outputs);
    $display("PASS: idle optimization cycle equivalence rows=%0d cols=%0d mac=%0d bias=%0d tasks=%0d",ROWS,COLS,mac_count,bias_count,outputs);
    $finish;
  end
  initial begin #2000000;$fatal(1,"equivalence global timeout");end
endmodule
