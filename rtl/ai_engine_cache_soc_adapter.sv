// Register-controlled boundary for one integer 8x16xK cache-resident tile.
// A system DMA may drive load_valid/load_select_b/load_addr/load_data; that
// external protocol is intentionally left outside this module until the E203
// bus and SRAM contracts are frozen.
module ai_engine_cache_soc_adapter #(
  parameter int DATA_WIDTH = 16,
  parameter int ROWS = 8,
  parameter int COLS = 16,
  parameter int K = 64,
  parameter int CACHE_ADDR_WIDTH = 10
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
  input logic load_valid,
  input logic load_select_b,
  input logic [CACHE_ADDR_WIDTH-1:0] load_addr,
  input logic [DATA_WIDTH-1:0] load_data,
  output logic load_ready,
  input logic result_rd_en,
  input logic [CACHE_ADDR_WIDTH-1:0] result_rd_addr,
  output logic [DATA_WIDTH-1:0] result_rd_data,
  output logic result_rd_valid,
  output logic engine_busy,
  output logic engine_done,
  output logic engine_error
);
  logic engine_start;
  logic [31:0] src_a_base, src_b_base, dst_base;
  logic [15:0] matrix_m, matrix_k, matrix_n;
  logic config_ok;
  logic loop_start, loop_busy, loop_done, loop_error;
  logic config_error_latched;

  // One tile may be a tail tile. Multi-tile scheduling and external SRAM
  // addressing remain in the scheduler/DMA integration layer.
  assign config_ok = (matrix_m > 0) && (matrix_m <= ROWS) &&
                     (matrix_k == K) &&
                     (matrix_n > 0) && (matrix_n <= COLS);
  assign loop_start = engine_start && config_ok;
  assign engine_busy = loop_busy;
  assign engine_done = loop_done;
  assign engine_error = loop_error || config_error_latched;
  assign load_ready = !loop_busy;

  // Hold rejected-configuration status long enough for the CPU to observe it.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) config_error_latched <= 1'b0;
    else if (engine_start) config_error_latched <= !config_ok;
  end

  ai_engine_regs u_regs (
    .clk(clk), .rst_n(rst_n),
    .req_valid(bus_valid), .req_write(bus_write),
    .req_addr(bus_addr), .req_wdata(bus_wdata), .req_ready(bus_ready),
    .rsp_valid(bus_rsp_valid), .rsp_rdata(bus_rdata),
    .engine_busy(engine_busy), .engine_done(engine_done),
    .engine_error(engine_error), .engine_start(engine_start),
    .src_a_base(src_a_base), .src_b_base(src_b_base), .dst_base(dst_base),
    .matrix_m(matrix_m), .matrix_k(matrix_k), .matrix_n(matrix_n)
  );

  ai_engine_tile_loop #(
    .DATA_WIDTH(DATA_WIDTH), .ACC_WIDTH(DATA_WIDTH), .ROWS(ROWS),
    .COLS(COLS), .K(K), .CACHE_ADDR_WIDTH(CACHE_ADDR_WIDTH)
  ) u_tile_loop (
    .clk(clk), .rst_n(rst_n), .start(loop_start),
    .valid_rows(matrix_m), .valid_cols(matrix_n),
    .a_load_en(load_valid && !load_select_b && load_ready),
    .a_load_addr(load_addr), .a_load_data(load_data),
    .b_load_en(load_valid && load_select_b && load_ready),
    .b_load_addr(load_addr), .b_load_data(load_data),
    .result_rd_en(result_rd_en), .result_rd_addr(result_rd_addr),
    .result_rd_data(result_rd_data), .result_rd_valid(result_rd_valid),
    .busy(loop_busy), .done(loop_done), .error(loop_error)
  );
endmodule
