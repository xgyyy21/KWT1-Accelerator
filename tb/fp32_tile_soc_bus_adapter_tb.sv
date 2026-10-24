`timescale 1ns/1ps

module fp32_tile_soc_bus_adapter_tb;
  logic clk = 1'b0;
  always #5 clk = ~clk;
  logic rst_n = 1'b0;
  logic tile_req_valid = 1'b0;
  logic tile_req_write = 1'b0;
  logic [31:0] tile_req_addr = 0;
  logic [15:0] tile_req_wdata = 0;
  logic tile_req_ready, tile_rsp_valid;
  logic [15:0] tile_rsp_rdata;
  logic soc_req_valid, soc_req_write;
  logic [31:0] soc_req_addr;
  logic [15:0] soc_req_wdata;
  logic soc_req_ready = 1'b0;
  logic soc_rsp_valid = 1'b0;
  logic [15:0] soc_rsp_rdata = 0;
  logic busy, error;

  fp32_tile_soc_bus_adapter dut (
    .clk(clk), .rst_n(rst_n),
    .tile_req_valid(tile_req_valid), .tile_req_write(tile_req_write),
    .tile_req_addr(tile_req_addr), .tile_req_wdata(tile_req_wdata),
    .tile_req_ready(tile_req_ready), .tile_rsp_valid(tile_rsp_valid),
    .tile_rsp_rdata(tile_rsp_rdata), .soc_req_valid(soc_req_valid),
    .soc_req_write(soc_req_write), .soc_req_addr(soc_req_addr),
    .soc_req_wdata(soc_req_wdata), .soc_req_ready(soc_req_ready),
    .soc_rsp_valid(soc_rsp_valid), .soc_rsp_rdata(soc_rsp_rdata),
    .busy(busy), .error(error)
  );

  initial begin
    repeat (2) @(negedge clk);
    rst_n = 1'b1;

    // A request must remain visible while the SoC applies backpressure.
    @(negedge clk);
    tile_req_valid = 1'b1; tile_req_write = 1'b0;
    tile_req_addr = 32'h0000_0120;
    #1;
    if (tile_req_ready || !soc_req_valid || soc_req_addr != 32'h120)
      $fatal(1, "read request was not held under backpressure");

    @(negedge clk); soc_req_ready = 1'b1;
    #1;
    if (!tile_req_ready || !soc_req_valid || soc_req_write)
      $fatal(1, "read request was not accepted when ready");
    @(posedge clk); #1;
    tile_req_valid = 1'b0;
    if (!busy || tile_req_ready)
      $fatal(1, "read did not create one outstanding transaction");

    // A second request cannot pass before the response.
    @(negedge clk); tile_req_valid = 1'b1; tile_req_addr = 32'h200;
    #1;
    if (tile_req_ready || soc_req_addr != 32'h200)
      $fatal(1, "second read was not stalled");
    @(negedge clk); soc_rsp_rdata = 16'hbeef; soc_rsp_valid = 1'b1;
    #1;
    if (!tile_rsp_valid || tile_rsp_rdata != 16'hbeef)
      $fatal(1, "read response was not returned");
    @(posedge clk); #1;
    soc_rsp_valid = 1'b0; tile_req_valid = 1'b0;
    if (busy)
      $fatal(1, "read pending did not clear");

    // Writes are forwarded and do not wait for a response.
    @(negedge clk);
    tile_req_valid = 1'b1; tile_req_write = 1'b1;
    tile_req_addr = 32'h0000_0340; tile_req_wdata = 16'h1234;
    #1;
    if (!tile_req_ready || !soc_req_valid || !soc_req_write ||
        soc_req_addr != 32'h340 || soc_req_wdata != 16'h1234)
      $fatal(1, "write request was not forwarded");
    @(posedge clk); #1;
    tile_req_valid = 1'b0; tile_req_write = 1'b0;
    if (busy || error)
      $fatal(1, "write changed adapter state unexpectedly");

    $display("fp32_tile_soc_bus_adapter_tb PASS read backpressure/response and write forwarding");
    $finish;
  end

  initial begin
    #10000;
    $fatal(1, "fp32_tile_soc_bus_adapter_tb timeout");
  end
endmodule
