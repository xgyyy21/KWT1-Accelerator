`timescale 1ns/1ps

module fp32_tile_cache_streamer_tb;
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

  logic busy, done, stream_valid, task_first, task_last;
  logic [31:0] a_left [2], b_top [2], bias_in [2];
  integer stream_count = 0;

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

  fp32_tile_cache_streamer #(.ROWS(2), .COLS(2), .K(2)) dut (
    .clk(clk), .rst_n(rst_n), .start(start),
    .task_first_cfg(1'b1), .task_last_cfg(1'b1),
    .a_rd_en(a_rd_en), .a_rd_addr(a_rd_addr), .a_rd_data(a_rd_data),
    .a_rd_valid(a_rd_valid), .b_rd_en(b_rd_en), .b_rd_addr(b_rd_addr),
    .b_rd_data(b_rd_data), .b_rd_valid(b_rd_valid),
    .result_rd_en(result_rd_en), .result_rd_addr(result_rd_addr),
    .result_rd_data(result_rd_data), .result_rd_valid(result_rd_valid),
    .busy(busy), .done(done), .stream_valid(stream_valid),
    .task_first(task_first), .task_last(task_last), .a_left(a_left),
    .b_top(b_top), .bias_in(bias_in)
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

  initial begin
    repeat (2) @(negedge clk);
    rst_n = 1'b1;

    // A[row][k] = [[1,2],[3,4]], B[k][col] = [[10,20],[30,40]].
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

    @(negedge clk);
    start = 1'b1;
    @(negedge clk);
    start = 1'b0;

    while (stream_count < 2) begin
      @(negedge clk);
      if (stream_valid) begin
        if (stream_count == 0) begin
          if (!task_first || task_last || a_left[0] !== 32'h3f800000 ||
              a_left[1] !== 32'h40400000 || b_top[0] !== 32'h41200000 ||
              b_top[1] !== 32'h41a00000 || bias_in[0] !== 32'h3f000000 ||
              bias_in[1] !== 32'h3fc00000)
            $fatal(1, "K0 stream mismatch");
        end else begin
          if (task_first || !task_last || a_left[0] !== 32'h40000000 ||
              a_left[1] !== 32'h40800000 || b_top[0] !== 32'h41f00000 ||
              b_top[1] !== 32'h42200000)
            $fatal(1, "K1 stream mismatch");
        end
        stream_count = stream_count + 1;
      end
    end

    repeat (2) @(negedge clk);
    if (!done || busy) $fatal(1, "streamer did not finish cleanly");
    $display("PASS: fp32_tile_cache_streamer synchronous read and stream checks");
    $finish;
  end

  initial begin
    #100000;
    $fatal(1, "fp32_tile_cache_streamer_tb timeout");
  end
endmodule
