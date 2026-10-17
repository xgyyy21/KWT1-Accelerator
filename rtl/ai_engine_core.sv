module ai_engine_core #(
  parameter int DATA_WIDTH = 16,
  parameter int ACC_WIDTH  = 32,
  parameter int ROWS = 8,
  parameter int COLS = 16,
  // The undergraduate first-layer contract reduces over K=64 inputs.
  parameter int K = 64
) (
  input logic clk,
  input logic rst_n,
  input logic start,
  input logic tile_load_done,
  input logic writeback_done,
  input logic tile_in_valid,
  input logic [DATA_WIDTH-1:0] a_tile [ROWS],
  input logic [DATA_WIDTH-1:0] b_tile [COLS],
  input logic [15:0] valid_rows,
  input logic [15:0] valid_cols,
  output logic tile_load_start,
  output logic compute_start,
  output logic writeback_start,
  output logic busy,
  output logic done,
  output logic error,
  output logic result_valid,
  output logic result_last,
  output logic [ACC_WIDTH-1:0] result_data,
  output logic [15:0] result_row,
  output logic [15:0] result_col
);
  logic compute_done;
  logic stream_valid;
  logic stream_active;
  logic [DATA_WIDTH-1:0] a_stream [ROWS];
  logic [DATA_WIDTH-1:0] b_stream [COLS];
  logic tile_busy;
  logic compute_start_d;
  logic compute_start_pulse;
  logic [15:0] rows_q, cols_q;
  logic config_error;
  assign config_error = busy ? (rows_q==0 || rows_q>ROWS || cols_q==0 || cols_q>COLS) :
                               (valid_rows==0 || valid_rows>ROWS || valid_cols==0 || valid_cols>COLS);
  always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin rows_q<=0; cols_q<=0; end
    else if(start && !busy) begin rows_q<=valid_rows; cols_q<=valid_cols; end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) compute_start_d <= 1'b0;
    else compute_start_d <= compute_start;
  end
  assign compute_start_pulse = compute_start && !compute_start_d;

  ai_engine_fsm u_fsm (
    .clk(clk), .rst_n(rst_n), .start(start),
    .dma_load_done(tile_load_done), .compute_done(compute_done),
    .writeback_done(writeback_done), .error_in(config_error),
    .dma_load_start(tile_load_start), .compute_start(compute_start),
    .writeback_start(writeback_start), .busy(busy), .done(done),
    .error(error), .state()
  );

  tile_stream_adapter #(.DATA_WIDTH(DATA_WIDTH), .ROWS(ROWS), .COLS(COLS)) u_stream (
    .clk(clk), .rst_n(rst_n), .start(compute_start_pulse), .stop(compute_done),
    .input_valid(tile_in_valid), .a_mem_data(a_tile), .b_mem_data(b_tile),
    .stream_valid(stream_valid), .a_left(a_stream), .b_top(b_stream),
    .active(stream_active)
  );

  systolic_tile_engine #(
    .DATA_WIDTH(DATA_WIDTH), .ACC_WIDTH(ACC_WIDTH),
    .ROWS(ROWS), .COLS(COLS), .K(K)
  ) u_tile (
    .clk(clk), .rst_n(rst_n), .start(compute_start_pulse),
    .in_valid(stream_valid), .a_left(a_stream), .b_top(b_stream),
    .valid_rows(rows_q), .valid_cols(cols_q),
    .busy(tile_busy), .done(compute_done), .result_valid(result_valid),
    .result_last(result_last), .result_data(result_data),
    .result_row(result_row), .result_col(result_col)
  );
endmodule
