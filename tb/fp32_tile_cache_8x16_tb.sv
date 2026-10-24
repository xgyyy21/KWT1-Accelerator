`timescale 1ns/1ps

// Full production-geometry tile check.  The values are intentionally simple:
// every product is 1.0 and every bias is 1.0, so each K=32 result must be 33.0.
module fp32_tile_cache_8x16_tb;
  localparam logic [31:0] ONE_BITS = 32'h3f800000;
  localparam logic [31:0] EXPECTED_BITS = 32'h42040000; // 33.0

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

  logic cache_busy, cache_done, stream_valid, task_first, task_last;
  logic [31:0] a_left [8], b_top [16], bias_in [16];
  logic engine_start, engine_busy, engine_done;
  logic result_valid, result_last;
  logic [31:0] result_data;
  logic [15:0] result_row, result_col;
  integer result_count = 0;
  integer engine_done_seen = 0;
  logic [127:0] seen_results = '0;

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

  fp32_tile_cache_streamer #(.ROWS(8), .COLS(16), .K(32)) streamer (
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

  fp32_tile_engine #(.ROWS(8), .COLS(16), .K(32)) engine (
    .clk(clk), .rst_n(rst_n), .start(engine_start),
    .stream_valid(stream_valid), .task_first(task_first),
    .task_last(task_last), .a_left(a_left), .b_top(b_top),
    .bias_in(bias_in), .valid_rows(16'd8), .valid_cols(16'd16),
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

  initial begin : test_sequence
    integer i;
    repeat (2) @(negedge clk);
    rst_n = 1'b1;

    // A is [8][32], B is [32][16], bias is [16].
    for (i = 0; i < 8*32; i = i + 1)
      write_fp32(0, i, ONE_BITS);
    for (i = 0; i < 32*16; i = i + 1)
      write_fp32(1, i, ONE_BITS);
    for (i = 0; i < 16; i = i + 1)
      write_fp32(2, i, ONE_BITS);

    @(negedge clk); start = 1'b1;
    @(negedge clk); start = 1'b0;
    while (result_count < 8*16) begin
      @(negedge clk);
      if (engine_done) engine_done_seen = 1;
      if (result_valid) begin
        if (result_row >= 8 || result_col >= 16)
          $fatal(1, "result coordinate out of range row=%0d col=%0d",
                 result_row, result_col);
        if (result_data !== EXPECTED_BITS)
          $fatal(1, "result mismatch row=%0d col=%0d got=%08h expected=%08h",
                 result_row, result_col, result_data, EXPECTED_BITS);
        if (seen_results[result_row*16+result_col])
          $fatal(1, "duplicate result row=%0d col=%0d", result_row, result_col);
        seen_results[result_row*16+result_col] = 1'b1;
        if (result_last !== (result_count == 8*16-1))
          $fatal(1, "result_last mismatch at count=%0d", result_count);
        result_count = result_count + 1;
      end
    end
    while (!engine_done_seen) begin
      @(negedge clk);
      if (engine_done) engine_done_seen = 1;
    end
    if (seen_results !== {128{1'b1}})
      $fatal(1, "not all 128 result coordinates were observed");
    if (engine_busy) $fatal(1, "8x16 engine remains busy after done");
    $display("PASS: cache to 8x16 FP32 tile engine K=32 results=%0d", result_count);
    $finish;
  end

  initial begin
    #1000000;
    $fatal(1, "fp32_tile_cache_8x16_tb timeout");
  end
endmodule
