// Snapshot one array completion and emit one result per cycle. Downstream must
// accept every valid beat: backpressure is not part of this interface yet.
module tile_result_collector #(
  parameter int DATA_WIDTH = 32,
  parameter int ROWS = 8,
  parameter int COLS = 16
) (
  input logic clk, input logic rst_n, input logic start,
  input logic pe_result_valid,
  input logic [DATA_WIDTH-1:0] pe_result [ROWS][COLS],
  input logic [15:0] valid_rows, input logic [15:0] valid_cols,
  output logic result_valid, output logic result_last,
  output logic [DATA_WIDTH-1:0] result_data,
  output logic [15:0] result_row, output logic [15:0] result_col,
  output logic busy, output logic done
);
  integer row_idx, col_idx, r, c;
  logic [15:0] rows_q, cols_q;
  logic draining;
  logic [DATA_WIDTH-1:0] snapshot [ROWS][COLS];
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      row_idx<=0; col_idx<=0; result_valid<=0; result_last<=0;
      result_data<='0; result_row<=0; result_col<=0; busy<=0; done<=0;
      rows_q<=0; cols_q<=0; draining<=0;
      for(r=0;r<ROWS;r=r+1) for(c=0;c<COLS;c=c+1) snapshot[r][c]<='0;
    end else begin
      result_valid<=0; result_last<=0; done<=0;
      if (start && !busy) begin
        row_idx<=0; col_idx<=0; rows_q<=valid_rows; cols_q<=valid_cols; draining<=0;
        if(valid_rows==0 || valid_cols==0 || valid_rows>ROWS || valid_cols>COLS) begin
          busy<=0; done<=1;
        end else busy<=1;
      end else if (busy && !draining && pe_result_valid) begin
        for(r=0;r<ROWS;r=r+1) for(c=0;c<COLS;c=c+1) snapshot[r][c]<=pe_result[r][c];
        draining<=1;
      end else if (busy && draining) begin
        result_valid<=1; result_data<=snapshot[row_idx][col_idx];
        result_row<=16'(row_idx); result_col<=16'(col_idx);
        if (row_idx == rows_q-1 && col_idx == cols_q-1) begin
          result_last<=1; busy<=0; draining<=0; done<=1;
        end else if (col_idx == cols_q-1) begin
          col_idx<=0; row_idx<=row_idx+1;
        end else col_idx<=col_idx+1;
      end
    end
  end
endmodule
