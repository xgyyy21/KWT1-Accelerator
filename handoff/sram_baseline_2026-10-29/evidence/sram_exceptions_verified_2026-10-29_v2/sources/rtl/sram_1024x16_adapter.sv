`timescale 1ns/1ps
// One logical 1024 x 16 single port, built from eight 128 x 16 macro ports.
// This module exports physical pins; it does not infer or model SRAM storage.
// Read request accepted at E: Q/response valid after E, consumed at E+1.
// A stalled read response blocks all further requests to this logical bank.
module sram_1024x16_adapter #(
  parameter logic [2:0] EMA_VALUE = 3'd2,
  parameter logic [1:0] EMAW_VALUE = 2'd3
) (
  input  logic clk,
  input  logic rst_n,
  input  logic standby,
  input  logic req_valid,
  output logic req_ready,
  input  logic req_write,
  input  logic [9:0] req_addr,
  input  logic [15:0] req_wdata,
  output logic rsp_valid,
  input  logic rsp_ready,
  output logic [15:0] rsp_data,
  output logic [7:0] macro_cen,
  output logic [7:0] macro_gwen,
  output logic [7:0][15:0] macro_wen,
  output logic [7:0][6:0] macro_a,
  output logic [7:0][15:0] macro_d,
  input  wire  [7:0][15:0] macro_q,
  output wire  [7:0][2:0] macro_ema,
  output wire  [7:0][1:0] macro_emaw,
  output wire  [7:0] macro_ret1n
);
  logic [2:0] response_slot;
  wire request_fire = req_valid && req_ready;

  assign req_ready = rst_n && !standby && (!rsp_valid || rsp_ready);
  assign rsp_data = rsp_valid ? macro_q[response_slot] : 16'b0;

  for (genvar slot = 0; slot < 8; slot++) begin : g_settings
    wire selected = request_fire && (req_addr[9:7] == 3'(slot));
    assign macro_cen[slot] = !selected;
    assign macro_gwen[slot] = !(selected && req_write);
    assign macro_wen[slot] = (selected && req_write) ? 16'h0000 : 16'hffff;
    assign macro_a[slot] = selected ? req_addr[6:0] : 7'b0;
    assign macro_d[slot] = selected ? req_wdata : 16'b0;
    assign macro_ema[slot] = EMA_VALUE;
    assign macro_emaw[slot] = EMAW_VALUE;
    assign macro_ret1n[slot] = 1'b1; // No dynamic retention transitions.
  end

  // Only response/control state is reset. The macros have no reset pin.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rsp_valid <= 1'b0;
      response_slot <= 3'b0;
    end else if (request_fire) begin
      rsp_valid <= !req_write;
      if (!req_write)
        response_slot <= req_addr[9:7];
    end else if (rsp_valid && rsp_ready) begin
      rsp_valid <= 1'b0;
    end
  end
endmodule
