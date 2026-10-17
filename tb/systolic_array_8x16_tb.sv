`timescale 1ns/1ps
module systolic_array_8x16_tb;
  localparam int DW = 16;
  localparam int AW = 32;
  localparam int ROWS = 8;
  localparam int COLS = 16;
  localparam int K = 4;
  logic clk = 0;
  always #5 clk = ~clk;
  logic rst_n = 0, start = 0, in_valid = 0;
  logic [DW-1:0] a_left [ROWS];
  logic [DW-1:0] b_top [COLS];
  logic [31:0] bias_data [COLS];
  logic busy, done, result_valid;
  logic [AW-1:0] result [ROWS][COLS];
  integer i, j, t;

  systolic_array_8x16 #(.DATA_WIDTH(DW), .ACC_WIDTH(AW), .K(K)) dut (.*);

  initial begin
    for (i=0; i<ROWS; i=i+1) a_left[i] = 0;
    for (j=0; j<COLS; j=j+1) b_top[j] = 0;
    for (j=0; j<COLS; j=j+1) bias_data[j] = 0;
    repeat (2) @(negedge clk);
    rst_n = 1;
    @(negedge clk); start = 1;
    @(negedge clk); start = 0;
    // Feed four K slices. All rows/columns use value 1, so each PE accumulates K.
    for (t=0; t<K; t=t+1) begin
      for (i=0; i<ROWS; i=i+1) a_left[i] = 1;
      for (j=0; j<COLS; j=j+1) b_top[j] = 1;
      in_valid = 1;
      @(negedge clk);
    end
    in_valid = 0;
    for (i=0; i<ROWS; i=i+1) a_left[i] = 0;
    for (j=0; j<COLS; j=j+1) b_top[j] = 0;
    wait (result_valid);
    @(negedge clk);
    for (i=0; i<ROWS; i=i+1)
      for (j=0; j<COLS; j=j+1)
        if (result[i][j] !== K)
          $fatal(1, "array mismatch at %0d,%0d: %0d", i, j, result[i][j]);
    $display("systolic_array_8x16_tb PASS");
    $finish;
  end
  initial begin #10000; $fatal(1,"systolic_array_8x16_tb timeout"); end
endmodule
