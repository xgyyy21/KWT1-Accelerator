// M/N/K tile scheduler shared by DMA and the systolic tile engine.
module matrix_task_scheduler #(
  parameter int ROW_TILE = 8,
  parameter int COL_TILE = 16,
  parameter int K_TILE = 64
) (
  input logic clk,
  input logic rst_n,
  input logic start,
  input logic advance,
  input logic [15:0] matrix_m,
  input logic [15:0] matrix_k,
  input logic [15:0] matrix_n,
  output logic busy,
  output logic done,
  output logic [15:0] row_base,
  output logic [15:0] col_base,
  output logic [15:0] k_base,
  output logic [15:0] rows_valid,
  output logic [15:0] cols_valid,
  output logic [15:0] k_valid,
  output logic k_first,
  output logic k_last
);
  logic [15:0] rb, cb, kb;
  logic [15:0] m_q, k_q, n_q;
  initial begin
    if(ROW_TILE<=0 || COL_TILE<=0 || K_TILE<=0 || ROW_TILE>65535 || COL_TILE>65535 || K_TILE>65535)
      $fatal(1,"invalid scheduler tile dimensions");
  end
  function automatic [15:0] min16(input [15:0] left, input integer right);
    min16 = (left < right) ? left : 16'(right);
  endfunction

  always_comb begin
    row_base = rb; col_base = cb; k_base = kb;
    rows_valid = (m_q > rb) ? min16(m_q-rb, ROW_TILE) : 0;
    cols_valid = (n_q > cb) ? min16(n_q-cb, COL_TILE) : 0;
    k_valid = (k_q > kb) ? min16(k_q-kb, K_TILE) : 0;
    k_first = (kb == 0);
    k_last = (k_q == 0) || (kb + K_TILE >= k_q);
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rb <= 0; cb <= 0; kb <= 0; busy <= 0; done <= 0; m_q<=0; k_q<=0; n_q<=0;
    end else begin
      done <= 0;
      if (start && !busy) begin
        rb <= 0; cb <= 0; kb <= 0;
        m_q<=matrix_m; k_q<=matrix_k; n_q<=matrix_n;
        busy <= (matrix_m!=0 && matrix_k!=0 && matrix_n!=0);
        done <= (matrix_m==0 || matrix_k==0 || matrix_n==0);
      end else if (busy && advance) begin
        if (kb + K_TILE < k_q)
          kb <= kb + K_TILE;
        else if (cb + COL_TILE < n_q) begin
          kb <= 0; cb <= cb + COL_TILE;
        end else if (rb + ROW_TILE < m_q) begin
          kb <= 0; cb <= 0; rb <= rb + ROW_TILE;
        end else begin
          busy <= 0; done <= 1;
        end
      end
    end
  end
endmodule
