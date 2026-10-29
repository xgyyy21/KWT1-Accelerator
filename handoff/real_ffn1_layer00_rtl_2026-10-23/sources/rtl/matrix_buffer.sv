// Legacy wide-result buffer, not the teacher's three 16x1024 cache interface.
// New integrations should use matrix_cache_manager.
module matrix_buffer #(
  parameter int DATA_WIDTH = 16,
  parameter int ADDR_WIDTH = 12,
  parameter int DEPTH = 4096
) (
  input  logic clk,
  input  logic rst_n,
  input  logic a_wr_en,
  input  logic [ADDR_WIDTH-1:0] a_wr_addr,
  input  logic [DATA_WIDTH-1:0] a_wr_data,
  input  logic b_wr_en,
  input  logic [ADDR_WIDTH-1:0] b_wr_addr,
  input  logic [DATA_WIDTH-1:0] b_wr_data,
  input  logic result_wr_en,
  input  logic [ADDR_WIDTH-1:0] result_wr_addr,
  input  logic [2*DATA_WIDTH-1:0] result_wr_data,
  input  logic [ADDR_WIDTH-1:0] a_rd_addr,
  input  logic [ADDR_WIDTH-1:0] b_rd_addr,
  input  logic [ADDR_WIDTH-1:0] result_rd_addr,
  output logic [DATA_WIDTH-1:0] a_rd_data,
  output logic [DATA_WIDTH-1:0] b_rd_data,
  output logic [2*DATA_WIDTH-1:0] result_rd_data
);
  logic [DATA_WIDTH-1:0] a_mem [0:DEPTH-1];
  logic [DATA_WIDTH-1:0] b_mem [0:DEPTH-1];
  logic [2*DATA_WIDTH-1:0] result_mem [0:DEPTH-1];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      a_rd_data <= '0;
      b_rd_data <= '0;
      result_rd_data <= '0;
    end else begin
      if (a_wr_en && a_wr_addr<DEPTH) a_mem[a_wr_addr] <= a_wr_data;
      if (b_wr_en && b_wr_addr<DEPTH) b_mem[b_wr_addr] <= b_wr_data;
      if (result_wr_en && result_wr_addr<DEPTH) result_mem[result_wr_addr] <= result_wr_data;
      a_rd_data <= (a_rd_addr<DEPTH) ? a_mem[a_rd_addr] : '0;
      b_rd_data <= (b_rd_addr<DEPTH) ? b_mem[b_rd_addr] : '0;
      result_rd_data <= (result_rd_addr<DEPTH) ? result_mem[result_rd_addr] : '0;
    end
  end
endmodule
