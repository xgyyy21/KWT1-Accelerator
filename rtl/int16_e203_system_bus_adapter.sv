// E203-facing INT16 adapter.
//
// The control plane is the 32-bit sysper ICB slave.  Matrix traffic leaves
// the accelerator through the 32-bit ext2dtcm ICB agent interface.  The
// accelerator internally produces byte addresses; this wrapper checks the
// complete DTCM window before translating a valid address to the E203 local
// DTCM offset.  An out-of-window request is accepted and completed with an
// error response, rather than being silently aliased by truncating address
// bits.
module int16_e203_system_bus_adapter #(
  parameter int ADDR_WIDTH = 32,
  parameter int DTCM_ADDR_WIDTH = 18,
  parameter logic [ADDR_WIDTH-1:0] CTRL_BASE = 32'h1100_0000,
  parameter logic [ADDR_WIDTH-1:0] DTCM_BASE = 32'h9000_0000,
  parameter bit STRICT_COMPETITION_SHAPES = 1'b0
) (
  input  logic clk,
  input  logic rst_n,

  input  logic sysper_icb_cmd_valid,
  output logic sysper_icb_cmd_ready,
  input  logic [ADDR_WIDTH-1:0] sysper_icb_cmd_addr,
  input  logic sysper_icb_cmd_read,
  input  logic [31:0] sysper_icb_cmd_wdata,
  input  logic [3:0] sysper_icb_cmd_wmask,
  output logic sysper_icb_rsp_valid,
  input  logic sysper_icb_rsp_ready,
  output logic [31:0] sysper_icb_rsp_rdata,
  output logic sysper_icb_rsp_err,

  output logic ext2dtcm_icb_cmd_valid,
  input  logic ext2dtcm_icb_cmd_ready,
  output logic [DTCM_ADDR_WIDTH-1:0] ext2dtcm_icb_cmd_addr,
  output logic ext2dtcm_icb_cmd_read,
  output logic [31:0] ext2dtcm_icb_cmd_wdata,
  output logic [3:0] ext2dtcm_icb_cmd_wmask,
  input  logic ext2dtcm_icb_rsp_valid,
  output logic ext2dtcm_icb_rsp_ready,
  input  logic [31:0] ext2dtcm_icb_rsp_rdata,
  input  logic ext2dtcm_icb_rsp_err,

  output logic accel_busy,
  output logic accel_done,
  output logic accel_error
);
  localparam longint unsigned DTCM_SIZE_BYTES = (64'd1 << DTCM_ADDR_WIDTH);
  localparam logic [ADDR_WIDTH-1:0] DTCM_LIMIT =
    DTCM_BASE + DTCM_SIZE_BYTES[ADDR_WIDTH-1:0];

  logic m_cmd_valid;
  logic m_cmd_ready;
  logic [ADDR_WIDTH-1:0] m_cmd_addr;
  logic m_cmd_read;
  logic [31:0] m_cmd_wdata;
  logic [3:0] m_cmd_wmask;
  logic m_rsp_valid;
  logic m_rsp_ready;
  logic [31:0] m_rsp_rdata;
  logic m_rsp_err;

  logic local_error_valid;
  logic local_error_ready;
  logic command_in_window;
  logic command_aligned;
  logic command_is_valid;

  assign command_in_window = (m_cmd_addr >= DTCM_BASE) &&
                             (m_cmd_addr < DTCM_LIMIT);
  assign command_aligned = (m_cmd_addr[1:0] == 2'b00);
  assign command_is_valid = command_in_window && command_aligned;

  int16_accelerator_top #(
    .ADDR_WIDTH(ADDR_WIDTH),
    .CTRL_BASE(CTRL_BASE),
    .STRICT_COMPETITION_SHAPES(STRICT_COMPETITION_SHAPES)
  ) u_accelerator (
    .clk(clk), .rst_n(rst_n),
    .s_icb_cmd_valid(sysper_icb_cmd_valid),
    .s_icb_cmd_ready(sysper_icb_cmd_ready),
    .s_icb_cmd_addr(sysper_icb_cmd_addr),
    .s_icb_cmd_read(sysper_icb_cmd_read),
    .s_icb_cmd_wdata(sysper_icb_cmd_wdata),
    .s_icb_cmd_wmask(sysper_icb_cmd_wmask),
    .s_icb_rsp_valid(sysper_icb_rsp_valid),
    .s_icb_rsp_ready(sysper_icb_rsp_ready),
    .s_icb_rsp_rdata(sysper_icb_rsp_rdata),
    .s_icb_rsp_err(sysper_icb_rsp_err),
    .m_icb_cmd_valid(m_cmd_valid),
    .m_icb_cmd_ready(m_cmd_ready),
    .m_icb_cmd_addr(m_cmd_addr),
    .m_icb_cmd_read(m_cmd_read),
    .m_icb_cmd_wdata(m_cmd_wdata),
    .m_icb_cmd_wmask(m_cmd_wmask),
    .m_icb_rsp_valid(m_rsp_valid),
    .m_icb_rsp_ready(m_rsp_ready),
    .m_icb_rsp_rdata(m_rsp_rdata),
    .m_icb_rsp_err(m_rsp_err),
    .accel_busy(accel_busy), .accel_done(accel_done),
    .accel_error(accel_error), .current_row(), .current_col(),
    .current_k(), .current_k_block()
  );

  // Invalid addresses are accepted by the accelerator-side handshake and
  // completed locally with an error.  No invalid command reaches DTCM.
  assign local_error_ready = m_rsp_ready;
  assign m_cmd_ready = local_error_valid ? 1'b0 :
                       (command_is_valid ? ext2dtcm_icb_cmd_ready : 1'b1);
  assign ext2dtcm_icb_cmd_valid = m_cmd_valid && command_is_valid &&
                                  !local_error_valid;
  assign ext2dtcm_icb_cmd_addr = DTCM_ADDR_WIDTH'(m_cmd_addr - DTCM_BASE);
  assign ext2dtcm_icb_cmd_read = m_cmd_read;
  assign ext2dtcm_icb_cmd_wdata = m_cmd_wdata;
  assign ext2dtcm_icb_cmd_wmask = m_cmd_wmask;

  assign m_rsp_valid = local_error_valid || ext2dtcm_icb_rsp_valid;
  assign m_rsp_rdata = local_error_valid ? 32'd0 : ext2dtcm_icb_rsp_rdata;
  assign m_rsp_err = local_error_valid || ext2dtcm_icb_rsp_err;
  assign ext2dtcm_icb_rsp_ready = m_rsp_ready && !local_error_valid;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      local_error_valid <= 1'b0;
    end else begin
      if (local_error_valid && local_error_ready)
        local_error_valid <= 1'b0;
      if (m_cmd_valid && m_cmd_ready && !command_is_valid)
        local_error_valid <= 1'b1;
    end
  end

`ifndef SYNTHESIS
  initial begin
    if (ADDR_WIDTH != 32)
      $fatal(1, "INT16 E203 adapter requires 32-bit global addresses");
    if (DTCM_ADDR_WIDTH < 2 || DTCM_ADDR_WIDTH > ADDR_WIDTH)
      $fatal(1, "invalid DTCM address width");
  end
`endif
endmodule
