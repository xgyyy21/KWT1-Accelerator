module block_counter #(
  parameter int M = 99,
  parameter int N = 256,
  parameter int K = 64,
  parameter int ROWS = 8,
  parameter int COLS = 16,
  parameter int K_TILE = 1
) (
  input logic clk,
  input logic rst_n,
  input logic start,
  input logic advance,
  output logic busy,
  output logic done,
  output logic [15:0] row_base,
  output logic [15:0] col_base,
  output logic [15:0] k_base,
  output logic [15:0] row_valid,
  output logic [15:0] col_valid,
  output logic [15:0] k_valid
);
  integer rb, cb, kb;
  initial begin
    if(ROWS<=0 || COLS<=0 || K_TILE<=0 || M<0 || N<0 || K<0 || M>65535 || N>65535 || K>65535)
      $fatal(1,"invalid block_counter parameters");
  end
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rb <= 0; cb <= 0; kb <= 0; busy <= 0; done <= 0;
    end else begin
      done <= 0;
      if (start && !busy) begin
        rb <= 0; cb <= 0; kb <= 0;
        busy <= (M>0 && N>0 && K>0); done <= (M<=0 || N<=0 || K<=0);
      end
      else if (busy && advance) begin
        if (kb + K_TILE < K) kb <= kb + K_TILE;
        else if (cb + COLS < N) begin cb <= cb + COLS; kb <= 0; end
        else if (rb + ROWS < M) begin rb <= rb + ROWS; cb <= 0; kb <= 0; end
        else begin busy <= 0; done <= 1; end
      end
    end
  end
  always_comb begin
    row_base = rb; col_base = cb; k_base = kb;
    row_valid = (M-rb > ROWS) ? ROWS : (M-rb);
    col_valid = (N-cb > COLS) ? COLS : (N-cb);
    k_valid = (K-kb > K_TILE) ? K_TILE : (K-kb);
  end
endmodule
