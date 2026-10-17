module systolic_array_8x16 #(
  parameter int DATA_WIDTH = 16,
  parameter int ACC_WIDTH = 2 * DATA_WIDTH,
  parameter int ROWS = 8,
  parameter int COLS = 16,
  parameter int K = 64,
  parameter bit SIGNED_DATA = 1'b1
) (
  input logic clk, input logic rst_n, input logic start, input logic in_valid,
  input logic [DATA_WIDTH-1:0] a_left [ROWS],
  input logic [DATA_WIDTH-1:0] b_top [COLS],
  output logic busy, output logic done, output logic result_valid,
  output logic [ACC_WIDTH-1:0] result [ROWS][COLS]
);
  logic [DATA_WIDTH-1:0] a_pipe[ROWS][COLS], b_pipe[ROWS][COLS];
  logic [DATA_WIDTH-1:0] a_skew[ROWS][ROWS], b_skew[COLS][COLS];
  logic va[ROWS][COLS], vb[ROWS][COLS];
  logic va_skew[ROWS][ROWS], vb_skew[COLS][COLS];
  logic first_a[ROWS][COLS], first_b[ROWS][COLS];
  logic last_a[ROWS][COLS], last_b[ROWS][COLS];
  logic first_a_skew[ROWS][ROWS], first_b_skew[COLS][COLS];
  logic last_a_skew[ROWS][ROWS], last_b_skew[COLS][COLS];
  logic pe_valid[ROWS][COLS], pe_first[ROWS][COLS], pe_last[ROWS][COLS];
  logic pe_result_valid[ROWS][COLS], pe_busy[ROWS][COLS];
  logic [ACC_WIDTH-1:0] pe_result[ROWS][COLS];
  logic result_pending;
  integer count, r, c;
  logic accept_start, accept_input;
  assign accept_start = start && !busy && !result_pending;
  assign accept_input = busy && in_valid && (count < K);
  initial begin
    if(ROWS<=0 || COLS<=0 || K<=0 || DATA_WIDTH<=0 || ACC_WIDTH<=0)
      $fatal(1,"invalid systolic array parameters");
  end

  generate
    genvar gr, gc;
    for (gr=0; gr<ROWS; gr=gr+1) begin : GVR
      for (gc=0; gc<COLS; gc=gc+1) begin : GVC
        assign pe_valid[gr][gc] = va[gr][gc] && vb[gr][gc];
        assign pe_first[gr][gc] = first_a[gr][gc] && first_b[gr][gc];
        assign pe_last[gr][gc] = last_a[gr][gc] && last_b[gr][gc];
      end
    end
  endgenerate

  pe_array_8x16 #(.DATA_WIDTH(DATA_WIDTH), .ACC_WIDTH(ACC_WIDTH), .ROWS(ROWS), .COLS(COLS), .SIGNED_DATA(SIGNED_DATA)) u_pe_array (
    .clk(clk), .rst_n(rst_n), .clear_acc(accept_start), .in_valid(pe_valid),
    .first_valid(pe_first), .last_valid(pe_last),
    .a_data(a_pipe), .b_data(b_pipe), .result_valid(pe_result_valid),
    .result(pe_result), .busy(pe_busy)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      busy <= 0; done <= 0; result_valid <= 0; count <= 0; result_pending <= 0;
      for (r=0;r<ROWS;r=r+1) for (c=0;c<COLS;c=c+1) begin
        a_pipe[r][c] <= '0; b_pipe[r][c] <= '0; va[r][c] <= 0; vb[r][c] <= 0;
        first_a[r][c] <= 0; first_b[r][c] <= 0; last_a[r][c] <= 0; last_b[r][c] <= 0; result[r][c] <= '0;
      end
      for (r=0;r<ROWS;r=r+1) for (c=0;c<ROWS;c=c+1) begin
        a_skew[r][c] <= '0; va_skew[r][c] <= 0; first_a_skew[r][c] <= 0; last_a_skew[r][c] <= 0;
      end
      for (r=0;r<COLS;r=r+1) for (c=0;c<COLS;c=c+1) begin
        b_skew[r][c] <= '0; vb_skew[r][c] <= 0; first_b_skew[r][c] <= 0; last_b_skew[r][c] <= 0;
      end
    end else begin
      done <= 0; result_valid <= 0;
      if (result_pending) begin
        result_valid <= 1;
        done <= 1;
        result_pending <= 0;
      end
      if (accept_start) begin
        busy <= 1; count <= 0; result_pending <= 0;
        for (r=0;r<ROWS;r=r+1) for (c=0;c<COLS;c=c+1) begin
          a_pipe[r][c] <= '0; b_pipe[r][c] <= '0; va[r][c] <= 0; vb[r][c] <= 0;
          first_a[r][c] <= 0; first_b[r][c] <= 0; last_a[r][c] <= 0; last_b[r][c] <= 0;
        end
        for (r=0;r<ROWS;r=r+1) for (c=0;c<ROWS;c=c+1) begin
          a_skew[r][c] <= '0; va_skew[r][c] <= 0; first_a_skew[r][c] <= 0; last_a_skew[r][c] <= 0;
        end
        for (r=0;r<COLS;r=r+1) for (c=0;c<COLS;c=c+1) begin
          b_skew[r][c] <= '0; vb_skew[r][c] <= 0; first_b_skew[r][c] <= 0; last_b_skew[r][c] <= 0;
        end
      end else if (busy) begin
        for (r=0;r<ROWS;r=r+1) begin
          a_skew[r][0] <= a_left[r]; va_skew[r][0] <= accept_input;
          first_a_skew[r][0] <= accept_input && (count == 0); last_a_skew[r][0] <= accept_input && (count == K-1);
          for (c=1;c<ROWS;c=c+1) begin
            a_skew[r][c] <= a_skew[r][c-1]; va_skew[r][c] <= va_skew[r][c-1];
            first_a_skew[r][c] <= first_a_skew[r][c-1]; last_a_skew[r][c] <= last_a_skew[r][c-1];
          end
          a_pipe[r][0] <= a_skew[r][r]; va[r][0] <= va_skew[r][r];
          first_a[r][0] <= first_a_skew[r][r]; last_a[r][0] <= last_a_skew[r][r];
          for (c=1;c<COLS;c=c+1) begin
            a_pipe[r][c] <= a_pipe[r][c-1]; va[r][c] <= va[r][c-1];
            first_a[r][c] <= first_a[r][c-1]; last_a[r][c] <= last_a[r][c-1];
          end
        end
        for (c=0;c<COLS;c=c+1) begin
          b_skew[c][0] <= b_top[c]; vb_skew[c][0] <= accept_input;
          first_b_skew[c][0] <= accept_input && (count == 0); last_b_skew[c][0] <= accept_input && (count == K-1);
          for (r=1;r<COLS;r=r+1) begin
            b_skew[c][r] <= b_skew[c][r-1]; vb_skew[c][r] <= vb_skew[c][r-1];
            first_b_skew[c][r] <= first_b_skew[c][r-1]; last_b_skew[c][r] <= last_b_skew[c][r-1];
          end
          b_pipe[0][c] <= b_skew[c][c]; vb[0][c] <= vb_skew[c][c];
          first_b[0][c] <= first_b_skew[c][c]; last_b[0][c] <= last_b_skew[c][c];
          for (r=1;r<ROWS;r=r+1) begin
            b_pipe[r][c] <= b_pipe[r-1][c]; vb[r][c] <= vb[r-1][c];
            first_b[r][c] <= first_b[r-1][c]; last_b[r][c] <= last_b[r-1][c];
          end
        end
        if (accept_input) count <= count + 1;
        for (r=0;r<ROWS;r=r+1) for (c=0;c<COLS;c=c+1)
          if (pe_result_valid[r][c]) result[r][c] <= pe_result[r][c];
        if (pe_result_valid[ROWS-1][COLS-1]) begin
          busy <= 0;
          result_pending <= 1;
        end
      end
    end
  end
endmodule
