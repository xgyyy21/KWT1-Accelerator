`timescale 1ns/1ps

module fp32_tile_engine_2x2_tb;
  logic clk = 1'b0;
  always #5 clk = ~clk;
  logic rst_n = 1'b0;
  logic start = 1'b0;
  logic stream_valid = 1'b0;
  logic task_first = 1'b0;
  logic task_last = 1'b0;
  logic [31:0] a_left [2];
  logic [31:0] b_top [2];
  logic [31:0] bias_in [2];
  logic [15:0] valid_rows = 2;
  logic [15:0] valid_cols = 2;
  logic busy, done, result_valid, result_last;
  logic [31:0] result_data;
  logic [15:0] result_row, result_col;
  integer count;

  fp32_tile_engine #(.ROWS(2), .COLS(2), .K(2)) dut (
    .clk(clk), .rst_n(rst_n), .start(start),
    .stream_valid(stream_valid), .task_first(task_first),
    .task_last(task_last), .a_left(a_left), .b_top(b_top),
    .bias_in(bias_in), .valid_rows(valid_rows), .valid_cols(valid_cols),
    .busy(busy), .done(done), .result_valid(result_valid),
    .result_last(result_last), .result_data(result_data),
    .result_row(result_row), .result_col(result_col)
  );

  initial begin
    a_left[0] = 0; a_left[1] = 0;
    b_top[0] = 0; b_top[1] = 0;
    bias_in[0] = 32'h3e800000;
    bias_in[1] = 32'hbf000000;
    repeat (2) @(negedge clk);
    rst_n = 1'b1;

    @(negedge clk);
    start = 1'b1; stream_valid = 1'b1; task_first = 1'b1; task_last = 1'b0;
    a_left[0] = 32'h3f800000; a_left[1] = 32'h3f000000;
    b_top[0] = 32'h40000000; b_top[1] = 32'hbf800000;
    @(negedge clk);
    start = 1'b0; task_first = 1'b0; task_last = 1'b1;
    a_left[0] = 32'hc0000000; a_left[1] = 32'h40400000;
    b_top[0] = 32'h3fc00000; b_top[1] = 32'h3f000000;
    @(negedge clk);
    stream_valid = 1'b0; task_last = 1'b0;
    a_left[0] = 0; a_left[1] = 0; b_top[0] = 0; b_top[1] = 0;

    count = 0;
    while (!done) begin
      @(posedge clk);
      #1;
      if (result_valid) begin
        case (count)
          0: if (result_row !== 0 || result_col !== 0 || result_data !== 32'hbf400000 || result_last) $fatal(1, "tile result 0 mismatch");
          1: if (result_row !== 0 || result_col !== 1 || result_data !== 32'hc0200000 || result_last) $fatal(1, "tile result 1 mismatch");
          2: if (result_row !== 1 || result_col !== 0 || result_data !== 32'h40b80000 || result_last) $fatal(1, "tile result 2 mismatch");
          3: if (result_row !== 1 || result_col !== 1 || result_data !== 32'h3f000000 || !result_last) $fatal(1, "tile result 3 mismatch");
          default: $fatal(1, "too many tile results");
        endcase
        count = count + 1;
      end
    end
    if (count != 4 || !done || busy)
      $fatal(1, "tile handshake/count mismatch count=%0d done=%0d busy=%0d", count, done, busy);
    $display("fp32_tile_engine_2x2_tb PASS results=%0d", count);
    $finish;
  end

  initial begin
    #300000;
    $fatal(1, "fp32_tile_engine_2x2_tb timeout");
  end
endmodule
