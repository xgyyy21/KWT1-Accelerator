`timescale 1ns/1ps

module fp32_matrix_tile_scheduler_tb;
  logic clk = 1'b0;
  always #5 clk = ~clk;
  logic rst_n = 1'b0;
  logic start = 1'b0;
  logic tile_done = 1'b0;
  logic [15:0] matrix_m, matrix_k, matrix_n;
  logic tile_start, tile_busy, done, config_error, task_first, task_last;
  logic supported_shape;
  logic [31:0] tile_index;
  logic [15:0] row_base, col_base, k_base, rows_valid, cols_valid, k_valid;
  logic [15:0] k_block_index, k_block_count;
  integer count;
  integer first_count;
  integer last_count;
  integer expected_k_blocks_mon;
  logic tile_pending;

  fp32_matrix_tile_scheduler dut (
    .clk(clk), .rst_n(rst_n), .start(start), .tile_done(tile_done),
    .matrix_m(matrix_m), .matrix_k(matrix_k), .matrix_n(matrix_n),
    .tile_start(tile_start), .tile_busy(tile_busy), .done(done),
    .config_error(config_error), .tile_index(tile_index),
    .row_base(row_base), .col_base(col_base), .k_base(k_base),
    .rows_valid(rows_valid), .cols_valid(cols_valid), .k_valid(k_valid),
    .task_first(task_first), .task_last(task_last),
    .k_block_index(k_block_index), .k_block_count(k_block_count),
    .supported_shape(supported_shape)
  );

  // Capture each one-cycle tile_start once at the opposite clock edge, then
  // return tile_done after one simulated datapath cycle.
  always @(negedge clk) begin
    if (!rst_n) begin
      tile_done <= 1'b0;
      tile_pending <= 1'b0;
    end else if (tile_pending) begin
      tile_done <= 1'b1;
      tile_pending <= 1'b0;
    end else begin
      tile_done <= 1'b0;
      if (tile_start) begin
        if (rows_valid == 0 || cols_valid == 0 || k_valid == 0)
          $fatal(1, "invalid descriptor index=%0d", tile_index);
        if (k_base != 0 || k_block_index != 0)
          $fatal(1, "outer scheduler must start at K block zero index=%0d", tile_index);
        if (k_block_count != expected_k_blocks_mon)
          $fatal(1, "K block count mismatch got=%0d expected=%0d",
                 k_block_count, expected_k_blocks_mon);
        if (task_first) first_count = first_count + 1;
        if (task_last) last_count = last_count + 1;
        count = count + 1;
        tile_pending <= 1'b1;
      end
    end
  end

  task automatic run_shape(input logic [15:0] m, input logic [15:0] k,
                           input logic [15:0] n, input integer expected_blocks,
                           input integer expected_k_blocks);
    integer guard;
    begin
      matrix_m = m; matrix_k = k; matrix_n = n;
      expected_k_blocks_mon = expected_k_blocks;
      count = 0; first_count = 0; last_count = 0; guard = 0;
      @(negedge clk); start = 1'b1;
      @(negedge clk); start = 1'b0;
      if (!supported_shape) $fatal(1, "valid shape rejected");
      while (!done) begin
        // Observe the one-cycle descriptor pulse midway between active edges
        // so the registered pulse is not hidden by its deasserting NBA.
        @(negedge clk);
        guard = guard + 1;
        if (guard > expected_blocks*8 + 20)
          $fatal(1, "scheduler timeout count=%0d index=%0d", count, tile_index);
      end
      if (count != expected_blocks || first_count != expected_blocks ||
          last_count != expected_blocks || tile_busy || config_error)
        $fatal(1, "scheduler result mismatch count=%0d first=%0d last=%0d busy=%0d error=%0d",
               count, first_count, last_count, tile_busy, config_error);
    end
  endtask

  initial begin
    matrix_m = 0; matrix_k = 0; matrix_n = 0;
    count=0; first_count=0; last_count=0; tile_pending=0; tile_done=0;
    repeat (2) @(negedge clk);
    rst_n = 1'b1;
    run_shape(16'd99, 16'd64, 16'd256, 208, 2);
    run_shape(16'd99, 16'd256, 16'd64, 52, 8);
    matrix_m = 16'd8; matrix_k = 16'd8; matrix_n = 16'd8;
    @(negedge clk); start = 1'b1;
    @(negedge clk); start = 1'b0;
    @(posedge clk); #1;
    if (!config_error || tile_start || tile_busy)
      $fatal(1, "unsupported shape was not rejected");
    $display("fp32_matrix_tile_scheduler_tb PASS shapes=2 spatial_tiles=260");
    $finish;
  end

  initial begin
    #3000000;
    $fatal(1, "fp32_matrix_tile_scheduler_tb timeout");
  end
endmodule
