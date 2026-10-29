`timescale 1ns/1ps
module sram_fp32_cache_adapter_tb;
  logic clk = 0;
  always #5 clk = ~clk;
  logic rst_n = 1;
  logic [2:0] standby = 0, req_valid = 0, req_write = 0, rsp_ready = 3'b111;
  logic [2:0][9:0] req_addr = 0;
  logic [2:0][15:0] req_wdata = 0;
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
  bit pending [0:2];
  logic [15:0] expected_response [0:2];
  integer pending_addr [0:2];
  integer cycles = 0, writes = 0, reads = 0, responses = 0, cancelled = 0;
  integer pin_checks = 0, blocked_cycles = 0, trace_fd;
  bit held_req [0:2];
  logic [26:0] held_payload [0:2];
  string trace_path;

  function automatic [15:0] pattern(input integer bank, input integer address);
    pattern = 16'h1937 ^ (bank * 16'h4567) ^ (address * 16'h003d);
  endfunction

  // Independent reference storage plus a one-response-slot protocol scoreboard.
  // Check the preceding cycle's response before evaluating this edge's request.
  always @(posedge clk) begin : scoreboard
    integer selected, active_count;
    logic [23:0][15:0] old_q;
    logic [23:0] reading_now;
    cycles = cycles + 1;
    old_q = macro_q;
    reading_now = ~macro_cen & macro_gwen;
    for (integer b = 0; b < 3; b++) begin
      active_count = 0;
      selected = b*8 + (req_addr[b] >> 7);
      for (integer s = b*8; s < b*8+8; s++) begin
        pin_checks = pin_checks + 1;
        if (macro_ema[s] !== 3'd2 || macro_emaw[s] !== 2'd3 ||
            macro_ret1n[s] !== 1'b1)
          $fatal(1, "Incorrect fixed operating-mode pins macro=%0d", s);
        if (macro_cen[s] === 1'b0) active_count = active_count + 1;
        if (rst_n && req_valid[b] && req_ready[b] && s == selected) begin
          if (macro_cen[s] !== 1'b0 || macro_gwen[s] !== !req_write[b] ||
              macro_wen[s] !== (req_write[b] ? 16'h0000 : 16'hffff) ||
              macro_a[s] !== (req_addr[b] % 128) || macro_d[s] !== req_wdata[b])
            $fatal(1, "Macro decode/control/data mismatch bank=%0d addr=%0d", b, req_addr[b]);
        end else if (macro_cen[s] !== 1'b1 || macro_gwen[s] !== 1'b1 ||
                     macro_wen[s] !== 16'hffff) begin
          $fatal(1, "Inactive macro was enabled or write-masked incorrectly macro=%0d", s);
        end
      end
      if (active_count > 1) $fatal(1, "More than one macro active per bank");
      if (!rst_n) begin
        held_req[b] = 0;
        if (req_ready[b] !== 0 || rsp_valid[b] !== 0 || active_count != 0)
          $fatal(1, "Reset did not suppress requests/responses");
        if (pending[b]) begin
          cancelled = cancelled + 1;
          $fdisplay(trace_fd, "%0d,reset_cancel,%0d,%0d,-1,-1,0000", cycles, b, pending_addr[b]);
        end
        pending[b] = 0;
      end else begin
        if (held_req[b] && (!req_valid[b] ||
            {req_write[b],req_addr[b],req_wdata[b]} !== held_payload[b]))
          $fatal(1, "Producer changed a stalled request bank=%0d", b);
        held_req[b] = req_valid[b] && !req_ready[b];
        held_payload[b] = {req_write[b],req_addr[b],req_wdata[b]};
        if (rsp_valid[b] !== pending[b])
          $fatal(1, "Read latency/valid mismatch bank=%0d cycle=%0d", b, cycles);
        if (pending[b] && rsp_data[b] !== expected_response[b])
          $fatal(1, "Read data mismatch bank=%0d addr=%0d expected=%h got=%h",
                 b, pending_addr[b], expected_response[b], rsp_data[b]);
        if (pending[b] && rsp_ready[b]) begin
          responses = responses + 1;
          $fdisplay(trace_fd, "%0d,read_response,%0d,%0d,%0d,%0d,%04h", cycles,
                    b, pending_addr[b], b*8+pending_addr[b]/128,
                    pending_addr[b]%128, rsp_data[b]);
          pending[b] = 0;
        end
        if (req_valid[b] && !req_ready[b]) blocked_cycles = blocked_cycles + 1;
        if (req_valid[b] && req_ready[b]) begin
          if (req_write[b]) begin
            reference_mem[b][req_addr[b]] = req_wdata[b];
            writes = writes + 1;
            $fdisplay(trace_fd, "%0d,write,%0d,%0d,%0d,%0d,%04h", cycles,
                      b, req_addr[b], selected, req_addr[b]%128, req_wdata[b]);
          end else begin
            if (pending[b]) $fatal(1, "Overwrote a stalled read response");
            pending[b] = 1;
            expected_response[b] = reference_mem[b][req_addr[b]];
            pending_addr[b] = req_addr[b];
            reads = reads + 1;
            $fdisplay(trace_fd, "%0d,read_request,%0d,%0d,%0d,%0d,0000", cycles,
                      b, req_addr[b], selected, req_addr[b]%128);
          end
        end
      end
    end
    #1;
    for (integer s = 0; s < 24; s++) begin
      if (!reading_now[s] && macro_q[s] !== old_q[s])
        $fatal(1, "Q changed during write, reset or standby macro=%0d", s);
    end
  end

  task automatic tick;
    @(posedge clk);
    #2;
  endtask

  task automatic stop_requests;
    @(negedge clk);
    req_valid = 0;
    tick();
  endtask

  task automatic all_banks(input bit writing, input integer address);
    @(negedge clk);
    req_valid = 3'b111;
    req_write = {3{writing}};
    for (integer b = 0; b < 3; b++) begin
      req_addr[b] = address;
      req_wdata[b] = pattern(b, address);
    end
    #1;
    if (req_ready !== 3'b111) $fatal(1, "Unexpected backpressure");
    tick();
  endtask

  initial begin : tests
    integer writes_before, reads_before;
    logic [31:0] fp32_bits;
    if (!$value$plusargs("trace=%s", trace_path)) trace_path = "sram_access_trace.csv";
    trace_fd = $fopen(trace_path, "w");
    if (trace_fd == 0) $fatal(1, "Cannot create access trace");
    $fdisplay(trace_fd, "cycle,event,bank,word_addr,macro_index,macro_addr,data_hex");
    for (integer b = 0; b < 3; b++) pending[b] = 0;

    // Reset gates even actively asserted write requests; SRAM is not cleared.
    #1;
    rst_n = 0;
    req_valid = 3'b111;
    req_write = 3'b111;
    tick(); tick();
    @(negedge clk);
    req_valid = 0;
    rst_n = 1;
    tick();
    all_banks(0, 21); // Unknown storage remains unknown, not a fabricated zero.
    stop_requests();
    $display("CHECK reset suppression and uninitialized storage PASS");

    // Every address in every macro, including all seven macro boundaries.
    for (integer a = 0; a < 1024; a++) all_banks(1, a);
    stop_requests();
    for (integer a = 0; a < 1024; a++) all_banks(0, a);
    stop_requests();
    $display("CHECK all 3072 words, three parallel banks, back-to-back reads PASS");

    // Explicit FP32 low/high reconstruction straddling a macro boundary.
    // Address 127 is deliberately used to exercise the transport, not tile alignment.
    @(negedge clk);
    req_valid = 3'b001; req_write = 3'b001; req_addr[0] = 127; req_wdata[0] = 16'h5678;
    tick();
    @(negedge clk);
    req_addr[0] = 128; req_wdata[0] = 16'h3f81;
    tick();
    @(negedge clk);
    req_write = 0; req_addr[0] = 127;
    tick();
    if (rsp_valid[0] !== 1 || rsp_data[0] !== 16'h5678) $fatal(1, "FP32 low word");
    fp32_bits[15:0] = rsp_data[0];
    @(negedge clk);
    req_addr[0] = 128;
    tick();
    fp32_bits[31:16] = rsp_data[0];
    if (fp32_bits !== 32'h3f815678) $fatal(1, "FP32 low/high assembly");
    stop_requests();
    $display("CHECK FP32 two-word transport and macro-boundary selection PASS");

    // Read->write to the same address: pending read returns old Q, a later read
    // returns the new word. No simultaneous read/write request is representable.
    all_banks(0, 255);
    @(negedge clk);
    req_write = 3'b111;
    for (integer b = 0; b < 3; b++) req_wdata[b] = pattern(b, 255) ^ 16'hffff;
    tick();
    all_banks(0, 255);
    stop_requests();

    // Hold bank A's response. Other banks must continue; a queued A write must
    // neither corrupt Q nor reach its macro until the response is consumed.
    all_banks(0, 400);
    @(negedge clk);
    rsp_ready = 3'b110;
    req_valid = 3'b111; req_write = 3'b111;
    req_addr[0] = 700; req_addr[1] = 701; req_addr[2] = 702;
    req_wdata[0] = 16'hbabe; req_wdata[1] = 16'hcafe; req_wdata[2] = 16'h1234;
    writes_before = writes;
    repeat (4) tick();
    if (writes != writes_before+8 || req_ready[0] !== 0)
      $fatal(1, "Stalled bank blocked other banks or accepted a write");
    @(negedge clk);
    rsp_ready = 3'b111;
    tick(); // Pending read consumed and queued write accepted at this edge.
    stop_requests();
    @(negedge clk);
    req_valid = 3'b001; req_write = 0; req_addr[0] = 700;
    tick();
    if (rsp_data[0] !== 16'hbabe) $fatal(1, "Queued write not preserved");
    stop_requests();
    $display("CHECK response backpressure, write blocking and independent banks PASS");

    // Standby inhibits new requests and keeps a stalled response available.
    all_banks(0, 511);
    @(negedge clk);
    standby = 3'b111; rsp_ready = 0;
    req_valid = 3'b111; req_write = 3'b111;
    writes_before = writes;
    reads_before = reads;
    repeat (3) tick();
    if (writes != writes_before || reads != reads_before || rsp_valid !== 3'b111)
      $fatal(1, "Standby changed access/response state");
    @(negedge clk);
    rsp_ready = 3'b111;
    tick();
    @(negedge clk);
    standby = 0;
    tick();
    stop_requests(); // Held requests are accepted on wake-up, never withdrawn.
    $display("CHECK standby with pending response and wake-up PASS");

    // Reset cancels three held responses but leaves all SRAM contents intact.
    all_banks(0, 1023);
    @(negedge clk);
    rsp_ready = 0; req_valid = 3'b111; req_write = 3'b111;
    req_wdata = '0; rst_n = 0;
    tick(); tick();
    @(negedge clk);
    req_valid = 0; rsp_ready = 3'b111; rst_n = 1;
    tick();
    all_banks(0, 1023);
    stop_requests();
    $display("CHECK reset cancellation and SRAM content retention PASS");

    if (reads != responses+cancelled || writes < 3072 || responses < 3072 || cancelled != 3)
      $fatal(1, "Incomplete scoreboard accounting");
    $display("PASS sram_fp32_cache_adapter writes=%0d read_requests=%0d read_responses=%0d reset_cancelled=%0d blocked_bank_cycles=%0d macro_pin_checks=%0d cycles=%0d",
             writes, reads, responses, cancelled, blocked_cycles, pin_checks, cycles);
    $fclose(trace_fd);
    $finish;
  end

  initial begin
    #100000;
    $fatal(1, "SRAM wrapper test timeout");
  end
endmodule
