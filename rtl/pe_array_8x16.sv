// 8x16 PE fabric. Data movement is external; this module owns only PE
// arithmetic and per-cell accumulation control.
module pe_array_8x16 #(
  parameter int DATA_WIDTH = 16,
  parameter int ACC_WIDTH = 2 * DATA_WIDTH,
  parameter int ROWS = 8,
  parameter int COLS = 16,
  parameter bit SIGNED_DATA = 1'b1,
  parameter bit FP32_MODE = 1'b0,
  parameter int K = 64
) (
  input logic clk,
  input logic rst_n,
  input logic clear_acc,
  input logic in_valid [ROWS][COLS],
  input logic first_valid [ROWS][COLS],
  input logic last_valid [ROWS][COLS],
  input logic [DATA_WIDTH-1:0] a_data [ROWS][COLS],
  input logic [DATA_WIDTH-1:0] b_data [ROWS][COLS],
  input logic [31:0] bias_data [COLS],
  output logic result_valid [ROWS][COLS],
  output logic [ACC_WIDTH-1:0] result [ROWS][COLS],
  output logic busy [ROWS][COLS],
  output logic trace_valid [ROWS][COLS],
  output logic [31:0] trace_cycle [ROWS][COLS],
  output logic [15:0] trace_k [ROWS][COLS],
  output logic [31:0] trace_x_bits [ROWS][COLS],
  output logic [31:0] trace_w_bits [ROWS][COLS],
  output logic [31:0] trace_acc_before_bits [ROWS][COLS],
  output logic [31:0] trace_product_bits [ROWS][COLS],
  output logic [31:0] trace_acc_after_bits [ROWS][COLS],
  output logic trace_bias_valid [ROWS][COLS],
  output logic [31:0] trace_bias_bits [ROWS][COLS]
);
  genvar r, c;
  generate
    for (r=0; r<ROWS; r=r+1) begin : GEN_R
      for (c=0; c<COLS; c=c+1) begin : GEN_C
        if (FP32_MODE) begin : GEN_FP32
          fp32_pe_mac #(.K(K)) u_fp32_pe (
            .clk(clk), .rst_n(rst_n), .enable(1'b1),
            .clear_acc(clear_acc), .task_first(first_valid[r][c]),
            .task_last(last_valid[r][c]), .in_valid(in_valid[r][c]),
            .a_in(a_data[r][c]), .b_in(b_data[r][c]), .bias_in(bias_data[c]),
            .result_valid(result_valid[r][c]), .result(result[r][c]),
            .busy(busy[r][c]), .done(), .trace_valid(trace_valid[r][c]),
            .trace_cycle(trace_cycle[r][c]), .trace_k(trace_k[r][c]),
            .trace_x_bits(trace_x_bits[r][c]), .trace_w_bits(trace_w_bits[r][c]),
            .trace_acc_before_bits(trace_acc_before_bits[r][c]),
            .trace_product_bits(trace_product_bits[r][c]),
            .trace_acc_after_bits(trace_acc_after_bits[r][c]),
            .trace_bias_valid(trace_bias_valid[r][c]),
            .trace_bias_bits(trace_bias_bits[r][c])
          );
        end else begin : GEN_INT
          pe_mac #(.DATA_WIDTH(DATA_WIDTH), .ACC_WIDTH(ACC_WIDTH),
                   .SIGNED_DATA(SIGNED_DATA)) u_pe (
            .clk(clk), .rst_n(rst_n), .enable(1'b1),
            .clear_acc(clear_acc), .task_first(first_valid[r][c]),
            .task_last(last_valid[r][c]), .in_valid(in_valid[r][c]),
            .a_in(a_data[r][c]), .b_in(b_data[r][c]),
            .a_valid_out(), .b_valid_out(), .a_out(), .b_out(),
            .result_valid(result_valid[r][c]), .result(result[r][c]),
            .busy(busy[r][c]), .done()
          );
          assign trace_valid[r][c] = 1'b0;
          assign trace_cycle[r][c] = 32'b0;
          assign trace_k[r][c] = 16'b0;
          assign trace_x_bits[r][c] = 32'b0;
          assign trace_w_bits[r][c] = 32'b0;
          assign trace_acc_before_bits[r][c] = 32'b0;
          assign trace_product_bits[r][c] = 32'b0;
          assign trace_acc_after_bits[r][c] = 32'b0;
          assign trace_bias_valid[r][c] = 1'b0;
          assign trace_bias_bits[r][c] = 32'b0;
        end
      end
    end
  endgenerate
  initial begin
    if (FP32_MODE && (DATA_WIDTH!=32 || ACC_WIDTH!=32))
      $fatal(1,"FP32 PE array requires DATA_WIDTH=ACC_WIDTH=32");
  end
endmodule
