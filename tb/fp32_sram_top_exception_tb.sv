`timescale 1ns/1ps
// Top-level SRAM/bus exception checks. This is a functional-model test only:
// it does not claim E203 protocol or vendor SRAM timing coverage.
module fp32_sram_top_exception_tb;
  logic clk = 1'b0;
  always #5 clk = ~clk;
  logic rst_n = 1'b1;
  logic [2:0] standby = 3'b000;
  logic nice_valid = 1'b0, nice_write = 1'b0;
  logic [31:0] nice_addr = 0, nice_wdata = 0;
  wire nice_ready, nice_rsp_valid;
  wire [31:0] nice_rsp_rdata;
  wire sys_valid, sys_write;
  wire [31:0] sys_addr;
  wire [15:0] sys_wdata;
  logic sys_ready = 1'b0, sys_rsp_valid = 1'b0;
  logic [15:0] sys_rsp_rdata = 16'h0000;
  wire tile_start, tile_busy, accel_done, accel_error;
  wire [31:0] tile_index;
  wire [15:0] row_base, col_base, k_base, rows_valid, cols_valid, k_valid;
  wire task_first, task_last;
  wire [15:0] k_block_index, k_block_count;
  wire [23:0] macro_cen, macro_gwen, macro_ret1n;
  wire [23:0][15:0] macro_wen, macro_d, macro_q;
  wire [23:0][6:0] macro_a;
  wire [23:0][2:0] macro_ema;
  wire [23:0][1:0] macro_emaw;
  integer cycles = 0;

  fp32_accelerator_top #(.STRICT_COMPETITION_SHAPES(1'b1),
                         .USE_SRAM_MACROS(1'b1)) dut (
    .clk(clk), .rst_n(rst_n), .cache_standby(standby),
    .macro_cen(macro_cen), .macro_gwen(macro_gwen), .macro_wen(macro_wen),
    .macro_a(macro_a), .macro_d(macro_d), .macro_q(macro_q),
    .macro_ema(macro_ema), .macro_emaw(macro_emaw),
    .macro_ret1n(macro_ret1n),
    .nice_req_valid(nice_valid), .nice_req_write(nice_write),
    .nice_req_addr(nice_addr), .nice_req_wdata(nice_wdata),
    .nice_req_ready(nice_ready), .nice_rsp_valid(nice_rsp_valid),
    .nice_rsp_rdata(nice_rsp_rdata), .sys_req_valid(sys_valid),
    .sys_req_write(sys_write), .sys_req_addr(sys_addr),
    .sys_req_wdata(sys_wdata), .sys_req_ready(sys_ready),
    .sys_rsp_valid(sys_rsp_valid), .sys_rsp_rdata(sys_rsp_rdata),
    .tile_start(tile_start), .tile_busy(tile_busy), .accel_done(accel_done),
    .accel_error(accel_error), .tile_index(tile_index), .row_base(row_base),
    .col_base(col_base), .k_base(k_base), .rows_valid(rows_valid),
    .cols_valid(cols_valid), .k_valid(k_valid), .task_first(task_first),
    .task_last(task_last), .k_block_index(k_block_index),
    .k_block_count(k_block_count)
  );

  for (genvar s = 0; s < 24; s++) begin : g_sram
    ramsp128x16_functional_model u_mem (
      .CLK(clk), .CEN(macro_cen[s]), .GWEN(macro_gwen[s]),
      .WEN(macro_wen[s]), .A(macro_a[s]), .D(macro_d[s]), .Q(macro_q[s]),
      .EMA(macro_ema[s]), .EMAW(macro_emaw[s]), .RET1N(macro_ret1n[s])
    );
  end

  task automatic send_nice_write(input integer addr, input logic [31:0] value);
    begin
      @(negedge clk);
      nice_valid = 1'b1; nice_write = 1'b1;
      nice_addr = addr; nice_wdata = value;
      while (!nice_ready) @(posedge clk);
      @(posedge clk);
      @(negedge clk);
      nice_valid = 1'b0; nice_write = 1'b0;
    end
  endtask

  always @(posedge clk) cycles = cycles + 1;

  initial begin
    #1 rst_n = 1'b0;
    repeat (2) @(negedge clk);
    rst_n = 1'b1;

    // A response with no accepted read must become a sticky top-level error.
    @(negedge clk);
    sys_rsp_valid = 1'b1;
    @(posedge clk); #1;
    if (!accel_error)
      $fatal(1, "orphan System-Bus response did not reach accelerator error");
    sys_rsp_valid = 1'b0;
    $display("CHECK top-level orphan response error PASS");

    // Reset clears the sticky error and must suppress all macro requests.
    @(negedge clk); rst_n = 1'b0;
    @(posedge clk); #1;
    if (accel_error || tile_busy || macro_cen !== {24{1'b1}} ||
        macro_gwen !== {24{1'b1}} || macro_ret1n !== {24{1'b1}})
      $fatal(1, "reset did not clear top error or suppress SRAM activity");
    rst_n = 1'b1;
    $display("CHECK reset clears error and suppresses SRAM pins PASS");

    // Start a legal shape, accept one System-Bus read, leave its response
    // outstanding, then reset. The pending transaction must be cancelled.
    send_nice_write('h08, 32'd1000);
    send_nice_write('h0c, 32'd5000);
    send_nice_write('h20, 32'd9000);
    send_nice_write('h10, 32'd12000);
    send_nice_write('h14, 32'd99);
    send_nice_write('h18, 32'd64);
    send_nice_write('h1c, 32'd256);
    send_nice_write('h00, 32'd1);
    while (!sys_valid) @(posedge clk);
    if (sys_write) $fatal(1, "first transaction was unexpectedly a write");
    begin
      logic [31:0] held_addr;
      held_addr = sys_addr;
      repeat (2) begin
        @(posedge clk); #1;
        if (!sys_valid || sys_addr !== held_addr || sys_ready)
          $fatal(1, "System-Bus read was not held under backpressure");
      end
    end
    @(negedge clk); sys_ready = 1'b1;
    @(posedge clk); #1;
    sys_ready = 1'b0;
    if (!dut.u_system_bus.busy)
      $fatal(1, "accepted read did not create a pending response");
    @(negedge clk); rst_n = 1'b0;
    @(posedge clk); #1;
    if (sys_valid || tile_busy || accel_error || dut.u_system_bus.busy ||
        macro_cen !== {24{1'b1}})
      $fatal(1, "reset did not cancel pending integrated transaction");
    sys_rsp_valid = 1'b0;
    rst_n = 1'b1;
    repeat (2) @(posedge clk);
    if (sys_valid || tile_busy || accel_error)
      $fatal(1, "stale task or error survived reset");
    $display("CHECK pending read cancellation and restart state PASS");
    $display("PASS fp32_sram_top_exception checks=3 cycles=%0d scope=functional_model", cycles);
    $finish;
  end

  initial begin
    #200000;
    $fatal(1, "fp32_sram_top_exception timeout cycle=%0d", cycles);
  end
endmodule
