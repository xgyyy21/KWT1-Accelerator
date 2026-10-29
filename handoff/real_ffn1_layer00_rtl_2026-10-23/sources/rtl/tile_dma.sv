// Address-only prototype, not a complete bus DMA. One atomic address beat is
// accepted on busy && result_ready; all addresses/valid hold during stalls.
module tile_dma #(
  parameter int DATA_WIDTH = 16,
  parameter int ADDR_WIDTH = 12,
  parameter int TILE_WORDS = 128
) (
  input logic clk,
  input logic rst_n,
  input logic start,
  input logic [ADDR_WIDTH-1:0] src_a_base,
  input logic [ADDR_WIDTH-1:0] src_b_base,
  input logic [ADDR_WIDTH-1:0] dst_base,
  output logic busy,
  output logic done,
  output logic [ADDR_WIDTH-1:0] a_addr,
  output logic [ADDR_WIDTH-1:0] b_addr,
  output logic [ADDR_WIDTH-1:0] result_addr,
  output logic a_valid,
  output logic b_valid,
  input logic result_ready,
  output logic result_valid
);
  integer count;
  logic [ADDR_WIDTH-1:0] a_base_q, b_base_q, dst_q;
  assign a_addr = a_base_q + ADDR_WIDTH'(count);
  assign b_addr = b_base_q + ADDR_WIDTH'(count);
  assign result_addr = dst_q + ADDR_WIDTH'(count);
  assign a_valid = busy;
  assign b_valid = busy;
  assign result_valid = busy;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      count <= 0; busy <= 0; done <= 0;
      a_base_q<=0; b_base_q<=0; dst_q<=0;
    end else begin
      done <= 0;
      if (start && !busy) begin
        count <= 0; busy <= (TILE_WORDS>0); done <= (TILE_WORDS<=0);
        a_base_q<=src_a_base; b_base_q<=src_b_base; dst_q<=dst_base;
      end else if (busy && result_ready) begin
        if (count == TILE_WORDS-1) begin
          busy <= 0; done <= 1;
        end else count <= count + 1;
      end
    end
  end
endmodule
