`timescale 1ns/1ps

module kwt1_e203_nice_wrapper_tb;
  localparam logic [6:0] OPCODE = 7'h7b;
  logic clk = 1'b0;
  always #5 clk = ~clk;
  logic rst_n = 1'b0;
  logic nice_active, nice_mem_holdup;
  logic nice_req_valid = 1'b0, nice_req_ready;
  logic [31:0] nice_req_inst = '0, nice_req_rs1 = '0, nice_req_rs2 = '0;
  logic nice_rsp_valid, nice_rsp_ready = 1'b1;
  logic [31:0] nice_rsp_rdat;
  logic nice_rsp_err;
  logic nice_icb_cmd_valid, nice_icb_cmd_ready = 1'b1;
  logic [31:0] nice_icb_cmd_addr, nice_icb_cmd_wdata;
  logic nice_icb_cmd_read;
  logic [1:0] nice_icb_cmd_size;
  logic nice_icb_rsp_valid = 1'b0, nice_icb_rsp_ready;
  logic [31:0] nice_icb_rsp_rdata = '0;
  logic nice_icb_rsp_err = 1'b0;
  logic [2:0] cache_standby = '0;
  wire [23:0] macro_cen, macro_gwen, macro_ret1n;
  wire [23:0][15:0] macro_wen, macro_d;
  wire [23:0][6:0] macro_a;
  wire [23:0][15:0] macro_q = '0;
  wire [23:0][2:0] macro_ema;
  wire [23:0][1:0] macro_emaw;
  logic sys_req_valid, sys_req_write, sys_req_ready = 1'b1;
  logic [31:0] sys_req_addr;
  logic [15:0] sys_req_wdata;
  logic sys_rsp_valid = 1'b0;
  logic [15:0] sys_rsp_rdata = '0;
  logic [15:0] sys_mem [0:1023];
  integer sys_write_count = 0;
  logic engine_busy, engine_done, engine_error;
  logic [31:0] held_data, held_inst, held_rs1, held_rs2;
  logic held_err;

  kwt1_e203_nice_wrapper #(
    .KWT_OPCODE(OPCODE), .KWT_FUNCT7(7'h00),
    .STRICT_COMPETITION_SHAPES(1'b0)
  ) dut (
    .nice_clk(clk), .nice_rst_n(rst_n), .nice_active(nice_active),
    .nice_mem_holdup(nice_mem_holdup), .nice_req_valid(nice_req_valid),
    .nice_req_ready(nice_req_ready), .nice_req_inst(nice_req_inst),
    .nice_req_rs1(nice_req_rs1), .nice_req_rs2(nice_req_rs2),
    .nice_rsp_valid(nice_rsp_valid), .nice_rsp_ready(nice_rsp_ready),
    .nice_rsp_rdat(nice_rsp_rdat), .nice_rsp_err(nice_rsp_err),
    .nice_icb_cmd_valid(nice_icb_cmd_valid), .nice_icb_cmd_ready(nice_icb_cmd_ready),
    .nice_icb_cmd_addr(nice_icb_cmd_addr), .nice_icb_cmd_read(nice_icb_cmd_read),
    .nice_icb_cmd_wdata(nice_icb_cmd_wdata), .nice_icb_cmd_size(nice_icb_cmd_size),
    .nice_icb_rsp_valid(nice_icb_rsp_valid), .nice_icb_rsp_ready(nice_icb_rsp_ready),
    .nice_icb_rsp_rdata(nice_icb_rsp_rdata), .nice_icb_rsp_err(nice_icb_rsp_err),
    .cache_standby(cache_standby), .macro_cen(macro_cen), .macro_gwen(macro_gwen),
    .macro_wen(macro_wen), .macro_a(macro_a), .macro_d(macro_d), .macro_q(macro_q),
    .macro_ema(macro_ema), .macro_emaw(macro_emaw), .macro_ret1n(macro_ret1n),
    .sys_req_valid(sys_req_valid), .sys_req_write(sys_req_write),
    .sys_req_addr(sys_req_addr), .sys_req_wdata(sys_req_wdata),
    .sys_req_ready(sys_req_ready), .sys_rsp_valid(sys_rsp_valid),
    .sys_rsp_rdata(sys_rsp_rdata), .engine_busy(engine_busy),
    .engine_done(engine_done), .engine_error(engine_error)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      sys_rsp_valid <= 1'b0;
      sys_rsp_rdata <= '0;
    end else begin
      sys_rsp_valid <= 1'b0;
      if (sys_req_valid && sys_req_ready) begin
        if (sys_req_write) begin
          sys_mem[sys_req_addr[9:0]] <= sys_req_wdata;
          sys_write_count <= sys_write_count + 1;
        end else begin
          sys_rsp_valid <= 1'b1;
          sys_rsp_rdata <= sys_mem[sys_req_addr[9:0]];
        end
      end
    end
  end

  function automatic [31:0] enc(input logic [2:0] funct3);
    enc = {7'h00, 5'h00, 5'h00, funct3, 5'h00, OPCODE};
  endfunction

  task automatic issue_and_check(input logic [2:0] funct3,
                                 input logic [31:0] rs1,
                                 input logic [31:0] rs2,
                                 input logic expect_err,
                                 input logic [31:0] expect_data);
    begin
      @(negedge clk);
      while (!nice_req_ready) @(negedge clk);
      nice_req_inst = enc(funct3);
      nice_req_rs1 = rs1;
      nice_req_rs2 = rs2;
      nice_req_valid = 1'b1;
      @(posedge clk);
      #1 nice_req_valid = 1'b0;
      while (!nice_rsp_valid) @(negedge clk);
      #1;
      if (nice_rsp_err !== expect_err)
        $fatal(1, "unexpected response error: got %b expected %b", nice_rsp_err, expect_err);
      if (nice_rsp_rdat !== expect_data)
        $fatal(1, "unexpected response data: got %h expected %h", nice_rsp_rdat, expect_data);
      @(posedge clk);
      #1;
      if (nice_rsp_valid) $fatal(1, "response did not clear after handshake");
    end
  endtask

  initial begin
    repeat (3) @(negedge clk);
    rst_n = 1'b1;

    if ($bits(sys_req_wdata) != 16) $fatal(1, "System Bus payload width is not 16 bits");
    if (nice_mem_holdup || nice_icb_cmd_valid || nice_icb_rsp_ready)
      $fatal(1, "NICE ICB must remain inactive in this prototype");

    // Register write/read and STATUS use the selected mock instruction fields.
    issue_and_check(3'd0, 32'h14, 32'd2, 1'b0, 32'd0);
    issue_and_check(3'd1, 32'h14, 32'd0, 1'b0, 32'd2);
    issue_and_check(3'd3, 32'd0, 32'd0, 1'b0, 32'd0);

    // One real 1x1 FP32 task through the wrapped accelerator and 16-bit bus.
    for (integer i = 0; i < 1024; i = i + 1) sys_mem[i] = 16'h0000;
    sys_mem[0] = 16'h0000; sys_mem[1] = 16'h3f80;   // X = 1.0
    sys_mem[16] = 16'h0000; sys_mem[17] = 16'h4000; // W = 2.0
    sys_mem[32] = 16'h0000; sys_mem[33] = 16'h4040; // bias = 3.0
    issue_and_check(3'd0, 32'h08, 32'd0, 1'b0, 32'd0);
    issue_and_check(3'd0, 32'h0c, 32'd16, 1'b0, 32'd0);
    issue_and_check(3'd0, 32'h10, 32'd48, 1'b0, 32'd0);
    issue_and_check(3'd0, 32'h20, 32'd32, 1'b0, 32'd0);
    issue_and_check(3'd0, 32'h14, 32'd1, 1'b0, 32'd0);
    issue_and_check(3'd0, 32'h18, 32'd1, 1'b0, 32'd0);
    issue_and_check(3'd0, 32'h1c, 32'd1, 1'b0, 32'd0);
    issue_and_check(3'd2, 32'd0, 32'd0, 1'b0, 32'd0);
    wait (engine_done || engine_error);
    repeat (2) @(posedge clk);
    if (engine_error) $fatal(1, "1x1 task reported accelerator error");
    if (sys_mem[48] !== 16'h0000 || sys_mem[49] !== 16'h40a0)
      $fatal(1, "1x1 writeback mismatch: got %h_%h expected 40a0_0000", sys_mem[49], sys_mem[48]);
    if (sys_write_count != 2)
      $fatal(1, "expected two 16-bit writeback transfers, got %0d", sys_write_count);
    issue_and_check(3'd3, 32'd0, 32'd0, 1'b0, 32'd2);

    // Misaligned and unmapped register offsets are rejected explicitly.
    issue_and_check(3'd0, 32'h15, 32'd3, 1'b1, 32'd0);
    issue_and_check(3'd1, 32'h24, 32'd0, 1'b1, 32'd0);
    issue_and_check(3'd0, 32'h100, 32'd3, 1'b1, 32'd0);

    // Response payload/error and request payload remain stable under stalls.
    nice_rsp_ready = 1'b0;
    @(negedge clk);
    nice_req_inst = enc(3'd3);
    nice_req_rs1 = '0;
    nice_req_rs2 = '0;
    nice_req_valid = 1'b1;
    @(posedge clk); #1 nice_req_valid = 1'b0;
    while (!nice_rsp_valid) @(negedge clk);
    #1;
    held_data = nice_rsp_rdat;
    held_err = nice_rsp_err;
    @(negedge clk);
    nice_req_inst = enc(3'd0);
    nice_req_rs1 = 32'h18;
    nice_req_rs2 = 32'd64;
    nice_req_valid = 1'b1;
    held_inst = nice_req_inst;
    held_rs1 = nice_req_rs1;
    held_rs2 = nice_req_rs2;
    repeat (3) begin
      @(posedge clk); #1;
      if (!nice_rsp_valid || nice_rsp_rdat !== held_data || nice_rsp_err !== held_err)
        $fatal(1, "response was not held under backpressure");
      if (nice_req_ready || !nice_active || nice_req_inst !== held_inst ||
          nice_req_rs1 !== held_rs1 || nice_req_rs2 !== held_rs2)
        $fatal(1, "request was not held stable while response channel stalled");
    end
    nice_rsp_ready = 1'b1;
    @(posedge clk); #1;
    if (nice_rsp_valid) $fatal(1, "stalled response did not handshake");
    @(posedge clk); #1 nice_req_valid = 1'b0;
    while (!nice_rsp_valid) @(negedge clk);
    #1;
    if (nice_rsp_err || nice_rsp_rdat !== 32'd0)
      $fatal(1, "queued-after-response config write failed");
    @(posedge clk); #1;
    issue_and_check(3'd1, 32'h18, 32'd0, 1'b0, 32'd64);

    // Reads remain available during BUSY; all writes fail explicitly.
    force dut.engine_busy = 1'b1;
    issue_and_check(3'd3, 32'd0, 32'd0, 1'b0, 32'd3);
    issue_and_check(3'd0, 32'h18, 32'd128, 1'b1, 32'd0);
    issue_and_check(3'd2, 32'd0, 32'd0, 1'b1, 32'd0);
    issue_and_check(3'd4, 32'd1, 32'd0, 1'b1, 32'd0);
    release dut.engine_busy;

    // DONE/ERROR are sticky until explicit CLEAR in the wrapped register block.
    force dut.engine_done = 1'b1;
    force dut.engine_error = 1'b1;
    issue_and_check(3'd3, 32'd0, 32'd0, 1'b0, 32'd6);
    release dut.engine_done;
    release dut.engine_error;
    issue_and_check(3'd4, 32'd3, 32'd0, 1'b0, 32'd0);
    issue_and_check(3'd3, 32'd0, 32'd0, 1'b0, 32'd0);

    // Bad opcode/funct encodings are rejected by this standalone wrapper.
    @(negedge clk);
    nice_req_inst = 32'h0000_0073;
    nice_req_rs1 = '0; nice_req_rs2 = '0; nice_req_valid = 1'b1;
    @(posedge clk); #1 nice_req_valid = 1'b0;
    while (!nice_rsp_valid) @(negedge clk);
    #1 if (!nice_rsp_err) $fatal(1, "unsupported opcode was not rejected");
    @(posedge clk); #1;
    @(negedge clk);
    nice_req_inst = {7'h01, 5'd0, 5'd0, 3'd3, 5'd0, OPCODE};
    nice_req_valid = 1'b1;
    @(posedge clk); #1 nice_req_valid = 1'b0;
    while (!nice_rsp_valid) @(negedge clk);
    #1 if (!nice_rsp_err) $fatal(1, "unsupported funct7 was not rejected");
    @(posedge clk); #1;

    // Reset cancels a response that has not yet been consumed.
    nice_rsp_ready = 1'b0;
    @(negedge clk);
    nice_req_inst = enc(3'd3); nice_req_valid = 1'b1;
    @(posedge clk); #1 nice_req_valid = 1'b0;
    while (!nice_rsp_valid) @(negedge clk);
    rst_n = 1'b0;
    @(posedge clk); #1;
    if (nice_rsp_valid || nice_active) $fatal(1, "reset did not cancel response");
    nice_rsp_ready = 1'b1;
    rst_n = 1'b1;

    $display("kwt1_e203_nice_wrapper_tb PASS protocol, busy policy, clear, reset, 16-bit payload width");
    $finish;
  end

  initial begin
    #100000;
    $fatal(1, "kwt1_e203_nice_wrapper_tb timeout");
  end
endmodule
