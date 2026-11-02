`timescale 1ns/1ps
// Continuous two-job test through the E203-shaped adapter.
// No reset or SRAM clear is issued between jobs. The test checks reload,
// sticky status handling, 16-bit writeback, request stability under System
// Bus backpressure, and recovery after an explicit status clear.
module kwt1_e203_nice_wrapper_continuous_tb;
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
  logic sys_req_valid, sys_req_write, sys_req_ready = 1'b0;
  logic [31:0] sys_req_addr;
  logic [15:0] sys_req_wdata;
  logic sys_rsp_valid = 1'b0;
  logic [15:0] sys_rsp_rdata = '0;
  logic [15:0] sys_mem [0:1023];
  logic sys_read_pending = 1'b0;
  logic [31:0] pending_addr = '0;
  integer cycle = 0;
  integer job_id = -1;
  integer job_writes = 0;
  integer total_writes = 0;
  integer bus_waits = 0;
  integer busy_seen = 0;
  logic held_valid = 1'b0;
  logic held_write;
  logic [31:0] held_addr;
  logic [15:0] held_data;
  logic [31:0] expected_result;

  kwt1_e203_nice_adapter #(
    .KWT_OPCODE(OPCODE), .KWT_FUNCT7(7'h00),
    .STRICT_COMPETITION_SHAPES(1'b0), .USE_SRAM_MACROS(1'b0)
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
    .sys_rsp_rdata(sys_rsp_rdata), .engine_busy(), .engine_done(), .engine_error()
  );

  function automatic [31:0] enc(input logic [2:0] funct3);
    enc = {7'h00, 5'h00, 5'h00, funct3, 5'h00, OPCODE};
  endfunction

  always @(negedge clk) begin
    if (rst_n) sys_req_ready = ((cycle % 7) != 0) && ((cycle % 7) != 1);
    else sys_req_ready = 1'b0;
  end

  always @(posedge clk) begin
    cycle = cycle + 1;
    if (!rst_n) begin
      sys_rsp_valid <= 1'b0;
      sys_read_pending <= 1'b0;
      held_valid <= 1'b0;
    end else begin
      sys_rsp_valid <= 1'b0;
      if (sys_read_pending) begin
        sys_rsp_valid <= 1'b1;
        sys_rsp_rdata <= sys_mem[pending_addr[9:0]];
        sys_read_pending <= 1'b0;
      end
      if (held_valid && (!sys_req_valid || sys_req_write !== held_write ||
          sys_req_addr !== held_addr || sys_req_wdata !== held_data))
        $fatal(1, "System Bus request changed while backpressured");
      held_valid <= sys_req_valid && !sys_req_ready;
      held_write <= sys_req_write;
      held_addr <= sys_req_addr;
      held_data <= sys_req_wdata;
      if (held_valid) bus_waits = bus_waits + 1;

      if (sys_req_valid && sys_req_ready) begin
        if (sys_req_write) begin
          if (sys_req_addr[31:10] != 0 || sys_req_addr[9:0] > 1021)
            $fatal(1, "write outside modeled 16-bit bus memory");
          if (sys_req_addr[9:0] < pending_addr[9:0] && job_id < 0)
            $fatal(1, "unexpected pre-job write");
          if (sys_req_addr[9:0] < 1023 &&
              (sys_req_addr[9:0] == 48 || sys_req_addr[9:0] == 49 ||
               sys_req_addr[9:0] == 112 || sys_req_addr[9:0] == 113)) begin
            if (sys_req_wdata !== (sys_req_addr[0] ? expected_result[31:16] : expected_result[15:0]))
              $fatal(1, "writeback mismatch job=%0d addr=%0d got=%h expected=%h",
                     job_id, sys_req_addr, sys_req_wdata, expected_result);
            job_writes = job_writes + 1;
            total_writes = total_writes + 1;
          end
          sys_mem[sys_req_addr[9:0]] <= sys_req_wdata;
        end else begin
          if (sys_read_pending) $fatal(1, "two outstanding reads");
          sys_read_pending <= 1'b1;
          pending_addr <= sys_req_addr;
        end
      end
    end
  end

  task automatic nice_cmd(input logic [2:0] funct3, input logic [31:0] rs1,
                          input logic [31:0] rs2, input logic expect_err,
                          input logic [31:0] expect_data);
    begin
      @(negedge clk);
      while (!nice_req_ready) @(negedge clk);
      nice_req_inst = enc(funct3); nice_req_rs1 = rs1; nice_req_rs2 = rs2;
      nice_req_valid = 1'b1;
      @(posedge clk); #1 nice_req_valid = 1'b0;
      while (!nice_rsp_valid) @(negedge clk);
      #1;
      if (nice_rsp_err !== expect_err || nice_rsp_rdat !== expect_data)
        $fatal(1, "NICE response mismatch funct3=%0d err=%b/%b data=%h/%h",
               funct3, nice_rsp_err, expect_err, nice_rsp_rdat, expect_data);
      @(posedge clk); #1;
      if (nice_rsp_valid) $fatal(1, "NICE response did not retire");
    end
  endtask

  task automatic read_status(output logic [31:0] status);
    begin
      @(negedge clk);
      while (!nice_req_ready) @(negedge clk);
      nice_req_inst = enc(3'd3); nice_req_rs1 = 0; nice_req_rs2 = 0;
      nice_req_valid = 1'b1;
      @(posedge clk); #1 nice_req_valid = 1'b0;
      while (!nice_rsp_valid) @(negedge clk);
      #1;
      if (nice_rsp_err) $fatal(1, "STATUS read returned ERROR");
      status = nice_rsp_rdat;
      @(posedge clk); #1;
      if (nice_rsp_valid) $fatal(1, "STATUS response did not retire");
    end
  endtask

  task automatic run_job(input integer id, input integer a_base,
                         input integer b_base, input integer bias_base,
                         input integer y_base, input logic [31:0] x_bits,
                         input logic [31:0] w_bits, input logic [31:0] bias_bits,
                         input logic [31:0] result_bits);
    logic [31:0] status;
    integer guard;
    begin
      job_id = id; expected_result = result_bits; job_writes = 0;
      sys_mem[a_base] = x_bits[15:0]; sys_mem[a_base+1] = x_bits[31:16];
      sys_mem[b_base] = w_bits[15:0]; sys_mem[b_base+1] = w_bits[31:16];
      sys_mem[bias_base] = bias_bits[15:0]; sys_mem[bias_base+1] = bias_bits[31:16];
      sys_mem[y_base] = 16'hdead; sys_mem[y_base+1] = 16'hbeef;
      nice_cmd(3'd0, 32'h08, a_base, 1'b0, 0);
      nice_cmd(3'd0, 32'h0c, b_base, 1'b0, 0);
      nice_cmd(3'd0, 32'h20, bias_base, 1'b0, 0);
      nice_cmd(3'd0, 32'h10, y_base, 1'b0, 0);
      nice_cmd(3'd0, 32'h14, 1, 1'b0, 0);
      nice_cmd(3'd0, 32'h18, 1, 1'b0, 0);
      nice_cmd(3'd0, 32'h1c, 1, 1'b0, 0);
      nice_cmd(3'd2, 0, 0, 1'b0, 0);
      guard = 0; status = 0;
      while (!status[1] && guard < 100000) begin
        read_status(status);
        if (status[0]) busy_seen = busy_seen + 1;
        if (status[2]) $fatal(1, "job=%0d reported ERROR", id);
        guard = guard + 1;
      end
      if (!status[1] || status[0] || job_writes != 2)
        $fatal(1, "job=%0d did not complete cleanly status=%h writes=%0d", id, status, job_writes);
      if (sys_mem[y_base] !== result_bits[15:0] || sys_mem[y_base+1] !== result_bits[31:16])
        $fatal(1, "job=%0d stale/result memory mismatch", id);
      $display("PASS continuous job=%0d result=%h writes=%0d busy_samples=%0d",
               id, result_bits, job_writes, busy_seen);
    end
  endtask

  initial begin
    for (integer i = 0; i < 1024; i = i + 1) sys_mem[i] = 16'h0000;
    repeat (3) @(negedge clk); rst_n = 1'b1;
    if (nice_mem_holdup !== 1'b0 || nice_icb_cmd_valid !== 1'b0 ||
        nice_icb_rsp_ready !== 1'b0) $fatal(1, "NICE ICB path is not inactive");
    run_job(0, 0, 16, 32, 48, 32'h3f800000, 32'h40000000,
            32'h40400000, 32'h40a00000); // 1*2+3=5
    run_job(1, 64, 80, 96, 112, 32'h40000000, 32'h40800000,
            32'hbf800000, 32'h40e00000); // 2*4-1=7

    // Explicitly verify clear after the second job and response backpressure.
    nice_rsp_ready = 1'b0;
    @(negedge clk); while (!nice_req_ready) @(negedge clk);
    nice_req_inst = enc(3'd3); nice_req_rs1 = 0; nice_req_rs2 = 0; nice_req_valid = 1'b1;
    @(posedge clk); #1 nice_req_valid = 1'b0;
    while (!nice_rsp_valid) @(negedge clk);
    if (!nice_active || nice_req_ready) $fatal(1, "NICE backpressure policy failed");
    repeat (2) begin
      @(posedge clk); #1;
      if (!nice_rsp_valid || nice_req_ready) $fatal(1, "NICE response not held");
    end
    nice_rsp_ready = 1'b1; @(posedge clk); #1;
    if (nice_rsp_valid) $fatal(1, "NICE held response did not retire");
    nice_cmd(3'd4, 32'd3, 0, 1'b0, 0);
    nice_cmd(3'd3, 0, 0, 1'b0, 0);
    if (bus_waits == 0 || busy_seen == 0 || total_writes != 4)
      $fatal(1, "coverage missing waits=%0d busy=%0d writes=%0d", bus_waits, busy_seen, total_writes);
    $display("PASS kwt1_e203_nice_wrapper_continuous_tb jobs=2 writes=%0d bus_waits=%0d busy_samples=%0d no_reset_between_jobs=1",
             total_writes, bus_waits, busy_seen);
    $finish;
  end
  initial begin
    #5000000;
    $fatal(1, "continuous wrapper test timeout");
  end
endmodule
