`timescale 1ns/1ps
// One logical 1024 x 16 single port, built from eight 128 x 16 macro ports.
// This module exports physical pins; it does not infer or model SRAM storage.
// Requests are accepted on posedge. A queued command is driven on negedge,
// sampled by the macro on the following posedge, and held until the next
// negedge so macro input hold time is not violated by post-edge handshake
// changes. Read response becomes valid after the macro sampling edge.
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
  logic command_pending;
  logic command_write;
  logic [9:0] command_addr;
  logic [15:0] command_wdata;
  wire request_fire = req_valid && req_ready;

  assign req_ready = rst_n && !standby && !command_pending &&
                     (!rsp_valid || rsp_ready);
  assign rsp_data = rsp_valid ? macro_q[response_slot] : 16'b0;

  for (genvar slot = 0; slot < 8; slot++) begin : g_settings
    assign macro_ema[slot] = EMA_VALUE;
    assign macro_emaw[slot] = EMAW_VALUE;
    assign macro_ret1n[slot] = 1'b1; // No dynamic retention transitions.
  end

  // Capture the request before presenting it to the SRAM on a falling edge.
  // The macro then samples stable pins at the next rising edge.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      command_pending <= 1'b0;
      command_write <= 1'b0;
      command_addr <= 10'b0;
      command_wdata <= 16'b0;
      rsp_valid <= 1'b0;
      response_slot <= 3'b0;
    end else begin
      if (request_fire) begin
        command_pending <= 1'b1;
        command_write <= req_write;
        command_addr <= req_addr;
        command_wdata <= req_wdata;
        if (!req_write)
          response_slot <= req_addr[9:7];
      end else begin
        command_pending <= 1'b0;
      end

      if (rsp_valid && rsp_ready)
        rsp_valid <= 1'b0;
      if (command_pending && !command_write)
        rsp_valid <= 1'b1;
    end
  end

  // Macro controls only transition on falling edges. They remain unchanged
  // across the rising edge at which the SRAM samples them, including when
  // rsp_valid changes and req_ready is backpressured.
  always_ff @(negedge clk or negedge rst_n) begin
    if (!rst_n) begin
      macro_cen <= '1;
      macro_gwen <= '1;
      macro_wen <= '1;
      macro_a <= '0;
      macro_d <= '0;
    end else begin
      macro_cen <= '1;
      macro_gwen <= '1;
      macro_wen <= '1;
      macro_a <= '0;
      macro_d <= '0;
      if (command_pending) begin
        macro_cen[command_addr[9:7]] <= 1'b0;
        macro_gwen[command_addr[9:7]] <= !command_write;
        macro_wen[command_addr[9:7]] <= command_write ? 16'h0000 : 16'hffff;
        macro_a[command_addr[9:7]] <= command_addr[6:0];
        macro_d[command_addr[9:7]] <= command_wdata;
      end
    end
  end
endmodule
