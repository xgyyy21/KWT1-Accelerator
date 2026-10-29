`timescale 1ns/1ps
module fp32_bus_fault_guard_tb;
  logic clk=0, rst_n=0;
  always #5 clk=~clk;
  logic req_valid=0, req_write=0;
  logic [31:0] req_addr=32'd127;
  logic [15:0] req_wdata=16'h5678;
  wire req_ready, rsp_valid;
  wire [15:0] rsp_rdata;
  wire bus_req_valid, bus_req_write;
  wire [31:0] bus_req_addr;
  wire [15:0] bus_req_wdata;
  logic bus_req_ready=0, bus_rsp_valid=0, bus_error=0;
  logic [15:0] bus_rsp_rdata=16'hbeef;
  wire pending, error;
  wire [2:0] error_code;
  integer checks=0, fd, cycle=0;
  string path;
  fp32_bus_fault_guard #(.TIMEOUT_CYCLES(4)) dut (.*);
  task automatic step;
    @(posedge clk); #1;
  endtask
  task automatic reset_bus;
    @(negedge clk);
    rst_n=0; req_valid=0; bus_req_ready=0; bus_rsp_valid=0; bus_error=0;
    step();
    if(error || pending || req_ready || bus_req_valid || rsp_valid)
      $fatal(1,"reset did not suppress channels");
    @(negedge clk); rst_n=1;
  endtask
  task automatic check_fault(input integer code);
    if (!error || error_code != code || pending || req_ready || bus_req_valid || rsp_valid)
      $fatal(1,"fault mismatch code=%0d actual=%0d",code,error_code);
    checks=checks+1;
    // Late read replies and new requests must not escape the fail-stop state.
    @(negedge clk); bus_rsp_valid=1; req_valid=1; bus_req_ready=1;
    repeat(3) begin
      step();
      if(!error || error_code!=code || req_ready || bus_req_valid || rsp_valid)
        $fatal(1,"fault not sticky or late reply escaped");
    end
  endtask
  always @(posedge clk) begin
    cycle=cycle+1;
    #2;
    $fdisplay(fd,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",
      cycle,rst_n,req_valid,req_ready,bus_req_valid,bus_req_ready,
      bus_rsp_valid,bus_error,pending,rsp_valid,error,error_code);
  end
  initial begin
    if(!$value$plusargs("trace=%s",path)) path="bus_fault_trace.csv";
    fd=$fopen(path,"w");
    if(!fd) $fatal(1,"trace open failed");
    $fdisplay(fd,"cycle,rst_n,req_valid,req_ready,bus_req_valid,bus_req_ready,bus_rsp_valid,bus_error,pending,rsp_valid,error,error_code");
    reset_bus();
    @(negedge clk); req_valid=1; req_write=1;
    repeat(3) begin
      step();
      if(error || !bus_req_valid || bus_req_addr!=127 || bus_req_wdata!=16'h5678)
        $fatal(1,"held request changed or timed out early");
    end
    // Acceptance on the last permitted edge wins over the timeout.
    @(negedge clk); bus_req_ready=1;
    step();
    if(error || pending) $fatal(1,"last-edge write failed");
    checks=checks+1;
    @(negedge clk); req_write=0; req_addr=128;
    step();
    if(!pending) $fatal(1,"read not pending");
    @(negedge clk); req_valid=0;
    repeat(3) begin step(); if(error) $fatal(1,"early response timeout"); end
    @(negedge clk); bus_rsp_valid=1;
    #1;
    if(!rsp_valid || rsp_rdata!=16'hbeef) $fatal(1,"last-edge response lost");
    step();
    if(error || pending) $fatal(1,"last-edge response failed");
    checks=checks+1;

    reset_bus();
    @(negedge clk); req_valid=1;
    repeat(3) begin step(); if(error) $fatal(1,"early request timeout"); end
    step(); check_fault(1);
    reset_bus();
    @(negedge clk); req_valid=1; req_write=0; bus_req_ready=1;
    step();
    @(negedge clk); req_valid=0;
    repeat(3) begin step(); if(error) $fatal(1,"early read timeout"); end
    step(); check_fault(2);
    reset_bus();
    @(negedge clk); req_valid=1; req_write=0; bus_req_ready=1;
    step();
    @(negedge clk); req_valid=0; bus_error=1; bus_rsp_valid=1;
    #1; if(rsp_valid) $fatal(1,"faulting read exposed as successful response");
    step(); check_fault(3);
    reset_bus();
    @(negedge clk); bus_rsp_valid=1;
    step(); check_fault(4);
    reset_bus();
    @(negedge clk); req_valid=1; req_write=1; bus_req_ready=1;
    step();
    if(error || pending || !req_ready) $fatal(1,"reset recovery failed");
    checks=checks+1;
    @(negedge clk); req_valid=0;
    step();
    $display("PASS fp32_bus_fault_guard checks=%0d timeout_cycles=4 scope=standalone_prototype",checks);
    $fclose(fd); $finish;
  end
  initial begin #10000; $fatal(1,"test watchdog"); end
endmodule
