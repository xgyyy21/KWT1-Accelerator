`timescale 1ns/1ps
module fp32_tile_cache_bridge_tb;
  logic clk = 0;
  always #5 clk = ~clk;
  logic rst_n = 0;
  logic [2:0] standby = 0, wr_valid = 0, rd_valid = 0;
  logic [2:0][9:0] wr_addr = 0, rd_addr = 0;
  logic [2:0][15:0] wr_data = 0;
  wire [2:0] wr_ready, rd_ready, rsp_valid;
  wire [2:0][15:0] rsp_data;
  wire [23:0] macro_cen, macro_gwen, macro_ret1n;
  wire [23:0][15:0] macro_wen, macro_d, macro_q;
  wire [23:0][6:0] macro_a;
  wire [23:0][2:0] macro_ema;
  wire [23:0][1:0] macro_emaw;
  fp32_tile_cache_bridge #(.USE_SRAM_MACROS(1'b1)) dut (.*);
  for (genvar m = 0; m < 24; m++) begin : g_memory
    ramsp128x16_functional_model u_mem (
      .CLK(clk), .CEN(macro_cen[m]), .GWEN(macro_gwen[m]), .WEN(macro_wen[m]),
      .A(macro_a[m]), .D(macro_d[m]), .Q(macro_q[m]),
      .EMA(macro_ema[m]), .EMAW(macro_emaw[m]), .RET1N(macro_ret1n[m])
    );
  end
  initial begin
    repeat (2) @(negedge clk);
    rst_n = 1;
    wr_valid = 3'b111;
    wr_addr = {10'd1023,10'd128,10'd127};
    wr_data = {16'h3333,16'h2222,16'h1111};
    @(posedge clk); #1;
    if (wr_ready !== 3'b111 || rsp_valid !== 0) $fatal(1,"Initial writes failed");
    @(negedge clk);
    wr_valid = 3'b001;
    wr_data[0] = 16'ha55a;
    rd_valid = 3'b111;
    rd_addr = wr_addr;
    #1;
    if (rd_ready !== 3'b110) $fatal(1,"Write must block same-bank read only");
    @(posedge clk); #1;
    if (rsp_valid !== 3'b110 || rsp_data[1] !== 16'h2222 || rsp_data[2] !== 16'h3333)
      $fatal(1,"Independent bank reads failed during bank A collision");
    @(negedge clk);
    wr_valid = 0;
    rd_valid = 3'b001;
    standby = 3'b001;
    #1;
    if (rd_ready[0] !== 0) $fatal(1,"Standby did not stall pending read");
    @(posedge clk); #1;
    if (rsp_valid !== 0 || macro_cen !== 24'hffffff) $fatal(1,"Standby issued a request");
    @(negedge clk); standby = 0;
    @(posedge clk); #1;
    if (rsp_valid !== 3'b001 || rsp_data[0] !== 16'ha55a)
      $fatal(1,"Deferred read did not observe accepted write");
    @(negedge clk); rd_valid = 0;
    @(posedge clk); #1;
    if (rsp_valid !== 0) $fatal(1,"Duplicate response");
    $display("PASS cache_bridge arbitration=write_priority independent_banks=3 standby_resume=1");
    $finish;
  end
  initial begin
    #1000;
    $fatal(1,"Cache bridge timeout");
  end
endmodule
