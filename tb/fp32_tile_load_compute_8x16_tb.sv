`timescale 1ns/1ps

module fp32_tile_load_compute_8x16_tb;
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
  logic [15:0] ext_mem [0:65535];
  logic bus_pending = 1'b0;
  logic [31:0] bus_pending_addr = 0;
  logic [31:0] expected_bits;
  integer i, r, c, result_count = 0;

  fp32_tile_load_compute #(.ROW_TILE(8), .COL_TILE(16), .K_TILE(32)) dut (
    .clk(clk), .rst_n(rst_n), .start(start),
    .matrix_m(16'd8), .matrix_k(16'd32), .matrix_n(16'd16),
    .row_base(16'd0), .col_base(16'd0), .k_base(16'd0),
    .rows_valid(16'd8), .cols_valid(16'd16), .k_valid(16'd32),
    .task_first_cfg(1'b1), .task_last_cfg(1'b1),
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
    .done(done), .error(error), .state(state)
  );

  // One-cycle external read response and immediate write acceptance.
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

  task automatic ext_write_fp32(input integer base, input integer elem,
                                input logic [31:0] bits);
    begin
      ext_mem[base + elem*2] = bits[15:0];
      ext_mem[base + elem*2 + 1] = bits[31:16];
    end
  endtask

  function automatic [31:0] row_value(input integer row);
    begin
      case (row)
        0: row_value = 32'h42000000; // 32
        1: row_value = 32'h42800000; // 64
        2: row_value = 32'h42c00000; // 96
        3: row_value = 32'h43000000; // 128
        4: row_value = 32'h43200000; // 160
        5: row_value = 32'h43400000; // 192
        6: row_value = 32'h43600000; // 224
        default: row_value = 32'h43800000; // 256
      endcase
    end
  endfunction

  function automatic [31:0] input_row_value(input integer row);
    begin
      case (row)
        0: input_row_value = 32'h3f800000;
        1: input_row_value = 32'h40000000;
        2: input_row_value = 32'h40400000;
        3: input_row_value = 32'h40800000;
        4: input_row_value = 32'h40a00000;
        5: input_row_value = 32'h40c00000;
        6: input_row_value = 32'h40e00000;
        default: input_row_value = 32'h41000000;
      endcase
    end
  endfunction

  always @(negedge clk) begin
    if (result_valid) begin
      expected_bits = row_value(result_row);
      if (result_data !== expected_bits)
        $fatal(1, "result mismatch row=%0d col=%0d got=%08h expected=%08h",
               result_row, result_col, result_data, expected_bits);
      result_count = result_count + 1;
    end
  end

  initial begin
    for (i = 0; i < 65536; i = i + 1) ext_mem[i] = 16'd0;
    // A is row-major and each row is constant. B is all ones, so every
    // output in a row equals 32 times that row's input value.
    for (r = 0; r < 8; r = r + 1)
      for (c = 0; c < 32; c = c + 1)
        ext_write_fp32(1000, r*32+c, input_row_value(r));
    for (r = 0; r < 32; r = r + 1)
      for (c = 0; c < 16; c = c + 1)
        ext_write_fp32(5000, r*16+c, 32'h3f800000);
    for (c = 0; c < 16; c = c + 1)
      ext_write_fp32(9000, c, 32'h00000000);

    repeat (2) @(negedge clk);
    rst_n = 1'b1;
    @(negedge clk); start = 1'b1;
    @(posedge clk); #1;
    if (!busy) $fatal(1, "8x16 FSM did not enter load phase");
    @(negedge clk); start = 1'b0;

    wait (load_done);
    wait (compute_done);
    wait (result_count == 128);
    if (result_count != 128)
      $fatal(1, "expected 128 computed results, got %0d", result_count);
    wait (done);
    if (error || writeback_busy)
      $fatal(1, "8x16 closed path ended in error or stayed busy");

    for (r = 0; r < 8; r = r + 1) begin
      for (c = 0; c < 16; c = c + 1) begin
        expected_bits = row_value(r);
        if (ext_mem[12000 + (r*16+c)*2] !== expected_bits[15:0] ||
            ext_mem[12001 + (r*16+c)*2] !== expected_bits[31:16])
          $fatal(1, "writeback mismatch row=%0d col=%0d got=%04h/%04h expected=%08h",
                 r, c, ext_mem[12000 + (r*16+c)*2],
                 ext_mem[12001 + (r*16+c)*2], expected_bits);
      end
    end
    $display("PASS: fp32 tile load plus compute plus writeback 8x16x32");
    $finish;
  end

  initial begin
    #1000000;
    $fatal(1, "fp32_tile_load_compute_8x16_tb timeout");
  end
endmodule
