// Functional FP32 PE with 8-cycle multiply and 4-cycle add latency.
// The reference arithmetic functions currently execute combinationally before
// their latency registers, so this is an integration model, not timing closure.
module fp32_pe_mac #(
  parameter int K = 64,
  parameter int MUL_LATENCY = 8,
  parameter int ADD_LATENCY = 4
) (
  input logic clk, input logic rst_n, input logic enable, input logic clear_acc,
  input logic task_first, input logic task_last, input logic in_valid,
  input logic [31:0] a_in, input logic [31:0] b_in,
  input logic [31:0] bias_in,
  output logic result_valid, output logic [31:0] result,
  output logic busy, output logic done,
  output logic trace_valid, output logic [31:0] trace_cycle,
  output logic [15:0] trace_k,
  output logic [31:0] trace_x_bits, trace_w_bits,
  output logic [31:0] trace_acc_before_bits, trace_product_bits,
  output logic [31:0] trace_acc_after_bits,
  output logic trace_bias_valid, output logic [31:0] trace_bias_bits
);
  import fp32_math_pkg::*;
  localparam logic [2:0] S_IDLE=3'd0, S_MULT=3'd1, S_ADD=3'd2,
                         S_BIAS=3'd3, S_DONE=3'd4;
  logic [2:0] state;
  logic [31:0] mul_product_pipe [0:MUL_LATENCY-1];
  logic [31:0] mul_x_pipe [0:MUL_LATENCY-1], mul_w_pipe [0:MUL_LATENCY-1];
  logic [15:0] mul_k_pipe [0:MUL_LATENCY-1];
  logic mul_last_pipe [0:MUL_LATENCY-1], mul_valid_pipe [0:MUL_LATENCY-1];
  logic [31:0] product_mem [0:K-1], x_mem [0:K-1], w_mem [0:K-1];
  logic [31:0] add_before_pipe [0:ADD_LATENCY-1];
  logic [31:0] add_product_pipe [0:ADD_LATENCY-1], add_sum_pipe [0:ADD_LATENCY-1];
  logic [31:0] add_x_pipe [0:ADD_LATENCY-1], add_w_pipe [0:ADD_LATENCY-1];
  logic [15:0] add_k_pipe [0:ADD_LATENCY-1];
  logic add_bias_pipe [0:ADD_LATENCY-1], add_valid_pipe [0:ADD_LATENCY-1];
  logic [31:0] accumulator;
  logic add_busy;
  integer input_count, expected_count, add_index, cycle_count;
  integer i;

  initial begin
    if (K<=0 || MUL_LATENCY!=8 || ADD_LATENCY!=4)
      $fatal(1,"fp32_pe_mac requires K>0 and the 8+4-cycle pipeline contract");
  end
  assign busy = (state != S_IDLE) && (state != S_DONE);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state<=S_IDLE; accumulator<=0; result<=0; result_valid<=0; done<=0;
      add_busy<=0; input_count<=0; expected_count<=0; add_index<=0; cycle_count<=0;
      trace_valid<=0; trace_cycle<=0; trace_k<=0; trace_x_bits<=0; trace_w_bits<=0;
      trace_acc_before_bits<=0; trace_product_bits<=0; trace_acc_after_bits<=0;
      trace_bias_valid<=0; trace_bias_bits<=0;
      for(i=0;i<MUL_LATENCY;i=i+1) begin
        mul_product_pipe[i]<=0; mul_x_pipe[i]<=0; mul_w_pipe[i]<=0;
        mul_k_pipe[i]<=0; mul_last_pipe[i]<=0; mul_valid_pipe[i]<=0;
      end
      for(i=0;i<ADD_LATENCY;i=i+1) begin
        add_before_pipe[i]<=0; add_product_pipe[i]<=0; add_sum_pipe[i]<=0;
        add_x_pipe[i]<=0; add_w_pipe[i]<=0; add_k_pipe[i]<=0;
        add_bias_pipe[i]<=0; add_valid_pipe[i]<=0;
      end
      for(i=0;i<K;i=i+1) begin product_mem[i]<=0; x_mem[i]<=0; w_mem[i]<=0; end
    end else begin
      cycle_count<=cycle_count+1;
      result_valid<=0; done<=0; trace_valid<=0; trace_bias_valid<=0;
      for(i=MUL_LATENCY-1;i>0;i=i-1) begin
        mul_product_pipe[i]<=mul_product_pipe[i-1]; mul_x_pipe[i]<=mul_x_pipe[i-1];
        mul_w_pipe[i]<=mul_w_pipe[i-1]; mul_k_pipe[i]<=mul_k_pipe[i-1];
        mul_last_pipe[i]<=mul_last_pipe[i-1]; mul_valid_pipe[i]<=mul_valid_pipe[i-1];
      end
      mul_valid_pipe[0]<=0;
      for(i=ADD_LATENCY-1;i>0;i=i-1) begin
        add_before_pipe[i]<=add_before_pipe[i-1];
        add_product_pipe[i]<=add_product_pipe[i-1]; add_sum_pipe[i]<=add_sum_pipe[i-1];
        add_x_pipe[i]<=add_x_pipe[i-1]; add_w_pipe[i]<=add_w_pipe[i-1];
        add_k_pipe[i]<=add_k_pipe[i-1]; add_bias_pipe[i]<=add_bias_pipe[i-1];
        add_valid_pipe[i]<=add_valid_pipe[i-1];
      end
      add_valid_pipe[0]<=0;

      if (clear_acc || task_first) begin
        state<=S_MULT; accumulator<=0; input_count<=0; expected_count<=0;
        add_index<=0; add_busy<=0;
        for(i=0;i<MUL_LATENCY;i=i+1) mul_valid_pipe[i]<=0;
        for(i=0;i<ADD_LATENCY;i=i+1) add_valid_pipe[i]<=0;
        for(i=0;i<K;i=i+1) begin product_mem[i]<=0; x_mem[i]<=0; w_mem[i]<=0; end
        if(task_first && enable && in_valid) begin
          mul_valid_pipe[0]<=1; mul_product_pipe[0]<=fp32_mul(a_in,b_in);
          mul_x_pipe[0]<=a_in; mul_w_pipe[0]<=b_in;
          mul_k_pipe[0]<=0; mul_last_pipe[0]<=task_last;
          input_count<=1;
        end
      end else begin
        if (state==S_MULT && enable && in_valid) begin
          if(input_count>=K) $fatal(1,"fp32_pe_mac input exceeds configured K");
          mul_valid_pipe[0]<=1; mul_product_pipe[0]<=fp32_mul(a_in,b_in);
          mul_x_pipe[0]<=a_in; mul_w_pipe[0]<=b_in;
          mul_k_pipe[0]<=16'(input_count); mul_last_pipe[0]<=task_last;
          input_count<=input_count+1;
        end
        if(mul_valid_pipe[MUL_LATENCY-1]) begin
          product_mem[mul_k_pipe[MUL_LATENCY-1]]<=mul_product_pipe[MUL_LATENCY-1];
          x_mem[mul_k_pipe[MUL_LATENCY-1]]<=mul_x_pipe[MUL_LATENCY-1];
          w_mem[mul_k_pipe[MUL_LATENCY-1]]<=mul_w_pipe[MUL_LATENCY-1];
          if(mul_last_pipe[MUL_LATENCY-1]) begin
            expected_count<=mul_k_pipe[MUL_LATENCY-1]+1;
            add_index<=0; state<=S_ADD;
          end
        end
        if((state==S_ADD || state==S_BIAS) && !add_busy) begin
          add_valid_pipe[0]<=1; add_before_pipe[0]<=accumulator;
          add_bias_pipe[0]<=(state==S_BIAS);
          if(state==S_BIAS) begin
            add_product_pipe[0]<=bias_in; add_sum_pipe[0]<=fp32_add(accumulator,bias_in);
            add_x_pipe[0]<=0; add_w_pipe[0]<=0; add_k_pipe[0]<=16'hffff;
          end else begin
            add_product_pipe[0]<=product_mem[add_index];
            add_sum_pipe[0]<=fp32_add(accumulator,product_mem[add_index]);
            add_x_pipe[0]<=x_mem[add_index]; add_w_pipe[0]<=w_mem[add_index];
            add_k_pipe[0]<=16'(add_index);
          end
          add_busy<=1;
        end
        if(add_valid_pipe[ADD_LATENCY-1]) begin
          accumulator<=add_sum_pipe[ADD_LATENCY-1]; add_busy<=0;
          trace_cycle<=32'(cycle_count+1);
          trace_acc_before_bits<=add_before_pipe[ADD_LATENCY-1];
          trace_acc_after_bits<=add_sum_pipe[ADD_LATENCY-1];
          if(add_bias_pipe[ADD_LATENCY-1]) begin
            trace_bias_valid<=1; trace_bias_bits<=add_product_pipe[ADD_LATENCY-1];
            result<=add_sum_pipe[ADD_LATENCY-1]; result_valid<=1; done<=1; state<=S_DONE;
          end else begin
            trace_valid<=1; trace_k<=add_k_pipe[ADD_LATENCY-1];
            trace_x_bits<=add_x_pipe[ADD_LATENCY-1]; trace_w_bits<=add_w_pipe[ADD_LATENCY-1];
            trace_product_bits<=add_product_pipe[ADD_LATENCY-1];
            if(add_k_pipe[ADD_LATENCY-1]+1==expected_count) state<=S_BIAS;
            else add_index<=add_index+1;
          end
        end
      end
    end
  end
endmodule
