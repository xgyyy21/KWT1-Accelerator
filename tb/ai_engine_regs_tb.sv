`timescale 1ns/1ps
module ai_engine_regs_tb;
  logic clk=0; always #5 clk=~clk;
  logic rst_n=0, req_valid=0, req_write=0, req_ready, rsp_valid;
  logic [31:0] req_addr=0, req_wdata=0, rsp_rdata;
  logic busy=0, done=0, error=0, start;
  logic [31:0] src_a,src_b,dst; logic [15:0] m,k,n;
  ai_engine_regs dut(.*,.engine_busy(busy),.engine_done(done),.engine_error(error),
    .engine_start(start),.src_a_base(src_a),.src_b_base(src_b),.dst_base(dst),
    .matrix_m(m),.matrix_k(k),.matrix_n(n));
  task wr(input [7:0] a,input [31:0] d); begin @(negedge clk); req_addr=a; req_wdata=d; req_write=1; req_valid=1; @(negedge clk); req_valid=0; req_write=0; end endtask
  task rd_status(input [2:0] expected); begin
    @(negedge clk); req_addr=4; req_write=0; req_valid=1;
    @(negedge clk); req_valid=0;
    if(!rsp_valid || rsp_rdata!=={29'b0,expected}) $fatal(1,"status got=%h expected=%h",rsp_rdata,expected);
  end endtask
  initial begin
    repeat(2) @(negedge clk); rst_n=1;
    wr(8'h08,32'h100); wr(8'h0c,32'h200); wr(8'h10,32'h300); wr(8'h14,99); wr(8'h18,64); wr(8'h1c,256); wr(0,1);
    if(src_a!==32'h100 || src_b!==32'h200 || dst!==32'h300 || m!==99 || k!==64 || n!==256) $fatal(1,"register write failure");
    if(!start) $fatal(1,"start pulse missing");
    @(negedge clk); busy=1;
    wr(8'h08,32'hbad); wr(0,1);
    if(start || src_a!==32'h100) $fatal(1,"busy task was restarted/reconfigured");
    rd_status(3'b101);
    @(negedge clk); busy=0; done=1;
    @(negedge clk); done=0;
    repeat(3) @(negedge clk);
    rd_status(3'b110);
    wr(0,6); rd_status(0);
    @(negedge clk); error=1;
    @(negedge clk); error=0;
    rd_status(3'b100);
    wr(0,1); rd_status(0);
    // A previous job's completion must not survive an accepted new START.
    @(negedge clk); done=1; req_addr=0; req_write=1; req_valid=1; req_wdata=1;
    @(negedge clk); done=0; req_write=0; req_valid=0;
    rd_status(0);
    $display("ai_engine_regs_tb PASS"); $finish;
  end
  initial begin #10000; $fatal(1,"ai_engine_regs_tb timeout"); end
endmodule
