// Matrix-level tile controller for the two undergraduate GEMM shapes.
// It emits one block_start pulse, holds the corresponding coordinates while
// the tile engine runs, and advances in K -> column -> row order only after
// block_done.  Data movement is deliberately outside this module.
module fp32_matrix_block_controller #(
  parameter int ROW_TILE = 8,
  parameter int COL_TILE = 16,
  parameter int K_TILE = 32
) (
  input logic clk,
  input logic rst_n,
  input logic start,
  input logic block_done,
  input logic [15:0] matrix_m,
  input logic [15:0] matrix_k,
  input logic [15:0] matrix_n,
  output logic block_start,
  output logic busy,
  output logic done,
  output logic [31:0] block_index,
  output logic [15:0] row_base,
  output logic [15:0] col_base,
  output logic [15:0] k_base,
  output logic [15:0] rows_valid,
  output logic [15:0] cols_valid,
  output logic [15:0] k_valid,
  output logic k_first,
  output logic k_last
);
  typedef enum logic [1:0] {S_IDLE, S_ISSUE, S_WAIT} state_t;
  state_t state;
  logic [15:0] m_q, k_q, n_q;

  function automatic [15:0] min16(input [15:0] left, input integer right);
    min16 = (left < right) ? left : 16'(right);
  endfunction

  always_comb begin
    rows_valid = (m_q > row_base) ? min16(m_q-row_base, ROW_TILE) : 16'd0;
    cols_valid = (n_q > col_base) ? min16(n_q-col_base, COL_TILE) : 16'd0;
    k_valid = (k_q > k_base) ? min16(k_q-k_base, K_TILE) : 16'd0;
    k_first = (k_base == 0);
    k_last = (k_valid != 0) && (k_base + k_valid >= k_q);
  end

  initial begin
    if (ROW_TILE <= 0 || COL_TILE <= 0 || K_TILE <= 0)
      $fatal(1, "invalid FP32 matrix tile dimensions");
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= S_IDLE;
      block_start <= 1'b0;
      busy <= 1'b0;
      done <= 1'b0;
      block_index <= 32'd0;
      m_q <= 16'd0;
      k_q <= 16'd0;
      n_q <= 16'd0;
      row_base <= 16'd0;
      col_base <= 16'd0;
      k_base <= 16'd0;
    end else begin
      done <= 1'b0;
      case (state)
        S_IDLE: begin
          block_start <= 1'b0;
          if (start) begin
            m_q <= matrix_m;
            k_q <= matrix_k;
            n_q <= matrix_n;
            row_base <= 16'd0;
            col_base <= 16'd0;
            k_base <= 16'd0;
            block_index <= 32'd0;
            busy <= (matrix_m != 0 && matrix_k != 0 && matrix_n != 0);
            if (matrix_m != 0 && matrix_k != 0 && matrix_n != 0) begin
              state <= S_ISSUE;
              block_start <= 1'b1;
            end else begin
              state <= S_IDLE;
              done <= 1'b1;
            end
          end
        end
        S_ISSUE: begin
          // block_start is a one-cycle launch pulse.  Holding it through
          // S_WAIT would make a downstream tile engine accept the same
          // descriptor more than once while it is still starting.
          block_start <= 1'b0;
          state <= S_WAIT;
        end
        S_WAIT: begin
          block_start <= 1'b0;
          if (block_done) begin
            if (k_base + k_valid < k_q) begin
              k_base <= k_base + K_TILE;
            end else if (col_base + cols_valid < n_q) begin
              k_base <= 16'd0;
              col_base <= col_base + COL_TILE;
            end else if (row_base + rows_valid < m_q) begin
              k_base <= 16'd0;
              col_base <= 16'd0;
              row_base <= row_base + ROW_TILE;
            end else begin
              busy <= 1'b0;
              done <= 1'b1;
              state <= S_IDLE;
            end

            if (row_base + rows_valid < m_q ||
                col_base + cols_valid < n_q ||
                k_base + k_valid < k_q) begin
              block_index <= block_index + 1'b1;
              state <= S_ISSUE;
              block_start <= 1'b1;
            end
          end
        end
        default: state <= S_IDLE;
      endcase
    end
  end
endmodule
