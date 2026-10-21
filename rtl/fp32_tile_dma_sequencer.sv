// Tile DMA request sequencer.
//
// This module emits one 16-bit transfer request at a time.  It freezes the
// ordering and address contract for a tile but deliberately leaves the actual
// external bus data channel to the platform wrapper:
//   LOAD_A -> LOAD_B -> LOAD_BIAS -> WRITE_RESULT.
// For load phases, req_addr is an external source address and the cache_*
// outputs identify the local SRAM write destination.  For WRITE_RESULT,
// req_addr is the external destination and cache_* identify the local result
// SRAM read source.  A request advances only when req_ready is asserted.
module fp32_tile_dma_sequencer #(
  parameter int ROW_TILE = 8,
  parameter int COL_TILE = 16,
  parameter int K_TILE = 32,
  parameter int ADDR_WIDTH = 32,
  parameter int CACHE_ADDR_WIDTH = 10,
  parameter bit ENABLE_RESULT_WRITE = 1'b1
) (
  input logic clk,
  input logic rst_n,
  input logic start,
  input logic [15:0] matrix_m,
  input logic [15:0] matrix_k,
  input logic [15:0] matrix_n,
  input logic [15:0] row_base,
  input logic [15:0] col_base,
  input logic [15:0] k_base,
  input logic [15:0] rows_valid,
  input logic [15:0] cols_valid,
  input logic [15:0] k_valid,
  input logic [ADDR_WIDTH-1:0] a_base_word,
  input logic [ADDR_WIDTH-1:0] b_base_word,
  input logic [ADDR_WIDTH-1:0] bias_base_word,
  input logic [ADDR_WIDTH-1:0] result_base_word,
  input logic req_ready,
  output logic busy,
  output logic done,
  output logic req_valid,
  output logic req_write,
  output logic [ADDR_WIDTH-1:0] req_addr,
  output logic [1:0] cache_bank,
  output logic cache_write,
  output logic cache_read,
  output logic [CACHE_ADDR_WIDTH-1:0] cache_word_addr,
  output logic [15:0] local_row,
  output logic [15:0] local_col,
  output logic [15:0] local_k,
  output logic word_high,
  output logic [2:0] phase
);
  localparam logic [2:0] PH_IDLE = 3'd0;
  localparam logic [2:0] PH_A = 3'd1;
  localparam logic [2:0] PH_B = 3'd2;
  localparam logic [2:0] PH_BIAS = 3'd3;
  localparam logic [2:0] PH_RESULT = 3'd4;
  localparam logic [2:0] PH_DONE = 3'd5;

  logic [2:0] state;
  logic [15:0] m_q, k_q, n_q;
  logic [15:0] row_base_q, col_base_q, k_base_q;
  logic [15:0] rows_q, cols_q, kval_q;
  logic [ADDR_WIDTH-1:0] a_base_q, b_base_q, bias_base_q, result_base_q;
  logic [15:0] row_idx, col_idx, k_idx;
  logic half_idx;

  logic ga_valid, gb_valid, gbias_valid, gres_valid;
  logic [ADDR_WIDTH-1:0] ga_addr, gb_addr, gbias_addr, gres_addr;
  logic lm_valid_a, lm_valid_b, lm_valid_bias, lm_valid_result;
  logic [CACHE_ADDR_WIDTH-1:0] lm_addr_a, lm_addr_b, lm_addr_bias, lm_addr_result;

  fp32_matrix_global_addr_gen #(
    .ROW_TILE(ROW_TILE), .COL_TILE(COL_TILE), .K_TILE(K_TILE),
    .ADDR_WIDTH(ADDR_WIDTH)
  ) u_global_addr (
    .matrix_m(m_q), .matrix_k(k_q), .matrix_n(n_q),
    .row_base(row_base_q), .col_base(col_base_q), .k_base(k_base_q),
    .local_row(row_idx), .local_col(col_idx), .local_k(k_idx),
    .word_high(half_idx), .a_base_word(a_base_q),
    .b_base_word(b_base_q), .bias_base_word(bias_base_q),
    .result_base_word(result_base_q), .a_valid(ga_valid),
    .b_valid(gb_valid), .bias_valid(gbias_valid), .result_valid(gres_valid),
    .a_word_addr(ga_addr), .b_word_addr(gb_addr),
    .bias_word_addr(gbias_addr), .result_word_addr(gres_addr)
  );

  fp32_tile_cache_mapper #(
    .ROW_TILE(ROW_TILE), .COL_TILE(COL_TILE), .K_TILE(K_TILE),
    .ADDR_WIDTH(CACHE_ADDR_WIDTH)
  ) u_local_addr (
    .local_row(row_idx), .local_col(col_idx), .local_k(k_idx),
    .word_high(half_idx), .a_valid(lm_valid_a), .b_valid(lm_valid_b),
    .bias_valid(lm_valid_bias), .result_valid(lm_valid_result),
    .a_word_addr(lm_addr_a), .b_word_addr(lm_addr_b),
    .bias_word_addr(lm_addr_bias), .result_word_addr(lm_addr_result)
  );

  always_comb begin
    busy = (state != PH_IDLE) && (state != PH_DONE);
    done = (state == PH_DONE);
    req_valid = busy;
    req_write = (state == PH_RESULT);
    req_addr = '0;
    cache_bank = 2'd0;
    cache_write = 1'b0;
    cache_read = 1'b0;
    cache_word_addr = '0;
    local_row = row_idx;
    local_col = col_idx;
    local_k = k_idx;
    word_high = half_idx;
    phase = state;

    case (state)
      PH_A: begin
        req_addr = ga_addr;
        cache_bank = 2'd0;
        cache_write = 1'b1;
        cache_word_addr = lm_addr_a;
      end
      PH_B: begin
        req_addr = gb_addr;
        cache_bank = 2'd1;
        cache_write = 1'b1;
        cache_word_addr = lm_addr_b;
      end
      PH_BIAS: begin
        req_addr = gbias_addr;
        cache_bank = 2'd2;
        cache_write = 1'b1;
        cache_word_addr = lm_addr_bias;
      end
      PH_RESULT: begin
        req_addr = gres_addr;
        cache_bank = 2'd2;
        cache_read = 1'b1;
        cache_word_addr = lm_addr_result;
      end
      default: begin end
    endcase
  end

  task automatic advance_half_or_element;
    begin
      if (!half_idx) begin
        half_idx <= 1'b1;
      end else begin
        half_idx <= 1'b0;
        case (state)
          PH_A: begin
            if (k_idx + 1 < kval_q) k_idx <= k_idx + 1'b1;
            else begin
              k_idx <= 0;
              if (row_idx + 1 < rows_q) row_idx <= row_idx + 1'b1;
              else begin
                row_idx <= 0; col_idx <= 0; k_idx <= 0; state <= PH_B;
              end
            end
          end
          PH_B: begin
            if (col_idx + 1 < cols_q) col_idx <= col_idx + 1'b1;
            else begin
              col_idx <= 0;
              if (k_idx + 1 < kval_q) k_idx <= k_idx + 1'b1;
              else begin
                row_idx <= 0; col_idx <= 0; k_idx <= 0; state <= PH_BIAS;
              end
            end
          end
          PH_BIAS: begin
            if (col_idx + 1 < cols_q) col_idx <= col_idx + 1'b1;
            else begin
              row_idx <= 0; col_idx <= 0; k_idx <= 0;
              if (ENABLE_RESULT_WRITE)
                state <= PH_RESULT;
              else
                state <= PH_DONE;
            end
          end
          PH_RESULT: begin
            if (col_idx + 1 < cols_q) col_idx <= col_idx + 1'b1;
            else if (row_idx + 1 < rows_q) begin
              row_idx <= row_idx + 1'b1; col_idx <= 0;
            end else begin
              state <= PH_DONE;
            end
          end
          default: begin end
        endcase
      end
    end
  endtask

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= PH_IDLE;
      m_q <= 0; k_q <= 0; n_q <= 0;
      row_base_q <= 0; col_base_q <= 0; k_base_q <= 0;
      rows_q <= 0; cols_q <= 0; kval_q <= 0;
      a_base_q <= 0; b_base_q <= 0; bias_base_q <= 0; result_base_q <= 0;
      row_idx <= 0; col_idx <= 0; k_idx <= 0; half_idx <= 0;
    end else begin
      if (state == PH_IDLE && start) begin
        m_q <= matrix_m; k_q <= matrix_k; n_q <= matrix_n;
        row_base_q <= row_base; col_base_q <= col_base; k_base_q <= k_base;
        rows_q <= rows_valid; cols_q <= cols_valid; kval_q <= k_valid;
        a_base_q <= a_base_word; b_base_q <= b_base_word;
        bias_base_q <= bias_base_word; result_base_q <= result_base_word;
        row_idx <= 0; col_idx <= 0; k_idx <= 0; half_idx <= 0;
        if (rows_valid == 0 || cols_valid == 0 || k_valid == 0)
          state <= PH_DONE;
        else
          state <= PH_A;
      end else if (busy && req_ready) begin
        advance_half_or_element();
      end else if (state == PH_DONE) begin
        state <= PH_IDLE;
      end
    end
  end
endmodule
