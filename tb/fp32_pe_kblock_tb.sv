`timescale 1ns/1ps

// Checks the structural rule that a completed K block keeps its partial sum.
// K=2 is used twice: block 0 computes 1+1=2, block 1 computes 2+3=5, so the
// preserved accumulator is 7 before the final bias of 1 is applied.
module fp32_pe_kblock_tb;
  logic clk = 1'b0;
  always #5 clk = ~clk;

  logic rst_n = 1'b0;
  logic enable = 1'b1;
  logic clear_acc = 1'b0;
  logic task_first = 1'b0;
  logic task_last = 1'b0;
  logic in_valid = 1'b0;
  logic [31:0] a_in = 32'd0;
  logic [31:0] b_in = 32'h3f800000;
  logic [31:0] bias_in = 32'h3f800000;
  logic checkpoint_restore=0;
  logic [31:0] checkpoint_accumulator=0, checkpoint_bias=0;
  wire [31:0] checkpoint_accumulator_out, checkpoint_bias_out;
  wire [2:0] checkpoint_state_out;

  logic result_valid, busy, done;
  logic [31:0] result;
  logic trace_valid, trace_bias_valid;
  logic [31:0] trace_cycle, trace_x_bits, trace_w_bits;
  logic [15:0] trace_k;
  logic [31:0] trace_acc_before_bits, trace_product_bits, trace_acc_after_bits;
  logic [31:0] trace_bias_bits;

  fp32_pe_mac #(.K(2), .MUL_LATENCY(8), .ADD_LATENCY(4)) dut (
    .clk(clk), .rst_n(rst_n), .enable(enable), .clear_acc(clear_acc),
    .task_first(task_first), .task_last(task_last), .in_valid(in_valid),
    .a_in(a_in), .b_in(b_in), .bias_in(bias_in),
    .checkpoint_restore(checkpoint_restore), .checkpoint_accumulator(checkpoint_accumulator),
    .checkpoint_bias(checkpoint_bias), .checkpoint_accumulator_out(checkpoint_accumulator_out),
    .checkpoint_bias_out(checkpoint_bias_out), .checkpoint_state_out(checkpoint_state_out),
    .result_valid(result_valid), .result(result), .busy(busy), .done(done),
    .trace_valid(trace_valid), .trace_cycle(trace_cycle), .trace_k(trace_k),
    .trace_x_bits(trace_x_bits), .trace_w_bits(trace_w_bits),
    .trace_acc_before_bits(trace_acc_before_bits),
    .trace_product_bits(trace_product_bits),
    .trace_acc_after_bits(trace_acc_after_bits),
    .trace_bias_valid(trace_bias_valid), .trace_bias_bits(trace_bias_bits)
  );

  task automatic drive_block(input logic first_block, input logic last_block,
                             input logic [31:0] first_x, input logic [31:0] second_x);
    begin
      @(negedge clk);
      a_in = first_x;
      task_first = first_block;
      task_last = 1'b0;
      in_valid = 1'b1;
      @(negedge clk);
      a_in = second_x;
      task_first = 1'b0;
      task_last = last_block;
      in_valid = 1'b1;
      @(negedge clk);
      in_valid = 1'b0;
      task_last = 1'b0;
      a_in = 32'd0;
    end
  endtask

  task automatic wait_mac(input logic [31:0] expected_before,
                          input logic [31:0] expected_after, input integer expected_k);
    integer guard;
    begin
      guard = 0;
      while (1) begin
        @(posedge clk);
        #1;
        guard = guard + 1;
        if (guard > 100) $fatal(1, "timeout waiting for MAC k=%0d", expected_k);
        if (trace_bias_valid) $fatal(1, "bias arrived before requested MAC");
        if (trace_valid) begin
          if (trace_k !== expected_k[15:0])
            $fatal(1, "K mismatch got=%0d expected=%0d", trace_k, expected_k);
          if (trace_acc_before_bits !== expected_before ||
              trace_acc_after_bits !== expected_after)
            $fatal(1, "partial sum mismatch k=%0d before=%08x after=%08x",
                   expected_k, trace_acc_before_bits, trace_acc_after_bits);
          break;
        end
      end
    end
  endtask

  initial begin
    repeat (2) @(negedge clk);
    rst_n = 1'b1;

    // First block: 1 + 1 = 2, but task_last is low, so no bias/result yet.
    drive_block(1'b1, 1'b0, 32'h3f800000, 32'h3f800000);
    wait_mac(32'h00000000, 32'h3f800000, 0);
    wait_mac(32'h3f800000, 32'h40000000, 1);
    if (trace_bias_valid || result_valid || !busy)
      $fatal(1, "non-final block incorrectly completed bias/result");

    // Second block starts without task_first: the previous partial sum is kept.
    drive_block(1'b0, 1'b1, 32'h40000000, 32'h40400000);
    wait_mac(32'h40000000, 32'h40800000, 0);
    wait_mac(32'h40800000, 32'h40e00000, 1);

    while (!trace_bias_valid) begin
      @(posedge clk);
      #1;
    end
    if (trace_acc_before_bits !== 32'h40e00000 ||
        trace_acc_after_bits !== 32'h41000000 ||
        trace_bias_bits !== 32'h3f800000 ||
        result !== 32'h41000000 || !result_valid || !done || busy)
      $fatal(1, "final block/bias mismatch before=%08x after=%08x bias=%08x result=%08x",
             trace_acc_before_bits, trace_acc_after_bits, trace_bias_bits, result);

    $display("fp32_pe_kblock_tb PASS preserved_partial_sum=7 bias=1 result=8");
    $finish;
  end

  initial begin
    #300000;
    $fatal(1, "fp32_pe_kblock_tb timeout");
  end
endmodule
