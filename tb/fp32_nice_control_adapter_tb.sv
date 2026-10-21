`timescale 1ns/1ps

module fp32_nice_control_adapter_tb;
  logic clk = 1'b0;
  always #5 clk = ~clk;
  logic rst_n = 1'b0;
  logic req_valid = 1'b0, req_write = 1'b0;
  logic [31:0] req_addr = 0, req_wdata = 0;
  logic req_ready, rsp_valid;
  logic [31:0] rsp_rdata;
  logic engine_busy = 1'b0, engine_done = 1'b0, engine_error = 1'b0;
  logic engine_start;
  logic [31:0] src_a_base, src_b_base, bias_base, dst_base;
  logic [15:0] matrix_m, matrix_k, matrix_n;

  fp32_nice_control_adapter dut (
    .clk(clk), .rst_n(rst_n), .nice_req_valid(req_valid),
    .nice_req_write(req_write), .nice_req_addr(req_addr),
    .nice_req_wdata(req_wdata), .nice_req_ready(req_ready),
    .nice_rsp_valid(rsp_valid), .nice_rsp_rdata(rsp_rdata),
    .engine_busy(engine_busy), .engine_done(engine_done),
    .engine_error(engine_error), .engine_start(engine_start),
    .src_a_base(src_a_base), .src_b_base(src_b_base),
    .bias_base(bias_base), .dst_base(dst_base),
    .matrix_m(matrix_m), .matrix_k(matrix_k), .matrix_n(matrix_n)
  );

  task automatic write_reg(input logic [7:0] addr, input logic [31:0] data);
    begin
      @(negedge clk);
      req_addr = addr; req_wdata = data; req_write = 1'b1; req_valid = 1'b1;
      @(posedge clk); #1;
      req_valid = 1'b0; req_write = 1'b0;
    end
  endtask

  task automatic read_reg(input logic [7:0] addr, input logic [31:0] expected);
    begin
      @(negedge clk);
      req_addr = addr; req_write = 1'b0; req_valid = 1'b1;
      @(posedge clk); #1;
      if (!rsp_valid || rsp_rdata !== expected)
        $fatal(1, "NICE read mismatch addr=%02x got=%08x expected=%08x",
               addr, rsp_rdata, expected);
      req_valid = 1'b0;
    end
  endtask

  initial begin
    repeat (2) @(negedge clk);
    rst_n = 1'b1;
    if (!req_ready) $fatal(1, "NICE request channel not ready");
    write_reg(8'h08, 32'h0000_1000);
    write_reg(8'h0c, 32'h0000_2000);
    write_reg(8'h20, 32'h0000_2800);
    write_reg(8'h10, 32'h0000_3000);
    write_reg(8'h14, 32'd99);
    write_reg(8'h18, 32'd64);
    write_reg(8'h1c, 32'd256);
    if (src_a_base !== 32'h1000 || src_b_base !== 32'h2000 ||
        bias_base !== 32'h2800 || dst_base !== 32'h3000 || matrix_m !== 99 || matrix_k !== 64 ||
        matrix_n !== 256)
      $fatal(1, "NICE configuration write mismatch");
    read_reg(8'h14, 32'd99);
    read_reg(8'h18, 32'd64);
    read_reg(8'h1c, 32'd256);
    write_reg(8'h00, 32'h1);
    if (!engine_start)
      $fatal(1, "NICE START did not produce engine_start");
    @(posedge clk); #1;
    if (engine_start) $fatal(1, "engine_start was not a pulse");
    $display("fp32_nice_control_adapter_tb PASS config/status/start control plane");
    $finish;
  end

  initial begin
    #10000;
    $fatal(1, "fp32_nice_control_adapter_tb timeout");
  end
endmodule
