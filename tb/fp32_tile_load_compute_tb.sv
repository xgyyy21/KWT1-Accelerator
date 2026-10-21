`timescale 1ns/1ps

module fp32_tile_load_compute_tb;
  import fp32_math_pkg::*;
  logic clk = 1'b0;
  always #5 clk = ~clk;
  logic rst_n = 1'b0;
  logic start = 1'b0;
  logic bus_req_valid, bus_req_write, bus_req_ready = 1'b1;
  logic [31:0] bus_req_addr;
  logic [15:0] bus_req_wdata, bus_rsp_rdata;
  logic bus_rsp_valid = 1'b0;
  logic error_in = 1'b0;
  logic load_busy, load_done, stream_busy, compute_busy, compute_done;
  logic writeback_busy, writeback_done;
  logic result_valid, result_last, busy, done, error;
  logic [31:0] result_data;
  logic [15:0] result_row, result_col;
  logic [2:0] state;
  logic [15:0] ext_mem [0:4095];
  logic bus_pending = 1'b0;
  logic [31:0] bus_pending_addr = 0;
  logic [31:0] expected_bits;
  integer i, result_count = 0;

  fp32_tile_load_compute #(.ROW_TILE(2), .COL_TILE(2), .K_TILE(2)) dut (
    .clk(clk), .rst_n(rst_n), .start(start),
    .matrix_m(16'd2), .matrix_k(16'd2), .matrix_n(16'd2),
    .row_base(16'd0), .col_base(16'd0), .k_base(16'd0),
    .rows_valid(16'd2), .cols_valid(16'd2), .k_valid(16'd2),
    .task_first_cfg(1'b1), .task_last_cfg(1'b1),
    .a_base_word(32'd100), .b_base_word(32'd200),
    .bias_base_word(32'd300), .result_base_word(32'd400),
    .bus_req_ready(bus_req_ready), .bus_rsp_valid(bus_rsp_valid),
    .bus_rsp_rdata(bus_rsp_rdata), .bus_req_valid(bus_req_valid),
    .bus_req_write(bus_req_write), .bus_req_addr(bus_req_addr),
    .bus_req_wdata(bus_req_wdata),
    .error_in(error_in), .load_busy(load_busy), .load_done(load_done),
    .stream_busy(stream_busy), .compute_busy(compute_busy),
    .compute_done(compute_done), .result_valid(result_valid),
    .result_last(result_last), .result_data(result_data),
    .result_row(result_row), .result_col(result_col), .busy(busy),
    .done(done), .error(error), .state(state)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      bus_pending <= 1'b0;
      bus_pending_addr <= 0;
      bus_rsp_valid <= 1'b0;
      bus_rsp_rdata <= 0;
    end else begin
      bus_rsp_valid <= bus_pending;
      if (bus_pending) bus_rsp_rdata <= ext_mem[bus_pending_addr];
      if (bus_req_valid && bus_req_write && bus_req_ready)
        ext_mem[bus_req_addr] <= bus_req_wdata;
      bus_pending <= bus_req_valid && !bus_req_write && bus_req_ready;
      if (bus_req_valid && bus_req_ready) bus_pending_addr <= bus_req_addr;
    end
  end

  task automatic ext_write_fp32(input integer base, input integer elem,
                                input logic [31:0] bits);
    begin
      ext_mem[base + elem*2] = bits[15:0];
      ext_mem[base + elem*2 + 1] = bits[31:16];
    end
  endtask

  function automatic [31:0] expected_result(input integer row, input integer col);
    logic [31:0] p0, p1, sum;
    begin
      if (row == 0 && col == 0) begin
        p0 = fp32_mul(32'h3f800000, 32'h41200000);
        p1 = fp32_mul(32'h40000000, 32'h41f00000);
        expected_result = fp32_add(fp32_add(p0, p1), 32'h3f000000);
      end else if (row == 0 && col == 1) begin
        p0 = fp32_mul(32'h3f800000, 32'h41a00000);
        p1 = fp32_mul(32'h40000000, 32'h42200000);
        expected_result = fp32_add(fp32_add(p0, p1), 32'h3fc00000);
      end else if (row == 1 && col == 0) begin
        p0 = fp32_mul(32'h40400000, 32'h41200000);
        p1 = fp32_mul(32'h40800000, 32'h41f00000);
        expected_result = fp32_add(fp32_add(p0, p1), 32'h3f000000);
      end else begin
        p0 = fp32_mul(32'h40400000, 32'h41a00000);
        p1 = fp32_mul(32'h40800000, 32'h42200000);
        expected_result = fp32_add(fp32_add(p0, p1), 32'h3fc00000);
      end
    end
  endfunction

  always @(negedge clk) begin
    if (result_valid) begin
      if (result_data !== expected_result(result_row, result_col))
        $fatal(1, "result mismatch row=%0d col=%0d got=%08h expected=%08h",
               result_row, result_col, result_data,
               expected_result(result_row, result_col));
      result_count = result_count + 1;
    end
  end

  initial begin
    for (i = 0; i < 4096; i = i + 1) ext_mem[i] = 16'd0;
    ext_write_fp32(100, 0, 32'h3f800000);
    ext_write_fp32(100, 1, 32'h40000000);
    ext_write_fp32(100, 2, 32'h40400000);
    ext_write_fp32(100, 3, 32'h40800000);
    ext_write_fp32(200, 0, 32'h41200000);
    ext_write_fp32(200, 1, 32'h41a00000);
    ext_write_fp32(200, 2, 32'h41f00000);
    ext_write_fp32(200, 3, 32'h42200000);
    ext_write_fp32(300, 0, 32'h3f000000);
    ext_write_fp32(300, 1, 32'h3fc00000);

    repeat (2) @(negedge clk);
    rst_n = 1'b1;
    @(negedge clk); start = 1'b1;
    @(posedge clk); #1;
    if (!busy) $fatal(1, "FSM did not enter load phase");
    @(negedge clk); start = 1'b0;

    wait (load_busy);
    wait (compute_busy);
    if (stream_busy !== 1'b1 && stream_busy !== 1'b0)
      $fatal(1, "streamer busy is unknown");
    wait (result_count == 4);
    wait (compute_done);
    @(posedge clk);
    #1;
    if (state != 3'd3) $fatal(1, "FSM did not reach writeback phase");
    wait (done);
    if (writeback_busy) $fatal(1, "writeback remains busy at DONE");
    for (i = 0; i < 4; i = i + 1) begin
      expected_bits = expected_result(i/2, i%2);
      if (ext_mem[400 + i*2] !== expected_bits[15:0] ||
          ext_mem[401 + i*2] !== expected_bits[31:16])
        $fatal(1, "writeback mismatch elem=%0d got=%04h/%04h expected=%08h",
               i, ext_mem[400 + i*2], ext_mem[401 + i*2],
               expected_bits);
    end
    $display("PASS: fp32 tile load plus compute integration 2x2x2");
    $finish;
  end

  initial begin
    #300000;
    $fatal(1, "fp32_tile_load_compute_tb timeout");
  end
endmodule
