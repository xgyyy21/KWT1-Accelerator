`timescale 1ns/1ps
module sram_macro_check_top (
  input  logic clk,
  input  logic rst_n,
  input  logic [2:0] standby,
  input  logic [2:0] req_valid,
  output wire  [2:0] req_ready,
  input  logic [2:0] req_write,
  input  logic [2:0][9:0] req_addr,
  input  logic [2:0][15:0] req_wdata,
  output wire  [2:0] rsp_valid,
  input  logic [2:0] rsp_ready,
  output wire  [2:0][15:0] rsp_data
);
  wire [23:0] macro_cen, macro_gwen, macro_ret1n;
  wire [23:0][15:0] macro_wen, macro_d, macro_q;
  wire [23:0][6:0] macro_a;
  wire [23:0][2:0] macro_ema;
  wire [23:0][1:0] macro_emaw;

  sram_fp32_cache_adapter u_adapter (
    .clk(clk), .rst_n(rst_n), .standby(standby),
    .req_valid(req_valid), .req_ready(req_ready),
    .req_write(req_write), .req_addr(req_addr), .req_wdata(req_wdata),
    .rsp_valid(rsp_valid), .rsp_ready(rsp_ready), .rsp_data(rsp_data),
    .macro_cen(macro_cen), .macro_gwen(macro_gwen),
    .macro_wen(macro_wen), .macro_a(macro_a), .macro_d(macro_d),
    .macro_q(macro_q), .macro_ema(macro_ema), .macro_emaw(macro_emaw),
    .macro_ret1n(macro_ret1n)
  );

  for (genvar slot = 0; slot < 24; slot++) begin : g_macro
    RAMSP128X16 u_macro (
      .CLK(clk), .CEN(macro_cen[slot]), .GWEN(macro_gwen[slot]),
      .WEN(macro_wen[slot]), .A(macro_a[slot]), .D(macro_d[slot]),
      .Q(macro_q[slot]), .EMA(macro_ema[slot]),
      .EMAW(macro_emaw[slot]), .RET1N(macro_ret1n[slot])
    );
  end
endmodule
