// Aligns a tile's row/column streams for a 2-D systolic array.
// Row r receives A after r cycles; column c receives B after c cycles.
module systolic_input_skew #(
  parameter int DATA_WIDTH = 16,
  parameter int ROWS = 8,
  parameter int COLS = 16
) (
  input  logic clk,
  input  logic rst_n,
  input  logic enable,
  input  logic in_valid,
  input  logic [DATA_WIDTH-1:0] a_in [ROWS],
  input  logic [DATA_WIDTH-1:0] b_in [COLS],
  output logic out_valid [ROWS][COLS],
  output logic [DATA_WIDTH-1:0] a_out [ROWS],
  output logic [DATA_WIDTH-1:0] b_out [COLS]
);
  logic [DATA_WIDTH-1:0] a_pipe [ROWS][ROWS];
  logic [DATA_WIDTH-1:0] b_pipe [COLS][COLS];
  logic v_a [ROWS][ROWS];
  logic v_b [COLS][COLS];
  integer i, j;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (i = 0; i < ROWS; i = i + 1)
        for (j = 0; j < ROWS; j = j + 1) begin
          a_pipe[i][j] <= '0;
          v_a[i][j] <= 1'b0;
        end
      for (i = 0; i < COLS; i = i + 1)
        for (j = 0; j < COLS; j = j + 1) begin
          b_pipe[i][j] <= '0;
          v_b[i][j] <= 1'b0;
        end
    end else if (enable) begin
      for (i = 0; i < ROWS; i = i + 1) begin
        a_pipe[i][0] <= a_in[i];
        v_a[i][0] <= in_valid;
        for (j = 1; j < ROWS; j = j + 1) begin
          a_pipe[i][j] <= a_pipe[i][j-1];
          v_a[i][j] <= v_a[i][j-1];
        end
      end
      for (i = 0; i < COLS; i = i + 1) begin
        b_pipe[i][0] <= b_in[i];
        v_b[i][0] <= in_valid;
        for (j = 1; j < COLS; j = j + 1) begin
          b_pipe[i][j] <= b_pipe[i][j-1];
          v_b[i][j] <= v_b[i][j-1];
        end
      end
    end
  end

  // Boundary-valid coincidence only, not the validity at interior PE (r,c).
  // Interior PE valid must also include the horizontal/vertical transit delay.
  generate
    for(genvar r=0;r<ROWS;r=r+1) begin : G_A
      assign a_out[r]=a_pipe[r][r];
      for(genvar c=0;c<COLS;c=c+1) begin : G_V
        assign out_valid[r][c]=enable && v_a[r][r] && v_b[c][c];
      end
    end
    for(genvar c=0;c<COLS;c=c+1) begin : G_B
      assign b_out[c]=b_pipe[c][c];
    end
  endgenerate
endmodule
