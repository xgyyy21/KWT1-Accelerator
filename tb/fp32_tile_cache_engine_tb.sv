`timescale 1ns/1ps

module fp32_tile_cache_engine_tb;
  import fp32_math_pkg::*;

  logic clk = 1'b0;
  always #5 clk = ~clk;
  logic rst_n = 1'b0;
  logic start = 1'b0;
  logic a_wr_en = 0, b_wr_en = 0, result_wr_en = 0;
  logic [9:0] a_wr_addr = 0, b_wr_addr = 0, result_wr_addr = 0;
  logic [15:0] a_wr_data = 0, b_wr_data = 0, result_wr_data = 0;
  logic a_rd_en, b_rd_en, result_rd_en;
  logic [9:0] a_rd_addr, b_rd_addr, result_rd_addr;
  logic [15:0] a_rd_data, b_rd_data, result_rd_data;
  logic a_rd_valid, b_rd_valid, result_rd_valid;
  logic stream_valid, task_first, task_last, cache_busy, cache_done;
  logic [31:0] a_left [2], b_top [2], bias_in [2];
  logic engine_start, engine_busy, engine_done;
  logic result_valid, result_last;
  logic [31:0] result_data;
  logic [15:0] result_row, result_col;
  integer result_count = 0;
  integer engine_done_seen = 0;

  matrix_cache_manager cache (
    .clk(clk), .rst_n(rst_n),
    .a_wr_en(a_wr_en), .a_wr_addr(a_wr_addr), .a_wr_data(a_wr_data),
    .b_wr_en(b_wr_en), .b_wr_addr(b_wr_addr), .b_wr_data(b_wr_data),
    .result_wr_en(result_wr_en), .result_wr_addr(result_wr_addr),
    .result_wr_data(result_wr_data),
    .a_rd_en(a_rd_en), .a_rd_addr(a_rd_addr), .a_rd_data(a_rd_data),
    .a_rd_valid(a_rd_valid), .b_rd_en(b_rd_en), .b_rd_addr(b_rd_addr),
    .b_rd_data(b_rd_data), .b_rd_valid(b_rd_valid),
    .result_rd_en(result_rd_en), .result_rd_addr(result_rd_addr),
    .result_rd_data(result_rd_data), .result_rd_valid(result_rd_valid)
  );

  fp32_tile_cache_streamer #(.ROWS(2), .COLS(2), .K(2)) streamer (
    .clk(clk), .rst_n(rst_n), .start(start),
    .task_first_cfg(1'b1), .task_last_cfg(1'b1),
    .a_rd_en(a_rd_en), .a_rd_addr(a_rd_addr), .a_rd_data(a_rd_data),
    .a_rd_valid(a_rd_valid), .b_rd_en(b_rd_en), .b_rd_addr(b_rd_addr),
    .b_rd_data(b_rd_data), .b_rd_valid(b_rd_valid),
    .result_rd_en(result_rd_en), .result_rd_addr(result_rd_addr),
    .result_rd_data(result_rd_data), .result_rd_valid(result_rd_valid),
    .busy(cache_busy), .done(cache_done), .stream_valid(stream_valid),
    .task_first(task_first), .task_last(task_last), .a_left(a_left),
    .b_top(b_top), .bias_in(bias_in)
  );

  assign engine_start = stream_valid && task_first;

  fp32_tile_engine #(.ROWS(2), .COLS(2), .K(2)) engine (
    .clk(clk), .rst_n(rst_n), .start(engine_start),
    .stream_valid(stream_valid), .task_first(task_first),
    .task_last(task_last), .a_left(a_left), .b_top(b_top),
    .bias_in(bias_in), .valid_rows(16'd2), .valid_cols(16'd2),
    .busy(engine_busy), .done(engine_done), .result_valid(result_valid),
    .result_last(result_last), .result_data(result_data),
    .result_row(result_row), .result_col(result_col)
  );

  task automatic write_word(input integer bank, input integer addr,
                            input logic [15:0] value);
    begin
      @(negedge clk);
      a_wr_en = 0; b_wr_en = 0; result_wr_en = 0;
      case (bank)
        0: begin a_wr_en = 1; a_wr_addr = addr[9:0]; a_wr_data = value; end
        1: begin b_wr_en = 1; b_wr_addr = addr[9:0]; b_wr_data = value; end
        default: begin result_wr_en = 1; result_wr_addr = addr[9:0];
          result_wr_data = value; end
      endcase
      @(negedge clk);
      a_wr_en = 0; b_wr_en = 0; result_wr_en = 0;
    end
  endtask

  task automatic write_fp32(input integer bank, input integer elem,
                            input logic [31:0] bits);
    begin
      write_word(bank, elem*2, bits[15:0]);
      write_word(bank, elem*2+1, bits[31:16]);
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

  initial begin
    repeat (2) @(negedge clk);
    rst_n = 1'b1;
    write_fp32(0, 0, 32'h3f800000);
    write_fp32(0, 1, 32'h40000000);
    write_fp32(0, 2, 32'h40400000);
    write_fp32(0, 3, 32'h40800000);
    write_fp32(1, 0, 32'h41200000);
    write_fp32(1, 1, 32'h41a00000);
    write_fp32(1, 2, 32'h41f00000);
    write_fp32(1, 3, 32'h42200000);
    write_fp32(2, 0, 32'h3f000000);
    write_fp32(2, 1, 32'h3fc00000);

    @(negedge clk); start = 1'b1;
    @(negedge clk); start = 1'b0;
    while (result_count < 4) begin
      @(negedge clk);
      if (engine_done) engine_done_seen = 1;
      if (result_valid) begin
        if (result_data !== expected_result(result_row, result_col))
          $fatal(1, "result mismatch row=%0d col=%0d got=%08h expected=%08h",
                 result_row, result_col, result_data,
                 expected_result(result_row, result_col));
        result_count = result_count + 1;
      end
    end
    while (!engine_done_seen) begin
      @(negedge clk);
      if (engine_done) engine_done_seen = 1;
    end
    if (engine_busy) $fatal(1, "engine did not finish cleanly");
    $display("PASS: cache to FP32 tile engine end-to-end 2x2x2");
    $finish;
  end

  initial begin
    #200000;
    $fatal(1, "fp32_tile_cache_engine_tb timeout");
  end
endmodule
