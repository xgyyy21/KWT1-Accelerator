`timescale 1ns/1ps

module fp32_matrix_global_addr_gen_tb;
  logic [15:0] matrix_m, matrix_k, matrix_n;
  logic [15:0] row_base, col_base, k_base;
  logic [15:0] local_row, local_col, local_k;
  logic word_high;
  logic [31:0] a_word_addr, b_word_addr, bias_word_addr, result_word_addr;
  logic a_valid, b_valid, bias_valid, result_valid;

  fp32_matrix_global_addr_gen dut (
    .matrix_m(matrix_m), .matrix_k(matrix_k), .matrix_n(matrix_n),
    .row_base(row_base), .col_base(col_base), .k_base(k_base),
    .local_row(local_row), .local_col(local_col), .local_k(local_k),
    .word_high(word_high), .a_base_word(32'd1000), .b_base_word(32'd2000),
    .bias_base_word(32'd3000), .result_base_word(32'd4000),
    .a_valid(a_valid), .b_valid(b_valid), .bias_valid(bias_valid),
    .result_valid(result_valid), .a_word_addr(a_word_addr),
    .b_word_addr(b_word_addr), .bias_word_addr(bias_word_addr),
    .result_word_addr(result_word_addr)
  );

  task automatic check_case(
    input integer m, input integer k, input integer n,
    input integer rb, input integer cb, input integer kb,
    input integer lr, input integer lc, input integer lk,
    input logic high_word
  );
    reg [63:0] grow, gcol, gk;
    reg [63:0] ea, eb, ebias, er;
    begin
      matrix_m = m; matrix_k = k; matrix_n = n;
      row_base = rb; col_base = cb; k_base = kb;
      local_row = lr; local_col = lc; local_k = lk;
      word_high = high_word;
      #1;
      grow = rb + lr; gcol = cb + lc; gk = kb + lk;
      ea = 1000 + (((grow*k + gk)*2) + (high_word ? 1 : 0));
      eb = 2000 + (((gk*n + gcol)*2) + (high_word ? 1 : 0));
      ebias = 3000 + ((gcol*2) + (high_word ? 1 : 0));
      er = 4000 + (((grow*n + gcol)*2) + (high_word ? 1 : 0));
      if (!a_valid || !b_valid || !bias_valid || !result_valid)
        $fatal(1, "unexpected invalid flag at global %0d,%0d,%0d",
               grow, gcol, gk);
      if (a_word_addr !== ea[31:0] || b_word_addr !== eb[31:0] ||
          bias_word_addr !== ebias[31:0] || result_word_addr !== er[31:0])
        $fatal(1, "address mismatch got A=%0d B=%0d bias=%0d result=%0d",
               a_word_addr, b_word_addr, bias_word_addr, result_word_addr);
    end
  endtask

  initial begin
    // First required shape: 99x64 times 64x256, last partial row/column tile.
    check_case(99, 64, 256, 96, 240, 32, 2, 15, 31, 1'b0);
    check_case(99, 64, 256, 96, 240, 32, 2, 15, 31, 1'b1);

    // Second required shape: 99x256 times 256x64, last K block and edge tile.
    check_case(99, 256, 64, 96, 48, 224, 2, 15, 31, 1'b0);
    check_case(99, 256, 64, 96, 48, 224, 2, 15, 31, 1'b1);

    // Out-of-range local coordinates must suppress the affected requests.
    matrix_m = 99; matrix_k = 64; matrix_n = 256;
    row_base = 96; col_base = 240; k_base = 32;
    local_row = 3; local_col = 0; local_k = 0; word_high = 0;
    #1;
    if (a_valid || result_valid || !b_valid || !bias_valid)
      $fatal(1, "row overflow flags are incorrect");
    local_row = 2; local_col = 16; local_k = 0;
    #1;
    if (b_valid || bias_valid || !a_valid || result_valid)
      $fatal(1, "column overflow flags are incorrect");
    local_row = 2; local_col = 15; local_k = 32;
    #1;
    if (a_valid || b_valid || !bias_valid || !result_valid)
      $fatal(1, "K overflow flags are incorrect");

    $display("fp32_matrix_global_addr_gen_tb PASS global matrix address and boundary checks");
    $finish;
  end
endmodule
