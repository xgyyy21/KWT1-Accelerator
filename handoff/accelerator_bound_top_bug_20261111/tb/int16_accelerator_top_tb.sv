module int16_accelerator_top_tb;
  localparam int M=2,K=64,N=18;
  localparam int A_BASE=32'h1000,B_BASE=32'h2000;
  localparam int BIAS_BASE=32'h8000,DST_BASE=32'h9000;
  logic clk=0;always #5 clk=~clk;
  logic rst_n=0,ctrl_valid=0,ctrl_read=0,ctrl_rsp_ready=1;
  logic[31:0]ctrl_addr=0,ctrl_wdata=0;logic[3:0]ctrl_wmask=4'b1111;
  wire ctrl_ready,ctrl_rsp_valid;wire[31:0]ctrl_rdata;wire ctrl_error;
  wire sys_valid,sys_read;wire[31:0]sys_addr,sys_wdata;wire[3:0]sys_wmask;
  logic sys_ready;wire sys_rsp_ready;logic sys_rsp_valid=0,sys_rsp_error=0;
  logic[31:0]sys_rsp_rdata=0;
  wire busy,done,error;wire[15:0]row_index,col_index,k_index,k_block;
  logic signed[15:0]memory[0:65535];
  logic response_pending;logic[31:0]pending_rdata;logic pending_error;
  logic pending_read;logic[15:0]read_word_index;integer cycle_count;
  integer commands_seen=0,responses_seen=0;logic[31:0]last_cmd_addr=0,last_rsp_data=0;
  int16_accelerator_top #(.STRICT_COMPETITION_SHAPES(0))dut(
    .clk(clk),.rst_n(rst_n),.s_icb_cmd_valid(ctrl_valid),
    .s_icb_cmd_ready(ctrl_ready),.s_icb_cmd_addr(ctrl_addr),
    .s_icb_cmd_read(ctrl_read),.s_icb_cmd_wdata(ctrl_wdata),
    .s_icb_cmd_wmask(ctrl_wmask),.s_icb_rsp_valid(ctrl_rsp_valid),
    .s_icb_rsp_ready(ctrl_rsp_ready),.s_icb_rsp_rdata(ctrl_rdata),
    .s_icb_rsp_err(ctrl_error),
    .m_icb_cmd_valid(sys_valid),.m_icb_cmd_ready(sys_ready),
    .m_icb_cmd_addr(sys_addr),.m_icb_cmd_read(sys_read),
    .m_icb_cmd_wdata(sys_wdata),.m_icb_cmd_wmask(sys_wmask),
    .m_icb_rsp_valid(sys_rsp_valid),.m_icb_rsp_ready(sys_rsp_ready),
    .m_icb_rsp_rdata(sys_rsp_rdata),.m_icb_rsp_err(sys_rsp_error),
    .accel_busy(busy),.accel_done(done),
    .accel_error(error),.current_row(row_index),.current_col(col_index),
    .current_k(k_index),.current_k_block(k_block));
  always_comb begin
    sys_ready=rst_n&&!response_pending&&!sys_rsp_valid&&((cycle_count%5)!=0);
  end
  always @(posedge clk or negedge rst_n)begin
    if(!rst_n)begin response_pending<=0;pending_rdata<=0;pending_error<=0;
      pending_read<=0;read_word_index<=0;sys_rsp_valid<=0;
      sys_rsp_rdata<=0;sys_rsp_error<=0;cycle_count<=0;end
    else begin
      cycle_count<=cycle_count+1;
      if(sys_valid&&sys_ready)begin commands_seen<=commands_seen+1;last_cmd_addr<=sys_addr;end
      if(sys_rsp_valid&&sys_rsp_ready)begin responses_seen<=responses_seen+1;last_rsp_data<=sys_rsp_rdata;end
      if(sys_rsp_valid&&sys_rsp_ready)begin
        sys_rsp_valid<=0;response_pending<=0;
      end
      if(sys_valid&&sys_ready)begin
        if(sys_read)begin
          pending_rdata<={memory[(sys_addr>>1)+1],memory[sys_addr>>1]};
          pending_read<=1;response_pending<=1;
        end else begin
          if(sys_wmask[1:0]==2'b11)memory[sys_addr>>1]<=sys_wdata[15:0];
          if(sys_wmask[3:2]==2'b11)memory[(sys_addr>>1)+1]<=sys_wdata[31:16];
          pending_rdata<=0;pending_read<=0;response_pending<=1;
        end
      end
      if(response_pending&&!sys_rsp_valid)begin
        sys_rsp_valid<=1;sys_rsp_rdata<=pending_rdata;
        sys_rsp_error<=pending_error;
      end
    end
  end
  task automatic mmio_write(input[7:0]offset,input[31:0]value);
    begin
      @(negedge clk);ctrl_valid=1;ctrl_read=0;ctrl_addr=offset;
      ctrl_wdata=value;ctrl_wmask=4'b1111;
      do @(posedge clk);while(!ctrl_ready);
      @(negedge clk);ctrl_valid=0;ctrl_read=0;ctrl_addr=0;ctrl_wdata=0;
      while(!ctrl_rsp_valid)@(posedge clk);
      if(ctrl_error)$fatal(1,"MMIO write failed offset=%h",offset);
    end
  endtask
  function automatic integer a_value(input integer r,input integer k);
    a_value=r?((k%5)-2):((k%7)-3);
  endfunction
  function automatic integer b_value(input integer k,input integer c);
    b_value=((k*3+c*5)%11)-5;
  endfunction
  function automatic integer bias_value(input integer c);bias_value=c*17-90;endfunction
  function automatic integer sat16(input longint signed value);
    if(value>32767)sat16=32767;else if(value< -32767)sat16=-32767;else sat16=value;
  endfunction
  task automatic put16(input integer byte_addr,input integer value);
    memory[byte_addr>>1]=value;
  endtask
  task automatic put32(input integer byte_addr,input integer value);
    begin memory[byte_addr>>1]=value[15:0];memory[(byte_addr>>1)+1]=value[31:16];end
  endtask
  initial begin
    for(integer i=0;i<65536;i=i+1)memory[i]=0;
    for(integer r=0;r<M;r=r+1)for(integer k=0;k<K;k=k+1)
      put16(A_BASE+2*(r*K+k),a_value(r,k));
    for(integer k=0;k<K;k=k+1)for(integer c=0;c<N;c=c+1)
      put16(B_BASE+2*(k*N+c),b_value(k,c));
    for(integer c=0;c<N;c=c+1)put32(BIAS_BASE+4*c,bias_value(c));
    repeat(4)@(negedge clk);rst_n=1;
    mmio_write(8'h08,A_BASE);mmio_write(8'h0c,B_BASE);
    mmio_write(8'h20,BIAS_BASE);mmio_write(8'h10,DST_BASE);
    mmio_write(8'h14,M);mmio_write(8'h18,K);mmio_write(8'h1c,N);
    mmio_write(8'h24,0);mmio_write(8'h00,1);
    while(!done&&!error)@(posedge clk);
    if(error)$fatal(1,"accelerator entered error state");
    @(posedge clk);
    if(commands_seen!=responses_seen)
      $fatal(1,"DONE before all accepted bus transactions responded: %0d/%0d",
        commands_seen,responses_seen);
    for(integer r=0;r<M;r=r+1)for(integer c=0;c<N;c=c+1)begin
      longint signed sum;integer expected;sum=bias_value(c);
      for(integer k=0;k<K;k=k+1)sum=sum+a_value(r,k)*b_value(k,c);
      expected=sat16(sum);
      if($signed(memory[(DST_BASE>>1)+r*N+c])!==expected)
        $fatal(1,"result mismatch r=%0d c=%0d got=%0d expected=%0d",r,c,
          $signed(memory[(DST_BASE>>1)+r*N+c]),expected);
    end
    // Run a second job without reset to verify K=256, state cleanup and
    // reloading of all INT16 operands/bias values.
    repeat(2)@(negedge clk);
    for(integer k=0;k<256;k=k+1)put16(A_BASE+2*k,a_value(0,k));
    for(integer k=0;k<256;k=k+1)for(integer c=0;c<16;c=c+1)
      put16(B_BASE+2*(k*16+c),b_value(k,c));
    for(integer c=0;c<16;c=c+1)begin
      put32(BIAS_BASE+4*c,bias_value(c));
      put16(DST_BASE+2*c,16'h55aa);
    end
    mmio_write(8'h14,1);mmio_write(8'h18,256);mmio_write(8'h1c,16);
    mmio_write(8'h00,1);
    while(!done&&!error)@(posedge clk);
    if(error)$fatal(1,"K256 job entered error state");
    @(posedge clk);
    if(commands_seen!=responses_seen)
      $fatal(1,"K256 DONE before all bus responses: %0d/%0d",
        commands_seen,responses_seen);
    for(integer c=0;c<16;c=c+1)begin
      longint signed sum;integer expected;sum=bias_value(c);
      for(integer k=0;k<256;k=k+1)sum=sum+a_value(0,k)*b_value(k,c);
      expected=sat16(sum);
      if($signed(memory[(DST_BASE>>1)+c])!==expected)
        $fatal(1,"K256 mismatch c=%0d got=%0d expected=%0d",c,
          $signed(memory[(DST_BASE>>1)+c]),expected);
    end
    $display("PASS int16_accelerator_top_tb K64_and_K256 PE=16 bus=32 continuous_jobs=2");
    $finish;
  end
  initial begin #5000000;
    $display("TIMEOUT state=%0d row=%0d col=%0d k=%0d bus_cmd=%b/%b rsp=%b/%b rsp_pending=%b master_outstanding=%b rspbuf=%b counts=%0d/%0d last=%h/%h",
      dut.state,row_index,col_index,k_index,sys_valid,sys_ready,
      sys_rsp_valid,sys_rsp_ready,response_pending,dut.master_outstanding,dut.master_rsp_valid_q,
      commands_seen,responses_seen,last_cmd_addr,last_rsp_data);
    $fatal(1,"timeout");
  end
endmodule
