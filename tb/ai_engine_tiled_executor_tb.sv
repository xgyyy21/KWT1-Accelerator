`timescale 1ns/1ps
module ai_engine_tiled_executor_tb;
  localparam int DW = 16;
  localparam int ROWS = 4;
  localparam int COLS = 4;
  localparam int K = 4;
  localparam int CACHE_AW = 6;
  localparam int M = 5;
  localparam int N = 5;
  logic clk = 0;
  always #5 clk = ~clk;
  logic rst_n = 0, task_start = 0;
  logic [15:0] matrix_m = M, matrix_k = K, matrix_n = N;
  logic tile_request_valid, tile_loaded = 0;
  logic [15:0] row_base, col_base, k_base, rows_valid, cols_valid, k_valid;
  logic load_valid = 0, load_select_b = 0, load_ready;
  logic [CACHE_AW-1:0] load_addr = 0;
  logic [DW-1:0] load_data = 0;
  logic writeback_start, writeback_done = 0;
  logic result_rd_en = 0;
  logic [CACHE_AW-1:0] result_rd_addr = 0;
  logic [DW-1:0] result_rd_data;
  logic result_rd_valid, busy, done, error;
  integer tile_count, row, col, k, addr, guard;
  integer expected_row, expected_col, expected_rows, expected_cols;

  ai_engine_tiled_executor #(
    .DATA_WIDTH(DW), .ROWS(ROWS), .COLS(COLS), .K(K),
    .CACHE_ADDR_WIDTH(CACHE_AW)
  ) dut (.*);

  task automatic cache_wr(input logic select_b, input integer address,
                          input logic [DW-1:0] data);
    begin
      @(negedge clk);
      if (!load_ready) $fatal(1, "cache port not ready for tile %0d", tile_count);
      load_valid = 1; load_select_b = select_b;
      load_addr = CACHE_AW'(address); load_data = data;
      @(negedge clk); load_valid = 0;
    end
  endtask

  task automatic service_requested_tile;
    begin
      expected_row = (tile_count / 2) * ROWS;
      expected_col = (tile_count % 2) * COLS;
      expected_rows = (expected_row + ROWS <= M) ? ROWS : M - expected_row;
      expected_cols = (expected_col + COLS <= N) ? COLS : N - expected_col;
      if (row_base !== expected_row || col_base !== expected_col || k_base !== 0 ||
          rows_valid !== expected_rows || cols_valid !== expected_cols || k_valid !== K)
        $fatal(1, "bad descriptor tile=%0d rb=%0d cb=%0d rv=%0d cv=%0d kv=%0d",
               tile_count, row_base, col_base, rows_valid, cols_valid, k_valid);
      // The test DMA supplies zero-padded full tiles; active entries are one.
      for (row = 0; row < ROWS; row = row + 1)
        for (k = 0; k < K; k = k + 1)
          cache_wr(0, row*K + k, row < expected_rows ? 16'd1 : 16'd0);
      for (k = 0; k < K; k = k + 1)
        for (col = 0; col < COLS; col = col + 1)
          cache_wr(1, k*COLS + col, col < expected_cols ? 16'd1 : 16'd0);
      @(negedge clk); tile_loaded = 1;
      @(negedge clk); tile_loaded = 0;
      wait (writeback_start);
      for (addr = 0; addr < expected_rows*expected_cols; addr = addr + 1) begin
        @(negedge clk); result_rd_en = 1; result_rd_addr = CACHE_AW'(addr);
        @(negedge clk); result_rd_en = 0;
        if (!result_rd_valid || result_rd_data !== K)
          $fatal(1, "bad result tile=%0d addr=%0d data=%h", tile_count, addr, result_rd_data);
      end
      @(negedge clk); writeback_done = 1;
      @(negedge clk); writeback_done = 0;
      tile_count = tile_count + 1;
    end
  endtask

  initial begin
    repeat (2) @(negedge clk);
    rst_n = 1;
    @(negedge clk); task_start = 1;
    @(negedge clk); task_start = 0;
    tile_count = 0; guard = 0;
    while (!done && !error && guard < 50000) begin
      @(negedge clk); guard = guard + 1;
      if (tile_request_valid) service_requested_tile();
    end
    if (error || !done || tile_count != 4 || busy)
      $fatal(1, "task completion failure done=%b error=%b tiles=%0d busy=%b",
             done, error, tile_count, busy);
    $display("ai_engine_tiled_executor_tb PASS tiles=%0d", tile_count);
    $finish;
  end


  initial begin #10000000; $fatal(1, "ai_engine_tiled_executor_tb timeout"); end
endmodule
