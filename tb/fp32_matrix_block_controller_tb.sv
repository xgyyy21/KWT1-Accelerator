`timescale 1ns/1ps

module fp32_matrix_block_controller_tb;
  logic clk = 1'b0;
  always #5 clk = ~clk;
  logic rst_n = 1'b0;
  logic start = 1'b0;
  logic block_done = 1'b0;
  logic [15:0] matrix_m, matrix_k, matrix_n;
  logic block_start, busy, done, k_first, k_last;
  logic [31:0] block_index;
  logic [15:0] row_base, col_base, k_base, rows_valid, cols_valid, k_valid;
  integer count;
  integer expected_blocks_mon;
  integer m_mon, k_mon, n_mon;
  logic block_pending;

  fp32_matrix_block_controller #(.ROW_TILE(8), .COL_TILE(16), .K_TILE(32)) dut (
    .clk(clk), .rst_n(rst_n), .start(start), .block_done(block_done),
    .matrix_m(matrix_m), .matrix_k(matrix_k), .matrix_n(matrix_n),
    .block_start(block_start), .busy(busy), .done(done),
    .block_index(block_index), .row_base(row_base), .col_base(col_base),
    .k_base(k_base), .rows_valid(rows_valid), .cols_valid(cols_valid),
    .k_valid(k_valid), .k_first(k_first), .k_last(k_last)
  );

  // The controller's block_start is a one-cycle launch pulse.  Observe it
  // once and return block_done only after one datapath cycle.
  always @(negedge clk) begin
    if (!rst_n) begin
      block_done <= 1'b0;
      block_pending <= 1'b0;
    end else if (block_pending) begin
      block_done <= 1'b1;
      block_pending <= 1'b0;
    end else begin
      block_done <= 1'b0;
      if (block_start) begin
        if (rows_valid == 0 || cols_valid == 0 || k_valid == 0)
          $fatal(1, "invalid block dimensions index=%0d", block_index);
        if (count == 0 && (row_base != 0 || col_base != 0 || k_base != 0 || !k_first))
          $fatal(1, "first block coordinates wrong");
        if (count == expected_blocks_mon-1) begin
          if (row_base + rows_valid < m_mon || col_base + cols_valid < n_mon ||
              k_base + k_valid < k_mon || !k_last)
            $fatal(1, "last block coordinates wrong");
        end
        count = count + 1;
        block_pending <= 1'b1;
      end
    end
  end

  task automatic run_shape(input logic [15:0] m, input logic [15:0] k,
                           input logic [15:0] n, input integer expected_blocks);
    integer guard;
    begin
      matrix_m = m; matrix_k = k; matrix_n = n;
      m_mon = m; k_mon = k; n_mon = n;
      expected_blocks_mon = expected_blocks;
      count = 0; guard = 0;
      @(negedge clk); start = 1'b1;
      @(negedge clk); start = 1'b0;
      while (!done) begin
        @(negedge clk);
        guard = guard + 1;
        if (guard > expected_blocks*8 + 20)
          $fatal(1, "controller timeout shape=%0dx%0dx%0d count=%0d index=%0d rb=%0d cb=%0d kb=%0d",
                 m, k, n, count, block_index, row_base, col_base, k_base);
      end
      if (count != expected_blocks || busy)
        $fatal(1, "block count/busy mismatch got=%0d expected=%0d busy=%0d",
               count, expected_blocks, busy);
    end
  endtask

  initial begin
    matrix_m = 0; matrix_k = 0; matrix_n = 0;
    count=0; expected_blocks_mon=0; m_mon=0; k_mon=0; n_mon=0; block_pending=0;
    repeat (2) @(negedge clk);
    rst_n = 1'b1;
    // 13 row blocks * 16 column blocks * 2 K blocks.
    run_shape(16'd99, 16'd64, 16'd256, 416);
    // 13 row blocks * 4 column blocks * 8 K blocks.
    run_shape(16'd99, 16'd256, 16'd64, 416);
    $display("fp32_matrix_block_controller_tb PASS shapes=2 blocks=832");
    $finish;
  end

  initial begin
    #2000000;
    $fatal(1, "fp32_matrix_block_controller_tb timeout");
  end
endmodule
