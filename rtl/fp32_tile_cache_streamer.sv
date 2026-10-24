// Loads one FP32 tile from synchronous 16-bit cache ports and emits one
// complete A row vector and B column vector for each K step.  The result
// cache port is used for the bias vector during load; result writeback stays
// outside this module.
module fp32_tile_cache_streamer #(
  parameter int ROWS = 8,
  parameter int COLS = 16,
  parameter int K = 32,
  parameter int ADDR_WIDTH = 10
) (
  input logic clk,
  input logic rst_n,
  input logic start,
  input logic task_first_cfg,
  input logic task_last_cfg,

  output logic a_rd_en,
  output logic [ADDR_WIDTH-1:0] a_rd_addr,
  input logic [15:0] a_rd_data,
  input logic a_rd_valid,
  output logic b_rd_en,
  output logic [ADDR_WIDTH-1:0] b_rd_addr,
  input logic [15:0] b_rd_data,
  input logic b_rd_valid,
  output logic result_rd_en,
  output logic [ADDR_WIDTH-1:0] result_rd_addr,
  input logic [15:0] result_rd_data,
  input logic result_rd_valid,

  output logic busy,
  output logic done,
  output logic stream_valid,
  output logic task_first,
  output logic task_last,
  output logic [31:0] a_left [ROWS],
  output logic [31:0] b_top [COLS],
  output logic [31:0] bias_in [COLS]
);
  localparam int A_ELEMS = ROWS * K;
  localparam int B_ELEMS = K * COLS;
  localparam int A_WORDS = A_ELEMS * 2;
  localparam int B_WORDS = B_ELEMS * 2;
  localparam int BIAS_WORDS = COLS * 2;

  typedef enum logic [1:0] {S_IDLE, S_LOAD, S_STREAM, S_DONE} state_t;
  state_t state;

  integer a_req_word, b_req_word, bias_req_word;
  integer a_rsp_word, b_rsp_word, bias_rsp_word;
  integer stream_k;
  logic [15:0] a_low_word, b_low_word, bias_low_word;
  logic [31:0] a_tile [ROWS][K];
  logic [31:0] b_tile [K][COLS];
  logic [31:0] bias_tile [COLS];

  initial begin
`ifndef SYNTHESIS
    if (ROWS <= 0 || COLS <= 0 || K <= 0 ||
        A_WORDS > (1 << ADDR_WIDTH) ||
        B_WORDS > (1 << ADDR_WIDTH) ||
        BIAS_WORDS > (1 << ADDR_WIDTH))
      $fatal(1, "FP32 tile cache streamer parameters exceed cache");
`endif
  end

  always_comb begin
    integer r;
    integer c;
    busy = (state != S_IDLE);
    a_rd_en = 1'b0;
    b_rd_en = 1'b0;
    result_rd_en = 1'b0;
    a_rd_addr = '0;
    b_rd_addr = '0;
    result_rd_addr = '0;
    stream_valid = 1'b0;
    task_first = 1'b0;
    task_last = 1'b0;
    for (r = 0; r < ROWS; r = r + 1)
      a_left[r] = '0;
    for (c = 0; c < COLS; c = c + 1) begin
      b_top[c] = '0;
      // PE bias is consumed after the final streamed K item because of the
      // multiplier/adder pipeline. Hold it beyond S_STREAM until the next
      // tile replaces it; clearing it at S_DONE would silently add zero.
      bias_in[c] = bias_tile[c];
    end

    if (state == S_LOAD) begin
      if (a_req_word < A_WORDS) begin
        a_rd_en = 1'b1;
        a_rd_addr = ADDR_WIDTH'(a_req_word);
      end
      if (b_req_word < B_WORDS) begin
        b_rd_en = 1'b1;
        b_rd_addr = ADDR_WIDTH'(b_req_word);
      end
      if (bias_req_word < BIAS_WORDS) begin
        result_rd_en = 1'b1;
        result_rd_addr = ADDR_WIDTH'(bias_req_word);
      end
    end

    if (state == S_STREAM) begin
      stream_valid = 1'b1;
      task_first = task_first_cfg && (stream_k == 0);
      task_last = task_last_cfg && (stream_k == K-1);
      for (r = 0; r < ROWS; r = r + 1)
        a_left[r] = a_tile[r][stream_k];
      for (c = 0; c < COLS; c = c + 1) begin
        b_top[c] = b_tile[stream_k][c];
        bias_in[c] = bias_tile[c];
      end
    end
  end

  // Bias words are captured into bias_in directly; the array output is held
  // at reset value until the tile has been fully loaded.
  always_ff @(posedge clk or negedge rst_n) begin
    integer r;
    integer c;
    if (!rst_n) begin
      state <= S_IDLE;
      done <= 1'b0;
      a_req_word <= 0;
      b_req_word <= 0;
      bias_req_word <= 0;
      a_rsp_word <= 0;
      b_rsp_word <= 0;
      bias_rsp_word <= 0;
      stream_k <= 0;
      a_low_word <= '0;
      b_low_word <= '0;
      bias_low_word <= '0;
      for (r = 0; r < ROWS; r = r + 1) begin
        for (c = 0; c < K; c = c + 1)
          a_tile[r][c] <= '0;
      end
      for (r = 0; r < K; r = r + 1)
        for (c = 0; c < COLS; c = c + 1)
          b_tile[r][c] <= '0;
      for (c = 0; c < COLS; c = c + 1) begin
        bias_tile[c] <= '0;
      end
    end else begin
      done <= 1'b0;
      case (state)
        S_IDLE: begin
          if (start) begin
            state <= S_LOAD;
            a_req_word <= 0;
            b_req_word <= 0;
            bias_req_word <= 0;
            a_rsp_word <= 0;
            b_rsp_word <= 0;
            bias_rsp_word <= 0;
          end
        end

        S_LOAD: begin
          if (a_req_word < A_WORDS) a_req_word <= a_req_word + 1;
          if (b_req_word < B_WORDS) b_req_word <= b_req_word + 1;
          if (bias_req_word < BIAS_WORDS) bias_req_word <= bias_req_word + 1;

          if (a_rd_valid) begin
            if ((a_rsp_word & 1) == 0)
              a_low_word <= a_rd_data;
            else
              a_tile[a_rsp_word / 2 / K][(a_rsp_word / 2) % K] <=
                {a_rd_data, a_low_word};
            a_rsp_word <= a_rsp_word + 1;
          end
          if (b_rd_valid) begin
            if ((b_rsp_word & 1) == 0)
              b_low_word <= b_rd_data;
            else
              b_tile[b_rsp_word / 2 / COLS][(b_rsp_word / 2) % COLS] <=
                {b_rd_data, b_low_word};
            b_rsp_word <= b_rsp_word + 1;
          end
          if (result_rd_valid) begin
            if ((bias_rsp_word & 1) == 0)
              bias_low_word <= result_rd_data;
            else
              bias_tile[(bias_rsp_word / 2) % COLS] <=
                {result_rd_data, bias_low_word};
            bias_rsp_word <= bias_rsp_word + 1;
          end

          if (a_rsp_word >= A_WORDS && b_rsp_word >= B_WORDS &&
              bias_rsp_word >= BIAS_WORDS) begin
            state <= S_STREAM;
            stream_k <= 0;
          end
        end

        S_STREAM: begin
          if (stream_k == K-1)
            state <= S_DONE;
          else
            stream_k <= stream_k + 1;
        end

        S_DONE: begin
          done <= 1'b1;
          state <= S_IDLE;
        end

        default: state <= S_IDLE;
      endcase
    end
  end
endmodule
