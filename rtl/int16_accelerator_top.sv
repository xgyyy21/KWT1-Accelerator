// Active INT16 accelerator: 16 PE lanes and signed INT48 accumulation.
// The 32-bit System Bus carries two adjacent INT16 elements per command.
module int16_accelerator_top #(
  parameter int ADDR_WIDTH=32,
  parameter logic [ADDR_WIDTH-1:0] CTRL_BASE='0,
  parameter bit STRICT_COMPETITION_SHAPES=1'b1
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
  output logic m_icb_cmd_valid,
  input logic m_icb_cmd_ready,
  output logic [ADDR_WIDTH-1:0] m_icb_cmd_addr,
  output logic m_icb_cmd_read,
  output logic [31:0] m_icb_cmd_wdata,
  output logic [3:0] m_icb_cmd_wmask,
  input logic m_icb_rsp_valid,
  output logic m_icb_rsp_ready,
  input logic [31:0] m_icb_rsp_rdata,
  input logic m_icb_rsp_err,
  output logic accel_busy,accel_done,accel_error,
  output logic [15:0] current_row,current_col,current_k,current_k_block
);
  localparam int LANES=16;
  typedef enum logic[3:0] {S_IDLE,S_BIAS_REQ,S_BIAS_WAIT,S_A_REQ,S_A_WAIT,
    S_B_REQ,S_B_WAIT,S_MAC,S_RESULT,S_WB_REQ,S_WB_WAIT,S_DONE,S_ERROR} state_t;
  state_t state;
  logic engine_start,supported_shape,config_aligned,pe_result_valid;
  logic master_outstanding,master_rsp_valid_q,master_rsp_ready;
  logic [31:0] master_rsp_rdata_q;
  logic master_rsp_err_q,master_cmd_fire,master_rsp_fire;
  logic [ADDR_WIDTH-1:0] a_base,b_base,bias_base,dst_base;
  logic [15:0] matrix_m,matrix_k,matrix_n;
  logic [4:0] out_shift,bias_idx,active_cols;
  logic [3:0] pair_idx;
  logic [31:0] a_pair;
  logic [63:0] address_calc;
  logic signed [15:0] b_vector[LANES],pe_result[LANES];
  logic signed [31:0] bias_vector[LANES];
  logic signed [47:0] pe_raw_sum[LANES];

  int16_system_bus_control #(.ADDR_WIDTH(ADDR_WIDTH),.CTRL_BASE(CTRL_BASE)) u_control(
    .clk(clk),.rst_n(rst_n),.s_icb_cmd_valid(s_icb_cmd_valid),
    .s_icb_cmd_ready(s_icb_cmd_ready),.s_icb_cmd_addr(s_icb_cmd_addr),
    .s_icb_cmd_read(s_icb_cmd_read),.s_icb_cmd_wdata(s_icb_cmd_wdata),
    .s_icb_cmd_wmask(s_icb_cmd_wmask),.s_icb_rsp_valid(s_icb_rsp_valid),
    .s_icb_rsp_ready(s_icb_rsp_ready),.s_icb_rsp_rdata(s_icb_rsp_rdata),
    .s_icb_rsp_err(s_icb_rsp_err),
    .engine_busy(accel_busy),.engine_done(accel_done),
    .engine_error(accel_error),.engine_start(engine_start),
    .a_base(a_base),.b_base(b_base),.bias_base(bias_base),
    .dst_base(dst_base),.matrix_m(matrix_m),.matrix_k(matrix_k),
    .matrix_n(matrix_n),.out_shift(out_shift));

  int16_pe_array_16 u_array(
    .clk(clk),.rst_n(rst_n),
    .start((state==S_MAC)&&(current_k==0)),
    .mac_valid(state==S_MAC),
    .mac_last((state==S_MAC)&&(current_k+1==matrix_k)),
    .a_in(current_k[0]?$signed(a_pair[31:16]):$signed(a_pair[15:0])),
    .b_in(b_vector),.bias_in(bias_vector),.out_shift(out_shift),
    .result_valid(pe_result_valid),.result(pe_result),.raw_sum(pe_raw_sum));

  assign supported_shape=STRICT_COMPETITION_SHAPES ?
    (((matrix_m==16'd99)&&(matrix_k==16'd64)&&(matrix_n==16'd256))||
     ((matrix_m==16'd99)&&(matrix_k==16'd256)&&(matrix_n==16'd64))) :
    ((matrix_m!=0)&&(matrix_n!=0)&&
     ((matrix_k==16'd64)||(matrix_k==16'd256)));
  assign config_aligned=((a_base[1:0]==0)&&(b_base[1:0]==0)&&
                         (bias_base[1:0]==0)&&(dst_base[1:0]==0));
  assign accel_busy=(state!=S_IDLE)&&(state!=S_DONE)&&(state!=S_ERROR);
  assign accel_done=(state==S_DONE);
  assign accel_error=(state==S_ERROR);
  assign current_k_block=current_k>>5;
  assign master_cmd_fire=m_icb_cmd_valid&&m_icb_cmd_ready;
  assign master_rsp_ready=(state==S_BIAS_WAIT)||(state==S_A_WAIT)||
                          (state==S_B_WAIT)||(state==S_WB_WAIT);
  assign m_icb_rsp_ready=!master_rsp_valid_q&&
                         (master_outstanding||master_cmd_fire);
  assign master_rsp_fire=m_icb_rsp_valid&&m_icb_rsp_ready;

  always_comb begin
    m_icb_cmd_valid=1'b0;m_icb_cmd_read=1'b1;m_icb_cmd_addr='0;
    m_icb_cmd_wdata='0;m_icb_cmd_wmask=4'b0000;address_calc=64'd0;
    case(state)
      S_BIAS_REQ:begin
        address_calc={32'd0,bias_base}+(64'(current_col+bias_idx)*4);
        m_icb_cmd_valid=1'b1;m_icb_cmd_addr=ADDR_WIDTH'(address_calc);
      end
      S_A_REQ:if(!current_k[0])begin
        address_calc={32'd0,a_base}+
          (((64'(current_row)*matrix_k)+(current_k&16'hfffe))*2);
        m_icb_cmd_valid=1'b1;m_icb_cmd_addr=ADDR_WIDTH'(address_calc);
      end
      S_B_REQ:begin
        address_calc={32'd0,b_base}+
          (((64'(current_k)*matrix_n)+current_col+(pair_idx*2))*2);
        m_icb_cmd_valid=1'b1;m_icb_cmd_addr=ADDR_WIDTH'(address_calc);
      end
      S_WB_REQ:begin
        address_calc={32'd0,dst_base}+
          (((64'(current_row)*matrix_n)+current_col+(pair_idx*2))*2);
        m_icb_cmd_valid=1'b1;m_icb_cmd_read=1'b0;
        m_icb_cmd_addr=ADDR_WIDTH'(address_calc);
        m_icb_cmd_wdata={pe_result[pair_idx*2+1],pe_result[pair_idx*2]};
        m_icb_cmd_wmask=(pair_idx*2+1<active_cols)?4'b1111:4'b0011;
      end
      default:begin end
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
      state<=S_IDLE;current_row<=0;current_col<=0;current_k<=0;
      bias_idx<=0;pair_idx<=0;active_cols<=0;a_pair<=0;
      master_outstanding<=1'b0;master_rsp_valid_q<=1'b0;
      master_rsp_rdata_q<='0;master_rsp_err_q<=1'b0;
      for(integer i=0;i<LANES;i=i+1)begin b_vector[i]<=0;bias_vector[i]<=0;end
    end else begin
      if(master_rsp_valid_q&&master_rsp_ready)
        master_rsp_valid_q<=1'b0;
      if(master_cmd_fire)
        master_outstanding<=1'b1;
      if(master_rsp_fire)begin
        master_rsp_valid_q<=1'b1;
        master_rsp_rdata_q<=m_icb_rsp_rdata;
        master_rsp_err_q<=m_icb_rsp_err;
        master_outstanding<=1'b0;
      end
      case(state)
        S_IDLE:if(engine_start)begin
          current_row<=0;current_col<=0;current_k<=0;bias_idx<=0;pair_idx<=0;
          active_cols<=(matrix_n<LANES)?matrix_n:LANES;
          for(integer i=0;i<LANES;i=i+1)begin b_vector[i]<=0;bias_vector[i]<=0;end
          if(supported_shape&&config_aligned) state<=S_BIAS_REQ;
          else state<=S_ERROR;
        end
        S_BIAS_REQ:if(m_icb_cmd_valid&&m_icb_cmd_ready)state<=S_BIAS_WAIT;
        S_BIAS_WAIT:if(master_rsp_valid_q&&master_rsp_ready)begin
          if(master_rsp_err_q)state<=S_ERROR;
          else begin
            bias_vector[bias_idx]<=$signed(master_rsp_rdata_q);
            if(bias_idx+1>=active_cols)begin bias_idx<=0;current_k<=0;state<=S_A_REQ;end
            else begin bias_idx<=bias_idx+1'b1;state<=S_BIAS_REQ;end
          end
        end
        S_A_REQ:begin
          if(current_k[0])begin pair_idx<=0;state<=S_B_REQ;end
          else if(m_icb_cmd_valid&&m_icb_cmd_ready)state<=S_A_WAIT;
        end
        S_A_WAIT:if(master_rsp_valid_q&&master_rsp_ready)begin
          if(master_rsp_err_q)state<=S_ERROR;
          else begin a_pair<=master_rsp_rdata_q;pair_idx<=0;state<=S_B_REQ;end
        end
        S_B_REQ:if(m_icb_cmd_valid&&m_icb_cmd_ready)state<=S_B_WAIT;
        S_B_WAIT:if(master_rsp_valid_q&&master_rsp_ready)begin
          if(master_rsp_err_q)state<=S_ERROR;
          else begin
            b_vector[pair_idx*2]<=$signed(master_rsp_rdata_q[15:0]);
            b_vector[pair_idx*2+1]<=((pair_idx*2+1)<active_cols)?
              $signed(master_rsp_rdata_q[31:16]):16'sd0;
            if(pair_idx+1>=((active_cols+1)>>1))begin pair_idx<=0;state<=S_MAC;end
            else begin pair_idx<=pair_idx+1'b1;state<=S_B_REQ;end
          end
        end
        S_MAC:begin
          if(current_k+1>=matrix_k)state<=S_RESULT;
          else begin current_k<=current_k+1'b1;state<=S_A_REQ;end
        end
        S_RESULT:if(pe_result_valid)begin pair_idx<=0;state<=S_WB_REQ;end
        S_WB_REQ:if(m_icb_cmd_valid&&m_icb_cmd_ready)state<=S_WB_WAIT;
        S_WB_WAIT:if(master_rsp_valid_q&&master_rsp_ready)begin
          if(master_rsp_err_q)state<=S_ERROR;
          else begin
          if(pair_idx+1>=((active_cols+1)>>1))begin
            pair_idx<=0;current_k<=0;bias_idx<=0;
            if(current_col+active_cols<matrix_n)begin
              current_col<=current_col+LANES;
              active_cols<=((matrix_n-(current_col+LANES))<LANES)?
                (matrix_n-(current_col+LANES)):LANES;
              state<=S_BIAS_REQ;
            end else if(current_row+1<matrix_m)begin
              current_row<=current_row+1'b1;current_col<=0;
              active_cols<=(matrix_n<LANES)?matrix_n:LANES;
              state<=S_BIAS_REQ;
            end else state<=S_DONE;
          end else begin
            pair_idx<=pair_idx+1'b1;
            state<=S_WB_REQ;
          end
          end
        end
        S_DONE:state<=S_IDLE;
        S_ERROR:if(engine_start)state<=S_IDLE;
        default:state<=S_ERROR;
      endcase
    end
  end
endmodule
