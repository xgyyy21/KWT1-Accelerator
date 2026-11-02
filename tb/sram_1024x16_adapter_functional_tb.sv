`timescale 1ns/1ps
// Behavioral end-to-end SRAM adapter test using the project functional model.
// It covers macro-boundary addresses, the final word, alternating access,
// response backpressure, standby request blocking, and reset retention.
module sram_1024x16_adapter_functional_tb;
  localparam logic [2:0] EMA = 3'd2;
  localparam logic [1:0] EMAW = 2'd3;
  logic clk = 1'b0;
  always #5 clk = ~clk;
  // Start high and assert reset after time zero so the negedge reset branch
  // executes in simulators that do not schedule an event for 0 -> 0.
  logic rst_n = 1'b1, standby = 1'b0;
  logic req_valid = 1'b0, req_write = 1'b0;
  logic [9:0] req_addr = '0;
  logic [15:0] req_wdata = '0;
  wire req_ready, rsp_valid;
  logic rsp_ready = 1'b1;
  wire [15:0] rsp_data;
  wire [7:0] macro_cen, macro_gwen, macro_ret1n;
  wire [7:0][15:0] macro_wen, macro_d, macro_q;
  wire [7:0][6:0] macro_a;
  wire [7:0][2:0] macro_ema;
  wire [7:0][1:0] macro_emaw;
  integer reads = 0, writes = 0, checks = 0;

  sram_1024x16_adapter #(.EMA_VALUE(EMA), .EMAW_VALUE(EMAW)) dut (.*);
  for (genvar s = 0; s < 8; s++) begin : g_macro
    ramsp128x16_functional_model u_model (
      .CLK(clk), .CEN(macro_cen[s]), .GWEN(macro_gwen[s]), .WEN(macro_wen[s]),
      .A(macro_a[s]), .D(macro_d[s]), .Q(macro_q[s]),
      .EMA(macro_ema[s]), .EMAW(macro_emaw[s]), .RET1N(macro_ret1n[s])
    );
  end

  task automatic write_word(input logic [9:0] addr, input logic [15:0] data);
    begin
      @(negedge clk);
      while (!req_ready) @(negedge clk);
      req_valid = 1'b1; req_write = 1'b1; req_addr = addr; req_wdata = data;
      @(posedge clk); #1;
      req_valid = 1'b0; req_write = 1'b0;
      @(negedge clk); #1;
      if (rsp_valid) $fatal(1, "write generated response addr=%0d", addr);
      writes = writes + 1;
    end
  endtask

  task automatic read_word(input logic [9:0] addr, input logic [15:0] expected);
    logic [15:0] actual;
    begin
      @(negedge clk);
      while (!req_ready) @(negedge clk);
      req_valid = 1'b1; req_write = 1'b0; req_addr = addr; req_wdata = '0;
      @(posedge clk); #1;
      req_valid = 1'b0;
      while (!rsp_valid) @(negedge clk);
      #1; actual = rsp_data;
      if (actual !== expected)
        $fatal(1, "read mismatch addr=%0d got=%h expected=%h", addr, actual, expected);
      checks = checks + 1; reads = reads + 1;
      @(posedge clk); #1;
      if (rsp_valid) $fatal(1, "read response did not retire addr=%0d", addr);
    end
  endtask

  initial begin
    #1 rst_n = 1'b0;
    repeat (2) @(negedge clk);
    if (req_ready !== 1'b0) $fatal(1, "reset accepted request");
    rst_n = 1'b1;

    // Address 127/128 exercise two physical macros; 1023 is the final word.
    write_word(10'd127, 16'h127a);
    write_word(10'd128, 16'h128b);
    write_word(10'd1023, 16'h3ffc);
    read_word(10'd127, 16'h127a);
    read_word(10'd128, 16'h128b);
    read_word(10'd1023, 16'h3ffc);

    // Hold a response and verify the next request cannot alter macro pins.
    rsp_ready = 1'b0;
    @(negedge clk);
    while (!req_ready) @(negedge clk);
    req_valid = 1'b1; req_write = 1'b0; req_addr = 10'd127;
    @(posedge clk); #1 req_valid = 1'b0;
    while (!rsp_valid) @(negedge clk);
    if (req_ready) $fatal(1, "read response did not backpressure request");
    repeat (3) begin
      @(posedge clk); #1;
      if (!rsp_valid || req_ready || macro_cen !== 8'hff)
        $fatal(1, "response hold/backpressure failed");
    end
    rsp_ready = 1'b1;
    @(posedge clk); #1;
    if (rsp_valid) $fatal(1, "held response did not retire");

    // Standby blocks acceptance and keeps all macros deselected.
    @(negedge clk); standby = 1'b1; req_valid = 1'b1; req_write = 1'b1;
    req_addr = 10'd128; req_wdata = 16'hface; #1;
    if (req_ready || macro_cen !== 8'hff) $fatal(1, "standby did not block request");
    @(posedge clk); #1;
    @(negedge clk); standby = 1'b0;
    #1;
    if (!req_ready) $fatal(1, "request did not resume after standby");
    @(posedge clk); #1 req_valid = 1'b0; req_write = 1'b0;
    @(negedge clk); #1;
    if (macro_cen[1] !== 1'b0 || macro_a[1] !== 7'd0 || macro_d[1] !== 16'hface)
      $fatal(1, "held standby request was not issued correctly");
    @(posedge clk); #1;
    writes = writes + 1;
    @(negedge clk); #1;
    if (macro_cen !== 8'hff) $fatal(1, "macro did not return idle after standby write");

    // Adapter reset must cancel protocol state but the SRAM model has no reset;
    // previously stored data must remain readable after restart.
    @(negedge clk); rst_n = 1'b0; #1;
    if (req_ready || rsp_valid || macro_cen !== 8'hff)
      $fatal(1, "reset did not suppress adapter pins");
    @(posedge clk); @(negedge clk); rst_n = 1'b1;
    read_word(10'd127, 16'h127a);
    // The request held during standby is accepted after wake-up and therefore
    // intentionally replaces address 128 with 0xface.
    read_word(10'd128, 16'hface);
    read_word(10'd1023, 16'h3ffc);

    $display("PASS sram_1024x16_adapter_functional_tb writes=%0d reads=%0d checks=%0d boundary=127,128,1023 standby=1 reset_retention=1",
             writes, reads, checks);
    $finish;
  end
  initial begin
    #200000;
    $fatal(1, "SRAM adapter functional test timeout");
  end
endmodule
