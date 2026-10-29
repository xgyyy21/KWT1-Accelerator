`timescale 1ns/1ps

module fp32_tile_kblock_load_compute_k256_tb;
  localparam logic [31:0] ONE_BITS = 32'h3f800000;
  localparam logic [31:0] EXPECTED_BITS = 32'h43808000; // 257.0

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
  logic [2:0] block_index;
  logic task_first, task_last;
  logic [2:0] state;
  logic [15:0] ext_mem [0:65535];
  logic bus_pending = 1'b0;
  logic [31:0] bus_pending_addr = 0;
  integer i, r, c, result_count = 0;

  fp32_tile_kblock_load_compute #(
    .ROW_TILE(2), .COL_TILE(2), .K_TILE(32), .K_BLOCKS(8)
  ) dut (
    .clk(clk), .rst_n(rst_n), .start(start), .k_block_count(16'd8),
    .matrix_m(16'd2), .matrix_k(16'd256), .matrix_n(16'd2),
    .row_base(16'd0), .col_base(16'd0), .k_base(16'd0),
    .rows_valid(16'd2), .cols_valid(16'd2), .k_valid_block(16'd32),
    .a_base_word(32'd1000), .b_base_word(32'd5000),
    .bias_base_word(32'd9000), .result_base_word(32'd12000),
    .bus_req_ready(bus_req_ready), .bus_rsp_valid(bus_rsp_valid),
    .bus_rsp_rdata(bus_rsp_rdata), .bus_req_valid(bus_req_valid),
    .bus_req_write(bus_req_write), .bus_req_addr(bus_req_addr),
    .bus_req_wdata(bus_req_wdata), .error_in(error_in),
    .load_busy(load_busy), .load_done(load_done),
    .stream_busy(stream_busy), .compute_busy(compute_busy),
    .compute_done(compute_done), .writeback_busy(writeback_busy),
    .writeback_done(writeback_done), .result_valid(result_valid),
    .result_last(result_last), .result_data(result_data),
    .result_row(result_row), .result_col(result_col), .busy(busy),
    .done(done), .error(error), .block_index(block_index),
    .task_first(task_first), .task_last(task_last), .state(state)
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
      if (bus_req_valid && !bus_req_write && bus_req_ready)
        bus_pending_addr <= bus_req_addr;
    end
  end

  always @(negedge clk) begin
    if (result_valid) begin
      if (result_data !== EXPECTED_BITS)
        $fatal(1, "K256 result mismatch row=%0d col=%0d got=%08h expected=%08h",
               result_row, result_col, result_data, EXPECTED_BITS);
      result_count = result_count + 1;
    end
  end

  task automatic ext_write_fp32(input integer base, input integer elem,
                                input logic [31:0] bits);
    begin
      ext_mem[base + elem*2] = bits[15:0];
      ext_mem[base + elem*2 + 1] = bits[31:16];
    end
  endtask

  initial begin
    for (i = 0; i < 65536; i = i + 1) ext_mem[i] = 16'd0;
    for (r = 0; r < 2; r = r + 1)
      for (c = 0; c < 256; c = c + 1)
        ext_write_fp32(1000, r*256+c, ONE_BITS);
    for (r = 0; r < 256; r = r + 1)
      for (c = 0; c < 2; c = c + 1)
        ext_write_fp32(5000, r*2+c, ONE_BITS);
    for (c = 0; c < 2; c = c + 1)
      ext_write_fp32(9000, c, ONE_BITS);

    repeat (2) @(negedge clk);
    rst_n = 1'b1;
    @(negedge clk); start = 1'b1;
    @(posedge clk); #1;
    if (!busy || !task_first || task_last || block_index != 0)
      $fatal(1, "K256 controller did not start block 0");
    @(negedge clk); start = 1'b0;

    wait (block_index == 7 && task_last);
    wait (compute_done);
    wait (result_count == 4);
    wait (done);
    if (error || writeback_busy)
      $fatal(1, "K256 closed path ended in error or remains busy");

    for (r = 0; r < 2; r = r + 1)
      for (c = 0; c < 2; c = c + 1) begin
        if (ext_mem[12000 + (r*2+c)*2] !== EXPECTED_BITS[15:0] ||
            ext_mem[12001 + (r*2+c)*2] !== EXPECTED_BITS[31:16])
          $fatal(1, "K256 writeback mismatch row=%0d col=%0d", r, c);
      end
    $display("PASS: fp32 eight-K-block load compute writeback 2x2 K=256");
    $finish;
  end

  initial begin
    #6000000;
    $fatal(1, "fp32_tile_kblock_load_compute_k256_tb timeout");
  end

endmodule
