// Parameterized FP32 PE array.  The default geometry is the teacher's
// 8x16 pulse-matrix core.
//
// A values enter from the left edge and move one column per clock.  B values
// enter from the top edge and move one row per clock.  Thus the matching A/B
// pair for PE(row,column) meets after row+column propagation clocks.  The
// first/last markers travel with the data, so each PE sees the same K order
// even though different cells start at different wall-clock cycles.
module fp32_pe_array_8x16 #(
  parameter int ROWS = 8,
  parameter int COLS = 16,
  parameter int K = 64
) (
  input  logic clk,
  input  logic rst_n,
  input  logic start,
  input  logic stream_valid,
  input  logic task_first,
  input  logic task_last,
  input  logic [31:0] a_left [ROWS],
  input  logic [31:0] b_top [COLS],
  input  logic [31:0] bias_in [COLS],
  input  logic checkpoint_save_req,
  input  logic checkpoint_restore_req,
  output logic checkpoint_busy,
  output logic checkpoint_done,
  output logic checkpoint_error,
  output logic checkpoint_mem_req,
  output logic checkpoint_mem_we,
  output logic [9:0] checkpoint_mem_addr,
  output logic [15:0] checkpoint_mem_wdata,
  input  logic checkpoint_mem_rvalid,
  input  logic [15:0] checkpoint_mem_rdata,
  output logic busy,
  output logic done,
  output logic result_valid,
  output logic [31:0] result [ROWS][COLS],
  output logic trace_valid [ROWS][COLS],
  output logic trace_bias_valid [ROWS][COLS],
  output logic [31:0] trace_cycle [ROWS][COLS],
  output logic [15:0] trace_k [ROWS][COLS],
  output logic [31:0] trace_x_bits [ROWS][COLS],
  output logic [31:0] trace_w_bits [ROWS][COLS],
  output logic [31:0] trace_acc_before_bits [ROWS][COLS],
  output logic [31:0] trace_product_bits [ROWS][COLS],
  output logic [31:0] trace_acc_after_bits [ROWS][COLS],
  output logic [31:0] trace_bias_bits [ROWS][COLS]
);
  localparam int TOTAL_CELLS = ROWS * COLS;

  logic [31:0] a_pipe [ROWS][COLS];
  logic [31:0] b_pipe [ROWS][COLS];
  logic [31:0] a_skew [ROWS][ROWS];
  logic [31:0] b_skew [COLS][COLS];
  logic a_valid [ROWS][COLS];
  logic b_valid [ROWS][COLS];
  logic a_skew_valid [ROWS][ROWS];
  logic b_skew_valid [COLS][COLS];
  logic a_first [ROWS][COLS];
  logic b_first [ROWS][COLS];
  logic a_last [ROWS][COLS];
  logic b_last [ROWS][COLS];
  logic a_skew_first [ROWS][ROWS];
  logic b_skew_first [COLS][COLS];
  logic a_skew_last [ROWS][ROWS];
  logic b_skew_last [COLS][COLS];

  logic cell_valid [ROWS][COLS];
  logic cell_first [ROWS][COLS];
  logic cell_last [ROWS][COLS];
  logic cell_result_valid [ROWS][COLS];
  logic cell_busy [ROWS][COLS];
  logic [31:0] cell_result [ROWS][COLS];
  logic [31:0] cell_acc_checkpoint [ROWS][COLS];
  logic [31:0] cell_bias_checkpoint [ROWS][COLS];
  logic [2:0] cell_state [ROWS][COLS];
  logic cell_checkpoint_restore [ROWS][COLS];

  // These arrays are declared before the PE generate block because they are
  // connected directly to the PE checkpoint ports.
  logic [31:0] checkpoint_acc_write [ROWS][COLS];
  logic [31:0] checkpoint_bias_write [ROWS][COLS];
  logic [31:0] checkpoint_acc_read [ROWS][COLS];
  logic [31:0] checkpoint_bias_read [ROWS][COLS];

  localparam logic [2:0] CP_IDLE=3'd0, CP_SAVE=3'd1, CP_READ_REQ=3'd2,
                         CP_READ_WAIT=3'd3, CP_APPLY=3'd4, CP_DONE=3'd5;
  logic [2:0] checkpoint_state;
  integer checkpoint_cell;
  integer checkpoint_word;
  integer rr, cc;
  logic all_cells_wait_block, all_cells_idle;
  integer check_r, check_c;

  integer result_seen;
  integer events_this_cycle;
  logic [TOTAL_CELLS-1:0] cell_result_mask;
  // Keep shifting until every input/marker token has drained. Once empty,
  // holding invalid payload registers cannot affect a PE or its timing.
  integer input_drain_cycles;
  integer r, c;

  wire accept_input = stream_valid && (busy || start);

  initial begin
    if (ROWS <= 0 || COLS <= 0 || K <= 0)
      $fatal(1, "invalid fp32_pe_array_8x16 parameters");
  end

  genvar gr, gc;
  generate
    for (gr = 0; gr < ROWS; gr = gr + 1) begin : G_CELL_ROW
      for (gc = 0; gc < COLS; gc = gc + 1) begin : G_CELL_COL
        assign cell_result_mask[gr*COLS+gc] = cell_result_valid[gr][gc];
        assign cell_valid[gr][gc] = a_valid[gr][gc] && b_valid[gr][gc];
        assign cell_first[gr][gc] = cell_valid[gr][gc] &&
                                     a_first[gr][gc] && b_first[gr][gc];
        assign cell_last[gr][gc] = cell_valid[gr][gc] &&
                                   a_last[gr][gc] && b_last[gr][gc];

        fp32_pe_mac #(.K(K), .MUL_LATENCY(8), .ADD_LATENCY(4)) u_pe (
          .clk(clk), .rst_n(rst_n), .enable(1'b1),
          .clear_acc(cell_first[gr][gc]),
          .task_first(cell_first[gr][gc]),
          .task_last(cell_last[gr][gc]),
          .in_valid(cell_valid[gr][gc]),
          .a_in(a_pipe[gr][gc]), .b_in(b_pipe[gr][gc]),
          .bias_in(bias_in[gc]),
          .checkpoint_restore(cell_checkpoint_restore[gr][gc]),
          .checkpoint_accumulator(checkpoint_acc_write[gr][gc]),
          .checkpoint_bias(checkpoint_bias_write[gr][gc]),
          .checkpoint_accumulator_out(cell_acc_checkpoint[gr][gc]),
          .checkpoint_bias_out(cell_bias_checkpoint[gr][gc]),
          .checkpoint_state_out(cell_state[gr][gc]),
          .result_valid(cell_result_valid[gr][gc]),
          .result(cell_result[gr][gc]),
          .busy(cell_busy[gr][gc]), .done(),
          .trace_valid(trace_valid[gr][gc]),
          .trace_cycle(trace_cycle[gr][gc]),
          .trace_k(trace_k[gr][gc]),
          .trace_x_bits(trace_x_bits[gr][gc]),
          .trace_w_bits(trace_w_bits[gr][gc]),
          .trace_acc_before_bits(trace_acc_before_bits[gr][gc]),
          .trace_product_bits(trace_product_bits[gr][gc]),
          .trace_acc_after_bits(trace_acc_after_bits[gr][gc]),
          .trace_bias_valid(trace_bias_valid[gr][gc]),
          .trace_bias_bits(trace_bias_bits[gr][gc])
        );
        always_comb result[gr][gc] = cell_result[gr][gc];
      end
    end
  endgenerate

  always_comb begin
    checkpoint_mem_req = 1'b0;
    checkpoint_mem_we = 1'b0;
    checkpoint_mem_addr = 10'd0;
    checkpoint_mem_wdata = 16'd0;
    checkpoint_busy = (checkpoint_state != CP_IDLE) && (checkpoint_state != CP_DONE);
    checkpoint_done = (checkpoint_state == CP_DONE);
    for (rr=0; rr<ROWS; rr=rr+1) begin
      for (cc=0; cc<COLS; cc=cc+1) begin
        checkpoint_acc_write[rr][cc] = checkpoint_acc_read[rr][cc];
        checkpoint_bias_write[rr][cc] = checkpoint_bias_read[rr][cc];
        cell_checkpoint_restore[rr][cc] = (checkpoint_state == CP_APPLY) &&
                                             (checkpoint_cell == rr*COLS+cc);
      end
    end
    if (checkpoint_state == CP_SAVE) begin
      checkpoint_mem_req = 1'b1;
      checkpoint_mem_we = 1'b1;
      checkpoint_mem_addr = 10'(checkpoint_cell*4 + checkpoint_word);
      case (checkpoint_word)
        0: checkpoint_mem_wdata = cell_acc_checkpoint[checkpoint_cell/COLS][checkpoint_cell%COLS][15:0];
        1: checkpoint_mem_wdata = cell_acc_checkpoint[checkpoint_cell/COLS][checkpoint_cell%COLS][31:16];
        2: checkpoint_mem_wdata = cell_bias_checkpoint[checkpoint_cell/COLS][checkpoint_cell%COLS][15:0];
        3: checkpoint_mem_wdata = cell_bias_checkpoint[checkpoint_cell/COLS][checkpoint_cell%COLS][31:16];
        default: checkpoint_mem_wdata = 16'd0;
      endcase
    end else if (checkpoint_state == CP_READ_REQ) begin
      checkpoint_mem_req = 1'b1;
      checkpoint_mem_we = 1'b0;
      checkpoint_mem_addr = 10'(checkpoint_cell*4 + checkpoint_word);
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin: checkpoint_control
    integer r, c;
    if (!rst_n) begin
      checkpoint_state <= CP_IDLE;
      checkpoint_cell <= 0;
      checkpoint_word <= 0;
      checkpoint_error <= 1'b0;
      for (r=0;r<ROWS;r=r+1) for(c=0;c<COLS;c=c+1) begin
        checkpoint_acc_read[r][c] <= 32'd0;
        checkpoint_bias_read[r][c] <= 32'd0;
      end
    end else begin
      checkpoint_error <= 1'b0;
      case (checkpoint_state)
        CP_IDLE: begin
          if (checkpoint_save_req && checkpoint_restore_req) begin
            checkpoint_error <= 1'b1;
          end else if (checkpoint_save_req) begin
            if (busy && all_cells_wait_block) begin
              checkpoint_cell <= 0;
              checkpoint_word <= 0;
              checkpoint_state <= CP_SAVE;
            end else checkpoint_error <= 1'b1;
          end else if (checkpoint_restore_req) begin
            if (!busy && all_cells_idle) begin
              checkpoint_cell <= 0;
              checkpoint_word <= 0;
              checkpoint_state <= CP_READ_REQ;
            end else checkpoint_error <= 1'b1;
          end
        end
        CP_SAVE: begin
          if (checkpoint_mem_req && checkpoint_mem_we) begin
            if (checkpoint_word == 3) begin
              checkpoint_word <= 0;
              if (checkpoint_cell == ROWS*COLS-1) checkpoint_state <= CP_DONE;
              else checkpoint_cell <= checkpoint_cell + 1;
            end else checkpoint_word <= checkpoint_word + 1;
          end
        end
        CP_READ_REQ: begin
          if (checkpoint_mem_req && !checkpoint_mem_we) checkpoint_state <= CP_READ_WAIT;
        end
        CP_READ_WAIT: begin
          if (checkpoint_mem_rvalid) begin
            case (checkpoint_word)
              0: checkpoint_acc_read[checkpoint_cell/COLS][checkpoint_cell%COLS][15:0] <= checkpoint_mem_rdata;
              1: checkpoint_acc_read[checkpoint_cell/COLS][checkpoint_cell%COLS][31:16] <= checkpoint_mem_rdata;
              2: checkpoint_bias_read[checkpoint_cell/COLS][checkpoint_cell%COLS][15:0] <= checkpoint_mem_rdata;
              3: checkpoint_bias_read[checkpoint_cell/COLS][checkpoint_cell%COLS][31:16] <= checkpoint_mem_rdata;
              default: checkpoint_error <= 1'b1;
            endcase
            if (checkpoint_word == 3) begin
              checkpoint_word <= 0;
              checkpoint_state <= CP_APPLY;
            end else begin
              checkpoint_word <= checkpoint_word + 1;
              checkpoint_state <= CP_READ_REQ;
            end
          end
        end
        CP_APPLY: begin
          if (checkpoint_cell == ROWS*COLS-1) checkpoint_state <= CP_DONE;
          else begin
            checkpoint_cell <= checkpoint_cell + 1;
            checkpoint_word <= 0;
            checkpoint_state <= CP_READ_REQ;
          end
        end
        CP_DONE: checkpoint_state <= CP_IDLE;
        default: begin checkpoint_state <= CP_IDLE; checkpoint_error <= 1'b1; end
      endcase
    end
  end

  always_comb begin
    all_cells_wait_block = 1'b1;
    all_cells_idle = 1'b1;
    for (check_r=0;check_r<ROWS;check_r=check_r+1)
      for (check_c=0;check_c<COLS;check_c=check_c+1) begin
        if (cell_state[check_r][check_c] != 3'd4)
          all_cells_wait_block = 1'b0;
        if (cell_state[check_r][check_c] != 3'd0)
          all_cells_idle = 1'b0;
      end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      busy <= 1'b0;
      done <= 1'b0;
      result_valid <= 1'b0;
      result_seen <= 0;
      input_drain_cycles <= 0;
      for (r = 0; r < ROWS; r = r + 1) begin
        for (c = 0; c < COLS; c = c + 1) begin
          a_pipe[r][c] <= 32'd0;
          b_pipe[r][c] <= 32'd0;
          a_valid[r][c] <= 1'b0;
          b_valid[r][c] <= 1'b0;
          a_first[r][c] <= 1'b0;
          b_first[r][c] <= 1'b0;
          a_last[r][c] <= 1'b0;
          b_last[r][c] <= 1'b0;
        end
        for (c = 0; c < ROWS; c = c + 1) begin
          a_skew[r][c] <= 32'd0;
          a_skew_valid[r][c] <= 1'b0;
          a_skew_first[r][c] <= 1'b0;
          a_skew_last[r][c] <= 1'b0;
        end
      end
      for (c = 0; c < COLS; c = c + 1) begin
        for (r = 0; r < COLS; r = r + 1) begin
          b_skew[c][r] <= 32'd0;
          b_skew_valid[c][r] <= 1'b0;
          b_skew_first[c][r] <= 1'b0;
          b_skew_last[c][r] <= 1'b0;
        end
      end
    end else begin
      done <= 1'b0;
      result_valid <= 1'b0;
      events_this_cycle = 0;

      if (start) begin
        busy <= 1'b1;
        result_seen <= 0;
      end

      // Input skew makes A(row,k) and B(k,col) meet at the same PE clock:
      // A is delayed by row and B is delayed by column before entering the
      // horizontal/vertical propagation paths.
      if (accept_input)
        input_drain_cycles <= ROWS + COLS + 1;
      else if (input_drain_cycles > 0)
        input_drain_cycles <= input_drain_cycles - 1;

      if (accept_input || input_drain_cycles > 0) begin
      for (r = 0; r < ROWS; r = r + 1) begin
        a_skew[r][0] <= a_left[r];
        a_skew_valid[r][0] <= accept_input;
        a_skew_first[r][0] <= accept_input && task_first;
        a_skew_last[r][0] <= accept_input && task_last;
        for (c = 1; c < ROWS; c = c + 1) begin
          a_skew[r][c] <= a_skew[r][c-1];
          a_skew_valid[r][c] <= a_skew_valid[r][c-1];
          a_skew_first[r][c] <= a_skew_first[r][c-1];
          a_skew_last[r][c] <= a_skew_last[r][c-1];
        end
        a_pipe[r][0] <= a_skew[r][r];
        a_valid[r][0] <= a_skew_valid[r][r];
        a_first[r][0] <= a_skew_first[r][r];
        a_last[r][0] <= a_skew_last[r][r];
        for (c = 1; c < COLS; c = c + 1) begin
          a_pipe[r][c] <= a_pipe[r][c-1];
          a_valid[r][c] <= a_valid[r][c-1];
          a_first[r][c] <= a_first[r][c-1];
          a_last[r][c] <= a_last[r][c-1];
        end
      end
      for (c = 0; c < COLS; c = c + 1) begin
        b_skew[c][0] <= b_top[c];
        b_skew_valid[c][0] <= accept_input;
        b_skew_first[c][0] <= accept_input && task_first;
        b_skew_last[c][0] <= accept_input && task_last;
        for (r = 1; r < COLS; r = r + 1) begin
          b_skew[c][r] <= b_skew[c][r-1];
          b_skew_valid[c][r] <= b_skew_valid[c][r-1];
          b_skew_first[c][r] <= b_skew_first[c][r-1];
          b_skew_last[c][r] <= b_skew_last[c][r-1];
        end
        b_pipe[0][c] <= b_skew[c][c];
        b_valid[0][c] <= b_skew_valid[c][c];
        b_first[0][c] <= b_skew_first[c][c];
        b_last[0][c] <= b_skew_last[c][c];
        for (r = 1; r < ROWS; r = r + 1) begin
          b_pipe[r][c] <= b_pipe[r-1][c];
          b_valid[r][c] <= b_valid[r-1][c];
          b_first[r][c] <= b_first[r-1][c];
          b_last[r][c] <= b_last[r-1][c];
        end
      end
      end

      // Capture the individually timed PE results and finish only after all
      // rows and columns have produced their final bias result.
      if (|cell_result_mask) begin
      for (r = 0; r < ROWS; r = r + 1) begin
        for (c = 0; c < COLS; c = c + 1) begin
          if (cell_result_valid[r][c]) begin
            events_this_cycle = events_this_cycle + 1;
          end
        end
      end
      end
      if (events_this_cycle != 0) begin
        if (result_seen + events_this_cycle >= TOTAL_CELLS) begin
          result_seen <= TOTAL_CELLS;
          busy <= 1'b0;
          result_valid <= 1'b1;
          done <= 1'b1;
        end else begin
          result_seen <= result_seen + events_this_cycle;
        end
      end
    end
  end
endmodule
