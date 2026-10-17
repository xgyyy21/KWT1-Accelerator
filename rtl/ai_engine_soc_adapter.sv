// SoC integration boundary for the AI Engine.
// The E203-side bus is reduced to a one-cycle register request/response;
// platform SRAM/DMA logic supplies one tile's parallel words and completion
// handshakes. A NICE or System-Bus adapter can be placed in front of this
// module without changing the compute datapath.
module ai_engine_soc_adapter #(
  parameter int DATA_WIDTH = 16,
  parameter int ACC_WIDTH = 32,
  parameter int ROWS = 8,
  parameter int COLS = 16,
  parameter int K = 4
) (
  input logic clk,
  input logic rst_n,
  input logic bus_valid,
  input logic bus_write,
  input logic [31:0] bus_addr,
  input logic [31:0] bus_wdata,
  output logic bus_ready,
  output logic bus_rsp_valid,
  output logic [31:0] bus_rdata,
  input logic tile_load_done,
  input logic tile_in_valid,
  input logic [DATA_WIDTH-1:0] a_tile [ROWS],
  input logic [DATA_WIDTH-1:0] b_tile [COLS],
  input logic [15:0] valid_rows,
  input logic [15:0] valid_cols,
  input logic writeback_done,
  output logic tile_load_start,
  output logic compute_start,
  output logic writeback_start,
  output logic result_valid,
  output logic result_last,
  output logic [ACC_WIDTH-1:0] result_data,
  output logic [15:0] result_row,
  output logic [15:0] result_col,
  output logic engine_busy,
  output logic engine_done,
  output logic engine_error
);
  logic engine_start;
  logic [31:0] src_a_base, src_b_base, dst_base;
  logic [15:0] matrix_m, matrix_k, matrix_n;

  ai_engine_regs u_regs (
    .clk(clk), .rst_n(rst_n), .req_valid(bus_valid), .req_write(bus_write),
    .req_addr(bus_addr), .req_wdata(bus_wdata), .req_ready(bus_ready),
    .rsp_valid(bus_rsp_valid), .rsp_rdata(bus_rdata),
    .engine_busy(engine_busy), .engine_done(engine_done),
    .engine_error(engine_error), .engine_start(engine_start),
    .src_a_base(src_a_base), .src_b_base(src_b_base), .dst_base(dst_base),
    .matrix_m(matrix_m), .matrix_k(matrix_k), .matrix_n(matrix_n)
  );

  ai_engine_core #(
    .DATA_WIDTH(DATA_WIDTH), .ACC_WIDTH(ACC_WIDTH),
    .ROWS(ROWS), .COLS(COLS), .K(K)
  ) u_core (
    .clk(clk), .rst_n(rst_n), .start(engine_start),
    .tile_load_done(tile_load_done), .writeback_done(writeback_done),
    .tile_in_valid(tile_in_valid), .a_tile(a_tile), .b_tile(b_tile),
    .valid_rows(valid_rows), .valid_cols(valid_cols),
    .tile_load_start(tile_load_start), .compute_start(compute_start),
    .writeback_start(writeback_start), .busy(engine_busy),
    .done(engine_done), .error(engine_error),
    .result_valid(result_valid), .result_last(result_last),
    .result_data(result_data), .result_row(result_row), .result_col(result_col)
  );
endmodule
