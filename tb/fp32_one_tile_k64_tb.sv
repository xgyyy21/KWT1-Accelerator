`timescale 1ns/1ps

// Minimal full-path diagnostic: one complete 8x16 spatial tile, K=64.
// It isolates tile load/stream/compute/writeback from the 208-tile FFN1 run.
module fp32_one_tile_k64_tb;
  localparam logic [31:0] ONE = 32'h3f800000;
  localparam logic [31:0] EXPECTED = 32'h42820000; // 64 + bias 1
  localparam integer M=8, K=64, N=16, MEM_WORDS=20000;
  logic clk=0; always #5 clk=~clk;
  logic rst_n=0, nv=0, nw=0; logic [31:0] na=0,nwd=0;
  logic nr,nrv; logic [31:0] nrd;
  logic sv,sw,sready=1,srv; logic [31:0] sa; logic [15:0] swd,srd;
  logic done,error,busy,tile_start; logic [31:0] tile_index;
  logic [15:0] row_base,col_base,k_base,rows_valid,cols_valid,k_valid;
  logic task_first,task_last; logic [15:0] k_block_index,k_block_count;
  logic [15:0] mem [0:MEM_WORDS-1];
  logic pending=0; logic [31:0] pending_addr=0;
  integer i,r,c,guard,writes=0;

  fp32_accelerator_top #(.STRICT_COMPETITION_SHAPES(1'b0)) dut (
    .clk(clk),.rst_n(rst_n),.nice_req_valid(nv),.nice_req_write(nw),
    .nice_req_addr(na),.nice_req_wdata(nwd),.nice_req_ready(nr),
    .nice_rsp_valid(nrv),.nice_rsp_rdata(nrd),.sys_req_valid(sv),
    .sys_req_write(sw),.sys_req_addr(sa),.sys_req_wdata(swd),
    .sys_req_ready(sready),.sys_rsp_valid(srv),.sys_rsp_rdata(srd),
    .tile_start(tile_start),.tile_busy(busy),.accel_done(done),
    .accel_error(error),.tile_index(tile_index),.row_base(row_base),
    .col_base(col_base),.k_base(k_base),.rows_valid(rows_valid),
    .cols_valid(cols_valid),.k_valid(k_valid),.task_first(task_first),
    .task_last(task_last),.k_block_index(k_block_index),
    .k_block_count(k_block_count));

  always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin pending<=0;srv<=0;srd<=0; end
    else begin
      srv<=pending;
      if(pending) srd<=mem[pending_addr];
      pending<=0;
      if(sv && sready) begin
        if(sw) begin mem[sa]<=swd; writes=writes+1; end
        else begin pending<=1; pending_addr<=sa; end
      end
    end
  end

  task automatic wf(input integer base,input integer elem,input logic [31:0] bits);
    begin mem[base+elem*2]=bits[15:0];mem[base+elem*2+1]=bits[31:16]; end
  endtask
  task automatic wr(input logic [7:0] addr,input logic [31:0] data);
    begin @(negedge clk);na={24'd0,addr};nwd=data;nw=1;nv=1;
      @(negedge clk);nv=0;nw=0;na=0;nwd=0; end
  endtask

  initial begin
    for(i=0;i<MEM_WORDS;i=i+1) mem[i]=0;
    for(r=0;r<M;r=r+1) for(c=0;c<K;c=c+1) wf(0,r*K+c,ONE);
    for(r=0;r<K;r=r+1) for(c=0;c<N;c=c+1) wf(5000,r*N+c,ONE);
    for(c=0;c<N;c=c+1) wf(12000,c,ONE);
    repeat(3) @(negedge clk); rst_n=1;
    wr(8'h08,0);wr(8'h0c,5000);wr(8'h20,12000);wr(8'h10,15000);
    wr(8'h14,M);wr(8'h18,K);wr(8'h1c,N);wr(8'h00,1);
    guard=0;
    while(!done && guard<2000000) begin @(posedge clk);guard=guard+1; end
    if(!done || error) $fatal(1,"one tile failed done=%0d error=%0d cycles=%0d",done,error,guard);
    for(r=0;r<M;r=r+1) for(c=0;c<N;c=c+1)
      if({mem[15000+(r*N+c)*2+1],mem[15000+(r*N+c)*2]}!==EXPECTED)
        $fatal(1,"one tile mismatch row=%0d col=%0d",r,c);
    if(writes != M*N*2) $fatal(1,"one tile writes=%0d expected=%0d",writes,M*N*2);
    $display("PASS: one 8x16 tile K=64 outputs=%0d writes=%0d cycles=%0d",M*N,writes,guard);
    $finish;
  end
  initial begin #30000000; $fatal(1,"one tile timeout"); end
endmodule
