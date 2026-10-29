// FP32 tile-level wrapper used between the future cache/DMA path and the
// 8x16 array.  It owns one output tile at a time and drains valid rows/cols
// in row-major order after the array has completed.
module fp32_tile_engine #(
  parameter int ROWS = 8,
  parameter int COLS = 16,
  parameter int K = 64
) (
  input logic clk,
  input logic rst_n,
  input logic start,
  input logic stream_valid,
  input logic task_first,
  input logic task_last,
  input logic [31:0] a_left [ROWS],
  input logic [31:0] b_top [COLS],
  input logic [31:0] bias_in [COLS],
  input logic [15:0] valid_rows,
  input logic [15:0] valid_cols,
  output logic busy,
  output logic done,
  output logic result_valid,
  output logic result_last,
  output logic [31:0] result_data,
  output logic [15:0] result_row,
  output logic [15:0] result_col
);
  logic array_busy;
  logic array_done;
  logic array_result_valid;
  logic [31:0] array_result [ROWS][COLS];
  logic collector_busy;
  logic collector_done;
  logic collector_start;
  logic array_start;

  assign busy = array_busy || collector_busy;
  assign collector_start = start && !busy;
  assign array_start = collector_start && valid_rows > 0 && valid_rows <= ROWS &&
                       valid_cols > 0 && valid_cols <= COLS;

  fp32_pe_array_8x16 #(.ROWS(ROWS), .COLS(COLS), .K(K)) u_array (
    .clk(clk), .rst_n(rst_n), .start(array_start),
    .stream_valid(stream_valid), .task_first(task_first),
    .task_last(task_last), .a_left(a_left), .b_top(b_top),
    .bias_in(bias_in),
    // Checkpoint SRAM control is not yet exposed at the tile-engine API.
    .checkpoint_save_req(1'b0), .checkpoint_restore_req(1'b0),
    .checkpoint_busy(), .checkpoint_done(), .checkpoint_error(),
    .checkpoint_mem_req(), .checkpoint_mem_we(), .checkpoint_mem_addr(),
    .checkpoint_mem_wdata(), .checkpoint_mem_rvalid(1'b0), .checkpoint_mem_rdata(16'd0),
    .busy(array_busy), .done(array_done),
    .result_valid(array_result_valid), .result(array_result)
  );

  tile_result_collector #(.DATA_WIDTH(32), .ROWS(ROWS), .COLS(COLS)) u_collector (
    .clk(clk), .rst_n(rst_n), .start(collector_start),
    .pe_result_valid(array_result_valid), .pe_result(array_result),
    .valid_rows(valid_rows), .valid_cols(valid_cols),
    .result_valid(result_valid), .result_last(result_last),
    .result_data(result_data), .result_row(result_row),
    .result_col(result_col), .busy(collector_busy), .done(collector_done)
  );

  assign done = collector_done;
endmodule
