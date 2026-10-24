`timescale 1ns/1ps
// Tests actual behavioral SRAM ports, not an expected-data-only readback.
module interface_v1_memory_tb;
  logic clk=0; always #5 clk=~clk;
  logic rst_n=0, a_wr_en=0,b_wr_en=0,result_wr_en=0;
  logic a_rd_en=0,b_rd_en=0,result_rd_en=0;
  logic [9:0] a_wr_addr=0,b_wr_addr=0,result_wr_addr=0;
  logic [9:0] a_rd_addr=0,b_rd_addr=0,result_rd_addr=0;
  logic [15:0] a_wr_data=0,b_wr_data=0,result_wr_data=0;
  wire [15:0] a_rd_data,b_rd_data,result_rd_data;
  wire a_rd_valid,b_rd_valid,result_rd_valid;
  integer fd,cycle=0,i,checked=0;
  matrix_cache_manager dut(.*);
  always @(posedge clk) cycle=cycle+1;
  task automatic read_check(input integer addr,input logic [15:0] av,bv,cv);
    integer request_cycle;
    begin
      @(negedge clk);
      a_rd_en=1;b_rd_en=1;result_rd_en=1;
      a_rd_addr=addr;b_rd_addr=addr;result_rd_addr=addr;
      request_cycle=cycle;
      @(negedge clk);
      if(!a_rd_valid || !b_rd_valid || !result_rd_valid ||
         a_rd_data!==av || b_rd_data!==bv || result_rd_data!==cv)
        $fatal(1,"SRAM read mismatch address=%0d",addr);
      $fdisplay(fd,"%0d,%0d,A,%0d,%04h",request_cycle,cycle,addr,a_rd_data);
      $fdisplay(fd,"%0d,%0d,B,%0d,%04h",request_cycle,cycle,addr,b_rd_data);
      $fdisplay(fd,"%0d,%0d,C,%0d,%04h",request_cycle,cycle,addr,result_rd_data);
      checked=checked+3;
      a_rd_en=0;b_rd_en=0;result_rd_en=0;
    end
  endtask
  initial begin
    fd=$fopen("logs/sram_word_readback.csv","w");
    if(!fd) $fatal(1,"cannot open SRAM log");
    $fdisplay(fd,"request_observation_cycle,data_observation_cycle,bank,local_word_address,actual_word_hex");
    repeat(2) @(negedge clk);rst_n=1;
    for(i=0;i<1024;i=i+1) begin
      @(negedge clk);
      a_wr_en=1;b_wr_en=1;result_wr_en=1;
      a_wr_addr=i;b_wr_addr=i;result_wr_addr=i;
      a_wr_data=16'(i ^ 16'h1234);b_wr_data=16'(i ^ 16'habcd);
      result_wr_data=16'(i ^ 16'h5678);
    end
    @(negedge clk);a_wr_en=0;b_wr_en=0;result_wr_en=0;
    for(i=0;i<1024;i=i+1)
      read_check(i,16'(i ^ 16'h1234),16'(i ^ 16'habcd),16'(i ^ 16'h5678));
    // Same-edge read/write must return old data, including the last address.
    @(negedge clk);
    a_wr_en=1;b_wr_en=1;result_wr_en=1;
    a_rd_en=1;b_rd_en=1;result_rd_en=1;
    a_wr_addr=1023;b_wr_addr=1023;result_wr_addr=1023;
    a_rd_addr=1023;b_rd_addr=1023;result_rd_addr=1023;
    a_wr_data=16'h0000;b_wr_data=16'hbf40;result_wr_data=16'hc020;
    @(negedge clk);
    if(a_rd_data!==16'h11cb || b_rd_data!==16'ha832 || result_rd_data!==16'h5587)
      $fatal(1,"same-address SRAM did not return old word");
    a_wr_en=0;b_wr_en=0;result_wr_en=0;
    a_rd_en=0;b_rd_en=0;result_rd_en=0;
    rst_n=0;
    @(negedge clk);
    if(a_rd_valid || b_rd_valid || result_rd_valid) $fatal(1,"reset did not clear valid");
    rst_n=1;
    read_check(1023,16'h0000,16'hbf40,16'hc020);
    @(negedge clk);
    if(a_rd_valid || b_rd_valid || result_rd_valid) $fatal(1,"idle valid did not clear");
    $fclose(fd);
    $display("interface_v1_memory_tb PASS words_checked=%0d banks=3 depth=1024 old_data_and_reset_retention=1",checked);
    $finish;
  end
  initial begin #200000; $fatal(1,"interface_v1_memory_tb timeout");end
endmodule
