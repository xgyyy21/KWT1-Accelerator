`timescale 1ns/1ps

module fp32_tile_cache_mapper_tb;
  localparam int ADDR_WIDTH = 10;

  logic [15:0] local_row;
  logic [15:0] local_col;
  logic [15:0] local_k;
  logic word_high;
  logic a_valid, b_valid, bias_valid, result_valid;
  logic [ADDR_WIDTH-1:0] a_word_addr, b_word_addr;
  logic [ADDR_WIDTH-1:0] bias_word_addr, result_word_addr;

  fp32_tile_cache_mapper dut (
    .local_row(local_row),
    .local_col(local_col),
    .local_k(local_k),
    .word_high(word_high),
    .a_valid(a_valid),
    .b_valid(b_valid),
    .bias_valid(bias_valid),
    .result_valid(result_valid),
    .a_word_addr(a_word_addr),
    .b_word_addr(b_word_addr),
    .bias_word_addr(bias_word_addr),
    .result_word_addr(result_word_addr)
  );

  task automatic check_addr(
    input int expected_a,
    input int expected_b,
    input int expected_bias,
    input int expected_result
  );
    begin
      #1;
      if (!a_valid || !b_valid || !bias_valid || !result_valid)
        $fatal(1, "valid flag unexpectedly low at row=%0d col=%0d k=%0d high=%0d",
               local_row, local_col, local_k, word_high);
      if (a_word_addr !== expected_a[ADDR_WIDTH-1:0])
        $fatal(1, "A address mismatch: got %0d expected %0d", a_word_addr, expected_a);
      if (b_word_addr !== expected_b[ADDR_WIDTH-1:0])
        $fatal(1, "B address mismatch: got %0d expected %0d", b_word_addr, expected_b);
      if (bias_word_addr !== expected_bias[ADDR_WIDTH-1:0])
        $fatal(1, "bias address mismatch: got %0d expected %0d", bias_word_addr, expected_bias);
      if (result_word_addr !== expected_result[ADDR_WIDTH-1:0])
        $fatal(1, "result address mismatch: got %0d expected %0d", result_word_addr, expected_result);
    end
  endtask

  initial begin
    local_row = 0;
    local_col = 0;
    local_k = 0;
    word_high = 1'b0;
    check_addr(0, 0, 0, 0);

    word_high = 1'b1;
    check_addr(1, 1, 1, 1);

    local_row = 7;
    local_col = 15;
    local_k = 31;
    word_high = 1'b0;
    check_addr(510, 1022, 30, 254);

    word_high = 1'b1;
    check_addr(511, 1023, 31, 255);

    // Invalid coordinates must not request a cache word.
    local_row = 8;
    local_col = 0;
    local_k = 0;
    word_high = 1'b0;
    #1;
    if (a_valid || result_valid || !b_valid || !bias_valid)
      $fatal(1, "row overflow valid flags are incorrect");

    local_row = 0;
    local_col = 16;
    local_k = 0;
    #1;
    if (b_valid || bias_valid || !a_valid || result_valid)
      $fatal(1, "column overflow valid flags are incorrect");

    local_row = 0;
    local_col = 0;
    local_k = 32;
    #1;
    if (a_valid || b_valid || !bias_valid || !result_valid)
      $fatal(1, "K overflow valid flags are incorrect");

    $display("PASS: fp32_tile_cache_mapper address and range checks");
    $finish;
  end
endmodule
