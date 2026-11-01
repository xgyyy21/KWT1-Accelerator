`timescale 1ns/1ps
// Pin/control-only contract test for the 1024x16 SRAM adapter.
// No SRAM model is instantiated: Q timing/hold behavior and EMAW legality are
// deliberately outside this test's claims.
module sram_1024x16_adapter_pin_tb;
  localparam logic [2:0] TEST_EMA = 3'd2;
  localparam logic [1:0] TEST_EMAW = 2'd3;

  logic clk = 1'b0;
  always #5 clk = ~clk;
  logic rst_n = 1'b0;
  logic standby = 1'b0;
  logic req_valid = 1'b0;
  wire req_ready;
  logic req_write = 1'b0;
  logic [9:0] req_addr = '0;
  logic [15:0] req_wdata = '0;
  wire rsp_valid;
  logic rsp_ready = 1'b1;
  wire [15:0] rsp_data;
  wire [7:0] macro_cen, macro_gwen, macro_ret1n;
  wire [7:0][15:0] macro_wen, macro_d;
  wire [7:0][6:0] macro_a;
  wire [7:0][2:0] macro_ema;
  wire [7:0][1:0] macro_emaw;
  logic [7:0][15:0] macro_q = 'x;
  integer checked_writes = 0;
  integer checked_reads = 0;
  integer checked_pin_states = 0;

  sram_1024x16_adapter #(
    .EMA_VALUE(TEST_EMA), .EMAW_VALUE(TEST_EMAW)
  ) dut (.*);

  task automatic check_all_idle(input string where_text);
    begin
      for (integer s = 0; s < 8; s++) begin
        if (macro_cen[s] !== 1'b1 || macro_gwen[s] !== 1'b1 ||
            macro_wen[s] !== 16'hffff || macro_a[s] !== 7'b0 ||
            macro_d[s] !== 16'b0)
          $fatal(1, "%s: inactive macro pins not idle slot=%0d", where_text, s);
      end
      checked_pin_states = checked_pin_states + 1;
    end
  endtask

  task automatic check_selected(
    input logic is_write,
    input logic [9:0] address,
    input logic [15:0] data
  );
    integer selected_slot;
    integer selected_count;
    begin
      selected_slot = address[9:7];
      selected_count = 0;
      for (integer s = 0; s < 8; s++) begin
        if (macro_ema[s] !== TEST_EMA || macro_emaw[s] !== TEST_EMAW ||
            macro_ret1n[s] !== 1'b1)
          $fatal(1, "Config/RET1N pin forwarding mismatch slot=%0d", s);
        if (s == selected_slot) begin
          if (macro_cen[s] !== 1'b0 || macro_gwen[s] !== !is_write ||
              macro_wen[s] !== (is_write ? 16'h0000 : 16'hffff) ||
              macro_a[s] !== address[6:0] || macro_d[s] !== data)
            $fatal(1, "Selected macro control/address/data mismatch addr=%0d", address);
          selected_count = selected_count + 1;
        end else if (macro_cen[s] !== 1'b1 || macro_gwen[s] !== 1'b1 ||
                     macro_wen[s] !== 16'hffff || macro_a[s] !== 7'b0 ||
                     macro_d[s] !== 16'b0) begin
          $fatal(1, "Unselected macro not idle addr=%0d slot=%0d", address, s);
        end
      end
      if (selected_count != 1)
        $fatal(1, "Expected exactly one selected macro, got %0d", selected_count);
      checked_pin_states = checked_pin_states + 1;
    end
  endtask

  task automatic issue_and_check(input logic is_write,
                                  input logic [9:0] address,
                                  input logic [15:0] data);
    begin
      @(negedge clk);
      req_valid = 1'b1;
      req_write = is_write;
      req_addr = address;
      req_wdata = data;
      rsp_ready = 1'b1;
      #1;
      if (req_ready !== 1'b1)
        $fatal(1, "Expected request acceptance addr=%0d", address);
      @(posedge clk);
      #1;
      @(negedge clk);
      #1;
      check_selected(is_write, address, data);
      req_valid = 1'b0;
      req_write = 1'b0;
      @(posedge clk);
      #1;
      check_selected(is_write, address, data);
      if (is_write) begin
        if (rsp_valid !== 1'b0)
          $fatal(1, "Write unexpectedly produced a read response");
        checked_writes = checked_writes + 1;
      end else begin
        if (rsp_valid !== 1'b1)
          $fatal(1, "Executed read did not raise rsp_valid addr=%0d", address);
        // Intentionally do not inspect rsp_data: this test has no SRAM model.
        checked_reads = checked_reads + 1;
      end
      @(negedge clk);
      #1;
      check_all_idle("macro command retired");
      @(posedge clk);
      #1;
      if (rsp_valid !== 1'b0)
        $fatal(1, "Response did not retire with rsp_ready asserted");
    end
  endtask

  initial begin : tests
    logic [15:0] data;
    #1;
    req_valid = 1'b1;
    req_write = 1'b1;
    rst_n = 1'b0;
    #1;
    if (req_ready !== 1'b0)
      $fatal(1, "Reset must suppress requests");
    @(negedge clk);
    #1;
    check_all_idle("reset");
    @(posedge clk);
    @(negedge clk);
    req_valid = 1'b0;
    rst_n = 1'b1;

    // Check every 10-bit word address for read and write pin decode.
    for (integer a = 0; a < 1024; a++) begin
      data = 16'h5a3c ^ (16'(a * 16'h003d));
      issue_and_check(1'b1, 10'(a), data);
    end
    for (integer a = 0; a < 1024; a++) begin
      data = 16'ha591 ^ (16'(a * 16'h001b));
      issue_and_check(1'b0, 10'(a), data);
    end

    // The command remains stable across the macro sampling edge even though
    // rsp_valid raises and request backpressure is asserted immediately after.
    @(negedge clk);
    req_valid = 1'b1; req_write = 1'b0; req_addr = 10'd127; req_wdata = 16'h0000;
    rsp_ready = 1'b0;
    #1;
    if (!req_ready) $fatal(1, "Initial read was not accepted");
    @(posedge clk); #1;
    if (req_ready) $fatal(1, "Pending macro command did not block a second request");
    @(negedge clk); #1;
    check_selected(1'b0, 10'd127, 16'h0000);
    req_valid = 1'b1; req_write = 1'b1; req_addr = 10'd128;
    req_wdata = 16'hcafe;
    @(posedge clk); #1;
    if (!rsp_valid) $fatal(1, "Expected pending read response");
    check_selected(1'b0, 10'd127, 16'h0000);
    @(negedge clk); #1;
    check_all_idle("response backpressure");
    if (req_ready !== 1'b0) $fatal(1, "Pending response failed to backpressure");
    repeat (2) begin
      @(posedge clk); #1;
      if (!rsp_valid || req_ready)
        $fatal(1, "Pending response/backpressure was not held");
      check_all_idle("response held");
    end
    @(negedge clk);
    rsp_ready = 1'b1;
    #1;
    if (!req_ready) $fatal(1, "Request did not resume when response ready");
    @(posedge clk); #1;
    if (rsp_valid) $fatal(1, "Consumed response remained valid");
    @(negedge clk); #1;
    check_selected(1'b1, 10'd128, 16'hcafe);
    req_valid = 1'b0; req_write = 1'b0;
    @(posedge clk); #1;
    check_selected(1'b1, 10'd128, 16'hcafe);
    @(negedge clk); #1;
    check_all_idle("write after held response");

    // Standby suppresses macro activity and request acceptance; the held
    // request remains available to be accepted after wake-up.
    @(negedge clk);
    standby = 1'b1; req_valid = 1'b1; req_write = 1'b1;
    req_addr = 10'd1023; req_wdata = 16'hbeef;
    #1;
    if (req_ready !== 1'b0) $fatal(1, "Standby accepted a request");
    check_all_idle("standby");
    @(posedge clk); #1;
    @(negedge clk);
    standby = 1'b0;
    #1;
    if (req_ready !== 1'b1) $fatal(1, "Held request did not resume after standby");
    @(posedge clk); #1;
    @(negedge clk);
    #1;
    check_selected(1'b1, 10'd1023, 16'hbeef);
    req_valid = 1'b0;
    @(posedge clk); #1;
    check_selected(1'b1, 10'd1023, 16'hbeef);
    @(negedge clk); #1;
    check_all_idle("standby write retired");

    // Reset cancels control state and prevents a macro operation; SRAM content
    // is intentionally outside scope because this TB has no storage model.
    @(negedge clk);
    req_valid = 1'b1; req_write = 1'b0; req_addr = 10'd1023;
    rsp_ready = 1'b0;
    #1;
    @(posedge clk); #1;
    @(negedge clk); #1;
    check_selected(1'b0, 10'd1023, req_wdata);
    req_valid = 1'b0;
    @(posedge clk); #1;
    if (!rsp_valid) $fatal(1, "Expected pending read before reset");
    @(negedge clk);
    rst_n = 1'b0;
    #1;
    if (req_ready || rsp_valid) $fatal(1, "Reset failed to cancel response state");
    check_all_idle("reset cancels response");
    @(posedge clk);

    $display("PASS sram_1024x16_adapter_pin_tb writes=%0d reads=%0d pin_states=%0d scope=pin_control_only EMAW_FORWARDING_ONLY Q_UNCHECKED",
             checked_writes, checked_reads, checked_pin_states);
    $finish;
  end

  initial begin
    #1000000;
    $fatal(1, "SRAM adapter pin test timeout");
  end
endmodule
