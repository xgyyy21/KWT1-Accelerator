`timescale 1ns/1ps
// Sixteen-bank INT16 weight tile storage. Bank i stores one output lane.
// A read broadcasts one K address and returns one cycle later. Each bank has
// one single-port operation per clock; a bus word may write two banks.
// Define INT16_USE_RAMSP128X16 when compiling against the real macro library.
module int16_weight_sram_16bank #(
  parameter int LANES = 16,
  parameter logic [2:0] EMA_VALUE = 3'd2,
  parameter logic [1:0] EMAW_VALUE = 2'd3
) (
  input  logic clk,
  input  logic rst_n,
  input  logic rd_en,
  input  logic [6:0] rd_addr,
  output logic rd_valid,
  output logic [LANES*16-1:0] rd_data_bus,
  input  logic [LANES-1:0] wr_en,
  input logic [6:0] wr_addr,
  input logic [LANES*16-1:0] wr_data_bus
);
  wire [LANES*16-1:0] macro_q_bus;

`ifdef INT16_USE_RAMSP128X16
  `define INT16_WEIGHT_USE_MACRO
`elsif SYNTHESIS
  `define INT16_WEIGHT_USE_MACRO
`endif

`ifdef INT16_WEIGHT_USE_MACRO
  for (genvar bank = 0; bank < LANES; bank = bank + 1) begin : g_macro
    wire [15:0] macro_q;
    assign macro_q_bus[bank*16 +: 16] = macro_q;
    RAMSP128X16 u_weight_bank (
      .CLK(clk), .CEN(!(rd_en || wr_en[bank])), .GWEN(!wr_en[bank]),
      .WEN(wr_en[bank] ? 16'h0000 : 16'hffff),
      .A(wr_en[bank] ? wr_addr : rd_addr),
      .D(wr_data_bus[bank*16 +: 16]), .Q(macro_q),
      .EMA(EMA_VALUE), .EMAW(EMAW_VALUE), .RET1N(1'b1));
  end
`else
  // One-dimensional fallback model: 16 banks x 128 words.
  logic [15:0] mem [0:LANES*128-1];
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rd_valid <= 1'b0;
      rd_data_bus <= '0;
    end else begin
      rd_valid <= rd_en;
      if (rd_en)
        for (int bank = 0; bank < LANES; bank = bank + 1)
          rd_data_bus[bank*16 +: 16] <= mem[bank*128 + rd_addr];
      for (int bank = 0; bank < LANES; bank = bank + 1)
        if (wr_en[bank]) mem[bank*128 + wr_addr] <= wr_data_bus[bank*16 +: 16];
    end
  end
`endif

`ifdef INT16_WEIGHT_USE_MACRO
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) rd_valid <= 1'b0;
    else rd_valid <= rd_en;
  end
  always_comb rd_data_bus = macro_q_bus;
`endif
`ifdef INT16_WEIGHT_USE_MACRO
  `undef INT16_WEIGHT_USE_MACRO
`endif
endmodule
