module int16_quantized_data_tb;
  localparam int MEM_WORDS=262144;
  localparam logic[31:0] A_BASE=32'h00001000,B_BASE=32'h00020000,
    BIAS_BASE=32'h00040000,DST_BASE=32'h00041000;
  logic clk=0;always #5 clk=~clk;
  logic rst_n=0,cmd_valid=0,cmd_read=0,rsp_ready=1;
  logic[31:0]cmd_addr=0,cmd_wdata=0;logic[3:0]cmd_wmask=4'hf;
  wire cmd_ready,rsp_valid;wire[31:0]rsp_rdata;wire rsp_err;
  wire m_valid,m_read,m_rsp_ready;wire[31:0]m_addr,m_wdata;
  wire[3:0]m_wmask;logic m_ready,m_rsp_valid=0,m_rsp_err=0;
  logic[31:0]m_rsp_rdata=0;wire busy,done,error;
  wire[15:0]row_index,col_index,k_index,k_block;
  logic signed[15:0]memory[0:MEM_WORDS-1];
  logic signed[15:0]a_data[0:65535],b_data[0:65535],expected[0:32767];
  logic signed[31:0]bias_data[0:255];
  logic response_pending;logic[31:0]response_data;logic response_error;
  integer m_dim,k_dim,n_dim,shift_cfg,cycle_count,commands_seen,responses_seen;
  integer a_count,b_count,bias_count,out_count;
  string a_file,b_file,bias_file,expected_file;

  int16_accelerator_top dut(
    .clk(clk),.rst_n(rst_n),
    .s_icb_cmd_valid(cmd_valid),.s_icb_cmd_ready(cmd_ready),
    .s_icb_cmd_addr(cmd_addr),.s_icb_cmd_read(cmd_read),
    .s_icb_cmd_wdata(cmd_wdata),.s_icb_cmd_wmask(cmd_wmask),
    .s_icb_rsp_valid(rsp_valid),.s_icb_rsp_ready(rsp_ready),
    .s_icb_rsp_rdata(rsp_rdata),.s_icb_rsp_err(rsp_err),
    .m_icb_cmd_valid(m_valid),.m_icb_cmd_ready(m_ready),
    .m_icb_cmd_addr(m_addr),.m_icb_cmd_read(m_read),
    .m_icb_cmd_wdata(m_wdata),.m_icb_cmd_wmask(m_wmask),
    .m_icb_rsp_valid(m_rsp_valid),.m_icb_rsp_ready(m_rsp_ready),
    .m_icb_rsp_rdata(m_rsp_rdata),.m_icb_rsp_err(m_rsp_err),
    .accel_busy(busy),.accel_done(done),.accel_error(error),
    .current_row(row_index),.current_col(col_index),.current_k(k_index),
    .current_k_block(k_block));

  always_comb m_ready=rst_n&&!response_pending&&!m_rsp_valid&&(cycle_count%7!=0);
  always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin response_pending<=0;response_data<=0;response_error<=0;
      m_rsp_valid<=0;m_rsp_rdata<=0;m_rsp_err<=0;cycle_count<=0;
      commands_seen<=0;responses_seen<=0;end
    else begin
      cycle_count<=cycle_count+1;
      if(m_rsp_valid&&m_rsp_ready)begin m_rsp_valid<=0;response_pending<=0;end
      if(m_valid&&m_ready)begin
        commands_seen<=commands_seen+1;
        if(m_read)begin
          response_data<={memory[(m_addr>>1)+1],memory[m_addr>>1]};
          response_error<=0;response_pending<=1;
        end else begin
          if(m_wmask[1:0]==2'b11)memory[m_addr>>1]<=m_wdata[15:0];
          if(m_wmask[3:2]==2'b11)memory[(m_addr>>1)+1]<=m_wdata[31:16];
          response_data<=0;response_error<=0;response_pending<=1;
        end
      end
      if(response_pending&&!m_rsp_valid)begin
        m_rsp_valid<=1;m_rsp_rdata<=response_data;m_rsp_err<=response_error;
      end
      if(m_rsp_valid&&m_rsp_ready)responses_seen<=responses_seen+1;
    end
  end

  task automatic mmio_write(input[7:0]offset,input[31:0]value);
    begin
      @(negedge clk);cmd_valid=1;cmd_read=0;cmd_addr=offset;
      cmd_wdata=value;cmd_wmask=4'hf;
      do @(posedge clk);while(!cmd_ready);
      @(negedge clk);cmd_valid=0;cmd_addr=0;cmd_wdata=0;
      while(!rsp_valid)@(posedge clk);
      if(rsp_err)$fatal(1,"MMIO write failed offset=%h",offset);
    end
  endtask

  initial begin
    if(!$value$plusargs("m=%d",m_dim)||!$value$plusargs("k=%d",k_dim)||
       !$value$plusargs("n=%d",n_dim)||!$value$plusargs("shift=%d",shift_cfg)||
       !$value$plusargs("a=%s",a_file)||!$value$plusargs("b=%s",b_file)||
       !$value$plusargs("bias=%s",bias_file)||!$value$plusargs("expected=%s",expected_file))
      $fatal(1,"missing M/K/N/shift or tensor image plusargs");
    if(m_dim!=99||n_dim!=256||(k_dim!=64&&k_dim!=256)||shift_cfg<0||shift_cfg>31)
      $fatal(1,"unsupported competition dimensions or shift");
    a_count=m_dim*k_dim;b_count=k_dim*n_dim;bias_count=n_dim;out_count=m_dim*n_dim;
    $readmemh(a_file,a_data,0,a_count-1);
    $readmemh(b_file,b_data,0,b_count-1);
    $readmemh(bias_file,bias_data,0,bias_count-1);
    $readmemh(expected_file,expected,0,out_count-1);
    for(integer i=0;i<MEM_WORDS;i=i+1)memory[i]=0;
    for(integer i=0;i<a_count;i=i+1)memory[(A_BASE>>1)+i]=a_data[i];
    for(integer i=0;i<b_count;i=i+1)memory[(B_BASE>>1)+i]=b_data[i];
    for(integer i=0;i<bias_count;i=i+1)begin
      memory[(BIAS_BASE>>1)+2*i]=bias_data[i][15:0];
      memory[(BIAS_BASE>>1)+2*i+1]=bias_data[i][31:16];
    end
    repeat(4)@(negedge clk);rst_n=1;
    mmio_write(8'h08,A_BASE);mmio_write(8'h0c,B_BASE);
    mmio_write(8'h20,BIAS_BASE);mmio_write(8'h10,DST_BASE);
    mmio_write(8'h14,m_dim);mmio_write(8'h18,k_dim);mmio_write(8'h1c,n_dim);
    mmio_write(8'h24,shift_cfg);mmio_write(8'h00,1);
    while(!done&&!error)@(posedge clk);
    if(error)$fatal(1,"accelerator ERROR row=%0d col=%0d k=%0d",
      row_index,col_index,k_index);
    @(posedge clk);
    if(commands_seen!=responses_seen)
      $fatal(1,"DONE before final bus response: commands=%0d responses=%0d",
        commands_seen,responses_seen);
    for(integer i=0;i<out_count;i=i+1)
      if(memory[(DST_BASE>>1)+i]!==expected[i])
        $fatal(1,"output mismatch index=%0d actual=%h expected=%h",i,
          memory[(DST_BASE>>1)+i],expected[i]);
    $display("PASS int16_quantized_data_tb M=%0d K=%0d N=%0d outputs=%0d shift=%0d",
      m_dim,k_dim,n_dim,out_count,shift_cfg);
    $finish;
  end
  initial begin #200000000;$fatal(1,"quantized-data test timeout");end
endmodule
