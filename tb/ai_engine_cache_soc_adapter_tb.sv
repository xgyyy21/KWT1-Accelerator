`timescale 1ns/1ps
module ai_engine_cache_soc_adapter_tb;
  localparam int DW = 16;
  localparam int ROWS = 8;
  localparam int COLS = 16;
  localparam int K = 64;
  localparam int CACHE_AW = 10;
  logic clk = 0;
  always #5 clk = ~clk;
  logic rst_n = 0;
  logic bus_valid = 0, bus_write = 0;
  logic [31:0] bus_addr = 0, bus_wdata = 0, bus_rdata;
  logic bus_ready, bus_rsp_valid;
  logic load_valid = 0, load_select_b = 0;
  logic [CACHE_AW-1:0] load_addr = 0;
  logic [DW-1:0] load_data = 0;
  logic load_ready;
  logic result_rd_en = 0;
  logic [CACHE_AW-1:0] result_rd_addr = 0;
  logic [DW-1:0] result_rd_data;
  logic result_rd_valid, engine_busy, engine_done, engine_error;
  integer row, col, k, addr, cycles;

  ai_engine_cache_soc_adapter #(
    .DATA_WIDTH(DW), .ROWS(ROWS), .COLS(COLS), .K(K),
    .CACHE_ADDR_WIDTH(CACHE_AW)
  ) dut (.*);

  task automatic bus_wr(input [7:0] address, input [31:0] data);
    begin
      @(negedge clk);
      bus_valid = 1; bus_write = 1; bus_addr = address; bus_wdata = data;
      @(negedge clk);
      bus_valid = 0; bus_write = 0;
    end
  endtask

  task automatic cache_wr(input logic select_b, input integer address,
                          input logic [DW-1:0] data);
    begin
      @(negedge clk);
      if (!load_ready) $fatal(1, "cache write accepted while engine busy");
      load_valid = 1; load_select_b = select_b;
      load_addr = CACHE_AW'(address); load_data = data;
      @(negedge clk);
      load_valid = 0;
    end
  endtask

  initial begin
    repeat (2) @(negedge clk);
    rst_n = 1;
    bus_wr(8'h14, ROWS); bus_wr(8'h18, K); bus_wr(8'h1c, COLS);
    for (row = 0; row < ROWS; row = row + 1)
      for (k = 0; k < K; k = k + 1)
        cache_wr(0, row*K + k, 16'd1);
    for (k = 0; k < K; k = k + 1)
      for (col = 0; col < COLS; col = col + 1)
        cache_wr(1, k*COLS + col, 16'd1);

    bus_wr(8'h00, 32'd1);
    cycles = 0;
    while (!engine_done && !engine_error && cycles < 10000) begin
      @(negedge clk); cycles = cycles + 1;
    end
    if (engine_error || !engine_done) $fatal(1, "valid register-started tile failed");
    for (addr = 0; addr < ROWS*COLS; addr = addr + 1) begin
      @(negedge clk); result_rd_en = 1; result_rd_addr = CACHE_AW'(addr);
      @(negedge clk); result_rd_en = 0;
      if (!result_rd_valid || result_rd_data !== 16'd64)
        $fatal(1, "result addr=%0d valid=%b data=%h", addr,
               result_rd_valid, result_rd_data);
    end

    // An oversized tile must be rejected rather than silently truncated.
    bus_wr(8'h1c, COLS+1);
    bus_wr(8'h00, 32'd1);
    repeat (3) @(negedge clk);
    if (!engine_error || engine_busy) $fatal(1, "unsupported tile was not rejected");
    $display("ai_engine_cache_soc_adapter_tb PASS cycles=%0d", cycles);
    $finish;
  end

  initial begin #80000; $fatal(1, "ai_engine_cache_soc_adapter_tb timeout"); end
endmodule
