// RTL-vs-software handoff test. Inputs are the package's one-16-bit-word-per-line
// .mem files; bias is low-word then high-word, matching the software manifest.
module int16_software_handoff_tb;
  localparam integer M=99, K=64, N=256, PE_LANES=16;
  localparam logic [31:0] A_BASE=32'h00001000, B_BASE=32'h00020000,
    BIAS_BASE=32'h00040000, DST_BASE=32'h00041000;
  localparam integer MEM_WORDS=262144;

  logic clk=0; always #5 clk=~clk;
  logic rst_n=0, s_valid=0, s_read=0, s_rsp_ready=1;
  logic [31:0] s_addr=0, s_wdata=0; logic [3:0] s_wmask=4'hf;
  wire s_ready, s_rsp_valid; wire [31:0] s_rsp_rdata; wire s_rsp_err;
  wire m_valid, m_read, m_rsp_ready; wire [31:0] m_addr, m_wdata;
  wire [3:0] m_wmask; logic m_ready, m_rsp_valid=0, m_rsp_err=0;
  logic [31:0] m_rsp_rdata=0; wire busy, done, error;
  wire [15:0] row_index, col_index, k_index, k_block;

  logic [15:0] a_words [0:M*K-1];
  logic [15:0] b_words [0:K*N-1];
  logic [15:0] bias_words [0:2*N-1];
  logic [15:0] expected_words [0:M*N-1];
  logic [15:0] memory [0:MEM_WORDS-1];
  logic response_pending; logic [31:0] response_data; logic response_error;
  integer cycle_count, command_count, response_count, output_write_count;
  integer layer_id, shift_cfg, mismatch_count, first_bad;
  string a_file, b_file, bias_file, expected_file;

  int16_accelerator_top dut(
    .clk(clk),.rst_n(rst_n),
    .s_icb_cmd_valid(s_valid),.s_icb_cmd_ready(s_ready),
    .s_icb_cmd_addr(s_addr),.s_icb_cmd_read(s_read),
    .s_icb_cmd_wdata(s_wdata),.s_icb_cmd_wmask(s_wmask),
    .s_icb_rsp_valid(s_rsp_valid),.s_icb_rsp_ready(s_rsp_ready),
    .s_icb_rsp_rdata(s_rsp_rdata),.s_icb_rsp_err(s_rsp_err),
    .m_icb_cmd_valid(m_valid),.m_icb_cmd_ready(m_ready),
    .m_icb_cmd_addr(m_addr),.m_icb_cmd_read(m_read),
    .m_icb_cmd_wdata(m_wdata),.m_icb_cmd_wmask(m_wmask),
    .m_icb_rsp_valid(m_rsp_valid),.m_icb_rsp_ready(m_rsp_ready),
    .m_icb_rsp_rdata(m_rsp_rdata),.m_icb_rsp_err(m_rsp_err),
    .accel_busy(busy),.accel_done(done),.accel_error(error),
    .current_row(row_index),.current_col(col_index),.current_k(k_index),
    .current_k_block(k_block));

  always_comb m_ready = rst_n && !response_pending && !m_rsp_valid &&
                        ((cycle_count % 7) != 0);

  always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) begin
      response_pending<=0; response_data<=0; response_error<=0;
      m_rsp_valid<=0; m_rsp_rdata<=0; m_rsp_err<=0; cycle_count<=0;
      command_count<=0; response_count<=0; output_write_count<=0;
    end else begin
      cycle_count<=cycle_count+1;
      if(m_rsp_valid && m_rsp_ready) begin m_rsp_valid<=0; response_pending<=0; end
      if(m_valid && m_ready) begin
        command_count<=command_count+1;
        if(!m_read && m_addr>=DST_BASE && m_addr<DST_BASE+(M*N*2))
          output_write_count<=output_write_count+1;
        if(m_read) begin
          response_data<={memory[(m_addr>>1)+1],memory[m_addr>>1]};
          response_error<=0; response_pending<=1;
        end else begin
          if(m_wmask[1:0]==2'b11) memory[m_addr>>1]<=m_wdata[15:0];
          if(m_wmask[3:2]==2'b11) memory[(m_addr>>1)+1]<=m_wdata[31:16];
          response_data<=0; response_error<=0; response_pending<=1;
        end
      end
      if(response_pending && !m_rsp_valid) begin
        m_rsp_valid<=1; m_rsp_rdata<=response_data; m_rsp_err<=response_error;
      end
      if(m_rsp_valid && m_rsp_ready) response_count<=response_count+1;
    end
  end

  task automatic mmio_write(input logic [7:0] offset, input logic [31:0] value);
    begin
      @(negedge clk); s_valid=1; s_read=0; s_addr={24'd0,offset};
      s_wdata=value; s_wmask=4'hf;
      do @(posedge clk); while(!s_ready);
      @(negedge clk); s_valid=0; s_addr=0; s_wdata=0;
      while(!s_rsp_valid) @(posedge clk);
      if(s_rsp_err) $fatal(1,"MMIO write failed offset=%h",offset);
      @(negedge clk);
    end
  endtask

  initial begin
    if(!$value$plusargs("layer=%d",layer_id) ||
       !$value$plusargs("shift=%d",shift_cfg) ||
       !$value$plusargs("a=%s",a_file) || !$value$plusargs("b=%s",b_file) ||
       !$value$plusargs("bias=%s",bias_file) ||
       !$value$plusargs("expected=%s",expected_file))
      $fatal(1,"missing layer/shift or input file plusargs");
    if(layer_id<0 || layer_id>11 || (shift_cfg!=15 && shift_cfg!=16))
      $fatal(1,"invalid layer or output shift");

    $readmemh(a_file,a_words,0,M*K-1);
    $readmemh(b_file,b_words,0,K*N-1);
    $readmemh(bias_file,bias_words,0,2*N-1);
    $readmemh(expected_file,expected_words,0,M*N-1);
    for(integer i=0;i<MEM_WORDS;i=i+1) memory[i]=0;
    for(integer i=0;i<M*K;i=i+1) memory[(A_BASE>>1)+i]=a_words[i];
    for(integer i=0;i<K*N;i=i+1) memory[(B_BASE>>1)+i]=b_words[i];
    // The input package stores each signed INT32 bias as low 16-bit word first.
    for(integer i=0;i<2*N;i=i+1) memory[(BIAS_BASE>>1)+i]=bias_words[i];

    repeat(4) @(negedge clk); rst_n=1;
    mmio_write(8'h08,A_BASE); mmio_write(8'h0c,B_BASE);
    mmio_write(8'h20,BIAS_BASE); mmio_write(8'h10,DST_BASE);
    mmio_write(8'h14,M); mmio_write(8'h18,K); mmio_write(8'h1c,N);
    mmio_write(8'h24,shift_cfg); mmio_write(8'h00,1);
    while(!done && !error) @(posedge clk);
    if(error) $fatal(1,"accelerator ERROR layer=%0d row=%0d col=%0d k=%0d",
      layer_id,row_index,col_index,k_index);
    @(posedge clk);
    if(command_count!=response_count)
      $fatal(1,"DONE before final response: commands=%0d responses=%0d",
        command_count,response_count);
    if(output_write_count!=((M*N)/2))
      $fatal(1,"write command count mismatch got=%0d expected=%0d",
        output_write_count,(M*N)/2);

    mismatch_count=0; first_bad=-1;
    for(integer i=0;i<M*N;i=i+1) begin
      if(memory[(DST_BASE>>1)+i]!==expected_words[i]) begin
        mismatch_count=mismatch_count+1;
        if(first_bad<0) first_bad=i;
        if(mismatch_count<=8)
          $display("MISMATCH layer=%0d index=%0d row=%0d col=%0d actual=%04h expected=%04h",
            layer_id,i,i/N,i%N,memory[(DST_BASE>>1)+i],expected_words[i]);
      end
    end
    $display("RESULT layer=%0d shift=%0d outputs=%0d writes=%0d commands=%0d responses=%0d mismatches=%0d first_bad=%0d",
      layer_id,shift_cfg,M*N,output_write_count,command_count,response_count,
      mismatch_count,first_bad);
    if(mismatch_count!=0) $fatal(1,"software candidate comparison mismatch");
    $display("PASS int16_software_handoff_tb layer=%0d",layer_id);
    $finish;
  end
  initial begin #200000000; $fatal(1,"timeout layer=%0d",layer_id); end
endmodule
