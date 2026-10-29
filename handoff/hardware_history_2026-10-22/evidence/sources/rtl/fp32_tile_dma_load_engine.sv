// External-bus read adapter for the A/B/bias half-word load phases.
// The bus contract is intentionally small: a request is accepted when
// bus_req_valid && bus_req_ready, and a later bus_rsp_valid returns one 16-bit
// word.  One read may be outstanding at a time, which makes the timing easy to
// verify and can be widened later without changing the cache-side contract.
module fp32_tile_dma_load_engine #(
  parameter int ROW_TILE = 8,
  parameter int COL_TILE = 16,
  parameter int K_TILE = 32,
  parameter int ADDR_WIDTH = 32,
  parameter int CACHE_ADDR_WIDTH = 10
) (
  input logic clk,
  input logic rst_n,
  input logic start,
  input logic [15:0] matrix_m,
  input logic [15:0] matrix_k,
  input logic [15:0] matrix_n,
  input logic [15:0] row_base,
  input logic [15:0] col_base,
  input logic [15:0] k_base,
  input logic [15:0] rows_valid,
  input logic [15:0] cols_valid,
  input logic [15:0] k_valid,
  input logic [ADDR_WIDTH-1:0] a_base_word,
  input logic [ADDR_WIDTH-1:0] b_base_word,
  input logic [ADDR_WIDTH-1:0] bias_base_word,
  input logic [ADDR_WIDTH-1:0] result_base_word,

  output logic bus_req_valid,
  output logic bus_req_write,
  output logic [ADDR_WIDTH-1:0] bus_req_addr,
  output logic [15:0] bus_req_wdata,
  input logic bus_req_ready,
  input logic bus_rsp_valid,
  input logic [15:0] bus_rsp_rdata,

  output logic a_wr_en,
  output logic [CACHE_ADDR_WIDTH-1:0] a_wr_addr,
  output logic [15:0] a_wr_data,
  output logic b_wr_en,
  output logic [CACHE_ADDR_WIDTH-1:0] b_wr_addr,
  output logic [15:0] b_wr_data,
  output logic result_wr_en,
  output logic [CACHE_ADDR_WIDTH-1:0] result_wr_addr,
  output logic [15:0] result_wr_data,
  output logic busy,
  output logic load_done
);
  logic seq_busy, seq_done, seq_req_valid, seq_req_write;
  logic [ADDR_WIDTH-1:0] seq_req_addr;
  logic [1:0] seq_cache_bank;
  logic seq_cache_write, seq_cache_read;
  logic [CACHE_ADDR_WIDTH-1:0] seq_cache_word_addr;
  logic [15:0] seq_local_row, seq_local_col, seq_local_k;
  logic seq_word_high;
  logic [2:0] seq_phase;
  logic seq_req_ready;

  logic read_pending;
  logic seq_finished;
  logic [1:0] pending_bank;
  logic [CACHE_ADDR_WIDTH-1:0] pending_addr;

  fp32_tile_dma_sequencer #(
    .ROW_TILE(ROW_TILE), .COL_TILE(COL_TILE), .K_TILE(K_TILE),
    .ADDR_WIDTH(ADDR_WIDTH), .CACHE_ADDR_WIDTH(CACHE_ADDR_WIDTH),
    .ENABLE_RESULT_WRITE(1'b0)
  ) u_seq (
    .clk(clk), .rst_n(rst_n), .start(start && !busy),
    .matrix_m(matrix_m), .matrix_k(matrix_k), .matrix_n(matrix_n),
    .row_base(row_base), .col_base(col_base), .k_base(k_base),
    .rows_valid(rows_valid), .cols_valid(cols_valid), .k_valid(k_valid),
    .a_base_word(a_base_word), .b_base_word(b_base_word),
    .bias_base_word(bias_base_word), .result_base_word(result_base_word),
    .req_ready(seq_req_ready), .busy(seq_busy), .done(seq_done),
    .req_valid(seq_req_valid), .req_write(seq_req_write),
    .req_addr(seq_req_addr), .cache_bank(seq_cache_bank),
    .cache_write(seq_cache_write), .cache_read(seq_cache_read),
    .cache_word_addr(seq_cache_word_addr), .local_row(seq_local_row),
    .local_col(seq_local_col), .local_k(seq_local_k),
    .word_high(seq_word_high), .phase(seq_phase)
  );

  assign busy = seq_busy || read_pending;
  assign seq_req_ready = seq_req_valid && !read_pending && bus_req_ready;
  assign bus_req_valid = seq_req_valid && !read_pending;
  assign bus_req_write = 1'b0;
  assign bus_req_addr = seq_req_addr;
  assign bus_req_wdata = 16'd0;

  always_comb begin
    a_wr_en = 1'b0;
    a_wr_addr = pending_addr;
    a_wr_data = bus_rsp_rdata;
    b_wr_en = 1'b0;
    b_wr_addr = pending_addr;
    b_wr_data = bus_rsp_rdata;
    result_wr_en = 1'b0;
    result_wr_addr = pending_addr;
    result_wr_data = bus_rsp_rdata;
    if (read_pending && bus_rsp_valid) begin
      case (pending_bank)
        2'd0: a_wr_en = 1'b1;
        2'd1: b_wr_en = 1'b1;
        2'd2: result_wr_en = 1'b1;
        default: begin end
      endcase
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      read_pending <= 1'b0;
      seq_finished <= 1'b0;
      pending_bank <= 2'd0;
      pending_addr <= '0;
      load_done <= 1'b0;
    end else begin
      load_done <= 1'b0;
      if (seq_done)
        seq_finished <= 1'b1;
      if (seq_finished && (!read_pending || bus_rsp_valid)) begin
        load_done <= 1'b1;
        seq_finished <= 1'b0;
      end
      if (bus_req_valid && bus_req_ready) begin
        read_pending <= 1'b1;
        pending_bank <= seq_cache_bank;
        pending_addr <= seq_cache_word_addr;
      end else if (read_pending && bus_rsp_valid) begin
        read_pending <= 1'b0;
      end
    end
  end
endmodule
