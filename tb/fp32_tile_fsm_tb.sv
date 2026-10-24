`timescale 1ns/1ps

module fp32_tile_fsm_tb;
  logic clk = 1'b0;
  always #5 clk = ~clk;

  logic rst_n;
  logic start;
  logic [15:0] rows_valid, cols_valid, k_valid;
  logic load_done, compute_done, writeback_done, error_in;
  logic load_start, compute_start, writeback_start;
  logic busy, done, error;
  logic [2:0] state;
  integer load_pulses, compute_pulses, writeback_pulses;

  fp32_tile_fsm #(.ROW_TILE(8), .COL_TILE(16), .K_TILE(32)) dut (
    .clk(clk), .rst_n(rst_n), .start(start),
    .rows_valid(rows_valid), .cols_valid(cols_valid), .k_valid(k_valid),
    .load_done(load_done), .compute_done(compute_done),
    .writeback_done(writeback_done), .error_in(error_in),
    .load_start(load_start), .compute_start(compute_start),
    .writeback_start(writeback_start), .busy(busy), .done(done),
    .error(error), .state(state)
  );

  always @(posedge clk) begin
    if (load_start) load_pulses = load_pulses + 1;
    if (compute_start) compute_pulses = compute_pulses + 1;
    if (writeback_start) writeback_pulses = writeback_pulses + 1;
  end

  task automatic check;
    input bit condition;
    input [8*120-1:0] message;
    begin
      if (!condition) begin
        $display("FAIL: %s", message);
        $fatal(1);
      end
    end
  endtask

  task automatic pulse_input_done;
    inout logic done_signal;
    begin
      @(negedge clk);
      done_signal = 1'b1;
      @(negedge clk);
      done_signal = 1'b0;
    end
  endtask

  initial begin
    rst_n = 1'b0;
    start = 1'b0;
    rows_valid = 16'd2;
    cols_valid = 16'd2;
    k_valid = 16'd2;
    load_done = 1'b0;
    compute_done = 1'b0;
    writeback_done = 1'b0;
    error_in = 1'b0;
    load_pulses = 0;
    compute_pulses = 0;
    writeback_pulses = 0;

    repeat (2) @(negedge clk);
    rst_n = 1'b1;

    @(negedge clk);
    start = 1'b1;
    @(posedge clk);
    #1;
    check(load_start && busy && !compute_start && !writeback_start,
          "valid tile enters LOAD with one load_start pulse");
    @(posedge clk);
    #1;
    check(load_pulses == 1, "load_start pulse count is one");
    @(negedge clk);
    start = 1'b0;

    @(negedge clk);
    load_done = 1'b1;
    @(posedge clk);
    #1;
    check(compute_start && busy && !load_start && !writeback_start,
          "load_done advances to COMPUTE with one compute_start pulse");
    @(posedge clk);
    #1;
    check(compute_pulses == 1, "compute_start pulse count is one");
    @(negedge clk);
    load_done = 1'b0;

    @(negedge clk);
    compute_done = 1'b1;
    @(posedge clk);
    #1;
    check(writeback_start && busy && !load_start && !compute_start,
          "compute_done advances to WRITEBACK with one writeback_start pulse");
    @(posedge clk);
    #1;
    check(writeback_pulses == 1, "writeback_start pulse count is one");
    @(negedge clk);
    compute_done = 1'b0;

    @(negedge clk);
    writeback_done = 1'b1;
    @(posedge clk);
    #1;
    check(done && !busy && !error, "writeback_done reaches DONE");
    @(negedge clk);
    writeback_done = 1'b0;
    @(posedge clk);
    #1;
    check(!done && !busy && !error, "DONE returns to IDLE");

    // Invalid dimensions must fail before any DMA phase starts.
    rows_valid = 16'd9;
    @(negedge clk);
    start = 1'b1;
    @(posedge clk);
    #1;
    check(error && !busy && load_pulses == 1,
          "invalid tile enters ERROR without a load_start pulse");
    @(negedge clk);
    start = 1'b0;

    $display("PASS: fp32_tile_fsm 2x2 phase sequencing and config checks");
    $finish;
  end
endmodule
