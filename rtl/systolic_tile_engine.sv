module systolic_tile_engine #(
  parameter int DATA_WIDTH = 16,
  parameter int ACC_WIDTH  = 32,
  parameter int ROWS = 8,
  parameter int COLS = 16,
  parameter int K = 64
) (
  input  logic clk,
  input  logic rst_n,
  input  logic start,
  input  logic in_valid,
  input  logic [DATA_WIDTH-1:0] a_left [ROWS],
  input  logic [DATA_WIDTH-1:0] b_top [COLS],
  input  logic [15:0] valid_rows,
  input  logic [15:0] valid_cols,
  output logic busy,
  output logic done,
  output logic result_valid,
  output logic result_last,
  output logic [ACC_WIDTH-1:0] result_data,
  output logic [15:0] result_row,
  output logic [15:0] result_col
);
  logic array_busy, array_done, array_result_valid;
  logic [ACC_WIDTH-1:0] array_result [ROWS][COLS];
  logic [31:0] zero_bias [COLS];
  logic collector_busy, collector_done;
  logic collector_start;
  logic array_start;

  assign collector_start = start && !busy;
  assign array_start = collector_start && valid_rows>0 && valid_rows<=ROWS &&
                       valid_cols>0 && valid_cols<=COLS;
  assign busy = array_busy | collector_busy;
  assign done = collector_done;

  genvar bias_col;
  generate for (bias_col=0; bias_col<COLS; bias_col=bias_col+1) begin : GEN_ZERO_BIAS
    assign zero_bias[bias_col] = 32'b0;
  end endgenerate

  systolic_array_8x16 #(
    .DATA_WIDTH(DATA_WIDTH), .ACC_WIDTH(ACC_WIDTH),
    .ROWS(ROWS), .COLS(COLS), .K(K)
  ) u_array (
    .clk(clk), .rst_n(rst_n), .start(array_start), .in_valid(in_valid),
    .a_left(a_left), .b_top(b_top), .bias_data(zero_bias),
    .busy(array_busy), .done(array_done),
    .result_valid(array_result_valid), .result(array_result)
  );

  tile_result_collector #(
    .DATA_WIDTH(ACC_WIDTH), .ROWS(ROWS), .COLS(COLS)
  ) u_collector (
    .clk(clk), .rst_n(rst_n), .start(collector_start),
    .pe_result_valid(array_result_valid), .pe_result(array_result),
    .valid_rows(valid_rows), .valid_cols(valid_cols),
    .result_valid(result_valid), .result_last(result_last),
    .result_data(result_data), .result_row(result_row), .result_col(result_col),
    .busy(collector_busy), .done(collector_done)
  );
endmodule
