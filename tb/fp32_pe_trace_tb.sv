`timescale 1ns/1ps

// Replaceable simulation adapter for a single FP32 PE.
//
// This initial adapter wraps fp32_mac_boundary only. It is intentionally
// marked as a candidate/reference path: fp32_mac_boundary is not integrated
// into the systolic array and does not implement the required 8+4 pipeline.
// Replace this adapter's internals and trace taps when the real FP32 PE exists;
// keep the testbench-facing ports stable where practical.
module fp32_pe_trace_adapter (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        enable,
  input  logic        in_valid,
  input  logic        task_first,
  input  logic        task_last,
  input  logic [31:0] x_bits,
  input  logic [31:0] w_bits,
  output logic        result_valid,
  output logic [31:0] result_bits,
  output logic [31:0] trace_acc_before_bits,
  output logic [31:0] trace_product_bits,
  output logic [31:0] trace_acc_after_bits
);
  import fp32_math_pkg::*;

  logic [31:0] candidate_acc;
  logic [31:0] candidate_product;

  fp32_mac_boundary u_candidate_reference (
    .clk(clk),
    .rst_n(rst_n),
    .valid(enable && in_valid),
    .a(x_bits),
    .b(w_bits),
    .clear_acc(enable && in_valid && task_first),
    .last(enable && in_valid && task_last),
    .result_valid(result_valid),
    .result(result_bits)
  );

  // White-box taps are confined to this temporary adapter. The real PE
  // adapter must connect equivalent architectural trace signals instead.
  assign candidate_acc = u_candidate_reference.acc;
  assign candidate_product = fp32_mul(x_bits, w_bits);
  assign trace_acc_before_bits = task_first ? 32'h00000000 : candidate_acc;
  assign trace_product_bits = candidate_product;
  assign trace_acc_after_bits = task_first ? candidate_product :
                                fp32_add(candidate_acc, candidate_product);
endmodule

module fp32_pe_trace_tb;
  import fp32_math_pkg::*;

  logic clk = 1'b0;
  always #5 clk = ~clk;

  logic rst_n = 1'b0;
  logic enable = 1'b1;
  logic in_valid = 1'b0;
  logic task_first = 1'b0;
  logic task_last = 1'b0;
  logic [31:0] x_bits = 32'b0;
  logic [31:0] w_bits = 32'b0;
  logic result_valid;
  logic [31:0] result_bits;
  logic [31:0] trace_acc_before_bits;
  logic [31:0] trace_product_bits;
  logic [31:0] trace_acc_after_bits;

  integer vector_fd;
  integer trace_fd;
  integer scan_count;
  integer case_id;
  integer row;
  integer column;
  integer k;
  integer last_k;
  integer k32_save;
  integer k32_restore;
  integer cycle_count;
  integer processed_rows;
  integer case0_rows;
  integer case1_rows;
  integer case2_rows;
  integer last_row_seen;
  integer last_column_seen;
  integer last_case_seen;
  integer previous_k;
  logic [31:0] expected_x_bits;
  logic [31:0] expected_w_bits;
  logic [31:0] expected_acc_before_bits;
  logic [31:0] expected_product_bits;
  logic [31:0] expected_acc_after_bits;
  logic [31:0] expected_bias_bits;
  logic [31:0] expected_acc_before_bias_bits;
  logic [31:0] expected_result_bits;
  logic [31:0] sampled_acc_before_bits;
  logic [31:0] sampled_product_bits;
  logic [31:0] sampled_acc_after_bits;
  logic [31:0] sampled_result_bits;
  logic [31:0] sampled_biased_result_bits;
  logic sampled_result_valid;
  string vector_path;
  string trace_path;

  fp32_pe_trace_adapter u_pe_adapter (
    .clk(clk),
    .rst_n(rst_n),
    .enable(enable),
    .in_valid(in_valid),
    .task_first(task_first),
    .task_last(task_last),
    .x_bits(x_bits),
    .w_bits(w_bits),
    .result_valid(result_valid),
    .result_bits(result_bits),
    .trace_acc_before_bits(trace_acc_before_bits),
    .trace_product_bits(trace_product_bits),
    .trace_acc_after_bits(trace_acc_after_bits)
  );

  function automatic [8*20-1:0] case_name(input integer id);
    begin
      case (id)
        0: case_name = "hand_2x2";
        1: case_name = "rounding_nonfused";
        2: case_name = "k32_boundary";
        default: case_name = "unknown_case";
      endcase
    end
  endfunction

  initial begin
    vector_path = "build/fp32_trace_reference/fp32_step_vectors.txt";
    trace_path = "build/fp32_trace_reference/pe_trace_framework.csv";
    if ($value$plusargs("VECTOR_FILE=%s", vector_path)) begin end
    if ($value$plusargs("TRACE_FILE=%s", trace_path)) begin end

    vector_fd = $fopen(vector_path, "r");
    if (vector_fd == 0)
      $fatal(1, "cannot open vector file: %0s (run Prepare-Fp32TraceVectors.ps1 first)", vector_path);
    trace_fd = $fopen(trace_path, "w");
    if (trace_fd == 0) $fatal(1, "cannot open trace output: %0s", trace_path);

    $fdisplay(trace_fd,
      "status,case_id,case,cycle,input_valid,result_valid,row,column,k,x_bits,w_bits,acc_before_bits,product_bits,acc_after_bits,task_first,task_last,trace_bias_valid,bias_bits,acc_before_bias_bits,result_bits,k32_save_marker,k32_restore_marker");

    cycle_count = 0;
    processed_rows = 0;
    case0_rows = 0;
    case1_rows = 0;
    case2_rows = 0;
    last_case_seen = -1;
    last_row_seen = -1;
    last_column_seen = -1;

    repeat (2) @(negedge clk);
    rst_n = 1'b1;

    while (!$feof(vector_fd)) begin
      scan_count = $fscanf(vector_fd,
        "%d %d %d %d %h %h %h %h %h %h %h %h %d %d %d\n",
        case_id, row, column, k,
        expected_x_bits, expected_w_bits,
        expected_acc_before_bits, expected_product_bits,
        expected_acc_after_bits, expected_bias_bits,
        expected_acc_before_bias_bits, expected_result_bits,
        last_k, k32_save, k32_restore);

      if (scan_count == -1) begin
        // Normal EOF after the final complete line.
      end else if (scan_count != 15) begin
        $fatal(1, "malformed vector line after %0d records: scanned %0d fields", processed_rows, scan_count);
      end else begin
        if (case_id < 0 || case_id > 2) $fatal(1, "invalid case id %0d", case_id);
        if (k < 0 || row < 0 || column < 0) $fatal(1, "negative vector coordinate");
        if ((last_k != 0) && (last_k != 1)) $fatal(1, "last_k must be 0 or 1");
        if ((k32_save != 0) && (k32_save != 1)) $fatal(1, "k32_save must be 0 or 1");
        if ((k32_restore != 0) && (k32_restore != 1)) $fatal(1, "k32_restore must be 0 or 1");

        if (last_case_seen != case_id || last_row_seen != row || last_column_seen != column) begin
          if (k != 0) $fatal(1, "new output cell must start at k=0; got k=%0d", k);
        end else if (k != (previous_k + 1)) begin
          $fatal(1, "K sequence discontinuity in case=%0d row=%0d column=%0d: got k=%0d after k=%0d",
                 case_id, row, column, k, previous_k);
        end

        @(negedge clk);
        in_valid = 1'b1;
        task_first = (k == 0);
        task_last = (last_k != 0);
        x_bits = expected_x_bits;
        w_bits = expected_w_bits;
        #1;

        sampled_acc_before_bits = trace_acc_before_bits;
        sampled_product_bits = trace_product_bits;
        sampled_acc_after_bits = trace_acc_after_bits;
        if (sampled_acc_before_bits !== expected_acc_before_bits)
          $fatal(1, "acc_before mismatch case=%0d row=%0d column=%0d k=%0d got=%08x expected=%08x",
                 case_id, row, column, k, sampled_acc_before_bits, expected_acc_before_bits);
        if (sampled_product_bits !== expected_product_bits)
          $fatal(1, "product mismatch case=%0d row=%0d column=%0d k=%0d got=%08x expected=%08x",
                 case_id, row, column, k, sampled_product_bits, expected_product_bits);
        if (sampled_acc_after_bits !== expected_acc_after_bits)
          $fatal(1, "acc_after mismatch case=%0d row=%0d column=%0d k=%0d got=%08x expected=%08x",
                 case_id, row, column, k, sampled_acc_after_bits, expected_acc_after_bits);

        @(posedge clk);
        #1;
        sampled_result_valid = result_valid;
        if (last_k != 0) begin
          if (sampled_result_valid !== 1'b1)
            $fatal(1, "missing result_valid case=%0d row=%0d column=%0d k=%0d", case_id, row, column, k);
          if (result_bits !== expected_acc_before_bias_bits)
            $fatal(1, "pre-bias result mismatch case=%0d row=%0d column=%0d got=%08x expected=%08x",
                   case_id, row, column, result_bits, expected_acc_before_bias_bits);
          sampled_result_bits = result_bits;
          sampled_biased_result_bits = fp32_add(result_bits, expected_bias_bits);
          if (sampled_biased_result_bits !== expected_result_bits)
            $fatal(1, "biased result mismatch case=%0d row=%0d column=%0d got=%08x expected=%08x",
                   case_id, row, column, sampled_biased_result_bits, expected_result_bits);
        end else begin
          if (sampled_result_valid !== 1'b0)
            $fatal(1, "unexpected result_valid before last K case=%0d row=%0d column=%0d k=%0d", case_id, row, column, k);
          sampled_result_bits = 32'b0;
          sampled_biased_result_bits = 32'b0;
        end

        $fdisplay(trace_fd,
          "framework_only,%0d,%0s,%0d,1,%0d,%0d,%0d,%0d,%08x,%08x,%08x,%08x,%08x,%0d,%0d,%0d,%08x,%08x,%08x,%0d,%0d",
          case_id, case_name(case_id), cycle_count, sampled_result_valid, row, column, k,
          expected_x_bits, expected_w_bits, sampled_acc_before_bits,
          sampled_product_bits, sampled_acc_after_bits, (k == 0), last_k,
          last_k, expected_bias_bits, expected_acc_before_bias_bits,
          sampled_biased_result_bits, k32_save, k32_restore);

        if (case_id == 0) case0_rows = case0_rows + 1;
        else if (case_id == 1) case1_rows = case1_rows + 1;
        else case2_rows = case2_rows + 1;
        processed_rows = processed_rows + 1;
        last_case_seen = case_id;
        last_row_seen = row;
        last_column_seen = column;
        previous_k = k;
        cycle_count = cycle_count + 1;
      end
    end

    in_valid = 1'b0;
    task_first = 1'b0;
    task_last = 1'b0;
    $fclose(vector_fd);
    $fclose(trace_fd);

    if (processed_rows != 74 || case0_rows != 8 || case1_rows != 2 || case2_rows != 64)
      $fatal(1, "unexpected vector totals: total=%0d hand_2x2=%0d rounding=%0d k32=%0d",
             processed_rows, case0_rows, case1_rows, case2_rows);

    $display("fp32_pe_trace_tb PASS FRAMEWORK_ONLY rows=%0d; no real FP32 PE validated", processed_rows);
    $finish;
  end

  initial begin
    #100000;
    $fatal(1, "fp32_pe_trace_tb timeout");
  end
endmodule
