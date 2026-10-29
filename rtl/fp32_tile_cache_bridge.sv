// Single-port arbitration between DMA writes and streamer reads.
// wr_en/rd_en are request-valid signals: keep address/data until *_ready.
// Writes have priority within each bank. Different banks remain independent.
module fp32_tile_cache_bridge #(
  parameter int ADDR_WIDTH = 10,
  parameter bit USE_SRAM_MACROS = 1'b0
) (
  input logic clk, rst_n,
  input logic [2:0] standby,
  input logic [2:0] wr_valid,
  output wire [2:0] wr_ready,
  input logic [2:0][ADDR_WIDTH-1:0] wr_addr,
  input logic [2:0][15:0] wr_data,
  input logic [2:0] rd_valid,
  output wire [2:0] rd_ready,
  input logic [2:0][ADDR_WIDTH-1:0] rd_addr,
  output wire [2:0] rsp_valid,
  output wire [2:0][15:0] rsp_data,
  output wire [23:0] macro_cen, macro_gwen,
  output wire [23:0][15:0] macro_wen,
  output wire [23:0][6:0] macro_a,
  output wire [23:0][15:0] macro_d,
  input wire [23:0][15:0] macro_q,
  output wire [23:0][2:0] macro_ema,
  output wire [23:0][1:0] macro_emaw,
  output wire [23:0] macro_ret1n
);
  wire [2:0] port_ready;
  assign wr_ready = port_ready;
  assign rd_ready = port_ready & ~wr_valid;
  if (USE_SRAM_MACROS) begin : g_macro
    wire [2:0][9:0] port_addr;
    for (genvar bank = 0; bank < 3; bank++) begin : g_addr
      assign port_addr[bank] = wr_valid[bank] ? wr_addr[bank] : rd_addr[bank];
    end
`ifndef SYNTHESIS
    initial if (ADDR_WIDTH != 10) $fatal(1, "Macro cache requires 10-bit word addresses");
`endif
    sram_fp32_cache_adapter u_macro (
      .clk(clk), .rst_n(rst_n), .standby(standby),
      .req_valid(wr_valid | rd_valid), .req_ready(port_ready),
      .req_write(wr_valid), .req_addr(port_addr), .req_wdata(wr_data),
      .rsp_valid(rsp_valid), .rsp_ready(3'b111), .rsp_data(rsp_data),
      .macro_cen(macro_cen), .macro_gwen(macro_gwen), .macro_wen(macro_wen),
      .macro_a(macro_a), .macro_d(macro_d), .macro_q(macro_q),
      .macro_ema(macro_ema), .macro_emaw(macro_emaw), .macro_ret1n(macro_ret1n)
    );
  end else begin : g_behavioral
    // Preserve the historical storage model, but enforce the same single-port
    // client contract here. Unconnected standby pins are ignored in this mode.
    assign port_ready = {3{rst_n}};
    matrix_cache_manager #(.DATA_WIDTH(16), .ADDR_WIDTH(ADDR_WIDTH),
                           .DEPTH(1 << ADDR_WIDTH)) u_memory (
      .clk(clk), .rst_n(rst_n),
      .a_wr_en(wr_valid[0] && wr_ready[0]), .a_wr_addr(wr_addr[0]), .a_wr_data(wr_data[0]),
      .b_wr_en(wr_valid[1] && wr_ready[1]), .b_wr_addr(wr_addr[1]), .b_wr_data(wr_data[1]),
      .result_wr_en(wr_valid[2] && wr_ready[2]), .result_wr_addr(wr_addr[2]), .result_wr_data(wr_data[2]),
      .a_rd_en(rd_valid[0] && rd_ready[0]), .a_rd_addr(rd_addr[0]), .a_rd_valid(rsp_valid[0]), .a_rd_data(rsp_data[0]),
      .b_rd_en(rd_valid[1] && rd_ready[1]), .b_rd_addr(rd_addr[1]), .b_rd_valid(rsp_valid[1]), .b_rd_data(rsp_data[1]),
      .result_rd_en(rd_valid[2] && rd_ready[2]), .result_rd_addr(rd_addr[2]), .result_rd_valid(rsp_valid[2]), .result_rd_data(rsp_data[2])
    );
    assign macro_cen = '1;
    assign macro_gwen = '1;
    assign macro_wen = '1;
    assign macro_a = '0;
    assign macro_d = '0;
    assign macro_ema = {24{3'd2}};
    assign macro_emaw = {24{2'd3}};
    assign macro_ret1n = '1;
  end
endmodule
