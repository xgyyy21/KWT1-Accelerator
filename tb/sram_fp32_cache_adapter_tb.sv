`timescale 1ns/1ps
module sram_fp32_cache_adapter_tb;
  logic clk = 1'b0;
  always #5 clk = ~clk;
  logic rst_n = 1'b1;
  logic [2:0] standby = '0;
  logic [2:0] req_valid = '0, req_write = '0, rsp_ready = 3'b111;
  logic [2:0][9:0] req_addr = '0;
  logic [2:0][15:0] req_wdata = '0;
  wire [2:0] req_ready, rsp_valid;
  wire [2:0][15:0] rsp_data;
  wire [23:0] macro_cen, macro_gwen, macro_ret1n;
  wire [23:0][15:0] macro_wen, macro_d, macro_q;
  wire [23:0][6:0] macro_a;
  wire [23:0][2:0] macro_ema;
  wire [23:0][1:0] macro_emaw;

  sram_fp32_cache_adapter dut (.*);
  for (genvar m = 0; m < 24; m++) begin : g_model
    ramsp128x16_functional_model u_sram (
      .CLK(clk), .CEN(macro_cen[m]), .GWEN(macro_gwen[m]),
      .WEN(macro_wen[m]), .A(macro_a[m]), .D(macro_d[m]), .Q(macro_q[m]),
      .EMA(macro_ema[m]), .EMAW(macro_emaw[m]), .RET1N(macro_ret1n[m])
    );
  end

  logic [15:0] reference_mem [0:2][0:1023];
  integer cycles = 0, writes = 0, reads = 0, responses = 0;
  integer macro_checks = 0, blocked_cycles = 0;
  integer trace_fd;
  string trace_path;

  function automatic [15:0] pattern(input integer bank, input integer address);
    pattern = 16'h1937 ^ (bank * 16'h4567) ^ (address * 16'h003d);
  endfunction

  task automatic check_idle(input string context_text);
    begin
      for (integer s = 0; s < 24; s++) begin
        if (macro_cen[s] !== 1'b1 || macro_gwen[s] !== 1'b1 ||
            macro_wen[s] !== 16'hffff || macro_a[s] !== 7'b0 ||
            macro_d[s] !== 16'b0)
          $fatal(1, "%s: macro pins not idle macro=%0d", context_text, s);
      end
      macro_checks++;
    end
  endtask

  task automatic check_command(input integer bank, input bit writing,
                               input integer address, input logic [15:0] data);
    integer slot, selected_count;
    begin
      slot = bank * 8 + (address >> 7);
      selected_count = 0;
      for (integer s = 0; s < 24; s++) begin
        if (macro_ema[s] !== 3'd2 || macro_emaw[s] !== 2'd3 ||
            macro_ret1n[s] !== 1'b1)
          $fatal(1, "Macro config pins mismatch macro=%0d", s);
        if (s / 8 == bank) begin
          if (!macro_cen[s]) selected_count++;
          if (s == slot) begin
            if (macro_cen[s] !== 1'b0 || macro_gwen[s] !== !writing ||
                macro_wen[s] !== (writing ? 16'h0000 : 16'hffff) ||
                macro_a[s] !== (address & 127) || macro_d[s] !== data)
              $fatal(1, "Selected macro mismatch bank=%0d addr=%0d", bank, address);
          end else if (macro_cen[s] !== 1'b1 || macro_gwen[s] !== 1'b1 ||
                       macro_wen[s] !== 16'hffff || macro_a[s] !== 7'b0 ||
                       macro_d[s] !== 16'b0) begin
            $fatal(1, "Unexpected active macro=%0d", s);
          end
        end
      end
      if (selected_count != 1)
        $fatal(1, "Expected one active macro, got %0d", selected_count);
      macro_checks++;
    end
  endtask

  // Accept at a rising edge, drive macro pins at the next falling edge, and
  // observe the macro operation/response at the following rising edge.
  task automatic transact_all(input bit writing, input integer address);
    logic [15:0] expected [0:2];
    begin
      @(negedge clk);
      req_valid = 3'b111;
      req_write = {3{writing}};
      for (integer b = 0; b < 3; b++) begin
        req_addr[b] = address;
        req_wdata[b] = pattern(b, address);
        expected[b] = reference_mem[b][address];
      end
      #1;
      if (req_ready !== 3'b111)
        $fatal(1, "Expected all-bank request ready addr=%0d ready=%b", address, req_ready);
      @(posedge clk); #1;
      if (req_ready !== 3'b000)
        $fatal(1, "Command slot did not apply backpressure after acceptance");

      @(negedge clk); #1;
      for (integer b = 0; b < 3; b++) begin
        check_command(b, writing, address, pattern(b, address));
        if (writing)
          reference_mem[b][address] = pattern(b, address);
      end
      req_valid = '0;

      @(posedge clk); #1;
      for (integer b = 0; b < 3; b++) begin
        if (writing) begin
          if (rsp_valid[b] !== 1'b0)
            $fatal(1, "Write produced a read response bank=%0d", b);
          writes++;
          $fdisplay(trace_fd, "%0d,write,%0d,%0d,%0d,%04h", cycles,
                    b, address, (address >> 7), pattern(b, address));
        end else begin
          if (rsp_valid[b] !== 1'b1 || rsp_data[b] !== expected[b])
            $fatal(1, "Read mismatch bank=%0d addr=%0d expected=%04h got=%04h valid=%b",
                   b, address, expected[b], rsp_data[b], rsp_valid[b]);
          reads++;
          $fdisplay(trace_fd, "%0d,read_response,%0d,%0d,%0d,%04h", cycles,
                    b, address, (address >> 7), rsp_data[b]);
        end
      end

      @(negedge clk); #1;
      check_idle("post-macro edge");
      if (!writing) begin
        @(posedge clk); #1;
        if (rsp_valid !== 3'b000)
          $fatal(1, "Read responses did not retire");
        responses += 3;
      end
    end
  endtask

  integer expected_before [0:2];
  initial begin
    #1 rst_n = 1'b0;
  end

  initial begin : tests
    if (!$value$plusargs("trace=%s", trace_path)) trace_path = "sram_access_trace.csv";
    trace_fd = $fopen(trace_path, "w");
    if (!trace_fd) $fatal(1, "Cannot create trace file");
    $fdisplay(trace_fd, "cycle,event,bank,word_addr,macro_index,data_hex");
    for (integer b = 0; b < 3; b++)
      for (integer a = 0; a < 1024; a++)
        reference_mem[b][a] = 16'hxxxx;

    repeat (2) @(negedge clk);
    #1;
    check_idle("reset");
    rst_n = 1'b1;

    // All logical words in all three banks, including every macro boundary.
    for (integer a = 0; a < 1024; a++) transact_all(1'b1, a);
    for (integer a = 0; a < 1024; a++) transact_all(1'b0, a);

    // Explicit low/high FP32 halfword transport across macro slots 0 and 1.
    transact_all(1'b1, 127);
    transact_all(1'b1, 128);
    transact_all(1'b0, 127);
    transact_all(1'b0, 128);
    $display("CHECK complete address map and 16-bit low/high transport PASS");

    // Stall one bank's read response and queue a write to that bank. Its
    // response and Q must remain stable; other banks remain independently ready.
    @(negedge clk);
    rsp_ready = 3'b110;
    req_valid = 3'b111;
    req_write = 3'b000;
    for (integer b = 0; b < 3; b++) begin
      req_addr[b] = 400;
      req_wdata[b] = '0;
    end
    #1;
    if (req_ready !== 3'b111) $fatal(1, "Initial backpressure read not ready");
    @(posedge clk); #1;
    @(negedge clk); #1;
    check_command(0, 1'b0, 400, 16'h0000);
    check_command(1, 1'b0, 400, 16'h0000);
    check_command(2, 1'b0, 400, 16'h0000);
    req_valid = 0;
    @(posedge clk); #1;
    if (rsp_valid !== 3'b111 || rsp_data[0] !== reference_mem[0][400])
      $fatal(1, "Expected three read responses before stalling");
    @(negedge clk); #1;
    check_idle("stalled response after macro hold window");

    req_valid = 3'b001; req_write = 3'b001;
    req_addr[0] = 700; req_wdata[0] = 16'hbabe;
    repeat (3) begin
      @(posedge clk); #1;
      if (req_ready[0] !== 1'b0 || rsp_valid[0] !== 1'b1 ||
          rsp_data[0] !== reference_mem[0][400])
        $fatal(1, "Stalled response/payload was not held");
      if (req_ready[1] !== 1'b1 || req_ready[2] !== 1'b1)
        $fatal(1, "Independent banks were unnecessarily stalled");
      check_idle("backpressure");
      blocked_cycles++;
    end
    @(negedge clk); rsp_ready = 3'b111; #1;
    if (!req_ready[0]) $fatal(1, "Queued write not released with response");
    @(posedge clk); #1; // Consume response and capture queued write.
    @(negedge clk); #1;
    check_command(0, 1'b1, 700, 16'hbabe);
    reference_mem[0][700] = 16'hbabe;
    req_valid = 0;
    @(posedge clk); #1;
    @(negedge clk); #1;
    check_idle("queued write complete");
    transact_all(1'b0, 700);
    $display("CHECK response backpressure and independent banks PASS");

    // Standby blocks new requests and does not disturb an existing response.
    @(negedge clk);
    standby = 3'b111; req_valid = 3'b111; req_write = 3'b111;
    req_addr = {3{10'd1023}}; req_wdata = {3{16'hbeef}};
    #1;
    if (req_ready !== 3'b000) $fatal(1, "Standby accepted a request");
    repeat (2) begin
      @(posedge clk); #1;
      check_idle("standby");
    end
    @(negedge clk); standby = '0; #1;
    if (req_ready !== 3'b111) $fatal(1, "Request did not resume after standby");
    @(posedge clk); #1;
    @(negedge clk); #1;
    for (integer b = 0; b < 3; b++) check_command(b, 1'b1, 1023, 16'hbeef);
    for (integer b = 0; b < 3; b++) reference_mem[b][1023] = 16'hbeef;
    req_valid = '0;
    @(posedge clk); #1;
    @(negedge clk); #1;
    check_idle("standby released");

    // Reset cancels a held response but does not reset macro storage.
    @(negedge clk);
    rsp_ready = 0; req_valid = 3'b001; req_write = 0;
    req_addr[0] = 1023; req_wdata[0] = 0;
    #1;
    if (!req_ready[0]) $fatal(1, "Reset test read not accepted");
    @(posedge clk); #1;
    @(negedge clk); #1;
    check_command(0, 1'b0, 1023, 16'h0000);
    req_valid = 0;
    @(posedge clk); #1;
    if (!rsp_valid[0] || rsp_data[0] !== 16'hbeef)
      $fatal(1, "Expected pending read before reset");
    @(negedge clk); rst_n = 0; rsp_ready = 3'b111;
    #1;
    if (rsp_valid !== 3'b000) $fatal(1, "Reset did not cancel response");
    @(negedge clk); #1;
    check_idle("reset");
    rst_n = 1;
    transact_all(1'b0, 1023);

    $display("PASS sram_fp32_cache_adapter writes=%0d read_requests=%0d read_responses=%0d blocked_bank_cycles=%0d macro_pin_checks=%0d cycles=%0d",
             writes, reads, responses, blocked_cycles, macro_checks, cycles);
    $fclose(trace_fd);
    $finish;
  end

  always @(posedge clk) begin
    cycles++;
    for (integer b = 0; b < 3; b++) begin
      integer active_count;
      active_count = 0;
      for (integer s = b*8; s < b*8+8; s++)
        if (!macro_cen[s]) active_count++;
      if (active_count > 1)
        $fatal(1, "More than one macro active in bank=%0d", b);
    end
  end

  initial begin
    #1000000;
    $fatal(1, "SRAM wrapper test timeout");
  end
endmodule
