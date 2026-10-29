// Two-or-more physical K-block integration for one 8x16 tile.
//
// Each block is loaded into the same local A/B/bias caches.  The first stream
// starts the FP32 tile engine; later streams are accepted by the still-live
// PE array without clearing its accumulators.  The writeback phase starts only
// after the final block and final PE result.
module fp32_tile_kblock_load_compute #(
  parameter int ROW_TILE = 8,
  parameter int COL_TILE = 16,
  parameter int K_TILE = 32,
  parameter int K_BLOCKS = 2,
  parameter int ADDR_WIDTH = 32,
  parameter int CACHE_ADDR_WIDTH = 10
) (
  input logic clk,
  input logic rst_n,
  input logic start,
  input logic [15:0] k_block_count,
  input logic [15:0] matrix_m,
  input logic [15:0] matrix_k,
  input logic [15:0] matrix_n,
  input logic [15:0] row_base,
  input logic [15:0] col_base,
  input logic [15:0] k_base,
  input logic [15:0] rows_valid,
  input logic [15:0] cols_valid,
  input logic [15:0] k_valid_block,
  input logic [ADDR_WIDTH-1:0] a_base_word,
  input logic [ADDR_WIDTH-1:0] b_base_word,
  input logic [ADDR_WIDTH-1:0] bias_base_word,
  input logic [ADDR_WIDTH-1:0] result_base_word,

  input logic bus_req_ready,
  input logic bus_rsp_valid,
  input logic [15:0] bus_rsp_rdata,
  output logic bus_req_valid,
  output logic bus_req_write,
  output logic [ADDR_WIDTH-1:0] bus_req_addr,
  output logic [15:0] bus_req_wdata,

  input logic error_in,
  output logic load_busy,
  output logic load_done,
  output logic stream_busy,
  output logic compute_busy,
  output logic compute_done,
  output logic writeback_busy,
  output logic writeback_done,
  output logic result_valid,
  output logic result_last,
  output logic [31:0] result_data,
  output logic [15:0] result_row,
  output logic [15:0] result_col,
  output logic busy,
  output logic done,
  output logic error,
  output logic [((K_BLOCKS <= 1) ? 1 : $clog2(K_BLOCKS))-1:0] block_index,
  output logic task_first,
  output logic task_last,
  output logic [2:0] state
);
  localparam int BLOCK_INDEX_WIDTH = (K_BLOCKS <= 1) ? 1 : $clog2(K_BLOCKS);

  logic load_start, stream_start, compute_start, writeback_start;
  logic ctrl_busy;
  logic stream_done;
  logic [15:0] current_k_base;

  logic load_bus_req_valid, load_bus_req_write;
  logic [ADDR_WIDTH-1:0] load_bus_req_addr;
  logic [15:0] load_bus_req_wdata;
  logic wb_bus_req_valid, wb_bus_req_write;
  logic [ADDR_WIDTH-1:0] wb_bus_req_addr;
  logic [15:0] wb_bus_req_wdata;

  logic a_wr_en, b_wr_en, result_wr_en;
  logic [CACHE_ADDR_WIDTH-1:0] a_wr_addr, b_wr_addr, result_wr_addr;
  logic [15:0] a_wr_data, b_wr_data, result_wr_data;
  logic a_rd_en, b_rd_en, result_rd_en;
  logic [CACHE_ADDR_WIDTH-1:0] a_rd_addr, b_rd_addr, result_rd_addr;
  logic [15:0] a_rd_data, b_rd_data, result_rd_data;
  logic a_rd_valid, b_rd_valid, result_rd_valid;

  logic stream_valid;
  logic stream_task_first;
  logic stream_task_last;
  logic [31:0] a_left [ROW_TILE];
  logic [31:0] b_top [COL_TILE];
  logic [31:0] bias_in [COL_TILE];

  logic wb_result_rd_en;
  logic [CACHE_ADDR_WIDTH-1:0] wb_result_rd_addr;
  logic [15:0] wb_result_rd_data;
  logic wb_result_rd_valid;
  logic [31:0] result_stage [ROW_TILE][COL_TILE];
  logic wb_stage_pending;
  logic [CACHE_ADDR_WIDTH-1:0] wb_stage_pending_addr;
  logic [15:0] wb_stage_read_data;
  integer stage_elem, stage_row, stage_col;
  integer sr, sc;

  assign busy = ctrl_busy;
  assign bus_req_valid = load_bus_req_valid || wb_bus_req_valid;
  assign bus_req_write = wb_bus_req_valid ? wb_bus_req_write : load_bus_req_write;
  assign bus_req_addr = wb_bus_req_valid ? wb_bus_req_addr : load_bus_req_addr;
  assign bus_req_wdata = wb_bus_req_valid ? wb_bus_req_wdata : load_bus_req_wdata;

  always_comb begin
    current_k_base = k_base + (block_index * K_TILE);
  end

  fp32_tile_kblock_fsm #(.BLOCKS(K_BLOCKS)) u_ctrl (
    .clk(clk), .rst_n(rst_n), .start(start),
    .block_count_cfg(k_block_count), .load_done(load_done),
    .stream_done(stream_done), .compute_done(compute_done),
    .writeback_done(writeback_done), .error_in(error_in),
    .load_start(load_start), .stream_start(stream_start),
    .compute_start(compute_start), .writeback_start(writeback_start),
    .task_first(task_first), .task_last(task_last), .busy(ctrl_busy),
    .done(done), .error(error), .block_index(block_index), .state(state)
  );

  fp32_tile_dma_load_engine #(
    .ROW_TILE(ROW_TILE), .COL_TILE(COL_TILE), .K_TILE(K_TILE),
    .ADDR_WIDTH(ADDR_WIDTH), .CACHE_ADDR_WIDTH(CACHE_ADDR_WIDTH)
  ) u_load (
    .clk(clk), .rst_n(rst_n), .start(load_start),
    .matrix_m(matrix_m), .matrix_k(matrix_k), .matrix_n(matrix_n),
    .row_base(row_base), .col_base(col_base), .k_base(current_k_base),
    .rows_valid(rows_valid), .cols_valid(cols_valid),
    .k_valid(k_valid_block), .a_base_word(a_base_word),
    .b_base_word(b_base_word), .bias_base_word(bias_base_word),
    .result_base_word(result_base_word),
    .bus_req_valid(load_bus_req_valid), .bus_req_write(load_bus_req_write),
    .bus_req_addr(load_bus_req_addr), .bus_req_wdata(load_bus_req_wdata),
    .bus_req_ready(bus_req_ready), .bus_rsp_valid(bus_rsp_valid),
    .bus_rsp_rdata(bus_rsp_rdata), .a_wr_en(a_wr_en), .a_wr_addr(a_wr_addr),
    .a_wr_data(a_wr_data), .b_wr_en(b_wr_en), .b_wr_addr(b_wr_addr),
    .b_wr_data(b_wr_data), .result_wr_en(result_wr_en),
    .result_wr_addr(result_wr_addr), .result_wr_data(result_wr_data),
    .busy(load_busy), .load_done(load_done)
  );

  matrix_cache_manager #(
    .DATA_WIDTH(16), .ADDR_WIDTH(CACHE_ADDR_WIDTH),
    .DEPTH(1 << CACHE_ADDR_WIDTH)
  ) u_cache (
    .clk(clk), .rst_n(rst_n),
    .a_wr_en(a_wr_en), .a_wr_addr(a_wr_addr), .a_wr_data(a_wr_data),
    .b_wr_en(b_wr_en), .b_wr_addr(b_wr_addr), .b_wr_data(b_wr_data),
    .result_wr_en(result_wr_en), .result_wr_addr(result_wr_addr),
    .result_wr_data(result_wr_data), .a_rd_en(a_rd_en), .a_rd_addr(a_rd_addr),
    .a_rd_data(a_rd_data), .a_rd_valid(a_rd_valid), .b_rd_en(b_rd_en),
    .b_rd_addr(b_rd_addr), .b_rd_data(b_rd_data), .b_rd_valid(b_rd_valid),
    .result_rd_en(result_rd_en), .result_rd_addr(result_rd_addr),
    .result_rd_data(result_rd_data), .result_rd_valid(result_rd_valid)
  );

  fp32_tile_cache_streamer #(
    .ROWS(ROW_TILE), .COLS(COL_TILE), .K(K_TILE),
    .ADDR_WIDTH(CACHE_ADDR_WIDTH)
  ) u_streamer (
    .clk(clk), .rst_n(rst_n), .start(stream_start),
    .task_first_cfg(task_first), .task_last_cfg(task_last),
    .a_rd_en(a_rd_en), .a_rd_addr(a_rd_addr), .a_rd_data(a_rd_data),
    .a_rd_valid(a_rd_valid), .b_rd_en(b_rd_en), .b_rd_addr(b_rd_addr),
    .b_rd_data(b_rd_data), .b_rd_valid(b_rd_valid),
    .result_rd_en(result_rd_en), .result_rd_addr(result_rd_addr),
    .result_rd_data(result_rd_data), .result_rd_valid(result_rd_valid),
    .busy(stream_busy), .done(stream_done), .stream_valid(stream_valid),
    .task_first(stream_task_first), .task_last(stream_task_last),
    .a_left(a_left), .b_top(b_top),
    .bias_in(bias_in)
  );

  fp32_tile_engine #(.ROWS(ROW_TILE), .COLS(COL_TILE), .K(K_TILE)) u_compute (
    .clk(clk), .rst_n(rst_n), .start(compute_start),
    .stream_valid(stream_valid), .task_first(stream_task_first),
    .task_last(stream_task_last), .a_left(a_left), .b_top(b_top),
    .bias_in(bias_in), .valid_rows(rows_valid), .valid_cols(cols_valid),
    .busy(compute_busy), .done(compute_done), .result_valid(result_valid),
    .result_last(result_last), .result_data(result_data),
    .result_row(result_row), .result_col(result_col)
  );

  fp32_tile_dma_writeback_engine #(
    .ROW_TILE(ROW_TILE), .COL_TILE(COL_TILE), .K_TILE(K_TILE),
    .ADDR_WIDTH(ADDR_WIDTH), .CACHE_ADDR_WIDTH(CACHE_ADDR_WIDTH)
  ) u_writeback (
    .clk(clk), .rst_n(rst_n), .start(writeback_start),
    .matrix_m(matrix_m), .matrix_k(matrix_k), .matrix_n(matrix_n),
    .row_base(row_base), .col_base(col_base), .rows_valid(rows_valid),
    .cols_valid(cols_valid), .result_base_word(result_base_word),
    .result_rd_en(wb_result_rd_en), .result_rd_addr(wb_result_rd_addr),
    .result_rd_data(wb_result_rd_data), .result_rd_valid(wb_result_rd_valid),
    .bus_req_valid(wb_bus_req_valid), .bus_req_write(wb_bus_req_write),
    .bus_req_addr(wb_bus_req_addr), .bus_req_wdata(wb_bus_req_wdata),
    .bus_req_ready(bus_req_ready), .busy(writeback_busy),
    .done(writeback_done)
  );

  always_comb begin
    stage_elem = wb_stage_pending_addr >> 1;
    stage_row = stage_elem / COL_TILE;
    stage_col = stage_elem % COL_TILE;
    wb_stage_read_data = 16'd0;
    if (stage_row < ROW_TILE && stage_col < COL_TILE) begin
      if (wb_stage_pending_addr[0])
        wb_stage_read_data = result_stage[stage_row][stage_col][31:16];
      else
        wb_stage_read_data = result_stage[stage_row][stage_col][15:0];
    end
  end

  assign wb_result_rd_data = wb_stage_read_data;
  assign wb_result_rd_valid = wb_stage_pending;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wb_stage_pending <= 1'b0;
      wb_stage_pending_addr <= '0;
      for (sr = 0; sr < ROW_TILE; sr = sr + 1)
        for (sc = 0; sc < COL_TILE; sc = sc + 1)
          result_stage[sr][sc] <= '0;
    end else begin
      wb_stage_pending <= wb_result_rd_en;
      if (wb_result_rd_en)
        wb_stage_pending_addr <= wb_result_rd_addr;
      if (result_valid && result_row < ROW_TILE && result_col < COL_TILE)
        result_stage[result_row][result_col] <= result_data;
    end
  end
endmodule
