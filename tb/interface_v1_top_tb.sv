`timescale 1ns/1ps
// Actual protocol-neutral top, using software-branch .mem inputs.
// The hand case is explicitly zero-padded to K=32 in external model memory.
// This is NOT an E203 simulation and NOT a 19-column formal PE trace.
module interface_v1_top_tb;
  localparam integer A=256,B=4096,BIAS=8192,Y=12288;
  logic clk=0;always #5 clk=~clk;
  logic rst_n=0,nice_req_valid=0,nice_req_write=0;
  logic [31:0] nice_req_addr=0,nice_req_wdata=0;
  wire nice_req_ready,nice_rsp_valid;
  wire [31:0] nice_rsp_rdata;
  wire sys_req_valid,sys_req_write;
  wire [31:0] sys_req_addr;
  wire [15:0] sys_req_wdata;
  logic sys_req_ready=0,sys_rsp_valid=0;
  logic [15:0] sys_rsp_rdata=0;
  wire accel_done,accel_error,tile_busy;
  logic [15:0] mem[0:16383];
  logic [15:0] xi[0:127],wi[0:127],bi[0:3],yi[0:7];
  integer fd,rf,of,df,cycle=0,job=0,writes=0,reads=0,last_write=-1;
  integer i,r,c,k,mq,nq,kq,guard,mac_count=0;
  logic pending=0,was_stalled=0;
  logic [31:0] read_addr=0,held_addr=0;
  logic held_write=0;
  logic [15:0] held_data=0;
  logic [31:0] got,expected;
  fp32_accelerator_top #(.STRICT_COMPETITION_SHAPES(0)) dut(
    .clk(clk),.rst_n(rst_n),.nice_req_valid(nice_req_valid),.nice_req_write(nice_req_write),
    .nice_req_addr(nice_req_addr),.nice_req_wdata(nice_req_wdata),
    .nice_req_ready(nice_req_ready),.nice_rsp_valid(nice_rsp_valid),.nice_rsp_rdata(nice_rsp_rdata),
    .sys_req_valid(sys_req_valid),.sys_req_write(sys_req_write),.sys_req_addr(sys_req_addr),
    .sys_req_wdata(sys_req_wdata),.sys_req_ready(sys_req_ready),.sys_rsp_valid(sys_rsp_valid),
    .sys_rsp_rdata(sys_rsp_rdata),.accel_done(accel_done),.accel_error(accel_error),.tile_busy(tile_busy));
  always @(negedge clk) sys_req_ready = rst_n && ((cycle%5)!=0) && ((cycle%5)!=1);
  always @(posedge clk) begin
    cycle=cycle+1;
    if(!rst_n) begin pending<=0;sys_rsp_valid<=0;was_stalled<=0;end
    else begin
      if(was_stalled && (!sys_req_valid || sys_req_addr!==held_addr ||
          sys_req_write!==held_write || sys_req_wdata!==held_data))
        $fatal(1,"payload changed under request backpressure");
      was_stalled<=sys_req_valid && !sys_req_ready;
      held_addr<=sys_req_addr;held_write<=sys_req_write;held_data<=sys_req_wdata;
      sys_rsp_valid<=pending;
      if(pending) sys_rsp_rdata<=mem[read_addr];
      pending<=0;
      if(sys_req_valid && sys_req_ready) begin
        if(sys_req_addr>=16384) $fatal(1,"model address out of range");
        $fdisplay(fd,"%0d,%0d,%0d,%0d,%04h",cycle,job,sys_req_write,sys_req_addr,sys_req_wdata);
        if(sys_req_write) begin
          if(sys_req_addr<Y || sys_req_addr>=Y+mq*nq*2) $fatal(1,"write outside output");
          mem[sys_req_addr]<=sys_req_wdata;writes=writes+1;last_write=cycle;
        end else begin
          pending<=1;read_addr<=sys_req_addr;reads=reads+1;
        end
      end
      if(sys_rsp_valid) $fdisplay(rf,"%0d,%0d,%04h",cycle,job,sys_rsp_rdata);
    end
  end
  // Record actual PE(0,0) retirement signals; no software-generated trace.
  always @(negedge clk) begin
    if(rst_n && dut.u_tile_engine.u_compute.u_array.trace_valid[0][0]) begin
      $fdisplay(df,"%0d,%0d,%0d,%0d,%08h,%08h,%08h,%08h,%08h",cycle,job,mac_count,
        dut.u_tile_engine.u_compute.u_array.trace_k[0][0],
        dut.u_tile_engine.u_compute.u_array.trace_x_bits[0][0],
        dut.u_tile_engine.u_compute.u_array.trace_w_bits[0][0],
        dut.u_tile_engine.u_compute.u_array.trace_acc_before_bits[0][0],
        dut.u_tile_engine.u_compute.u_array.trace_product_bits[0][0],
        dut.u_tile_engine.u_compute.u_array.trace_acc_after_bits[0][0]);
      if(job==2 && mac_count==31 &&
          dut.u_tile_engine.u_compute.u_array.trace_acc_after_bits[0][0]!==32'h40000000)
        $fatal(1,"K31 register partial sum mismatch");
      if(job==2 && mac_count==32 &&
          (dut.u_tile_engine.u_compute.u_array.trace_acc_before_bits[0][0]!==32'h40000000 ||
           dut.u_tile_engine.u_compute.u_array.trace_acc_after_bits[0][0]!==32'hbf800000))
        $fatal(1,"K32 register continuation mismatch");
      mac_count=mac_count+1;
    end
  end
  task automatic wr(input integer addr,input integer data);
    begin
      @(negedge clk);nice_req_addr=addr;nice_req_wdata=data;nice_req_valid=1;nice_req_write=1;
      @(negedge clk);nice_req_valid=0;nice_req_write=0;
    end
  endtask
  task automatic status_check(input logic [31:0] expected_status);
    begin
      @(negedge clk);nice_req_addr=4;nice_req_valid=1;nice_req_write=0;
      @(negedge clk);
      if(!nice_rsp_valid || nice_rsp_rdata!==expected_status)
        $fatal(1,"status mismatch got=%08h expected=%08h",nice_rsp_rdata,expected_status);
      nice_req_valid=0;
    end
  endtask
  task automatic run_job(input integer which);
    begin
      job=which;writes=0;reads=0;last_write=-1;mac_count=0;
      for(i=0;i<16384;i=i+1) mem[i]=0;
      if(which==2) begin
        mq=1;kq=64;nq=1;
        $readmemh("software_snapshot/software/examples/fp32_hand_image/tile_x.mem",xi,0,127);
        $readmemh("software_snapshot/software/examples/fp32_hand_image/tile_w.mem",wi,0,127);
        $readmemh("software_snapshot/software/examples/fp32_hand_image/tile_bias.mem",bi,0,1);
        $readmemh("software_snapshot/software/examples/fp32_hand_image/tile_expected.mem",yi,0,1);
        for(i=0;i<128;i=i+1) begin mem[A+i]=xi[i];mem[B+i]=wi[i];end
        for(i=0;i<2;i=i+1) mem[BIAS+i]=bi[i];
      end else begin
        mq=2;kq=32;nq=2;
        $readmemh("software_snapshot/software/examples/fp32_hand_image/x.mem",xi,0,7);
        $readmemh("software_snapshot/software/examples/fp32_hand_image/w.mem",wi,0,7);
        $readmemh("software_snapshot/software/examples/fp32_hand_image/bias.mem",bi,0,3);
        $readmemh("software_snapshot/software/examples/fp32_hand_image/expected.mem",yi,0,7);
        for(r=0;r<2;r=r+1) for(k=0;k<2;k=k+1)
          for(i=0;i<2;i=i+1) mem[A+(r*32+k)*2+i]=xi[(r*2+k)*2+i];
        for(k=0;k<2;k=k+1) for(c=0;c<2;c=c+1)
          for(i=0;i<2;i=i+1) mem[B+(k*2+c)*2+i]=wi[(k*2+c)*2+i];
        for(i=0;i<4;i=i+1) mem[BIAS+i]=bi[i];
      end
      for(i=0;i<mq*nq*2;i=i+1) mem[Y+i]=16'hdead;
      wr(8,A);wr(12,B);wr(32,BIAS);wr(16,Y);wr(20,mq);wr(24,kq);wr(28,nq);
      wr(0,1);
      guard=0;
      while(!accel_done && guard<200000) begin @(negedge clk);guard=guard+1;end
      if(!accel_done || accel_error || writes!=mq*nq*2 || last_write>=cycle)
        $fatal(1,"job failed/done before final write job=%0d writes=%0d",job,writes);
      if(mac_count!=kq) $fatal(1,"PE00 MAC count mismatch");
      $display("DONE job=%0d last_write_cycle=%0d done_observed_cycle=%0d reads=%0d writes=%0d",job,last_write,cycle,reads,writes);
      for(r=0;r<mq;r=r+1) for(c=0;c<nq;c=c+1) begin
        got={mem[Y+(r*nq+c)*2+1],mem[Y+(r*nq+c)*2]};
        expected={yi[(r*nq+c)*2+1],yi[(r*nq+c)*2]};
        $fdisplay(of,"%0d,%0d,%0d,%0d,%08h,%08h",job,r,c,Y+(r*nq+c)*2,got,expected);
        if(got!==expected) $fatal(1,"output mismatch job=%0d r=%0d c=%0d got=%08h expected=%08h",job,r,c,got,expected);
      end
      repeat(3) @(negedge clk);status_check(2);
      wr(0,2);status_check(0);
      $display("interface_v1_top_tb PASS job=%0d M=%0d K=%0d N=%0d",job,mq,kq,nq);
    end
  endtask
  initial begin
    fd=$fopen("logs/system_requests.csv","w");rf=$fopen("logs/system_read_responses.csv","w");
    of=$fopen("logs/output_readback.csv","w");df=$fopen("logs/pe00_register_continuation.csv","w");
    if(!fd || !rf || !of || !df) $fatal(1,"cannot open interface logs");
    $fdisplay(fd,"cycle,job,is_write,word_address,write_data_hex");
    $fdisplay(rf,"cycle,job,actual_read_data_hex");
    $fdisplay(of,"job,row,column,low_word_address,actual_fp32_bits,software_expected_bits");
    $fdisplay(df,"cycle,job,mac_ordinal,local_k,x_bits,w_bits,acc_before_bits,product_bits,acc_after_bits");
    repeat(3) @(negedge clk);rst_n=1;
    status_check(0);run_job(1);run_job(2);run_job(3);
    $fclose(fd);$fclose(rf);$fclose(of);$fclose(df);
    $display("interface_v1_top_tb PASS jobs=3 outputs=9 stall_and_done_order=1 SRAM_psum_restore=NOT_USED");
    $finish;
  end
  initial begin #10000000;$fatal(1,"interface_v1_top_tb timeout");end
endmodule
