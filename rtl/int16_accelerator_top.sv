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
  typedef enum logic[4:0] {S_IDLE,S_BIAS_REQ,S_BIAS_WAIT,S_A_REQ,S_A_WAIT,
    S_B_REQ,S_B_WAIT,S_MAC,S_RESULT,S_WB_REQ,S_WB_WAIT,S_DONE,S_ERROR,
    S_TILE_B_REQ,S_TILE_B_WAIT,S_CACHE_RD_REQ,S_CACHE_RD_WAIT} state_t;
  state_t state;
  logic engine_start,supported_shape,config_aligned,pe_result_valid,pe_input_error;
  logic master_outstanding,master_rsp_valid_q,master_rsp_ready;
  logic [31:0] master_rsp_rdata_q;
  logic master_rsp_err_q,master_cmd_fire,master_rsp_fire;
  logic master_cmd_pending_q;
  logic [ADDR_WIDTH-1:0] master_cmd_addr_q;
  logic master_cmd_read_q;
  logic [31:0] master_cmd_wdata_q;
  logic [3:0] master_cmd_wmask_q;
  logic command_build_valid,command_build_read;
  logic [ADDR_WIDTH-1:0] command_build_addr;
  logic [31:0] command_build_wdata;
  logic [3:0] command_build_wmask;
  logic [ADDR_WIDTH-1:0] a_base,b_base,bias_base,dst_base;
  logic [15:0] matrix_m,matrix_k,matrix_n;
  logic [4:0] out_shift,bias_idx,active_cols;
  logic [3:0] pair_idx;
  logic [31:0] a_pair;
  logic [63:0] address_calc;
  logic signed [15:0] b_vector[LANES],pe_result[LANES];
  logic signed [31:0] bias_vector[LANES];
  logic signed [47:0] pe_raw_sum[LANES];
  // K=64 layer-00 weight tile cache. One 64x16 INT16 tile is retained while
  // all M rows use the current output-column tile. Storage is sixteen
  // synchronous single-port SRAM banks, not a 2-D unpacked array.
  logic weight_cache_valid;
  logic cache_rd_en,cache_rd_valid;
  logic [6:0] cache_rd_addr,cache_wr_addr;
  logic [LANES-1:0] cache_wr_en;
  logic [LANES*16-1:0] cache_rd_data_bus,cache_wr_data_bus;
  // Retain a one-cycle PE result event across the S_MAC -> S_RESULT
  // transition so a bound-top state machine cannot miss final k=63.
  logic pe_result_seen_q;

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
    .result_valid(pe_result_valid),.input_error(pe_input_error),
    .result(pe_result),.raw_sum(pe_raw_sum));

  int16_weight_sram_16bank #(.LANES(LANES)) u_weight_cache_sram(
    .clk(clk),.rst_n(rst_n),.rd_en(cache_rd_en),.rd_addr(cache_rd_addr),
    .rd_valid(cache_rd_valid),.rd_data_bus(cache_rd_data_bus),
    .wr_en(cache_wr_en),.wr_addr(cache_wr_addr),.wr_data_bus(cache_wr_data_bus));

  // Cache writes happen only when a completed System-Bus read response is
  // being consumed. Reads are synchronous and are followed by WAIT state.
  always_comb begin
    cache_rd_en = (state==S_CACHE_RD_REQ);
    cache_rd_addr = current_k[6:0];
    cache_wr_addr = current_k[6:0];
    cache_wr_en = '0;
    cache_wr_data_bus = '0;
    if ((state==S_TILE_B_WAIT) && master_rsp_valid_q && master_rsp_ready &&
        !master_rsp_err_q) begin
      cache_wr_en[pair_idx*2] = 1'b1;
      cache_wr_data_bus[pair_idx*2*16 +: 16] = master_rsp_rdata_q[15:0];
      if ((pair_idx*2+1) < active_cols) begin
        cache_wr_en[pair_idx*2+1] = 1'b1;
        cache_wr_data_bus[(pair_idx*2+1)*16 +: 16] = master_rsp_rdata_q[31:16];
      end
    end
  end

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
  // The command boundary is registered.  Address generation and DTCM
  // window checking therefore cannot feed the shared-controller state in the
  // same combinational path as the accelerator FSM.
  assign m_icb_cmd_valid=master_cmd_pending_q;
  assign m_icb_cmd_addr=master_cmd_addr_q;
  assign m_icb_cmd_read=master_cmd_read_q;
  assign m_icb_cmd_wdata=master_cmd_wdata_q;
  assign m_icb_cmd_wmask=master_cmd_wmask_q;
  assign master_cmd_fire=m_icb_cmd_valid&&m_icb_cmd_ready;
  assign master_rsp_ready=(state==S_BIAS_WAIT)||(state==S_A_WAIT)||
                          (state==S_B_WAIT)||(state==S_WB_WAIT)||
                          (state==S_TILE_B_WAIT);
  assign m_icb_rsp_ready=!master_rsp_valid_q&&
                         (master_outstanding||master_cmd_fire);
  assign master_rsp_fire=m_icb_rsp_valid&&m_icb_rsp_ready;

  always_comb begin
    command_build_valid=1'b0;command_build_read=1'b1;
    command_build_addr='0;command_build_wdata='0;
    command_build_wmask=4'b0000;address_calc=64'd0;
    case(state)
      S_BIAS_REQ:begin
        address_calc={32'd0,bias_base}+(64'(current_col+bias_idx)*4);
        command_build_valid=1'b1;
        command_build_addr=ADDR_WIDTH'(address_calc);
      end
      S_TILE_B_REQ:begin
        address_calc={32'd0,b_base}+
          (((64'(current_k)*matrix_n)+current_col+(pair_idx*2))*2);
        command_build_valid=1'b1;
        command_build_addr=ADDR_WIDTH'(address_calc);
      end
      S_A_REQ:if(!current_k[0])begin
        address_calc={32'd0,a_base}+
          (((64'(current_row)*matrix_k)+(current_k&16'hfffe))*2);
        command_build_valid=1'b1;
        command_build_addr=ADDR_WIDTH'(address_calc);
      end
      S_B_REQ:begin
        address_calc={32'd0,b_base}+
          (((64'(current_k)*matrix_n)+current_col+(pair_idx*2))*2);
        command_build_valid=1'b1;
        command_build_addr=ADDR_WIDTH'(address_calc);
      end
      S_WB_REQ:begin
        address_calc={32'd0,dst_base}+
          (((64'(current_row)*matrix_n)+current_col+(pair_idx*2))*2);
        command_build_valid=1'b1;command_build_read=1'b0;
        command_build_addr=ADDR_WIDTH'(address_calc);
        command_build_wdata={pe_result[pair_idx*2+1],pe_result[pair_idx*2]};
        command_build_wmask=(pair_idx*2+1<active_cols)?4'b1111:4'b0011;
      end
      default:begin end
    endcase
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n)begin
      state<=S_IDLE;current_row<=0;current_col<=0;current_k<=0;
      bias_idx<=0;pair_idx<=0;active_cols<=0;a_pair<=0;
      weight_cache_valid<=1'b0;
      pe_result_seen_q<=1'b0;
      master_outstanding<=1'b0;master_rsp_valid_q<=1'b0;
      master_cmd_pending_q<=1'b0;master_cmd_addr_q<='0;
      master_cmd_read_q<=1'b1;master_cmd_wdata_q<='0;
      master_cmd_wmask_q<=4'b0000;
      master_rsp_rdata_q<='0;master_rsp_err_q<=1'b0;
      for(integer i=0;i<LANES;i=i+1)begin b_vector[i]<=0;bias_vector[i]<=0;end
    end else begin
      if(master_rsp_valid_q&&master_rsp_ready)
        master_rsp_valid_q<=1'b0;
      if(master_rsp_valid_q&&master_rsp_ready&&master_rsp_err_q)
        weight_cache_valid<=1'b0;
      if((state==S_MAC)&&pe_input_error)
        weight_cache_valid<=1'b0;
      if((state==S_IDLE)&&engine_start)
        pe_result_seen_q<=1'b0;
      else if((state==S_MAC)&&pe_result_valid)
        pe_result_seen_q<=1'b1;
      if(master_cmd_fire)
        master_outstanding<=1'b1;
      if(master_rsp_fire)begin
        master_rsp_valid_q<=1'b1;
        master_rsp_rdata_q<=m_icb_rsp_rdata;
        master_rsp_err_q<=m_icb_rsp_err;
        master_outstanding<=1'b0;
      end
      // Capture the complete command before exposing it to the external ICB.
      // A command remains pending, with all payload fields stable, until the
      // real external command handshake occurs.
      if(command_build_valid&&!master_cmd_pending_q)begin
        master_cmd_pending_q<=1'b1;
        master_cmd_addr_q<=command_build_addr;
        master_cmd_read_q<=command_build_read;
        master_cmd_wdata_q<=command_build_wdata;
        master_cmd_wmask_q<=command_build_wmask;
      end
      if(master_cmd_fire)
        master_cmd_pending_q<=1'b0;
      case(state)
        S_IDLE:if(engine_start)begin
          current_row<=0;current_col<=0;current_k<=0;bias_idx<=0;pair_idx<=0;
          weight_cache_valid<=1'b0;
          active_cols<=(matrix_n<LANES)?matrix_n:LANES;
          for(integer i=0;i<LANES;i=i+1)begin b_vector[i]<=0;bias_vector[i]<=0;end
          if(supported_shape&&config_aligned) state<=S_BIAS_REQ;
          else state<=S_ERROR;
        end
        S_BIAS_REQ:if(master_cmd_fire)state<=S_BIAS_WAIT;
        S_BIAS_WAIT:if(master_rsp_valid_q&&master_rsp_ready)begin
          if(master_rsp_err_q)state<=S_ERROR;
          else begin
            bias_vector[bias_idx]<=$signed(master_rsp_rdata_q);
            if(bias_idx+1>=active_cols)begin
              bias_idx<=0;current_k<=0;
              if(matrix_k==16'd64) begin pair_idx<=0;state<=S_TILE_B_REQ;end
              else state<=S_A_REQ;
            end
            else begin bias_idx<=bias_idx+1'b1;state<=S_BIAS_REQ;end
          end
        end
        S_A_REQ:begin
          if(current_k[0]&&matrix_k==16'd64)begin
            if(weight_cache_valid) state<=S_CACHE_RD_REQ;
            else state<=S_ERROR;
          end else if(current_k[0])begin pair_idx<=0;state<=S_B_REQ;end
          else if(master_cmd_fire)state<=S_A_WAIT;
        end
        S_A_WAIT:if(master_rsp_valid_q&&master_rsp_ready)begin
          if(master_rsp_err_q)state<=S_ERROR;
          else begin
            a_pair<=master_rsp_rdata_q;pair_idx<=0;
            if(matrix_k==16'd64) begin
              if(weight_cache_valid) state<=S_CACHE_RD_REQ;
              else state<=S_ERROR;
            end else state<=S_B_REQ;
          end
        end
        S_TILE_B_REQ:if(master_cmd_fire)state<=S_TILE_B_WAIT;
        S_TILE_B_WAIT:if(master_rsp_valid_q&&master_rsp_ready)begin
          if(master_rsp_err_q)state<=S_ERROR;
          else begin
            if(pair_idx+1>=((active_cols+1)>>1))begin
              pair_idx<=0;
              if(current_k+1>=matrix_k)begin
                current_k<=0;weight_cache_valid<=1'b1;state<=S_A_REQ;
              end else begin
                current_k<=current_k+1'b1;state<=S_TILE_B_REQ;
              end
            end else begin
              pair_idx<=pair_idx+1'b1;state<=S_TILE_B_REQ;
            end
          end
        end
        S_B_REQ:if(master_cmd_fire)state<=S_B_WAIT;
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
        S_CACHE_RD_REQ:state<=S_CACHE_RD_WAIT;
        S_CACHE_RD_WAIT:if(cache_rd_valid)begin
          for(integer i=0;i<LANES;i=i+1)
            b_vector[i]<=(i<active_cols)?
              $signed(cache_rd_data_bus[i*16 +: 16]):16'sd0;
          state<=S_MAC;
        end
        S_MAC:begin
          if(pe_input_error)state<=S_ERROR;
          else if(current_k+1>=matrix_k)state<=S_RESULT;
          else begin current_k<=current_k+1'b1;state<=S_A_REQ;end
        end
        S_RESULT:if(pe_result_valid||pe_result_seen_q)begin
          pe_result_seen_q<=1'b0;
          pair_idx<=0;state<=S_WB_REQ;
        end
        S_WB_REQ:if(master_cmd_fire)state<=S_WB_WAIT;
        S_WB_WAIT:if(master_rsp_valid_q&&master_rsp_ready)begin
          if(master_rsp_err_q)state<=S_ERROR;
          else begin
          if(pair_idx+1>=((active_cols+1)>>1))begin
            pair_idx<=0;current_k<=0;bias_idx<=0;
            if(matrix_k==16'd64) begin
              // K=64 layer-00 mode: keep the current W/bias tile while
              // advancing rows; load the next tile only after all rows.
              if(current_row+1<matrix_m)begin
                current_row<=current_row+1'b1;
                state<=S_A_REQ;
              end else if(current_col+active_cols<matrix_n)begin
                current_row<=0;current_col<=current_col+LANES;
                active_cols<=((matrix_n-(current_col+LANES))<LANES)?
                  (matrix_n-(current_col+LANES)):LANES;
                bias_idx<=0;pair_idx<=0;current_k<=0;
                weight_cache_valid<=1'b0;
                state<=S_BIAS_REQ;
              end else state<=S_DONE;
            end else if(current_col+active_cols<matrix_n)begin
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
