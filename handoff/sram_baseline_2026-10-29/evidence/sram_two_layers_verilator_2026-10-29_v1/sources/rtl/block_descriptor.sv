// Standard on-chip block metadata used between the controller, cache and PE array.
module block_descriptor #(
  parameter int ADDR_WIDTH = 32
) (
  input logic clk,
  input logic rst_n,
  input logic load,
  input logic [15:0] row_position,
  input logic [15:0] col_position,
  input logic [15:0] height,
  input logic [15:0] width,
  input logic has_valid_data,
  input logic allow_compute,
  input logic operation_done,
  output logic active,
  output logic valid,
  output logic permitted,
  output logic complete,
  output logic [15:0] row,
  output logic [15:0] col,
  output logic [15:0] block_height,
  output logic [15:0] block_width
);
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      active <= 0; valid <= 0; permitted <= 0; complete <= 0;
      row <= 0; col <= 0; block_height <= 0; block_width <= 0;
    end else if (load) begin
      active <= 1; valid <= has_valid_data; permitted <= allow_compute; complete <= 0;
      row <= row_position; col <= col_position;
      block_height <= height; block_width <= width;
    end else if (active && operation_done) begin
      complete <= 1; active <= 0;
    end
  end
endmodule
