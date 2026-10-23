// Control-plane adapter for the competition architecture.
//
// NICE carries configuration and status.  Matrix payloads do not pass through
// this module; they use the separate System-Bus/DMA data path.  The port names
// are intentionally a small internal request/response contract.  The E203
// platform wrapper is responsible for mapping its final NICE signal names to
// these ports.
module fp32_nice_control_adapter #(
  parameter int ADDR_WIDTH = 32,
  parameter int DATA_WIDTH = 32
) (
  input  logic                   clk,
  input  logic                   rst_n,
  input  logic                   nice_req_valid,
  input  logic                   nice_req_write,
  input  logic [ADDR_WIDTH-1:0]  nice_req_addr,
  input  logic [DATA_WIDTH-1:0]  nice_req_wdata,
  output logic                   nice_req_ready,
  output logic                   nice_rsp_valid,
  output logic [DATA_WIDTH-1:0]  nice_rsp_rdata,
  input  logic                   engine_busy,
  input  logic                   engine_done,
  input  logic                   engine_error,
  output logic                   engine_start,
  output logic [ADDR_WIDTH-1:0]  src_a_base,
  output logic [ADDR_WIDTH-1:0]  src_b_base,
  output logic [ADDR_WIDTH-1:0]  bias_base,
  output logic [ADDR_WIDTH-1:0]  dst_base,
  output logic [15:0]            matrix_m,
  output logic [15:0]            matrix_k,
  output logic [15:0]            matrix_n
);
  ai_engine_regs #(
    .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)
  ) u_regs (
    .clk(clk), .rst_n(rst_n),
    .req_valid(nice_req_valid), .req_write(nice_req_write),
    .req_addr(nice_req_addr), .req_wdata(nice_req_wdata),
    .req_ready(nice_req_ready), .rsp_valid(nice_rsp_valid),
    .rsp_rdata(nice_rsp_rdata), .engine_busy(engine_busy),
    .engine_done(engine_done), .engine_error(engine_error),
    .engine_start(engine_start), .src_a_base(src_a_base),
    .src_b_base(src_b_base), .bias_base(bias_base), .dst_base(dst_base),
    .matrix_m(matrix_m),
    .matrix_k(matrix_k), .matrix_n(matrix_n)
  );
endmodule
