// Tile-level phase controller for the FP32 accelerator path.
//
// The controller deliberately exposes only phase handshakes.  The DMA load,
// FP32 tile engine, and result writeback blocks can therefore be integrated
// one at a time without changing the sequencing contract:
//   IDLE -> LOAD -> COMPUTE -> WRITEBACK -> DONE.
// A start pulse is emitted once on entry to each active phase.
module fp32_tile_fsm #(
  parameter int ROW_TILE = 8,
  parameter int COL_TILE = 16,
  parameter int K_TILE = 32
) (
  input  logic clk,
  input  logic rst_n,
  input  logic start,
  input  logic [15:0] rows_valid,
  input  logic [15:0] cols_valid,
  input  logic [15:0] k_valid,
  input  logic load_done,
  input  logic compute_done,
  input  logic writeback_done,
  input  logic error_in,
  output logic load_start,
  output logic compute_start,
  output logic writeback_start,
  output logic busy,
  output logic done,
  output logic error,
  output logic [2:0] state
);
  localparam logic [2:0] S_IDLE = 3'd0;
  localparam logic [2:0] S_LOAD = 3'd1;
  localparam logic [2:0] S_COMPUTE = 3'd2;
  localparam logic [2:0] S_WRITEBACK = 3'd3;
  localparam logic [2:0] S_DONE = 3'd4;
  localparam logic [2:0] S_ERROR = 3'd5;

  logic [2:0] previous_state;
  logic config_error;

  always_comb begin
    config_error = (rows_valid == 16'd0) || (cols_valid == 16'd0) ||
                   (k_valid == 16'd0) || (rows_valid > ROW_TILE) ||
                   (cols_valid > COL_TILE) || (k_valid > K_TILE);
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= S_IDLE;
      previous_state <= S_IDLE;
    end else begin
      previous_state <= state;
      case (state)
        S_IDLE: begin
          if (start)
            state <= (config_error || error_in) ? S_ERROR : S_LOAD;
        end
        S_LOAD: begin
          if (error_in)
            state <= S_ERROR;
          else if (load_done)
            state <= S_COMPUTE;
        end
        S_COMPUTE: begin
          if (error_in)
            state <= S_ERROR;
          else if (compute_done)
            state <= S_WRITEBACK;
        end
        S_WRITEBACK: begin
          if (error_in)
            state <= S_ERROR;
          else if (writeback_done)
            state <= S_DONE;
        end
        S_DONE: begin
          if (start)
            state <= (config_error || error_in) ? S_ERROR : S_LOAD;
          else
            state <= S_IDLE;
        end
        S_ERROR: begin
          if (start)
            state <= (config_error || error_in) ? S_ERROR : S_LOAD;
          else
            state <= S_IDLE;
        end
        default: state <= S_ERROR;
      endcase
    end
  end

  always_comb begin
    load_start = (state == S_LOAD) && (previous_state != S_LOAD);
    compute_start = (state == S_COMPUTE) && (previous_state != S_COMPUTE);
    writeback_start = (state == S_WRITEBACK) && (previous_state != S_WRITEBACK);
    busy = (state == S_LOAD) || (state == S_COMPUTE) ||
           (state == S_WRITEBACK);
    done = (state == S_DONE);
    error = (state == S_ERROR);
  end
endmodule
