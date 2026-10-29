`timescale 1ns/1ps
// Capacity-preserving macro port organization for the teacher's three banks.
// Bank 0=A, 1=B, 2=C (currently bias in the FP32 compute path).
// Flat macro number = 8 * bank + local slot. Each bank accepts <=1 word/cycle.
module sram_fp32_cache_adapter #(
  parameter logic [2:0] EMA_VALUE = 3'd2,
  parameter logic [1:0] EMAW_VALUE = 2'd3
) (
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
  output wire  [2:0][15:0] rsp_data,
  output wire  [23:0] macro_cen,
  output wire  [23:0] macro_gwen,
  output wire  [23:0][15:0] macro_wen,
  output wire  [23:0][6:0] macro_a,
  output wire  [23:0][15:0] macro_d,
  input  wire  [23:0][15:0] macro_q,
  output wire  [23:0][2:0] macro_ema,
  output wire  [23:0][1:0] macro_emaw,
  output wire  [23:0] macro_ret1n
);
  for (genvar bank = 0; bank < 3; bank++) begin : g_bank
    sram_1024x16_adapter #(.EMA_VALUE(EMA_VALUE), .EMAW_VALUE(EMAW_VALUE)) u_bank (
      .clk(clk), .rst_n(rst_n), .standby(standby[bank]),
      .req_valid(req_valid[bank]), .req_ready(req_ready[bank]),
      .req_write(req_write[bank]), .req_addr(req_addr[bank]),
      .req_wdata(req_wdata[bank]), .rsp_valid(rsp_valid[bank]),
      .rsp_ready(rsp_ready[bank]), .rsp_data(rsp_data[bank]),
      .macro_cen(macro_cen[bank*8 +: 8]),
      .macro_gwen(macro_gwen[bank*8 +: 8]),
      .macro_wen(macro_wen[bank*8 +: 8]),
      .macro_a(macro_a[bank*8 +: 8]),
      .macro_d(macro_d[bank*8 +: 8]),
      .macro_q(macro_q[bank*8 +: 8]),
      .macro_ema(macro_ema[bank*8 +: 8]),
      .macro_emaw(macro_emaw[bank*8 +: 8]),
      .macro_ret1n(macro_ret1n[bank*8 +: 8])
    );
  end
endmodule
