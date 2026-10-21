`timescale 1ns/1ps

module fp32_tile_kblock_fsm_tb;
  logic clk = 1'b0;
  always #5 clk = ~clk;
  logic rst_n = 1'b0;
  logic start = 1'b0;
  logic [15:0] block_count_cfg = 16'd2;
  logic load_done = 1'b0, stream_done = 1'b0;
  logic compute_done = 1'b0, writeback_done = 1'b0, error_in = 1'b0;
  logic load_start, stream_start, compute_start, writeback_start;
  logic task_first, task_last, busy, done, error;
  logic block_index;
  logic [2:0] state;
  integer load_pulses = 0, stream_pulses = 0, compute_pulses = 0;

  fp32_tile_kblock_fsm #(.BLOCKS(2)) dut (
    .clk(clk), .rst_n(rst_n), .start(start),
    .block_count_cfg(block_count_cfg), .load_done(load_done),
    .stream_done(stream_done), .compute_done(compute_done),
    .writeback_done(writeback_done), .error_in(error_in),
    .load_start(load_start), .stream_start(stream_start),
    .compute_start(compute_start), .writeback_start(writeback_start),
    .task_first(task_first), .task_last(task_last), .busy(busy),
    .done(done), .error(error), .block_index(block_index), .state(state)
  );

  always @(posedge clk) begin
    if (load_start) load_pulses = load_pulses + 1;
    if (stream_start) stream_pulses = stream_pulses + 1;
    if (compute_start) compute_pulses = compute_pulses + 1;
  end

  initial begin
    repeat (2) @(negedge clk);
    rst_n = 1'b1;

    @(negedge clk); start = 1'b1;
    @(posedge clk); #1;
    if (!load_start || !busy || block_index != 0)
      $fatal(1, "block 0 did not start loading");
    @(negedge clk); start = 1'b0;

    @(negedge clk); load_done = 1'b1;
    @(posedge clk); #1;
    #1;
    if (!stream_start || !compute_start || !task_first || task_last)
      $fatal(1, "block 0 stream markers or compute start are wrong");
    @(negedge clk); load_done = 1'b0;
    @(negedge clk); stream_done = 1'b1;
    @(posedge clk); #1;
    #1;
    if (!load_start || block_index != 1 || task_first || !task_last)
      $fatal(1, "block 1 did not start after block 0 stream");
    @(negedge clk); stream_done = 1'b0;

    @(negedge clk); load_done = 1'b1;
    @(posedge clk); #1;
    #1;
    if (!stream_start || compute_start || task_first || !task_last)
      $fatal(1, "block 1 incorrectly restarted the PE engine");
    @(negedge clk); load_done = 1'b0;
    @(negedge clk); stream_done = 1'b1;
    @(posedge clk); #1;
    #1;
    if (state != 3'd3 || !busy)
      $fatal(1, "final block did not enter compute wait");
    @(negedge clk); stream_done = 1'b0;

    @(negedge clk); compute_done = 1'b1;
    @(posedge clk); #1;
    #1;
    if (!writeback_start)
      $fatal(1, "compute completion did not start writeback");
    @(negedge clk); compute_done = 1'b0;
    @(negedge clk); writeback_done = 1'b1;
    @(posedge clk); #1;
    #1;
    if (!done || error || busy)
      $fatal(1, "writeback completion did not reach DONE");
    @(negedge clk); writeback_done = 1'b0;
    if (load_pulses != 2 || stream_pulses != 2 || compute_pulses != 1)
      $fatal(1, "unexpected pulse counts load=%0d stream=%0d compute=%0d",
             load_pulses, stream_pulses, compute_pulses);
    block_count_cfg = 16'd0;
    @(negedge clk); start = 1'b1;
    @(posedge clk); #1;
    if (!error || busy || load_start)
      $fatal(1, "zero K-block count was not rejected");
    @(negedge clk); start = 1'b0;
    $display("PASS: fp32_tile_kblock_fsm two K-block sequencing");
    $finish;
  end

  initial begin
    #100000;
    $fatal(1, "fp32_tile_kblock_fsm_tb timeout");
  end
endmodule
