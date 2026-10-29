module ai_engine_fsm (
  input  logic clk,
  input  logic rst_n,
  input  logic start,
  input  logic dma_load_done,
  input  logic compute_done,
  input  logic writeback_done,
  input  logic error_in,
  output logic dma_load_start,
  output logic compute_start,
  output logic writeback_start,
  output logic busy,
  output logic done,
  output logic error,
  output logic [2:0] state
);
  localparam logic [2:0] S_IDLE=3'd0, S_LOAD=3'd1, S_COMPUTE=3'd2,
                         S_WRITE=3'd3, S_DONE=3'd4, S_ERROR=3'd5;
  logic [2:0] previous_state;
  always_ff @(posedge clk or negedge rst_n) begin
    if(!rst_n) previous_state<=S_IDLE;
    else previous_state<=state;
  end
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) state <= S_IDLE;
    else begin
      case (state)
        S_IDLE:    if (start) state <= error_in ? S_ERROR : S_LOAD;
        S_LOAD:    if (error_in) state <= S_ERROR; else if (dma_load_done) state <= S_COMPUTE;
        S_COMPUTE: if (error_in) state <= S_ERROR; else if (compute_done) state <= S_WRITE;
        S_WRITE:   if (error_in) state <= S_ERROR; else if (writeback_done) state <= S_DONE;
        S_DONE:    if(start) state <= error_in ? S_ERROR : S_LOAD; else state <= S_IDLE;
        S_ERROR:   if(start) state <= error_in ? S_ERROR : S_LOAD; else state <= S_IDLE;
        default:   state <= S_ERROR;
      endcase
    end
  end
  always_comb begin
    dma_load_start = (state == S_LOAD) && previous_state != S_LOAD;
    compute_start = (state == S_COMPUTE) && previous_state != S_COMPUTE;
    writeback_start = (state == S_WRITE) && previous_state != S_WRITE;
    busy = (state != S_IDLE) && (state != S_DONE) && (state != S_ERROR);
    done = (state == S_DONE);
    error = (state == S_ERROR);
  end
endmodule
