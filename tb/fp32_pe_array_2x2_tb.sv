`timescale 1ns/1ps

// Functional array check using the same hand_2x2 values as the single-PE TB.
// The DUT is instantiated as 2x2 to make the propagation and coordinate
// mapping easy to inspect; the RTL parameters are the same ones used by the
// 8x16 production geometry.
module fp32_pe_array_2x2_tb;
  logic clk = 1'b0;
  always #5 clk = ~clk;

  logic rst_n = 1'b0;
  logic start = 1'b0;
  logic stream_valid = 1'b0;
  logic task_first = 1'b0;
  logic task_last = 1'b0;
  logic [31:0] a_left [2];
  logic [31:0] b_top [2];
  logic [31:0] bias_in [2];
  logic checkpoint_save_req=0, checkpoint_restore_req=0;
  wire checkpoint_busy, checkpoint_done, checkpoint_error, checkpoint_mem_req, checkpoint_mem_we;
  wire [9:0] checkpoint_mem_addr;
  wire [15:0] checkpoint_mem_wdata;
  logic busy, done, result_valid;
  logic [31:0] result [2][2];
  logic trace_valid [2][2];
  logic trace_bias_valid [2][2];
  logic [31:0] trace_cycle [2][2];
  logic [15:0] trace_k [2][2];
  logic [31:0] trace_x_bits [2][2];
  logic [31:0] trace_w_bits [2][2];
  logic [31:0] trace_acc_before_bits [2][2];
  logic [31:0] trace_product_bits [2][2];
  logic [31:0] trace_acc_after_bits [2][2];
  logic [31:0] trace_bias_bits [2][2];
  integer trace_fd;
  integer mac_events;
  integer bias_events;
  integer tr, tc;

  fp32_pe_array_8x16 #(.ROWS(2), .COLS(2), .K(2)) dut (
    .clk(clk), .rst_n(rst_n), .start(start),
    .stream_valid(stream_valid), .task_first(task_first),
    .task_last(task_last), .a_left(a_left), .b_top(b_top),
    .bias_in(bias_in), .checkpoint_save_req(checkpoint_save_req),
    .checkpoint_restore_req(checkpoint_restore_req), .checkpoint_busy(checkpoint_busy),
    .checkpoint_done(checkpoint_done), .checkpoint_error(checkpoint_error),
    .checkpoint_mem_req(checkpoint_mem_req), .checkpoint_mem_we(checkpoint_mem_we),
    .checkpoint_mem_addr(checkpoint_mem_addr), .checkpoint_mem_wdata(checkpoint_mem_wdata),
    .checkpoint_mem_rvalid(1'b0), .checkpoint_mem_rdata(16'd0), .busy(busy), .done(done),
    .result_valid(result_valid), .result(result),
    .trace_valid(trace_valid), .trace_bias_valid(trace_bias_valid),
    .trace_cycle(trace_cycle), .trace_k(trace_k),
    .trace_x_bits(trace_x_bits), .trace_w_bits(trace_w_bits),
    .trace_acc_before_bits(trace_acc_before_bits),
    .trace_product_bits(trace_product_bits),
    .trace_acc_after_bits(trace_acc_after_bits),
    .trace_bias_bits(trace_bias_bits)
  );

  always @(posedge clk) begin
    #1;
    for (tr = 0; tr < 2; tr = tr + 1) begin
      for (tc = 0; tc < 2; tc = tc + 1) begin
        if (trace_valid[tr][tc]) begin
          mac_events = mac_events + 1;
          $fdisplay(trace_fd,
            "rtl_model_raw,hand_2x2,0,%0d,%0d,mac,%0d,1,%0d,%08x,%08x,%08x,%08x,%08x,%0s,%0s,%0s,%0s,%0s",
            tr, tc, trace_cycle[tr][tc], trace_k[tr][tc],
            trace_x_bits[tr][tc], trace_w_bits[tr][tc],
            trace_acc_before_bits[tr][tc], trace_product_bits[tr][tc],
            trace_acc_after_bits[tr][tc], "", "", "", "", "");
        end
        if (trace_bias_valid[tr][tc]) begin
          bias_events = bias_events + 1;
          $fdisplay(trace_fd,
            "rtl_model_raw,hand_2x2,0,%0d,%0d,bias,%0d,1,%0s,%0s,%0s,%08x,%0s,%08x,%08x,%08x,%0s,%0s,%0s",
            tr, tc, trace_cycle[tr][tc], "", "", "",
            trace_acc_before_bits[tr][tc], "",
            trace_acc_after_bits[tr][tc], trace_bias_bits[tr][tc],
            result[tr][tc], "", "", "");
        end
      end
    end
  end

  task automatic drive_k(
    input logic [31:0] x0, input logic [31:0] x1,
    input logic [31:0] w0, input logic [31:0] w1,
    input logic is_first, input logic is_last
  );
    begin
      @(negedge clk);
      a_left[0] = x0;
      a_left[1] = x1;
      b_top[0] = w0;
      b_top[1] = w1;
      start = is_first;
      task_first = is_first;
      task_last = is_last;
      stream_valid = 1'b1;
      @(negedge clk);
      start = 1'b0;
      task_first = 1'b0;
      task_last = 1'b0;
      stream_valid = 1'b0;
      a_left[0] = 32'd0;
      a_left[1] = 32'd0;
      b_top[0] = 32'd0;
      b_top[1] = 32'd0;
    end
  endtask

  initial begin
    a_left[0] = 0; a_left[1] = 0;
    b_top[0] = 0; b_top[1] = 0;
    bias_in[0] = 32'h3e800000; // +0.25
    bias_in[1] = 32'hbf000000; // -0.5
    trace_fd = $fopen("build/fp32_pe_array_hand_2x2_raw_trace.csv", "w");
    if (trace_fd == 0) $fatal(1, "cannot open array trace output");
    $fdisplay(trace_fd,
      "source_kind,case_id,tile_id,row,column,event,cycle,valid,k,x_bits,w_bits,acc_before_bits,product_bits,acc_after_bits,bias_bits,result_bits,rtl_commit,input_manifest_sha256,reference_trace_sha256");
    mac_events = 0;
    bias_events = 0;

    repeat (2) @(negedge clk);
    rst_n = 1'b1;

    // X = [[1, -2], [0.5, 3]], W = [[2, -1], [1.5, 0.5]].
    drive_k(32'h3f800000, 32'h3f000000,
            32'h40000000, 32'hbf800000, 1'b1, 1'b0);
    drive_k(32'hc0000000, 32'h40400000,
            32'h3fc00000, 32'h3f000000, 1'b0, 1'b1);

    while (!done) begin
      @(posedge clk);
      #1;
    end
    if (!result_valid || busy)
      $fatal(1, "array handshake mismatch valid=%0d busy=%0d", result_valid, busy);

    if (result[0][0] !== 32'hbf400000 ||
        result[0][1] !== 32'hc0200000 ||
        result[1][0] !== 32'h40b80000 ||
        result[1][1] !== 32'h3f000000)
      $fatal(1, "array result mismatch: [%08x %08x; %08x %08x]",
             result[0][0], result[0][1], result[1][0], result[1][1]);

    #2;
    $fclose(trace_fd);
    if (mac_events != 8 || bias_events != 4)
      $fatal(1, "unexpected array trace counts mac=%0d bias=%0d", mac_events, bias_events);

    $display("fp32_pe_array_2x2_tb PASS result=[[%08x,%08x],[%08x,%08x]] trace_mac=%0d trace_bias=%0d",
             result[0][0], result[0][1], result[1][0], result[1][1],
             mac_events, bias_events);
    $finish;
  end

  initial begin
    #300000;
    $fatal(1, "fp32_pe_array_2x2_tb timeout");
  end
endmodule
