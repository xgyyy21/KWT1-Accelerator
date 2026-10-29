// Local 16-bit SRAM layout for one FP32 tile.
//
// A tile is [ROW_TILE][K_TILE], B tile is [K_TILE][COL_TILE], bias is one
// vector of COL_TILE values, and result is [ROW_TILE][COL_TILE].  Each FP32
// value occupies two consecutive 16-bit words: low word first, high word
// second.  K_TILE=32 makes the B tile fit exactly in 1024 words for the
// teacher's 16-bit x 1024 cache.
module fp32_tile_cache_mapper #(
  parameter int ROW_TILE = 8,
  parameter int COL_TILE = 16,
  parameter int K_TILE = 32,
  parameter int ADDR_WIDTH = 10
) (
  input logic [15:0] local_row,
  input logic [15:0] local_col,
  input logic [15:0] local_k,
  input logic word_high,
  output logic a_valid,
  output logic b_valid,
  output logic bias_valid,
  output logic result_valid,
  output logic [ADDR_WIDTH-1:0] a_word_addr,
  output logic [ADDR_WIDTH-1:0] b_word_addr,
  output logic [ADDR_WIDTH-1:0] bias_word_addr,
  output logic [ADDR_WIDTH-1:0] result_word_addr
);
  integer a_index, b_index, bias_index, result_index;

  initial begin
    if (ROW_TILE <= 0 || COL_TILE <= 0 || K_TILE <= 0 ||
        ((ROW_TILE*K_TILE*2) > (1 << ADDR_WIDTH)) ||
        ((K_TILE*COL_TILE*2) > (1 << ADDR_WIDTH)))
      $fatal(1, "FP32 tile does not fit the configured 16-bit cache");
  end

  always_comb begin
    a_valid = (local_row < ROW_TILE) && (local_k < K_TILE);
    b_valid = (local_k < K_TILE) && (local_col < COL_TILE);
    bias_valid = (local_col < COL_TILE);
    result_valid = (local_row < ROW_TILE) && (local_col < COL_TILE);

    a_index = ((local_row * K_TILE) + local_k) * 2;
    b_index = ((local_k * COL_TILE) + local_col) * 2;
    bias_index = local_col * 2;
    result_index = ((local_row * COL_TILE) + local_col) * 2;

    a_word_addr = ADDR_WIDTH'(a_index + (word_high ? 1 : 0));
    b_word_addr = ADDR_WIDTH'(b_index + (word_high ? 1 : 0));
    bias_word_addr = ADDR_WIDTH'(bias_index + (word_high ? 1 : 0));
    result_word_addr = ADDR_WIDTH'(result_index + (word_high ? 1 : 0));
  end
endmodule
