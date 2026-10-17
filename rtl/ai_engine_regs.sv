// E203/NICE-facing control register boundary.
// The bus adapter outside this block translates the selected NICE or
// System-Bus protocol into this simple one-cycle register transaction.
module ai_engine_regs #(
  parameter int ADDR_WIDTH = 32,
  parameter int DATA_WIDTH = 32
) (
  input logic clk,
  input logic rst_n,
  input logic req_valid,
  input logic req_write,
  input logic [ADDR_WIDTH-1:0] req_addr,
  input logic [DATA_WIDTH-1:0] req_wdata,
  output logic req_ready,
  output logic rsp_valid,
  output logic [DATA_WIDTH-1:0] rsp_rdata,
  input logic engine_busy,
  input logic engine_done,
  input logic engine_error,
  output logic engine_start,
  output logic [ADDR_WIDTH-1:0] src_a_base,
  output logic [ADDR_WIDTH-1:0] src_b_base,
  output logic [ADDR_WIDTH-1:0] dst_base,
  output logic [15:0] matrix_m,
  output logic [15:0] matrix_k,
  output logic [15:0] matrix_n
);
  localparam logic [7:0] A_CTRL=8'h00, A_STATUS=8'h04, A_SRC_A=8'h08,
                         A_SRC_B=8'h0c, A_DST=8'h10, A_M=8'h14,
                         A_K=8'h18, A_N=8'h1c;
  assign req_ready = 1'b1;
  logic done_sticky, error_sticky;
  logic launch;
  assign launch = req_valid && req_write && req_addr[7:0]==A_CTRL &&
                  req_wdata[0] && !engine_busy && !engine_start;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rsp_valid <= 0; rsp_rdata <= '0; engine_start <= 0;
      src_a_base <= 0; src_b_base <= 0; dst_base <= 0;
      matrix_m <= 0; matrix_k <= 0; matrix_n <= 0;
      done_sticky<=0; error_sticky<=0;
    end else begin
      rsp_valid <= req_valid && !req_write;
      rsp_rdata <= '0;
      engine_start <= 0;
      if (req_valid && req_write) begin
        case (req_addr[7:0])
          // CTRL[0]: start, CTRL[1]: clear done, CTRL[2]: clear error.
          A_CTRL: begin
            if(req_wdata[1]) done_sticky<=0;
            if(req_wdata[2]) error_sticky<=0;
            if(req_wdata[0]) begin
              if(!engine_busy && !engine_start) begin
                engine_start<=1; done_sticky<=0; error_sticky<=0;
              end else error_sticky<=1;
            end
          end
          A_SRC_A: if(!engine_busy && !engine_start) src_a_base <= ADDR_WIDTH'(req_wdata);
          A_SRC_B: if(!engine_busy && !engine_start) src_b_base <= ADDR_WIDTH'(req_wdata);
          A_DST: if(!engine_busy && !engine_start) dst_base <= ADDR_WIDTH'(req_wdata);
          A_M: if(!engine_busy && !engine_start) matrix_m <= req_wdata[15:0];
          A_K: if(!engine_busy && !engine_start) matrix_k <= req_wdata[15:0];
          A_N: if(!engine_busy && !engine_start) matrix_n <= req_wdata[15:0];
          default: ;
        endcase
      end
      if (req_valid && !req_write) begin
        case (req_addr[7:0])
          A_STATUS: rsp_rdata <= DATA_WIDTH'({error_sticky | engine_error, done_sticky | engine_done, engine_busy});
          A_SRC_A: rsp_rdata <= src_a_base;
          A_SRC_B: rsp_rdata <= src_b_base;
          A_DST: rsp_rdata <= dst_base;
          A_M: rsp_rdata <= matrix_m;
          A_K: rsp_rdata <= matrix_k;
          A_N: rsp_rdata <= matrix_n;
          default: rsp_rdata <= '0;
        endcase
      end
      // Events beat explicit clears, but a new launch discards old-job events.
      if(engine_done && !launch) done_sticky<=1;
      if(engine_error && !launch) error_sticky<=1;
    end
  end
endmodule
