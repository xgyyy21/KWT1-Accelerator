// Three independent 16-bit x 1024 caches. SRAM reads are synchronous (one cycle).
// Same-address read/write returns the OLD word. Memory contents survive reset;
// software/control must load them before reading. Only read outputs are reset.
module matrix_cache_manager #(
  parameter int DATA_WIDTH = 16,
  parameter int ADDR_WIDTH = 10,
  parameter int DEPTH = 1024
) (
  input logic clk,
  input logic rst_n,
  input logic a_wr_en, input logic [ADDR_WIDTH-1:0] a_wr_addr, input logic [DATA_WIDTH-1:0] a_wr_data,
  input logic b_wr_en, input logic [ADDR_WIDTH-1:0] b_wr_addr, input logic [DATA_WIDTH-1:0] b_wr_data,
  input logic result_wr_en, input logic [ADDR_WIDTH-1:0] result_wr_addr, input logic [DATA_WIDTH-1:0] result_wr_data,
  input logic a_rd_en, input logic [ADDR_WIDTH-1:0] a_rd_addr,
  input logic b_rd_en, input logic [ADDR_WIDTH-1:0] b_rd_addr,
  input logic result_rd_en, input logic [ADDR_WIDTH-1:0] result_rd_addr,
  output logic [DATA_WIDTH-1:0] a_rd_data, output logic a_rd_valid,
  output logic [DATA_WIDTH-1:0] b_rd_data, output logic b_rd_valid,
  output logic [DATA_WIDTH-1:0] result_rd_data, output logic result_rd_valid
);
  logic [DATA_WIDTH-1:0] a_mem [0:DEPTH-1], b_mem [0:DEPTH-1], result_mem [0:DEPTH-1];
  initial begin
    if(DATA_WIDTH<=0 || ADDR_WIDTH<=0 || DEPTH<=0 || $clog2(DEPTH)>ADDR_WIDTH)
      $fatal(1,"invalid cache parameters");
  end
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      a_rd_data <= '0; b_rd_data <= '0; result_rd_data <= '0;
      a_rd_valid <= 0; b_rd_valid <= 0; result_rd_valid <= 0;
    end else begin
      a_rd_valid <= a_rd_en && a_rd_addr < DEPTH;
      b_rd_valid <= b_rd_en && b_rd_addr < DEPTH;
      result_rd_valid <= result_rd_en && result_rd_addr < DEPTH;
      if (a_wr_en && a_wr_addr < DEPTH) a_mem[a_wr_addr] <= a_wr_data;
      if (b_wr_en && b_wr_addr < DEPTH) b_mem[b_wr_addr] <= b_wr_data;
      if (result_wr_en && result_wr_addr < DEPTH) result_mem[result_wr_addr] <= result_wr_data;
      if (a_rd_en && a_rd_addr < DEPTH) a_rd_data <= a_mem[a_rd_addr];
      if (b_rd_en && b_rd_addr < DEPTH) b_rd_data <= b_mem[b_rd_addr];
      if (result_rd_en && result_rd_addr < DEPTH) result_rd_data <= result_mem[result_rd_addr];
    end
  end
endmodule
