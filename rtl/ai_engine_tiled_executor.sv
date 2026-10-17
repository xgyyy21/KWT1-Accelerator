// Hardware task sequencer for one-K-block tiled matrix product.
// It issues an M/N tile descriptor to an external DMA, waits for the DMA to
// fill the local A/B caches, computes one tile, then waits for writeback. The
// local PE path is fixed to K inputs, so K>parameter K accumulation is not
// claimed by this module.
module ai_engine_tiled_executor #(
  parameter int DATA_WIDTH = 16,
  parameter int ROWS = 8,
  parameter int COLS = 16,
  parameter int K = 64,
  parameter int CACHE_ADDR_WIDTH = 10
) (
  input logic clk,
  input logic rst_n,
  input logic task_start,
  input logic [15:0] matrix_m,
  input logic [15:0] matrix_k,
  input logic [15:0] matrix_n,
  output logic tile_request_valid,
  output logic [15:0] row_base,
  output logic [15:0] col_base,
  output logic [15:0] k_base,
  output logic [15:0] rows_valid,
  output logic [15:0] cols_valid,
  output logic [15:0] k_valid,
  input logic tile_loaded,
  input logic load_valid,
  input logic load_select_b,
  input logic [CACHE_ADDR_WIDTH-1:0] load_addr,
  input logic [DATA_WIDTH-1:0] load_data,
  output logic load_ready,
  output logic writeback_start,
  input logic writeback_done,
  input logic result_rd_en,
  input logic [CACHE_ADDR_WIDTH-1:0] result_rd_addr,
  output logic [DATA_WIDTH-1:0] result_rd_data,
  output logic result_rd_valid,
  output logic busy,
  output logic done,
  output logic error
);
  typedef enum logic [2:0] {
    S_WAIT_BLOCK, S_WAIT_LOAD, S_START_TILE, S_RUN_TILE,
    S_WRITEBACK, S_ADVANCE, S_ERROR
  } state_t;
  state_t state;
  logic controller_start, controller_busy, controller_done, block_start, block_done;
  logic task_config_ok, config_error_latched;
  logic loop_start, loop_busy, loop_done, loop_error;

  assign task_config_ok = (matrix_m > 0) && (matrix_k == K) && (matrix_n > 0);
  assign controller_start = task_start && task_config_ok;
  assign error = loop_error || config_error_latched;
  assign done = controller_done && !error;
  assign busy = controller_busy || state == S_WAIT_LOAD || state == S_START_TILE ||
                state == S_RUN_TILE || state == S_WRITEBACK || state == S_ADVANCE;
  assign tile_request_valid = (state == S_WAIT_LOAD);
  assign load_ready = (state == S_WAIT_LOAD) && !loop_busy;
  assign writeback_start = (state == S_WRITEBACK);
  assign loop_start = (state == S_START_TILE);
  assign block_done = (state == S_ADVANCE);

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) config_error_latched <= 1'b0;
    else if (task_start) config_error_latched <= !task_config_ok;
  end

  matrix_task_controller #(
    .ROW_TILE(ROWS), .COL_TILE(COLS), .K_TILE(K)
  ) u_controller (
    .clk(clk), .rst_n(rst_n), .start(controller_start),
    .matrix_m(matrix_m), .matrix_k(matrix_k), .matrix_n(matrix_n),
    .block_done(block_done), .block_start(block_start),
    .task_busy(controller_busy), .task_done(controller_done),
    .row_base(row_base), .col_base(col_base), .k_base(k_base),
    .rows_valid(rows_valid), .cols_valid(cols_valid), .k_valid(k_valid),
    .k_first(), .k_last()
  );

  ai_engine_tile_loop #(
    .DATA_WIDTH(DATA_WIDTH), .ACC_WIDTH(DATA_WIDTH), .ROWS(ROWS),
    .COLS(COLS), .K(K), .CACHE_ADDR_WIDTH(CACHE_ADDR_WIDTH)
  ) u_tile_loop (
    .clk(clk), .rst_n(rst_n), .start(loop_start),
    .valid_rows(rows_valid), .valid_cols(cols_valid),
    .a_load_en(load_valid && !load_select_b && load_ready),
    .a_load_addr(load_addr), .a_load_data(load_data),
    .b_load_en(load_valid && load_select_b && load_ready),
    .b_load_addr(load_addr), .b_load_data(load_data),
    .result_rd_en(result_rd_en), .result_rd_addr(result_rd_addr),
    .result_rd_data(result_rd_data), .result_rd_valid(result_rd_valid),
    .busy(loop_busy), .done(loop_done), .error(loop_error)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) state <= S_WAIT_BLOCK;
    else begin
      case (state)
        S_WAIT_BLOCK: begin
          if (error) state <= S_ERROR;
          else if (block_start) state <= S_WAIT_LOAD;
        end
        S_WAIT_LOAD: begin
          if (error) state <= S_ERROR;
          else if (tile_loaded) state <= S_START_TILE;
        end
        S_START_TILE: state <= S_RUN_TILE;
        S_RUN_TILE: begin
          if (error) state <= S_ERROR;
          else if (loop_done) state <= S_WRITEBACK;
        end
        S_WRITEBACK: if (writeback_done) state <= S_ADVANCE;
        S_ADVANCE: state <= S_WAIT_BLOCK;
        S_ERROR: if (task_start && task_config_ok) state <= S_WAIT_BLOCK;
        default: state <= S_ERROR;
      endcase
    end
  end
endmodule
