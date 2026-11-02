// Sequencer for multiple physical K blocks belonging to one logical tile.
// The PE engine is started only for the first block and remains alive while
// later blocks stream through it.  Writeback starts only after the final block
// has streamed and the PE engine reports its final result.
module fp32_tile_kblock_fsm #(
  parameter int BLOCKS = 2
) (
  input logic clk,
  input logic rst_n,
  input logic start,
  input logic [15:0] block_count_cfg,
  input logic load_done,
  input logic stream_done,
  input logic compute_done,
  input logic writeback_done,
  input logic error_in,
  output logic load_start,
  output logic stream_start,
  output logic compute_start,
  output logic writeback_start,
  output logic task_first,
  output logic task_last,
  output logic busy,
  output logic done,
  output logic error,
  output logic [((BLOCKS <= 1) ? 1 : $clog2(BLOCKS))-1:0] block_index,
  output logic [2:0] state
);
  localparam int INDEX_WIDTH = (BLOCKS <= 1) ? 1 : $clog2(BLOCKS);
  localparam logic [2:0] S_IDLE = 3'd0;
  localparam logic [2:0] S_LOAD = 3'd1;
  localparam logic [2:0] S_STREAM = 3'd2;
  localparam logic [2:0] S_WAIT_COMPUTE = 3'd3;
  localparam logic [2:0] S_WRITEBACK = 3'd4;
  localparam logic [2:0] S_DONE = 3'd5;
  localparam logic [2:0] S_ERROR = 3'd6;

  logic [2:0] previous_state;
  logic [15:0] block_count_q;

  function automatic logic config_invalid(input logic [15:0] count);
    config_invalid = (count == 0) || (count > BLOCKS);
  endfunction

  initial begin
    if (BLOCKS <= 0)
      $fatal(1, "fp32_tile_kblock_fsm requires at least one K block");
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state <= S_IDLE;
      previous_state <= S_IDLE;
      block_index <= '0;
      block_count_q <= 16'd0;
    end else begin
      previous_state <= state;
      case (state)
        S_IDLE: begin
          if (start) begin
            block_index <= '0;
            block_count_q <= block_count_cfg;
            state <= (error_in || config_invalid(block_count_cfg)) ? S_ERROR : S_LOAD;
          end
        end
        S_LOAD: begin
          if (error_in)
            state <= S_ERROR;
          else if (load_done)
            state <= S_STREAM;
        end
        S_STREAM: begin
          if (error_in)
            state <= S_ERROR;
          else if (stream_done) begin
            if (block_index + 1 < block_count_q) begin
              block_index <= block_index + 1'b1;
              state <= S_LOAD;
            end else begin
              state <= S_WAIT_COMPUTE;
            end
          end
        end
        S_WAIT_COMPUTE: begin
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
          if (start) begin
            block_index <= '0;
            block_count_q <= block_count_cfg;
            state <= (error_in || config_invalid(block_count_cfg)) ? S_ERROR : S_LOAD;
          end else begin
            state <= S_IDLE;
          end
        end
        S_ERROR: begin
          if (start) begin
            block_index <= '0;
            block_count_q <= block_count_cfg;
            state <= (error_in || config_invalid(block_count_cfg)) ? S_ERROR : S_LOAD;
          end else begin
            state <= S_IDLE;
          end
        end
        default: state <= S_ERROR;
      endcase
    end
  end

  always_comb begin
    load_start = (state == S_LOAD) && (previous_state != S_LOAD);
    stream_start = (state == S_STREAM) && (previous_state != S_STREAM);
    compute_start = stream_start && (block_index == 0);
    writeback_start = (state == S_WRITEBACK) &&
                      (previous_state != S_WRITEBACK);
    task_first = (block_index == 0);
    task_last = (block_count_q != 0) &&
                (block_index == block_count_q-1'b1);
    busy = (state != S_IDLE) && (state != S_DONE) && (state != S_ERROR);
    done = (state == S_DONE);
    error = (state == S_ERROR);
  end
endmodule
