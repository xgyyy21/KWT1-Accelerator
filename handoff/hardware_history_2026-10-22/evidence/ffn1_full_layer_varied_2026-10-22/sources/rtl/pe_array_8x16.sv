// 8x16 PE fabric. Data movement is external; this module owns only PE
// arithmetic and per-cell accumulation control.
module pe_array_8x16 #(
  parameter int DATA_WIDTH = 16,
  parameter int ACC_WIDTH = 2 * DATA_WIDTH,
  parameter int ROWS = 8,
  parameter int COLS = 16,
  parameter bit SIGNED_DATA = 1'b1
) (
  input logic clk,
  input logic rst_n,
  input logic clear_acc,
  input logic in_valid [ROWS][COLS],
  input logic first_valid [ROWS][COLS],
  input logic last_valid [ROWS][COLS],
  input logic [DATA_WIDTH-1:0] a_data [ROWS][COLS],
  input logic [DATA_WIDTH-1:0] b_data [ROWS][COLS],
  output logic result_valid [ROWS][COLS],
  output logic [ACC_WIDTH-1:0] result [ROWS][COLS],
  output logic busy [ROWS][COLS]
);
  genvar r, c;
  generate
    for (r=0; r<ROWS; r=r+1) begin : GEN_R
      for (c=0; c<COLS; c=c+1) begin : GEN_C
        pe_mac #(
          .DATA_WIDTH(DATA_WIDTH),
          .ACC_WIDTH(ACC_WIDTH),
          .SIGNED_DATA(SIGNED_DATA)
        ) u_pe (
          .clk(clk), .rst_n(rst_n), .enable(1'b1),
          .clear_acc(clear_acc),
          .task_first(first_valid[r][c]),
          .task_last(last_valid[r][c]),
          .in_valid(in_valid[r][c]),
          .a_in(a_data[r][c]), .b_in(b_data[r][c]),
          .a_valid_out(), .b_valid_out(), .a_out(), .b_out(),
          .result_valid(result_valid[r][c]),
          .result(result[r][c]), .busy(busy[r][c]), .done()
        );
      end
    end
  endgenerate
endmodule
