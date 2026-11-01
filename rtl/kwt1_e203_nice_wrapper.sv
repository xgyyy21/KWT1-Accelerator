// Standalone E203 NICE wrapper for KWT-1 control integration.
//
// This module deliberately keeps the KWT-1 payload path on the existing
// 16-bit System Bus.  The NICE ICB memory channel is left inactive until the
// platform-level DMA choice is jointly frozen.
module kwt1_e203_nice_wrapper #(
  parameter int E203_XLEN = 32,
  parameter int E203_ADDR_SIZE = 32,
  parameter logic [6:0] KWT_OPCODE = 7'h7b,
  parameter logic [6:0] KWT_FUNCT7 = 7'h00,
  parameter bit STRICT_COMPETITION_SHAPES = 1'b1,
  parameter bit USE_SRAM_MACROS = 1'b0
) (
  input  logic                         nice_clk,
  input  logic                         nice_rst_n,
  output logic                         nice_active,
  output logic                         nice_mem_holdup,

  input  logic                         nice_req_valid,
  output logic                         nice_req_ready,
  input  logic [E203_XLEN-1:0]         nice_req_inst,
  input  logic [E203_XLEN-1:0]         nice_req_rs1,
  input  logic [E203_XLEN-1:0]         nice_req_rs2,

  output logic                         nice_rsp_valid,
  input  logic                         nice_rsp_ready,
  output logic [E203_XLEN-1:0]         nice_rsp_rdat,
  output logic                         nice_rsp_err,

  output logic                         nice_icb_cmd_valid,
  input  logic                         nice_icb_cmd_ready,
  output logic [E203_ADDR_SIZE-1:0]    nice_icb_cmd_addr,
  output logic                         nice_icb_cmd_read,
  output logic [E203_XLEN-1:0]         nice_icb_cmd_wdata,
  output logic [1:0]                   nice_icb_cmd_size,
  input  logic                         nice_icb_rsp_valid,
  output logic                         nice_icb_rsp_ready,
  input  logic [E203_XLEN-1:0]         nice_icb_rsp_rdata,
  input  logic                         nice_icb_rsp_err,

  input  logic [2:0]                   cache_standby,
  output wire [23:0]                   macro_cen,
  output wire [23:0]                   macro_gwen,
  output wire [23:0][15:0]             macro_wen,
  output wire [23:0][6:0]              macro_a,
  output wire [23:0][15:0]             macro_d,
  input  wire [23:0][15:0]             macro_q,
  output wire [23:0][2:0]              macro_ema,
  output wire [23:0][1:0]              macro_emaw,
  output wire [23:0]                   macro_ret1n,

  output logic                         sys_req_valid,
  output logic                         sys_req_write,
  output logic [E203_ADDR_SIZE-1:0]    sys_req_addr,
  output logic [15:0]                  sys_req_wdata,
  input  logic                         sys_req_ready,
  input  logic                         sys_rsp_valid,
  input  logic [15:0]                  sys_rsp_rdata,

  output logic                         engine_busy,
  output logic                         engine_done,
  output logic                         engine_error
);
  localparam logic [2:0] F_CFG_WRITE = 3'd0;
  localparam logic [2:0] F_CFG_READ  = 3'd1;
  localparam logic [2:0] F_START     = 3'd2;
  localparam logic [2:0] F_STATUS    = 3'd3;
  localparam logic [2:0] F_CLEAR     = 3'd4;

  localparam logic [7:0] A_CTRL = 8'h00;
  localparam logic [7:0] A_STATUS = 8'h04;

  logic [6:0] req_opcode, req_funct7;
  logic [2:0] req_funct3;
  logic req_opcode_ok, req_funct_ok, req_supported;
  logic req_is_read, req_is_write, req_reg_valid;
  logic req_fire;
  logic ctrl_req_valid, ctrl_req_write;
  logic [E203_ADDR_SIZE-1:0] ctrl_req_addr;
  logic [E203_XLEN-1:0] ctrl_req_wdata;
  logic ctrl_req_ready, ctrl_rsp_valid;
  logic [31:0] ctrl_rsp_rdata;
  logic rsp_pending, wait_ctrl_rsp;
  logic [E203_XLEN-1:0] rsp_data_reg;
  logic rsp_err_reg;
  logic accel_start_unused;

  assign req_opcode = nice_req_inst[6:0];
  assign req_funct3 = nice_req_inst[14:12];
  assign req_funct7 = nice_req_inst[31:25];
  assign req_opcode_ok = req_opcode == KWT_OPCODE;
  assign req_funct_ok = req_funct7 == KWT_FUNCT7;
  assign req_is_read = req_funct3 == F_CFG_READ || req_funct3 == F_STATUS;
  assign req_is_write = req_funct3 == F_CFG_WRITE || req_funct3 == F_START ||
                        req_funct3 == F_CLEAR;
  always_comb begin
    req_reg_valid = 1'b0;
    if ((nice_req_rs1 >> 8) == '0 && nice_req_rs1[1:0] == 2'b00) begin
      case (nice_req_rs1[7:0])
        8'h00, 8'h04, 8'h08, 8'h0c, 8'h10,
        8'h14, 8'h18, 8'h1c, 8'h20: req_reg_valid = 1'b1;
        default: req_reg_valid = 1'b0;
      endcase
    end
  end
  assign req_supported = req_opcode_ok && req_funct_ok &&
                         (req_is_read || req_is_write) &&
                         ((req_funct3 != F_CFG_READ && req_funct3 != F_CFG_WRITE) || req_reg_valid);
  assign nice_req_ready = !rsp_pending && !wait_ctrl_rsp;
  assign req_fire = nice_req_valid && nice_req_ready;

  // Reads are allowed while BUSY; writes are accepted and answered with an
  // error while BUSY so the NICE requester cannot deadlock on a held valid.
  always_comb begin
    ctrl_req_valid = 1'b0;
    ctrl_req_write = 1'b0;
    ctrl_req_addr = '0;
    ctrl_req_wdata = '0;
    if (req_fire && req_supported && (!engine_busy || req_is_read)) begin
      ctrl_req_valid = 1'b1;
      if (req_funct3 == F_CFG_READ || req_funct3 == F_CFG_WRITE) begin
        ctrl_req_addr = '0;
        ctrl_req_addr[7:0] = nice_req_rs1[7:0];
      end else if (req_funct3 == F_STATUS) begin
        ctrl_req_addr = '0;
        ctrl_req_addr[7:0] = A_STATUS;
      end else begin
        ctrl_req_addr = '0;
        ctrl_req_addr[7:0] = A_CTRL;
      end

      if (req_funct3 == F_CFG_WRITE) begin
        ctrl_req_write = 1'b1;
        ctrl_req_wdata = nice_req_rs2;
      end else if (req_funct3 == F_START) begin
        ctrl_req_write = 1'b1;
        ctrl_req_wdata = 32'h0000_0001;
      end else if (req_funct3 == F_CLEAR) begin
        ctrl_req_write = 1'b1;
        ctrl_req_wdata = {29'b0, nice_req_rs1[1], nice_req_rs1[0], 1'b0};
      end
    end
  end

  assign ctrl_req_ready = 1'b1;

  // The current platform-neutral accelerator is the implementation behind
  // this wrapper. E203-specific naming and instruction decoding stop here.
  fp32_accelerator_top #(
    .ADDR_WIDTH(E203_ADDR_SIZE),
    .DATA_WIDTH(E203_XLEN),
    .STRICT_COMPETITION_SHAPES(STRICT_COMPETITION_SHAPES),
    .USE_SRAM_MACROS(USE_SRAM_MACROS)
  ) u_accelerator (
    .clk(nice_clk), .rst_n(nice_rst_n), .cache_standby(cache_standby),
    .macro_cen(macro_cen), .macro_gwen(macro_gwen), .macro_wen(macro_wen),
    .macro_a(macro_a), .macro_d(macro_d), .macro_q(macro_q),
    .macro_ema(macro_ema), .macro_emaw(macro_emaw), .macro_ret1n(macro_ret1n),
    .nice_req_valid(ctrl_req_valid), .nice_req_write(ctrl_req_write),
    .nice_req_addr(ctrl_req_addr), .nice_req_wdata(ctrl_req_wdata),
    .nice_req_ready(), .nice_rsp_valid(ctrl_rsp_valid),
    .nice_rsp_rdata(ctrl_rsp_rdata), .sys_req_valid(sys_req_valid),
    .sys_req_write(sys_req_write), .sys_req_addr(sys_req_addr),
    .sys_req_wdata(sys_req_wdata), .sys_req_ready(sys_req_ready),
    .sys_rsp_valid(sys_rsp_valid), .sys_rsp_rdata(sys_rsp_rdata),
    .tile_start(), .tile_busy(engine_busy), .accel_done(engine_done),
    .accel_error(engine_error), .tile_index(), .row_base(), .col_base(),
    .k_base(), .rows_valid(), .cols_valid(), .k_valid(), .task_first(),
    .task_last(), .k_block_index(), .k_block_count()
  );

  assign nice_rsp_valid = rsp_pending;
  assign nice_rsp_rdat = rsp_data_reg;
  assign nice_rsp_err = rsp_err_reg;
  // E203's NICE active indication tracks an in-flight NICE transaction.
  // The asynchronous accelerator job is reported separately through STATUS.
  assign nice_active = nice_req_valid || rsp_pending || wait_ctrl_rsp;
  // Matrix payloads use the independent System Bus in this revision.
  assign nice_mem_holdup = 1'b0;

  // Intentionally inactive until the DMA channel is jointly selected.
  assign nice_icb_cmd_valid = 1'b0;
  assign nice_icb_cmd_addr = '0;
  assign nice_icb_cmd_read = 1'b0;
  assign nice_icb_cmd_wdata = '0;
  assign nice_icb_cmd_size = 2'b00;
  assign nice_icb_rsp_ready = 1'b0;

  always_ff @(posedge nice_clk or negedge nice_rst_n) begin
    if (!nice_rst_n) begin
      rsp_pending <= 1'b0;
      wait_ctrl_rsp <= 1'b0;
      rsp_data_reg <= '0;
      rsp_err_reg <= 1'b0;
    end else begin
      if (rsp_pending && nice_rsp_ready)
        rsp_pending <= 1'b0;

      if (ctrl_rsp_valid && wait_ctrl_rsp) begin
        rsp_pending <= 1'b1;
        wait_ctrl_rsp <= 1'b0;
        rsp_data_reg <= ctrl_rsp_rdata;
        rsp_err_reg <= 1'b0;
      end

      if (req_fire) begin
        if (!req_supported || (engine_busy && req_is_write)) begin
          rsp_pending <= 1'b1;
          rsp_data_reg <= '0;
          rsp_err_reg <= 1'b1;
        end else if (req_is_read) begin
          wait_ctrl_rsp <= 1'b1;
        end else begin
          rsp_pending <= 1'b1;
          rsp_data_reg <= '0;
          rsp_err_reg <= 1'b0;
        end
      end
    end
  end

  // Kept as a named signal for waveform/debug visibility. The wrapped
  // accelerator owns the actual start pulse generated by its register block.
  assign accel_start_unused = 1'b0;
endmodule
