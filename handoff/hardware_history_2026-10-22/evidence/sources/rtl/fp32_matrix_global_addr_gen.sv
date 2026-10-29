// Global row-major FP32 address generator for one matrix tile.
// Addresses are 16-bit SRAM word addresses; each FP32 occupies low half then
// high half.  Base addresses are also expressed in 16-bit words.
module fp32_matrix_global_addr_gen #(
  parameter int ROW_TILE = 8,
  parameter int COL_TILE = 16,
  parameter int K_TILE = 32,
  parameter int ADDR_WIDTH = 32
) (
  input logic [15:0] matrix_m,
  input logic [15:0] matrix_k,
  input logic [15:0] matrix_n,
  input logic [15:0] row_base,
  input logic [15:0] col_base,
  input logic [15:0] k_base,
  input logic [15:0] local_row,
  input logic [15:0] local_col,
  input logic [15:0] local_k,
  input logic word_high,
  input logic [ADDR_WIDTH-1:0] a_base_word,
  input logic [ADDR_WIDTH-1:0] b_base_word,
  input logic [ADDR_WIDTH-1:0] bias_base_word,
  input logic [ADDR_WIDTH-1:0] result_base_word,
  output logic a_valid,
  output logic b_valid,
  output logic bias_valid,
  output logic result_valid,
  output logic [ADDR_WIDTH-1:0] a_word_addr,
  output logic [ADDR_WIDTH-1:0] b_word_addr,
  output logic [ADDR_WIDTH-1:0] bias_word_addr,
  output logic [ADDR_WIDTH-1:0] result_word_addr
);
  logic [31:0] global_row, global_col, global_k;
  logic [63:0] a_calc, b_calc, bias_calc, result_calc;
  logic [63:0] half_word;

  initial begin
    if (ROW_TILE <= 0 || COL_TILE <= 0 || K_TILE <= 0 || ADDR_WIDTH <= 0)
      $fatal(1, "invalid FP32 global address generator parameters");
  end

  always_comb begin
    global_row = row_base + local_row;
    global_col = col_base + local_col;
    global_k = k_base + local_k;
    half_word = word_high ? 64'd1 : 64'd0;

    a_valid = (local_row < ROW_TILE) && (local_k < K_TILE) &&
              (global_row < matrix_m) && (global_k < matrix_k);
    b_valid = (local_k < K_TILE) && (local_col < COL_TILE) &&
              (global_k < matrix_k) && (global_col < matrix_n);
    bias_valid = (local_col < COL_TILE) && (global_col < matrix_n);
    result_valid = (local_row < ROW_TILE) && (local_col < COL_TILE) &&
                   (global_row < matrix_m) && (global_col < matrix_n);

    a_calc = {32'd0, a_base_word} +
             ((((64'(global_row) * matrix_k) + global_k) * 2) + half_word);
    b_calc = {32'd0, b_base_word} +
             ((((64'(global_k) * matrix_n) + global_col) * 2) + half_word);
    bias_calc = {32'd0, bias_base_word} + ((64'(global_col) * 2) + half_word);
    result_calc = {32'd0, result_base_word} +
                  ((((64'(global_row) * matrix_n) + global_col) * 2) + half_word);

    a_word_addr = ADDR_WIDTH'(a_calc);
    b_word_addr = ADDR_WIDTH'(b_calc);
    bias_word_addr = ADDR_WIDTH'(bias_calc);
    result_word_addr = ADDR_WIDTH'(result_calc);
  end
endmodule
