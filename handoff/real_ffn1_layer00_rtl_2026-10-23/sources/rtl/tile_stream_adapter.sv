// Adapts one tile row/column word set to the array-facing streams.
// Upstream must assemble the parallel words using prefetch/registers; a single
// SRAM port cannot directly supply every array input each cycle.
module tile_stream_adapter #(
  parameter int DATA_WIDTH = 16,
  parameter int ROWS = 8,
  parameter int COLS = 16
) (
  input logic clk,
  input logic rst_n,
  input logic start,
  input logic stop,
  input logic input_valid,
  input logic [DATA_WIDTH-1:0] a_mem_data [ROWS],
  input logic [DATA_WIDTH-1:0] b_mem_data [COLS],
  output logic stream_valid,
  output logic [DATA_WIDTH-1:0] a_left [ROWS],
  output logic [DATA_WIDTH-1:0] b_top [COLS],
  output logic active
);
  integer i;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      active <= 1'b0;
      stream_valid <= 1'b0;
      for (i=0; i<ROWS; i=i+1) a_left[i] <= '0;
      for (i=0; i<COLS; i=i+1) b_top[i] <= '0;
    end else begin
      stream_valid <= 1'b0;
      if (start) active <= 1'b1;
      if (stop) active <= 1'b0;
      if (!stop && (active || start) && input_valid) begin
        stream_valid <= 1'b1;
        for (i=0; i<ROWS; i=i+1) a_left[i] <= a_mem_data[i];
        for (i=0; i<COLS; i=i+1) b_top[i] <= b_mem_data[i];
      end
    end
  end
endmodule
