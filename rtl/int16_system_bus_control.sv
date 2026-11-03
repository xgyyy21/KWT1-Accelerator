// 32-bit System-Bus ICB MMIO slave. Matrix bases are byte addresses.
module int16_system_bus_control #(
  parameter int ADDR_WIDTH=32,
  parameter logic [ADDR_WIDTH-1:0] CTRL_BASE='0
)(
  input logic clk,rst_n,
  input logic s_icb_cmd_valid,
  output logic s_icb_cmd_ready,
  input logic [ADDR_WIDTH-1:0] s_icb_cmd_addr,
  input logic s_icb_cmd_read,
  input logic [31:0] s_icb_cmd_wdata,
  input logic [3:0] s_icb_cmd_wmask,
  output logic s_icb_rsp_valid,
  input logic s_icb_rsp_ready,
  output logic [31:0] s_icb_rsp_rdata,
  output logic s_icb_rsp_err,
  input logic engine_busy,engine_done,engine_error,output logic engine_start,
  output logic [ADDR_WIDTH-1:0] a_base,b_base,bias_base,dst_base,
  output logic [15:0] matrix_m,matrix_k,matrix_n,output logic [4:0] out_shift
);
  localparam logic[7:0] A_CTRL=8'h00,A_STATUS=8'h04,A_A=8'h08,A_B=8'h0c,
    A_DST=8'h10,A_M=8'h14,A_K=8'h18,A_N=8'h1c,A_BIAS=8'h20,
    A_SHIFT=8'h24,A_FORMAT=8'h28;
  logic done_sticky,error_sticky,start_guard,fire,legal_read,legal_write;
  logic in_window,aligned,full_write_mask;
  logic[7:0] off;
  assign in_window=(s_icb_cmd_addr>=CTRL_BASE)&&
                   ((s_icb_cmd_addr-CTRL_BASE)<=ADDR_WIDTH'(8'hff));
  assign off=8'(s_icb_cmd_addr-CTRL_BASE);
  assign aligned=(s_icb_cmd_addr[1:0]==2'b00);
  assign full_write_mask=(s_icb_cmd_wmask==4'b1111);
  assign s_icb_cmd_ready=rst_n&&(!s_icb_rsp_valid||s_icb_rsp_ready);
  assign fire=s_icb_cmd_valid&&s_icb_cmd_ready;
  assign legal_read=in_window&&aligned&&(off==A_STATUS||
    off==A_A||off==A_B||off==A_DST||off==A_M||off==A_K||off==A_N||
    off==A_BIAS||off==A_SHIFT||off==A_FORMAT);
  assign legal_write=in_window&&aligned&&full_write_mask&&(off==A_CTRL||
    off==A_A||off==A_B||off==A_DST||off==A_M||off==A_K||off==A_N||
    off==A_BIAS||off==A_SHIFT);
  always_ff @(posedge clk or negedge rst_n)begin
    if(!rst_n)begin
      s_icb_rsp_valid<=0;s_icb_rsp_rdata<=0;s_icb_rsp_err<=0;engine_start<=0;
      a_base<=0;b_base<=0;bias_base<=0;dst_base<=0;matrix_m<=0;
      matrix_k<=0;matrix_n<=0;out_shift<=0;done_sticky<=0;
      error_sticky<=0;start_guard<=0;
    end else begin
      engine_start<=0;
      if(s_icb_rsp_valid&&s_icb_rsp_ready)s_icb_rsp_valid<=0;
      if(fire)begin
        s_icb_rsp_valid<=1;s_icb_rsp_rdata<=0;s_icb_rsp_err<=0;
        if(s_icb_cmd_read?!legal_read:!legal_write)s_icb_rsp_err<=1;
        else if(!s_icb_cmd_read&&engine_busy)s_icb_rsp_err<=1;
        else if(!s_icb_cmd_read)case(off)
          A_CTRL:begin
            if(s_icb_cmd_wdata[1])done_sticky<=0;
            if(s_icb_cmd_wdata[2])error_sticky<=0;
            if(s_icb_cmd_wdata[0]&&!start_guard)begin engine_start<=1;start_guard<=1;
              done_sticky<=0;error_sticky<=0;end
            else if(s_icb_cmd_wdata[0])s_icb_rsp_err<=1;
          end
          A_A:a_base<=s_icb_cmd_wdata;A_B:b_base<=s_icb_cmd_wdata;
          A_BIAS:bias_base<=s_icb_cmd_wdata;A_DST:dst_base<=s_icb_cmd_wdata;
          A_M:matrix_m<=s_icb_cmd_wdata[15:0];A_K:matrix_k<=s_icb_cmd_wdata[15:0];
          A_N:matrix_n<=s_icb_cmd_wdata[15:0];A_SHIFT:out_shift<=s_icb_cmd_wdata[4:0];
          default:;
        endcase
        else case(off)
          A_STATUS:s_icb_rsp_rdata<={29'd0,error_sticky|engine_error,
            done_sticky|engine_done,engine_busy};
          A_A:s_icb_rsp_rdata<=a_base;A_B:s_icb_rsp_rdata<=b_base;
          A_BIAS:s_icb_rsp_rdata<=bias_base;A_DST:s_icb_rsp_rdata<=dst_base;
          A_M:s_icb_rsp_rdata<=matrix_m;A_K:s_icb_rsp_rdata<=matrix_k;
          A_N:s_icb_rsp_rdata<=matrix_n;A_SHIFT:s_icb_rsp_rdata<=out_shift;
          A_FORMAT:s_icb_rsp_rdata<={8'd1,8'd16,8'd48,8'd16};
          default:s_icb_rsp_rdata<=0;
        endcase
      end
      if(engine_done)begin done_sticky<=1;start_guard<=0;end
      if(engine_error)begin error_sticky<=1;start_guard<=0;end
    end
  end
endmodule
