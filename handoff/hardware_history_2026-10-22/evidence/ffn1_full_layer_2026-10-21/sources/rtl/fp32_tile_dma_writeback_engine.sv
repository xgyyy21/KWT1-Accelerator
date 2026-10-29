// Result-tile readout and external 16-bit writeback engine.
// A synchronous local result SRAM is read one word at a time; after its
// one-cycle response, the word is held until the external write handshake.
module fp32_tile_dma_writeback_engine #(
  parameter int ROW_TILE = 8,
  parameter int COL_TILE = 16,
  parameter int K_TILE = 32,
  parameter int ADDR_WIDTH = 32,
  parameter int CACHE_ADDR_WIDTH = 10
) (
  input logic clk,
  input logic rst_n,
  input logic start,
  input logic [15:0] matrix_m,
  input logic [15:0] matrix_k,
  input logic [15:0] matrix_n,
  input logic [15:0] row_base,
  input logic [15:0] col_base,
  input logic [15:0] rows_valid,
  input logic [15:0] cols_valid,
  input logic [ADDR_WIDTH-1:0] result_base_word,
  output logic result_rd_en,
  output logic [CACHE_ADDR_WIDTH-1:0] result_rd_addr,
  input logic [15:0] result_rd_data,
  input logic result_rd_valid,
  output logic bus_req_valid,
  output logic bus_req_write,
  output logic [ADDR_WIDTH-1:0] bus_req_addr,
  output logic [15:0] bus_req_wdata,
  input logic bus_req_ready,
  output logic busy,
  output logic done
);
  localparam logic [2:0] S_IDLE = 3'd0;
  localparam logic [2:0] S_READ_REQ = 3'd1;
  localparam logic [2:0] S_READ_WAIT = 3'd2;
  localparam logic [2:0] S_WRITE = 3'd3;
  localparam logic [2:0] S_DONE = 3'd4;

  logic [2:0] state;
  logic [15:0] row_idx, col_idx;
  logic half_idx;
  logic [15:0] data_q;
  logic [15:0] m_q, k_q, n_q, row_base_q, col_base_q;
  logic [15:0] rows_q, cols_q;
  logic [ADDR_WIDTH-1:0] result_base_q;

  logic ga_valid, gb_valid, gbias_valid, gres_valid;
  logic [ADDR_WIDTH-1:0] ga_addr, gb_addr, gbias_addr, gres_addr;
  logic lm_valid_a, lm_valid_b, lm_valid_bias, lm_valid_result;
  logic [CACHE_ADDR_WIDTH-1:0] lm_addr_a, lm_addr_b, lm_addr_bias, lm_addr_result;

  fp32_matrix_global_addr_gen #(
    .ROW_TILE(ROW_TILE), .COL_TILE(COL_TILE), .K_TILE(K_TILE),
    .ADDR_WIDTH(ADDR_WIDTH)
  ) u_global_addr (
    .matrix_m(m_q), .matrix_k(k_q), .matrix_n(n_q),
    .row_base(row_base_q), .col_base(col_base_q), .k_base(16'd0),
    .local_row(row_idx), .local_col(col_idx), .local_k(16'd0),
    .word_high(half_idx), .a_base_word('0), .b_base_word('0),
    .bias_base_word('0), .result_base_word(result_base_q),
    .a_valid(ga_valid), .b_valid(gb_valid), .bias_valid(gbias_valid),
    .result_valid(gres_valid), .a_word_addr(ga_addr),
    .b_word_addr(gb_addr), .bias_word_addr(gbias_addr),
    .result_word_addr(gres_addr)
  );

  fp32_tile_cache_mapper #(
    .ROW_TILE(ROW_TILE), .COL_TILE(COL_TILE), .K_TILE(K_TILE),
    .ADDR_WIDTH(CACHE_ADDR_WIDTH)
  ) u_local_addr (
    .local_row(row_idx), .local_col(col_idx), .local_k(16'd0),
    .word_high(half_idx), .a_valid(lm_valid_a), .b_valid(lm_valid_b),
    .bias_valid(lm_valid_bias), .result_valid(lm_valid_result),
    .a_word_addr(lm_addr_a), .b_word_addr(lm_addr_b),
    .bias_word_addr(lm_addr_bias), .result_word_addr(lm_addr_result)
  );

  assign busy = (state != S_IDLE) && (state != S_DONE);
  assign done = (state == S_DONE);

  always_comb begin
    result_rd_en = (state == S_READ_REQ);
    result_rd_addr = lm_addr_result;
    bus_req_valid = (state == S_WRITE);
    bus_req_write = (state == S_WRITE);
    bus_req_addr = gres_addr;
    bus_req_wdata = data_q;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= S_IDLE;
      row_idx <= 0; col_idx <= 0; half_idx <= 0; data_q <= 0;
      m_q <= 0; k_q <= 0; n_q <= 0;
      row_base_q <= 0; col_base_q <= 0; rows_q <= 0; cols_q <= 0;
      result_base_q <= 0;
    end else begin
      case (state)
        S_IDLE: begin
          if (start) begin
            m_q <= matrix_m; k_q <= matrix_k; n_q <= matrix_n;
            row_base_q <= row_base; col_base_q <= col_base;
            rows_q <= rows_valid; cols_q <= cols_valid;
            result_base_q <= result_base_word;
            row_idx <= 0; col_idx <= 0; half_idx <= 0;
            if (rows_valid == 0 || cols_valid == 0)
              state <= S_DONE;
            else
              state <= S_READ_REQ;
          end
        end
        S_READ_REQ: state <= S_READ_WAIT;
        S_READ_WAIT: begin
          if (result_rd_valid) begin
            data_q <= result_rd_data;
            state <= S_WRITE;
          end
        end
        S_WRITE: begin
          if (bus_req_ready) begin
            if (!half_idx) begin
              half_idx <= 1'b1;
              state <= S_READ_REQ;
            end else begin
              half_idx <= 1'b0;
              if (col_idx + 1 < cols_q) begin
                col_idx <= col_idx + 1'b1;
                state <= S_READ_REQ;
              end else if (row_idx + 1 < rows_q) begin
                row_idx <= row_idx + 1'b1;
                col_idx <= 0;
                state <= S_READ_REQ;
              end else begin
                state <= S_DONE;
              end
            end
          end
        end
        S_DONE: state <= S_IDLE;
        default: state <= S_IDLE;
      endcase
    end
  end
endmodule
