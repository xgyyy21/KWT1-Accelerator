`timescale 1ns/1ps

// Full-geometry smoke test.  K=1 keeps the test short while exercising all
// 128 PE instances, input skew paths, result collection, and done generation.
module fp32_pe_array_8x16_tb;
  localparam int ROWS = 8;
  localparam int COLS = 16;
  localparam logic [31:0] ONE = 32'h3f800000;
  localparam logic [31:0] ZERO = 32'h00000000;

  logic clk = 1'b0;
  always #5 clk = ~clk;
  logic rst_n = 1'b0;
  logic start = 1'b0;
  logic stream_valid = 1'b0;
  logic task_first = 1'b0;
  logic task_last = 1'b0;
  logic [31:0] a_left [ROWS];
  logic [31:0] b_top [COLS];
  logic [31:0] bias_in [COLS];
  logic checkpoint_save_req=0, checkpoint_restore_req=0;
  wire checkpoint_busy, checkpoint_done, checkpoint_error, checkpoint_mem_req, checkpoint_mem_we;
  wire [9:0] checkpoint_mem_addr;
  wire [15:0] checkpoint_mem_wdata;
  logic busy, done, result_valid;
  logic [31:0] result [ROWS][COLS];
  integer r, c;

  fp32_pe_array_8x16 #(.ROWS(ROWS), .COLS(COLS), .K(1)) dut (
    .clk(clk), .rst_n(rst_n), .start(start),
    .stream_valid(stream_valid), .task_first(task_first),
    .task_last(task_last), .a_left(a_left), .b_top(b_top),
    .bias_in(bias_in), .checkpoint_save_req(checkpoint_save_req),
    .checkpoint_restore_req(checkpoint_restore_req), .checkpoint_busy(checkpoint_busy),
    .checkpoint_done(checkpoint_done), .checkpoint_error(checkpoint_error),
    .checkpoint_mem_req(checkpoint_mem_req), .checkpoint_mem_we(checkpoint_mem_we),
    .checkpoint_mem_addr(checkpoint_mem_addr), .checkpoint_mem_wdata(checkpoint_mem_wdata),
    .checkpoint_mem_rvalid(1'b0), .checkpoint_mem_rdata(16'd0), .busy(busy), .done(done),
    .result_valid(result_valid), .result(result)
  );

  initial begin
    for (r = 0; r < ROWS; r = r + 1) a_left[r] = ONE;
    for (c = 0; c < COLS; c = c + 1) begin
      b_top[c] = ONE;
      bias_in[c] = ZERO;
    end

    repeat (2) @(negedge clk);
    rst_n = 1'b1;
    @(negedge clk);
    start = 1'b1;
    stream_valid = 1'b1;
    task_first = 1'b1;
    task_last = 1'b1;
    @(negedge clk);
    start = 1'b0;
    stream_valid = 1'b0;
    task_first = 1'b0;
    task_last = 1'b0;

    while (!done) begin
      @(posedge clk);
      #1;
    end
    if (!result_valid || busy)
      $fatal(1, "8x16 handshake mismatch valid=%0d busy=%0d", result_valid, busy);
    for (r = 0; r < ROWS; r = r + 1)
      for (c = 0; c < COLS; c = c + 1)
        if (result[r][c] !== ONE)
          $fatal(1, "8x16 result mismatch row=%0d col=%0d got=%08x expected=%08x",
                 r, c, result[r][c], ONE);

    $display("fp32_pe_array_8x16_tb PASS cells=%0d result=1.0", ROWS*COLS);
    $finish;
  end

  initial begin
    #500000;
    $fatal(1, "fp32_pe_array_8x16_tb timeout");
  end
endmodule
