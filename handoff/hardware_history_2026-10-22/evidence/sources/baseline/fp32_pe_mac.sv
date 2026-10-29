// Single FP32 processing element.
//
// Structural contract used by the first hardware implementation:
//   * multiplier latency: 8 clocks;
//   * adder latency:      4 clocks;
//   * the accumulator register is the only source of the next partial sum;
//   * a new K block keeps the previous partial sum unless clear_acc/task_first
//     starts a completely new output element.
//
// The multiplier output is buffered per K item so that the external stream
// may be accepted while the dependent accumulator add is still in flight.
// The dependent additions themselves are issued one at a time.  This keeps
// the arithmetic semantics explicit: acc_after[k] is the registered result
// used as acc_before[k+1].
module baseline_fp32_pe_mac #(
  parameter int K = 64,
  parameter int MUL_LATENCY = 8,
  parameter int ADD_LATENCY = 4
) (
  input  logic clk,
  input  logic rst_n,
  input  logic enable,
  input  logic clear_acc,
  input  logic task_first,
  input  logic task_last,
  input  logic in_valid,
  input  logic [31:0] a_in,
  input  logic [31:0] b_in,
  input  logic [31:0] bias_in,
  input  logic checkpoint_restore,
  input  logic [31:0] checkpoint_accumulator,
  input  logic [31:0] checkpoint_bias,
  output logic [31:0] checkpoint_accumulator_out,
  output logic [31:0] checkpoint_bias_out,
  output logic [2:0] checkpoint_state_out,
  output logic result_valid,
  output logic [31:0] result,
  output logic busy,
  output logic done,
  output logic trace_valid,
  output logic [31:0] trace_cycle,
  output logic [15:0] trace_k,
  output logic [31:0] trace_x_bits,
  output logic [31:0] trace_w_bits,
  output logic [31:0] trace_acc_before_bits,
  output logic [31:0] trace_product_bits,
  output logic [31:0] trace_acc_after_bits,
  output logic trace_bias_valid,
  output logic [31:0] trace_bias_bits
);
  import fp32_math_pkg::*;

  localparam logic [2:0] S_IDLE       = 3'd0;
  localparam logic [2:0] S_COLLECT    = 3'd1;
  localparam logic [2:0] S_ADD        = 3'd2;
  localparam logic [2:0] S_BIAS       = 3'd3;
  localparam logic [2:0] S_WAIT_BLOCK = 3'd4;
  localparam logic [2:0] S_DONE       = 3'd5;

  logic [2:0] state;
  logic [31:0] accumulator;
  logic [31:0] bias_reg;
  logic [15:0] input_count;
  logic [15:0] expected_count;
  logic [15:0] add_index;
  logic final_block;
  logic add_busy;
  integer cycle_count;
  integer i;

  logic [31:0] mul_product_pipe [0:MUL_LATENCY-1];
  logic [31:0] mul_x_pipe       [0:MUL_LATENCY-1];
  logic [31:0] mul_w_pipe       [0:MUL_LATENCY-1];
  logic [15:0] mul_k_pipe       [0:MUL_LATENCY-1];
  logic        mul_block_end_pipe [0:MUL_LATENCY-1];
  logic        mul_valid_pipe   [0:MUL_LATENCY-1];

  logic [31:0] product_mem [0:K-1];
  logic [31:0] x_mem       [0:K-1];
  logic [31:0] w_mem       [0:K-1];

  logic [31:0] add_before_pipe  [0:ADD_LATENCY-1];
  logic [31:0] add_product_pipe [0:ADD_LATENCY-1];
  logic [31:0] add_sum_pipe     [0:ADD_LATENCY-1];
  logic [31:0] add_x_pipe       [0:ADD_LATENCY-1];
  logic [31:0] add_w_pipe       [0:ADD_LATENCY-1];
  logic [15:0] add_k_pipe       [0:ADD_LATENCY-1];
  logic        add_bias_pipe    [0:ADD_LATENCY-1];
  logic        add_valid_pipe   [0:ADD_LATENCY-1];

  assign busy = (state != S_IDLE) && (state != S_DONE);
  assign checkpoint_accumulator_out = accumulator;
  assign checkpoint_bias_out = bias_reg;
  assign checkpoint_state_out = state;

  initial begin
    if (K <= 0 || MUL_LATENCY != 8 || ADD_LATENCY != 4)
      $fatal(1, "baseline_fp32_pe_mac requires K>0 and an 8+4 cycle contract");
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state          <= S_IDLE;
      accumulator    <= 32'h00000000;
      bias_reg       <= 32'h00000000;
      input_count    <= 16'd0;
      expected_count <= 16'd0;
      add_index      <= 16'd0;
      final_block    <= 1'b0;
      add_busy       <= 1'b0;
      cycle_count    <= 0;
      result         <= 32'h00000000;
      result_valid   <= 1'b0;
      done           <= 1'b0;
      trace_valid    <= 1'b0;
      trace_cycle   <= 32'd0;
      trace_k        <= 16'd0;
      trace_x_bits   <= 32'd0;
      trace_w_bits   <= 32'd0;
      trace_acc_before_bits <= 32'd0;
      trace_product_bits    <= 32'd0;
      trace_acc_after_bits  <= 32'd0;
      trace_bias_valid      <= 1'b0;
      trace_bias_bits       <= 32'd0;
      for (i = 0; i < MUL_LATENCY; i = i + 1) begin
        mul_product_pipe[i] <= 32'd0;
        mul_x_pipe[i]       <= 32'd0;
        mul_w_pipe[i]       <= 32'd0;
        mul_k_pipe[i]       <= 16'd0;
        mul_block_end_pipe[i] <= 1'b0;
        mul_valid_pipe[i]   <= 1'b0;
      end
      for (i = 0; i < ADD_LATENCY; i = i + 1) begin
        add_before_pipe[i]  <= 32'd0;
        add_product_pipe[i] <= 32'd0;
        add_sum_pipe[i]     <= 32'd0;
        add_x_pipe[i]       <= 32'd0;
        add_w_pipe[i]       <= 32'd0;
        add_k_pipe[i]       <= 16'd0;
        add_bias_pipe[i]    <= 1'b0;
        add_valid_pipe[i]   <= 1'b0;
      end
      for (i = 0; i < K; i = i + 1) begin
        product_mem[i] <= 32'd0;
        x_mem[i]       <= 32'd0;
        w_mem[i]       <= 32'd0;
      end
    end else begin
      cycle_count <= cycle_count + 1;
      result_valid <= 1'b0;
      done         <= 1'b0;
      trace_valid  <= 1'b0;
      trace_bias_valid <= 1'b0;

      for (i = MUL_LATENCY-1; i > 0; i = i - 1) begin
        mul_product_pipe[i] <= mul_product_pipe[i-1];
        mul_x_pipe[i]       <= mul_x_pipe[i-1];
        mul_w_pipe[i]       <= mul_w_pipe[i-1];
        mul_k_pipe[i]       <= mul_k_pipe[i-1];
        mul_block_end_pipe[i] <= mul_block_end_pipe[i-1];
        mul_valid_pipe[i]   <= mul_valid_pipe[i-1];
      end
      mul_valid_pipe[0] <= 1'b0;

      for (i = ADD_LATENCY-1; i > 0; i = i - 1) begin
        add_before_pipe[i]  <= add_before_pipe[i-1];
        add_product_pipe[i] <= add_product_pipe[i-1];
        add_sum_pipe[i]     <= add_sum_pipe[i-1];
        add_x_pipe[i]       <= add_x_pipe[i-1];
        add_w_pipe[i]       <= add_w_pipe[i-1];
        add_k_pipe[i]       <= add_k_pipe[i-1];
        add_bias_pipe[i]    <= add_bias_pipe[i-1];
        add_valid_pipe[i]   <= add_valid_pipe[i-1];
      end
      add_valid_pipe[0] <= 1'b0;

      // A new task clears the accumulator.  The first block of a task also
      // captures bias.  Later K blocks must not clear the accumulator.
      if ((clear_acc || task_first) && enable && in_valid) begin
        state       <= S_COLLECT;
        accumulator <= 32'h00000000;
        bias_reg    <= bias_in;
        input_count <= 16'd1;
        add_index   <= 16'd0;
        add_busy    <= 1'b0;
        final_block <= task_last;
        for (i = 0; i < MUL_LATENCY; i = i + 1)
          mul_valid_pipe[i] <= 1'b0;
        for (i = 0; i < ADD_LATENCY; i = i + 1)
          add_valid_pipe[i] <= 1'b0;
        mul_valid_pipe[0] <= 1'b1;
        mul_product_pipe[0] <= fp32_mul(a_in, b_in);
        mul_x_pipe[0]       <= a_in;
        mul_w_pipe[0]       <= b_in;
        mul_k_pipe[0]       <= 16'd0;
        mul_block_end_pipe[0] <= (K == 1) || task_last;
      end else begin
        // Allow the controller to clear an unused block one clock before its
        // first valid pair arrives.  The next pair then uses k=0 and starts
        // from the explicitly stored zero accumulator.
        if ((clear_acc || task_first) && enable && !in_valid) begin
          state       <= S_COLLECT;
          accumulator <= 32'h00000000;
          bias_reg    <= bias_in;
          input_count <= 16'd0;
          add_index   <= 16'd0;
          add_busy    <= 1'b0;
          final_block <= 1'b0;
          for (i = 0; i < MUL_LATENCY; i = i + 1)
            mul_valid_pipe[i] <= 1'b0;
          for (i = 0; i < ADD_LATENCY; i = i + 1)
            add_valid_pipe[i] <= 1'b0;
        end
        // A normal block starts either while collecting the first task block
        // or in S_WAIT_BLOCK after a non-final K block.  The latter preserves
        // accumulator and uses local k=0 for the new block.
        if (state == S_WAIT_BLOCK && enable && in_valid) begin
          state       <= S_COLLECT;
          input_count <= 16'd1;
          final_block <= task_last;
          mul_valid_pipe[0] <= 1'b1;
          mul_product_pipe[0] <= fp32_mul(a_in, b_in);
          mul_x_pipe[0]       <= a_in;
          mul_w_pipe[0]       <= b_in;
          mul_k_pipe[0]       <= 16'd0;
          mul_block_end_pipe[0] <= (K == 1) || task_last;
        end else if (state == S_COLLECT && enable && in_valid) begin
          if (input_count >= K)
            $fatal(1, "baseline_fp32_pe_mac received more than K inputs in one block");
          input_count <= input_count + 1'b1;
          if (task_last)
            final_block <= 1'b1;
          mul_valid_pipe[0] <= 1'b1;
          mul_product_pipe[0] <= fp32_mul(a_in, b_in);
          mul_x_pipe[0]       <= a_in;
          mul_w_pipe[0]       <= b_in;
          mul_k_pipe[0]       <= input_count;
          mul_block_end_pipe[0] <= (input_count + 1'b1 >= K) || task_last;
        end

        // The multiplier output is the only source of product_mem.  This is
        // the explicit 8-clock multiplier boundary.
        if (mul_valid_pipe[MUL_LATENCY-1]) begin
          product_mem[mul_k_pipe[MUL_LATENCY-1]] <= mul_product_pipe[MUL_LATENCY-1];
          x_mem[mul_k_pipe[MUL_LATENCY-1]]       <= mul_x_pipe[MUL_LATENCY-1];
          w_mem[mul_k_pipe[MUL_LATENCY-1]]       <= mul_w_pipe[MUL_LATENCY-1];
          if (mul_block_end_pipe[MUL_LATENCY-1]) begin
            expected_count <= mul_k_pipe[MUL_LATENCY-1] + 1'b1;
            add_index      <= 16'd0;
            state          <= S_ADD;
          end
        end

        // One dependent add at a time.  add_busy prevents a second term from
        // reading the accumulator before the previous 4-cycle result returns.
        if ((state == S_ADD || state == S_BIAS) && !add_busy) begin
          add_valid_pipe[0] <= 1'b1;
          add_before_pipe[0] <= accumulator;
          add_bias_pipe[0] <= (state == S_BIAS);
          if (state == S_BIAS) begin
            add_product_pipe[0] <= bias_reg;
            add_sum_pipe[0]     <= fp32_add(accumulator, bias_reg);
            add_x_pipe[0]       <= 32'd0;
            add_w_pipe[0]       <= 32'd0;
            add_k_pipe[0]       <= 16'hffff;
          end else begin
            add_product_pipe[0] <= product_mem[add_index];
            add_sum_pipe[0]     <= fp32_add(accumulator, product_mem[add_index]);
            add_x_pipe[0]       <= x_mem[add_index];
            add_w_pipe[0]       <= w_mem[add_index];
            add_k_pipe[0]       <= add_index;
          end
          add_busy <= 1'b1;
        end

        if (add_valid_pipe[ADD_LATENCY-1]) begin
          accumulator <= add_sum_pipe[ADD_LATENCY-1];
          add_busy    <= 1'b0;
          trace_cycle <= cycle_count + 1;
          trace_acc_before_bits <= add_before_pipe[ADD_LATENCY-1];
          trace_acc_after_bits  <= add_sum_pipe[ADD_LATENCY-1];
          if (add_bias_pipe[ADD_LATENCY-1]) begin
            trace_bias_valid <= 1'b1;
            trace_bias_bits  <= add_product_pipe[ADD_LATENCY-1];
            result           <= add_sum_pipe[ADD_LATENCY-1];
            result_valid     <= 1'b1;
            done             <= 1'b1;
            state            <= S_DONE;
          end else begin
            trace_valid      <= 1'b1;
            trace_k          <= add_k_pipe[ADD_LATENCY-1];
            trace_x_bits     <= add_x_pipe[ADD_LATENCY-1];
            trace_w_bits     <= add_w_pipe[ADD_LATENCY-1];
            trace_product_bits <= add_product_pipe[ADD_LATENCY-1];
            if (add_k_pipe[ADD_LATENCY-1] + 1'b1 == expected_count) begin
              if (final_block)
                state <= S_BIAS;
              else
                state <= S_WAIT_BLOCK;
            end else begin
              add_index <= add_index + 1'b1;
            end
          end
        end
      end

      // Checkpoint restore has priority over ordinary pipeline advancement.
      // The controller only asserts it after the arithmetic has been reset
      // and all SRAM words for this PE have been read back.
      if (checkpoint_restore) begin
        state          <= S_WAIT_BLOCK;
        accumulator    <= checkpoint_accumulator;
        bias_reg       <= checkpoint_bias;
        input_count    <= 16'd0;
        expected_count <= 16'd0;
        add_index      <= 16'd0;
        final_block    <= 1'b0;
        add_busy       <= 1'b0;
        result         <= 32'd0;
        result_valid   <= 1'b0;
        done           <= 1'b0;
        for (i = 0; i < MUL_LATENCY; i = i + 1)
          mul_valid_pipe[i] <= 1'b0;
        for (i = 0; i < ADD_LATENCY; i = i + 1)
          add_valid_pipe[i] <= 1'b0;
      end
    end
  end
endmodule
