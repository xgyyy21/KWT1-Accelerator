`timescale 1ns/1ps

// First real testbench for rtl/fp32_pe_mac.sv.
//
// This test drives one PE four times.  Each run computes one output of the
// 2x2 hand_2x2 example with K=2, then checks the actual MAC and bias trace
// ports.  It deliberately does not use fp32_mac_boundary or a white-box
// reference adapter: the DUT is the repository fp32_pe_mac module itself.
//
// This is the task-1 bring-up test.  It checks the PE and prints measured
// events; it is not yet the final 19-column pe_trace.csv delivery.
module fp32_pe_hand_2x2_tb;
  import fp32_math_pkg::*;

  localparam int K = 2;

  logic clk = 1'b0;
  always #5 clk = ~clk;

  logic rst_n = 1'b0;
  logic enable = 1'b1;
  logic clear_acc = 1'b0;
  logic task_first = 1'b0;
  logic task_last = 1'b0;
  logic in_valid = 1'b0;
  logic [31:0] a_in = 32'b0;
  logic [31:0] b_in = 32'b0;
  logic [31:0] bias_in = 32'b0;

  logic result_valid;
  logic [31:0] result;
  logic busy;
  logic done;
  logic trace_valid;
  logic [31:0] trace_cycle;
  logic [15:0] trace_k;
  logic [31:0] trace_x_bits;
  logic [31:0] trace_w_bits;
  logic [31:0] trace_acc_before_bits;
  logic [31:0] trace_product_bits;
  logic [31:0] trace_acc_after_bits;
  logic trace_bias_valid;
  logic [31:0] trace_bias_bits;

  logic [31:0] x_mat [0:1][0:1];
  logic [31:0] w_mat [0:1][0:1];

  integer trace_fd;
  string trace_path;

  fp32_pe_mac #(.K(K), .MUL_LATENCY(8), .ADD_LATENCY(4)) dut (
    .clk(clk), .rst_n(rst_n), .enable(enable), .clear_acc(clear_acc),
    .task_first(task_first), .task_last(task_last), .in_valid(in_valid),
    .a_in(a_in), .b_in(b_in), .bias_in(bias_in),
    .result_valid(result_valid), .result(result), .busy(busy), .done(done),
    .trace_valid(trace_valid), .trace_cycle(trace_cycle), .trace_k(trace_k),
    .trace_x_bits(trace_x_bits), .trace_w_bits(trace_w_bits),
    .trace_acc_before_bits(trace_acc_before_bits),
    .trace_product_bits(trace_product_bits),
    .trace_acc_after_bits(trace_acc_after_bits),
    .trace_bias_valid(trace_bias_valid), .trace_bias_bits(trace_bias_bits)
  );

  task automatic run_cell(
    input integer row_idx,
    input integer col_idx,
    input logic [31:0] bias_value,
    input logic [31:0] expected_product0,
    input logic [31:0] expected_acc1,
    input logic [31:0] expected_product1,
    input logic [31:0] expected_acc2,
    input logic [31:0] expected_result
  );
    integer mac_seen;
    integer wait_cycles;
    begin
      // The module uses task_first as the start of a new output.  The first
      // input is accepted on the following rising edge.
      @(negedge clk);
      bias_in = bias_value;
      a_in = x_mat[row_idx][0];
      b_in = w_mat[0][col_idx];
      task_first = 1'b1;
      task_last = 1'b0;
      in_valid = 1'b1;

      @(negedge clk);
      a_in = x_mat[row_idx][1];
      b_in = w_mat[1][col_idx];
      task_first = 1'b0;
      task_last = 1'b1;
      in_valid = 1'b1;

      @(negedge clk);
      a_in = 32'b0;
      b_in = 32'b0;
      task_first = 1'b0;
      task_last = 1'b0;
      in_valid = 1'b0;

      mac_seen = 0;
      wait_cycles = 0;
      while (mac_seen < K) begin
        @(posedge clk);
        #1;
        wait_cycles = wait_cycles + 1;
        if (wait_cycles > 200)
          $fatal(1, "timeout waiting for MAC events row=%0d col=%0d", row_idx, col_idx);

        if (trace_bias_valid)
          $fatal(1, "bias event arrived before all MAC events row=%0d col=%0d", row_idx, col_idx);

        if (trace_valid) begin
          if (trace_k !== mac_seen[15:0])
            $fatal(1, "trace_k mismatch row=%0d col=%0d got=%0d expected=%0d",
                   row_idx, col_idx, trace_k, mac_seen);
          if (trace_x_bits !== x_mat[row_idx][mac_seen])
            $fatal(1, "trace X mismatch row=%0d col=%0d k=%0d got=%08x expected=%08x",
                   row_idx, col_idx, mac_seen, trace_x_bits, x_mat[row_idx][mac_seen]);
          if (trace_w_bits !== w_mat[mac_seen][col_idx])
            $fatal(1, "trace W mismatch row=%0d col=%0d k=%0d got=%08x expected=%08x",
                   row_idx, col_idx, mac_seen, trace_w_bits, w_mat[mac_seen][col_idx]);

          if (mac_seen == 0) begin
            if (trace_acc_before_bits !== 32'h00000000)
              $fatal(1, "first acc_before is not zero row=%0d col=%0d", row_idx, col_idx);
            if (trace_product_bits !== expected_product0)
              $fatal(1, "product0 mismatch row=%0d col=%0d got=%08x expected=%08x",
                     row_idx, col_idx, trace_product_bits, expected_product0);
            if (trace_acc_after_bits !== expected_product0)
              $fatal(1, "acc_after0 mismatch row=%0d col=%0d got=%08x expected=%08x",
                     row_idx, col_idx, trace_acc_after_bits, expected_product0);
          end else begin
            if (trace_acc_before_bits !== expected_acc1)
              $fatal(1, "acc_before1 mismatch row=%0d col=%0d got=%08x expected=%08x",
                     row_idx, col_idx, trace_acc_before_bits, expected_acc1);
            if (trace_product_bits !== expected_product1)
              $fatal(1, "product1 mismatch row=%0d col=%0d got=%08x expected=%08x",
                     row_idx, col_idx, trace_product_bits, expected_product1);
            if (trace_acc_after_bits !== expected_acc2)
              $fatal(1, "acc_after1 mismatch row=%0d col=%0d got=%08x expected=%08x",
                     row_idx, col_idx, trace_acc_after_bits, expected_acc2);
          end

          $display("PE_HAND_2X2 MAC row=%0d col=%0d k=%0d cycle=%0d x=%08x w=%08x before=%08x product=%08x after=%08x",
                   row_idx, col_idx, trace_k, trace_cycle, trace_x_bits, trace_w_bits,
                   trace_acc_before_bits, trace_product_bits, trace_acc_after_bits);
          $fdisplay(trace_fd,
            "rtl_model_raw,%0d,%0d,mac,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%08x,%08x,%08x,%08x,%08x,%08x,%08x",
            row_idx, col_idx, trace_cycle, trace_k, trace_valid, trace_bias_valid,
            result_valid, done, busy, trace_x_bits, trace_w_bits,
            trace_acc_before_bits, trace_product_bits, trace_acc_after_bits,
            32'h00000000, 32'h00000000);
          $fflush(trace_fd);
          mac_seen = mac_seen + 1;
        end
      end

      wait_cycles = 0;
      while (!trace_bias_valid) begin
        @(posedge clk);
        #1;
        wait_cycles = wait_cycles + 1;
        if (wait_cycles > 200)
          $fatal(1, "timeout waiting for bias event row=%0d col=%0d", row_idx, col_idx);
        if (trace_valid)
          $fatal(1, "unexpected extra MAC event before bias row=%0d col=%0d", row_idx, col_idx);
      end

      if (trace_bias_bits !== bias_value)
        $fatal(1, "bias mismatch row=%0d col=%0d got=%08x expected=%08x",
               row_idx, col_idx, trace_bias_bits, bias_value);
      if (trace_acc_before_bits !== expected_acc2)
        $fatal(1, "bias acc_before mismatch row=%0d col=%0d got=%08x expected=%08x",
               row_idx, col_idx, trace_acc_before_bits, expected_acc2);
      if (trace_acc_after_bits !== expected_result)
        $fatal(1, "bias acc_after mismatch row=%0d col=%0d got=%08x expected=%08x",
               row_idx, col_idx, trace_acc_after_bits, expected_result);
      if (!result_valid || !done || busy || result !== expected_result)
        $fatal(1, "result handshake mismatch row=%0d col=%0d valid=%0d done=%0d busy=%0d result=%08x expected=%08x",
               row_idx, col_idx, result_valid, done, busy, result, expected_result);

      $display("PE_HAND_2X2 BIAS row=%0d col=%0d cycle=%0d bias=%08x before=%08x after=%08x result=%08x",
               row_idx, col_idx, trace_cycle, trace_bias_bits, trace_acc_before_bits,
               trace_acc_after_bits, result);
      $fdisplay(trace_fd,
        "rtl_model_raw,%0d,%0d,bias,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%08x,%08x,%08x,%08x,%08x,%08x,%08x",
        row_idx, col_idx, trace_cycle, trace_k, trace_valid, trace_bias_valid,
        result_valid, done, busy, 32'h00000000, 32'h00000000,
        trace_acc_before_bits, 32'h00000000, trace_acc_after_bits,
        trace_bias_bits, result);
      $fflush(trace_fd);
    end
  endtask

  initial begin
    trace_path = "build/fp32_pe_hand_2x2_raw_trace.csv";
    if ($value$plusargs("TRACE_FILE=%s", trace_path)) begin end
    trace_fd = $fopen(trace_path, "w");
    if (trace_fd == 0)
      $fatal(1, "cannot open raw PE trace output: %0s", trace_path);
    $fdisplay(trace_fd,
      "capture_kind,row,column,event,cycle,trace_k,trace_valid,trace_bias_valid,result_valid,done,busy,x_bits,w_bits,acc_before_bits,product_bits,acc_after_bits,bias_bits,result_bits");

    // X = [[1.0, -2.0], [0.5, 3.0]]
    x_mat[0][0] = 32'h3f800000;
    x_mat[0][1] = 32'hc0000000;
    x_mat[1][0] = 32'h3f000000;
    x_mat[1][1] = 32'h40400000;

    // W = [[2.0, -1.0], [1.5, 0.5]]
    w_mat[0][0] = 32'h40000000;
    w_mat[0][1] = 32'hbf800000;
    w_mat[1][0] = 32'h3fc00000;
    w_mat[1][1] = 32'h3f000000;

    repeat (2) @(negedge clk);
    rst_n = 1'b1;

    run_cell(0, 0, 32'h3e800000, 32'h40000000, 32'h40000000,
             32'hc0400000, 32'hbf800000, 32'hbf400000);
    run_cell(0, 1, 32'hbf000000, 32'hbf800000, 32'hbf800000,
             32'hbf800000, 32'hc0000000, 32'hc0200000);
    run_cell(1, 0, 32'h3e800000, 32'h3f800000, 32'h3f800000,
             32'h40900000, 32'h40b00000, 32'h40b80000);
    run_cell(1, 1, 32'hbf000000, 32'hbf000000, 32'hbf000000,
             32'h3fc00000, 32'h3f800000, 32'h3f000000);

    $fclose(trace_fd);
    $display("fp32_pe_hand_2x2_tb PASS cells=4 mac_events=8 bias_events=4");
    $finish;
  end

  initial begin
    #200000;
    $fatal(1, "fp32_pe_hand_2x2_tb timeout");
  end
endmodule
