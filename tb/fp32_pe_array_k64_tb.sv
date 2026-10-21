`timescale 1ns/1ps

// Full 8x16/K=64 functional test.  Every product is 1.0 and every output
// bias is 1.0, so each cell must produce 64+1 = 65.0 (0x42820000).
module fp32_pe_array_k64_tb;
  localparam int ROWS = 8;
  localparam int COLS = 16;
  localparam int K = 64;
  localparam logic [31:0] ONE = 32'h3f800000;
  localparam logic [31:0] EXPECTED = 32'h42820000;

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
  integer r, c, k;

  fp32_pe_array_8x16 #(.ROWS(ROWS), .COLS(COLS), .K(K)) dut (
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
      bias_in[c] = ONE;
    end

    repeat (2) @(negedge clk);
    rst_n = 1'b1;

    for (k = 0; k < K; k = k + 1) begin
      @(negedge clk);
      start = (k == 0);
      stream_valid = 1'b1;
      task_first = (k == 0);
      task_last = (k == K-1);
      for (r = 0; r < ROWS; r = r + 1) a_left[r] = ONE;
      for (c = 0; c < COLS; c = c + 1) b_top[c] = ONE;
    end
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
      $fatal(1, "K64 array handshake mismatch valid=%0d busy=%0d", result_valid, busy);
    for (r = 0; r < ROWS; r = r + 1)
      for (c = 0; c < COLS; c = c + 1)
        if (result[r][c] !== EXPECTED)
          $fatal(1, "K64 result mismatch row=%0d col=%0d got=%08x expected=%08x",
                 r, c, result[r][c], EXPECTED);

    $display("fp32_pe_array_k64_tb PASS cells=%0d K=%0d result=65.0",
             ROWS*COLS, K);
    $finish;
  end

  initial begin
    #1000000;
    $fatal(1, "fp32_pe_array_k64_tb timeout");
  end
endmodule
