// Standalone accelerator top with protocol-neutral NICE and System-Bus ports.
//
// NICE is the control/status plane.  System Bus is the matrix payload plane.
// The internal tile datapath owns DMA/cache/PE/writeback. The outer ports are
// intentionally generic and can be mapped to E203 NICE/System-Bus later.
module fp32_accelerator_top #(
  parameter int ADDR_WIDTH = 32,
  parameter int DATA_WIDTH = 32,
  parameter bit STRICT_COMPETITION_SHAPES = 1'b1
) (
  input  logic                   clk,
  input  logic                   rst_n,

  // NICE control plane.
  input  logic                   nice_req_valid,
  input  logic                   nice_req_write,
  input  logic [ADDR_WIDTH-1:0]  nice_req_addr,
  input  logic [DATA_WIDTH-1:0]  nice_req_wdata,
  output logic                   nice_req_ready,
  output logic                   nice_rsp_valid,
  output logic [DATA_WIDTH-1:0]  nice_rsp_rdata,

  // System-Bus data plane, driven by the platform wrapper.
  output logic                   sys_req_valid,
  output logic                   sys_req_write,
  output logic [ADDR_WIDTH-1:0]  sys_req_addr,
  output logic [15:0]            sys_req_wdata,
  input  logic                   sys_req_ready,
  input  logic                   sys_rsp_valid,
  input  logic [15:0]            sys_rsp_rdata,

  output logic                   tile_start,
  output logic                   tile_busy,
  output logic                   accel_done,
  output logic                   accel_error,
  output logic [31:0]            tile_index,
  output logic [15:0]            row_base,
  output logic [15:0]            col_base,
  output logic [15:0]            k_base,
  output logic [15:0]            rows_valid,
  output logic [15:0]            cols_valid,
  output logic [15:0]            k_valid,
  output logic                   task_first,
  output logic                   task_last,
  output logic [15:0]            k_block_index,
  output logic [15:0]            k_block_count
);
  logic engine_start;
  logic [ADDR_WIDTH-1:0] src_a_base, src_b_base, bias_base, dst_base;
  logic [15:0] matrix_m, matrix_k, matrix_n;
  logic engine_tile_done, datapath_busy, datapath_error;
  logic tile_req_valid, tile_req_write, tile_req_ready;
  logic [ADDR_WIDTH-1:0] tile_req_addr;
  logic [15:0] tile_req_wdata, tile_rsp_rdata;
  logic tile_rsp_valid, bus_adapter_error;
  logic scheduler_error;

  fp32_nice_control_adapter #(
    .ADDR_WIDTH(ADDR_WIDTH), .DATA_WIDTH(DATA_WIDTH)
  ) u_nice (
    .clk(clk), .rst_n(rst_n),
    .nice_req_valid(nice_req_valid), .nice_req_write(nice_req_write),
    .nice_req_addr(nice_req_addr), .nice_req_wdata(nice_req_wdata),
    .nice_req_ready(nice_req_ready), .nice_rsp_valid(nice_rsp_valid),
    .nice_rsp_rdata(nice_rsp_rdata), .engine_busy(tile_busy),
    .engine_done(accel_done), .engine_error(accel_error),
    .engine_start(engine_start), .src_a_base(src_a_base),
    .src_b_base(src_b_base), .bias_base(bias_base), .dst_base(dst_base),
    .matrix_m(matrix_m),
    .matrix_k(matrix_k), .matrix_n(matrix_n)
  );

  fp32_matrix_tile_scheduler #(
    .STRICT_COMPETITION_SHAPES(STRICT_COMPETITION_SHAPES)
  ) u_scheduler (
    .clk(clk), .rst_n(rst_n), .start(engine_start),
    .tile_done(engine_tile_done),
    .matrix_m(matrix_m), .matrix_k(matrix_k), .matrix_n(matrix_n),
    .tile_start(tile_start), .tile_busy(tile_busy), .done(accel_done),
    .config_error(scheduler_error), .tile_index(tile_index),
    .row_base(row_base), .col_base(col_base), .k_base(k_base),
    .rows_valid(rows_valid), .cols_valid(cols_valid), .k_valid(k_valid),
    .task_first(task_first), .task_last(task_last),
    .k_block_index(k_block_index), .k_block_count(k_block_count),
    .supported_shape()
  );

  fp32_tile_kblock_load_compute #(
    .ROW_TILE(8), .COL_TILE(16), .K_TILE(32), .K_BLOCKS(8),
    .ADDR_WIDTH(ADDR_WIDTH), .CACHE_ADDR_WIDTH(10)
  ) u_tile_engine (
    .clk(clk), .rst_n(rst_n), .start(tile_start),
    .k_block_count(k_block_count),
    .matrix_m(matrix_m), .matrix_k(matrix_k), .matrix_n(matrix_n),
    .row_base(row_base), .col_base(col_base), .k_base(k_base),
    .rows_valid(rows_valid), .cols_valid(cols_valid),
    .k_valid_block(k_valid), .a_base_word(src_a_base),
    .b_base_word(src_b_base), .bias_base_word(bias_base),
    .result_base_word(dst_base), .bus_req_ready(tile_req_ready),
    .bus_rsp_valid(tile_rsp_valid), .bus_rsp_rdata(tile_rsp_rdata),
    .bus_req_valid(tile_req_valid), .bus_req_write(tile_req_write),
    .bus_req_addr(tile_req_addr), .bus_req_wdata(tile_req_wdata),
    .error_in(1'b0), .load_busy(), .load_done(), .stream_busy(),
    .compute_busy(), .compute_done(), .writeback_busy(),
    .writeback_done(), .result_valid(), .result_last(), .result_data(),
    .result_row(), .result_col(), .busy(datapath_busy),
    .done(engine_tile_done), .error(datapath_error), .block_index(),
    .task_first(), .task_last(), .state()
  );

  fp32_tile_soc_bus_adapter #(.ADDR_WIDTH(ADDR_WIDTH)) u_system_bus (
    .clk(clk), .rst_n(rst_n),
    .tile_req_valid(tile_req_valid), .tile_req_write(tile_req_write),
    .tile_req_addr(tile_req_addr), .tile_req_wdata(tile_req_wdata),
    .tile_req_ready(tile_req_ready), .tile_rsp_valid(tile_rsp_valid),
    .tile_rsp_rdata(tile_rsp_rdata), .soc_req_valid(sys_req_valid),
    .soc_req_write(sys_req_write), .soc_req_addr(sys_req_addr),
    .soc_req_wdata(sys_req_wdata), .soc_req_ready(sys_req_ready),
    .soc_rsp_valid(sys_rsp_valid), .soc_rsp_rdata(sys_rsp_rdata),
    .busy(), .error(bus_adapter_error)
  );

  assign accel_error = scheduler_error || datapath_error || bus_adapter_error;
endmodule
