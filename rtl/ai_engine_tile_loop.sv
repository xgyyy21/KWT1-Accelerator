// Provisional integer tile loop used to close the cache/stream/array/writeback
// path before the final FP32 memory contract is frozen.
// A and B are preloaded through the cache write ports. The loop then reads one
// cache word per cycle, assembles a tile in local registers, streams K beats to
// the systolic array, and writes the collected result tile to result cache.
module ai_engine_tile_loop #(
  parameter int DATA_WIDTH = 16,
  parameter int ACC_WIDTH = DATA_WIDTH,
  parameter int ROWS = 8,
  parameter int COLS = 16,
  parameter int K = 64,
  parameter int CACHE_ADDR_WIDTH = 10
) (
  input logic clk,
  input logic rst_n,
  input logic start,
  input logic [15:0] valid_rows,
  input logic [15:0] valid_cols,
  input logic a_load_en,
  input logic [CACHE_ADDR_WIDTH-1:0] a_load_addr,
  input logic [DATA_WIDTH-1:0] a_load_data,
  input logic b_load_en,
  input logic [CACHE_ADDR_WIDTH-1:0] b_load_addr,
  input logic [DATA_WIDTH-1:0] b_load_data,
  input logic result_rd_en,
  input logic [CACHE_ADDR_WIDTH-1:0] result_rd_addr,
  output logic [DATA_WIDTH-1:0] result_rd_data,
  output logic result_rd_valid,
  output logic busy,
  output logic done,
  output logic error
);
  localparam int A_WORDS = ROWS * K;
  localparam int B_WORDS = K * COLS;
  localparam int RESULT_WORDS = ROWS * COLS;

  typedef enum logic [3:0] {
    S_IDLE, S_LOAD_A, S_LOAD_B, S_START_COMPUTE,
    S_COMPUTE, S_WAIT_RESULT, S_DONE, S_ERROR
  } state_t;

  state_t state;
  integer a_issue, a_capture, b_issue, b_capture;
  integer k_index;
  logic [DATA_WIDTH-1:0] a_tile [K][ROWS];
  logic [DATA_WIDTH-1:0] b_tile [K][COLS];

  logic a_rd_en, b_rd_en;
  logic [CACHE_ADDR_WIDTH-1:0] a_rd_addr, b_rd_addr;
  logic [DATA_WIDTH-1:0] a_rd_data, b_rd_data;
  logic a_rd_valid, b_rd_valid;
  logic result_wr_en;
  logic [CACHE_ADDR_WIDTH-1:0] result_wr_addr;
  logic [DATA_WIDTH-1:0] result_wr_data;

  logic tile_start, tile_in_valid, tile_done;
  logic tile_result_valid, tile_result_last;
  logic [ACC_WIDTH-1:0] tile_result_data;
  logic [15:0] tile_result_row, tile_result_col;
  logic [DATA_WIDTH-1:0] a_left [ROWS];
  logic [DATA_WIDTH-1:0] b_top [COLS];
  logic [15:0] rows_q, cols_q;
  logic tile_config_valid;

  initial begin
    if (DATA_WIDTH <= 0 || ACC_WIDTH != DATA_WIDTH || ROWS <= 0 ||
        COLS <= 0 || K <= 0 || A_WORDS > (1 << CACHE_ADDR_WIDTH) ||
        B_WORDS > (1 << CACHE_ADDR_WIDTH) ||
        RESULT_WORDS > (1 << CACHE_ADDR_WIDTH))
      $fatal(1, "invalid tile loop parameters");
  end

  matrix_cache_manager #(
    .DATA_WIDTH(DATA_WIDTH), .ADDR_WIDTH(CACHE_ADDR_WIDTH),
    .DEPTH(1 << CACHE_ADDR_WIDTH)
  ) u_cache (
    .clk(clk), .rst_n(rst_n),
    .a_wr_en(a_load_en), .a_wr_addr(a_load_addr), .a_wr_data(a_load_data),
    .b_wr_en(b_load_en), .b_wr_addr(b_load_addr), .b_wr_data(b_load_data),
    .result_wr_en(result_wr_en), .result_wr_addr(result_wr_addr),
    .result_wr_data(result_wr_data),
    .a_rd_en(a_rd_en), .a_rd_addr(a_rd_addr), .a_rd_data(a_rd_data),
    .a_rd_valid(a_rd_valid), .b_rd_en(b_rd_en), .b_rd_addr(b_rd_addr),
    .b_rd_data(b_rd_data), .b_rd_valid(b_rd_valid),
    .result_rd_en(result_rd_en), .result_rd_addr(result_rd_addr),
    .result_rd_data(result_rd_data), .result_rd_valid(result_rd_valid)
  );

  assign a_rd_en = (state == S_LOAD_A) && (a_issue < A_WORDS);
  assign b_rd_en = (state == S_LOAD_B) && (b_issue < B_WORDS);
  assign a_rd_addr = CACHE_ADDR_WIDTH'(a_issue);
  assign b_rd_addr = CACHE_ADDR_WIDTH'(b_issue);

  assign tile_start = (state == S_START_COMPUTE);
  assign tile_in_valid = (state == S_COMPUTE) && (k_index < K);
  assign result_wr_en = tile_result_valid;
  assign result_wr_addr = CACHE_ADDR_WIDTH'(tile_result_row * COLS + tile_result_col);
  assign result_wr_data = tile_result_data;

  assign tile_config_valid = valid_rows > 0 && valid_rows <= ROWS &&
                             valid_cols > 0 && valid_cols <= COLS;

  assign busy = (state != S_IDLE) && (state != S_DONE) && (state != S_ERROR);
  assign done = (state == S_DONE);
  assign error = (state == S_ERROR);

  genvar gr, gc;
  generate
    for (gr = 0; gr < ROWS; gr = gr + 1) begin : GEN_A
      always_comb a_left[gr] = a_tile[k_index < K ? k_index : 0][gr];
    end
    for (gc = 0; gc < COLS; gc = gc + 1) begin : GEN_B
      always_comb b_top[gc] = b_tile[k_index < K ? k_index : 0][gc];
    end
  endgenerate

  systolic_tile_engine #(
    .DATA_WIDTH(DATA_WIDTH), .ACC_WIDTH(ACC_WIDTH),
    .ROWS(ROWS), .COLS(COLS), .K(K)
  ) u_tile (
    .clk(clk), .rst_n(rst_n), .start(tile_start),
    .in_valid(tile_in_valid), .a_left(a_left), .b_top(b_top),
    .valid_rows(rows_q), .valid_cols(cols_q), .busy(), .done(tile_done),
    .result_valid(tile_result_valid), .result_last(tile_result_last),
    .result_data(tile_result_data), .result_row(tile_result_row),
    .result_col(tile_result_col)
  );

  integer r, c;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= S_IDLE;
      a_issue <= 0; a_capture <= 0; b_issue <= 0; b_capture <= 0;
      k_index <= 0;
      rows_q <= 0; cols_q <= 0;
      for (r = 0; r < K; r = r + 1)
        for (c = 0; c < ROWS; c = c + 1) a_tile[r][c] <= '0;
      for (r = 0; r < K; r = r + 1)
        for (c = 0; c < COLS; c = c + 1) b_tile[r][c] <= '0;
    end else begin
      case (state)
        S_IDLE: begin
          if (start) begin
            if (tile_config_valid) begin
              state <= S_LOAD_A;
              a_issue <= 0; a_capture <= 0;
              rows_q <= valid_rows; cols_q <= valid_cols;
            end else state <= S_ERROR;
          end
        end
        S_LOAD_A: begin
          if (a_rd_en) a_issue <= a_issue + 1;
          if (a_rd_valid) begin
            // A cache is row-major: row*K + k. The array consumes A[k][row].
            a_tile[a_capture % K][a_capture / K] <= a_rd_data;
            if (a_capture == A_WORDS - 1) begin
              state <= S_LOAD_B;
              b_issue <= 0; b_capture <= 0;
            end else a_capture <= a_capture + 1;
          end
        end
        S_LOAD_B: begin
          if (b_rd_en) b_issue <= b_issue + 1;
          if (b_rd_valid) begin
            b_tile[b_capture / COLS][b_capture % COLS] <= b_rd_data;
            if (b_capture == B_WORDS - 1) begin
              state <= S_START_COMPUTE;
              k_index <= 0;
            end else b_capture <= b_capture + 1;
          end
        end
        S_START_COMPUTE: state <= S_COMPUTE;
        S_COMPUTE: begin
          if (k_index == K - 1) state <= S_WAIT_RESULT;
          else k_index <= k_index + 1;
        end
        S_WAIT_RESULT: if (tile_done) state <= S_DONE;
        S_DONE: begin
          if (start) begin
            if (tile_config_valid) begin
              state <= S_LOAD_A;
              a_issue <= 0; a_capture <= 0;
              rows_q <= valid_rows; cols_q <= valid_cols;
            end else state <= S_ERROR;
          end else state <= S_IDLE;
        end
        S_ERROR: if (start && tile_config_valid) begin
          state <= S_LOAD_A;
          a_issue <= 0; a_capture <= 0;
          rows_q <= valid_rows; cols_q <= valid_cols;
        end
        default: state <= S_ERROR;
      endcase
    end
  end
endmodule
