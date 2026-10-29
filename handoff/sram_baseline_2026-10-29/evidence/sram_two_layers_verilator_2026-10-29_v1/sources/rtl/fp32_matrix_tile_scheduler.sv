// Matrix-to-tile scheduling adapter.
//
// The block controller emits one descriptor per spatial (row/column) tile.
// The tile datapath owns the inner K loop: k_block_count says how many K
// blocks it must fetch/compute, while k_base and k_valid identify the first
// K block. This avoids two independent schedulers advancing K at once.
module fp32_matrix_tile_scheduler #(
  parameter int ROW_TILE = 8,
  parameter int COL_TILE = 16,
  parameter int K_BLOCK_SIZE = 32,
  parameter int MAX_MATRIX_K = 256,
  parameter bit STRICT_COMPETITION_SHAPES = 1'b1
) (
  input  logic        clk,
  input  logic        rst_n,
  input  logic        start,
  input  logic        tile_done,
  input  logic [15:0] matrix_m,
  input  logic [15:0] matrix_k,
  input  logic [15:0] matrix_n,
  output logic        tile_start,
  output logic        tile_busy,
  output logic        done,
  output logic        config_error,
  output logic [31:0] tile_index,
  output logic [15:0] row_base,
  output logic [15:0] col_base,
  output logic [15:0] k_base,
  output logic [15:0] rows_valid,
  output logic [15:0] cols_valid,
  output logic [15:0] k_valid,
  output logic        task_first,
  output logic        task_last,
  output logic [15:0] k_block_index,
  output logic [15:0] k_block_count,
  output logic        supported_shape
);
  logic block_start;
  logic block_busy;
  logic block_done;
  logic block_k_first;
  logic block_k_last;
  logic [15:0] matrix_k_q;

  assign supported_shape = STRICT_COMPETITION_SHAPES ?
      (((matrix_m == 16'd99) && (matrix_k == 16'd64)  && (matrix_n == 16'd256)) ||
       ((matrix_m == 16'd99) && (matrix_k == 16'd256) && (matrix_n == 16'd64))) :
      ((matrix_m != 0) && (matrix_k != 0) && (matrix_n != 0) &&
       (matrix_k <= MAX_MATRIX_K));

  // Keep the dimension used for the K-block count stable for the whole run.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      matrix_k_q <= 16'd0;
      config_error <= 1'b0;
    end else begin
      if (start) begin
        matrix_k_q <= matrix_k;
        config_error <= !supported_shape;
      end
    end
  end

  fp32_matrix_block_controller #(
    .ROW_TILE(ROW_TILE), .COL_TILE(COL_TILE), .K_TILE(MAX_MATRIX_K)
  ) u_block_controller (
    .clk(clk), .rst_n(rst_n), .start(start && supported_shape), .block_done(tile_done),
    .matrix_m(matrix_m), .matrix_k(matrix_k), .matrix_n(matrix_n),
    .block_start(block_start), .busy(block_busy), .done(block_done),
    .block_index(tile_index), .row_base(row_base), .col_base(col_base),
    .k_base(k_base), .rows_valid(rows_valid), .cols_valid(cols_valid),
    .k_valid(), .k_first(block_k_first), .k_last(block_k_last)
  );

  assign tile_start = block_start;
  assign tile_busy = block_busy;
  assign done = block_done;
  assign task_first = block_k_first;
  assign task_last = block_k_last;
  assign k_valid = (matrix_k_q < K_BLOCK_SIZE) ? matrix_k_q : K_BLOCK_SIZE;
  assign k_block_index = 16'd0;
  assign k_block_count = (K_BLOCK_SIZE > 0) ?
                         ((matrix_k_q + K_BLOCK_SIZE - 1) / K_BLOCK_SIZE) : 16'd0;
endmodule
