`timescale 1ns/1ps
module ai_engine_tile_loop_tb;
  localparam int DW = 16;
  localparam int AW = 16;
  localparam int ROWS = 8;
  localparam int COLS = 16;
  localparam int K = 64;
  localparam int CACHE_AW = 10;
  logic clk = 0;
  always #5 clk = ~clk;
  logic rst_n = 0, start = 0;
  logic a_load_en = 0, b_load_en = 0;
  logic [CACHE_AW-1:0] a_load_addr = 0, b_load_addr = 0;
  logic [DW-1:0] a_load_data = 0, b_load_data = 0;
  logic result_rd_en = 0;
  logic [CACHE_AW-1:0] result_rd_addr = 0;
  logic [DW-1:0] result_rd_data;
  logic result_rd_valid, busy, done, error;
  integer row, col, k, addr, cycles;

  ai_engine_tile_loop #(
    .DATA_WIDTH(DW), .ACC_WIDTH(AW), .ROWS(ROWS), .COLS(COLS),
    .K(K), .CACHE_ADDR_WIDTH(CACHE_AW)
  ) dut (.*);

  initial begin
    // Preload A and B with ones. Every output must equal K=64.
    repeat (2) @(negedge clk);
    rst_n = 1;
    for (row = 0; row < ROWS; row = row + 1)
      for (k = 0; k < K; k = k + 1) begin
        @(negedge clk);
        a_load_en = 1; a_load_addr = row*K + k; a_load_data = 16'd1;
      end
    @(negedge clk); a_load_en = 0;
    for (k = 0; k < K; k = k + 1)
      for (col = 0; col < COLS; col = col + 1) begin
        @(negedge clk);
        b_load_en = 1; b_load_addr = k*COLS + col; b_load_data = 16'd1;
      end
    @(negedge clk); b_load_en = 0;

    @(negedge clk); start = 1;
    @(negedge clk); start = 0;
    cycles = 0;
    while (!done && !error && cycles < 10000) begin
      @(negedge clk); cycles = cycles + 1;
    end
    if (error || !done) $fatal(1, "tile loop did not complete");

    for (addr = 0; addr < ROWS*COLS; addr = addr + 1) begin
      @(negedge clk); result_rd_en = 1; result_rd_addr = addr;
      @(negedge clk); result_rd_en = 0;
      if (!result_rd_valid || result_rd_data !== 16'd64)
        $fatal(1, "result addr=%0d valid=%b data=%h", addr,
               result_rd_valid, result_rd_data);
    end
    // A completed tile can be launched again without reset.
    @(negedge clk); start = 1;
    @(negedge clk); start = 0;
    cycles = 0;
    while (!done && !error && cycles < 10000) begin
      @(negedge clk); cycles = cycles + 1;
    end
    if (error || !done) $fatal(1, "second tile loop did not complete");
    $display("ai_engine_tile_loop_tb PASS cycles=%0d", cycles);
    $finish;
  end
endmodule
