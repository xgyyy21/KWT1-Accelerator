// Functional FP32 reference MAC, not integrated into the PE array.
// This computes combinational functions between registers; it does NOT
// implement the teacher-required 8-cycle multiply + 4-cycle add pipeline.
module fp32_mac_boundary (
  input logic clk, input logic rst_n, input logic valid,
  input logic [31:0] a, input logic [31:0] b,
  input logic clear_acc, input logic last,
  output logic result_valid, output logic [31:0] result
);
  import fp32_math_pkg::*;
  logic [31:0] acc;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin acc <= 0; result <= 0; result_valid <= 0; end
    else begin
      result_valid <= 0;
      // Functional reference boundary only; this is NOT the required 8+4 pipeline.
      if (clear_acc) acc <= 0;
      if (valid) begin
        acc <= clear_acc ? fp32_mul(a,b) : fp32_add(acc, fp32_mul(a,b));
        if (last) begin
          result <= clear_acc ? fp32_mul(a,b) : fp32_add(acc, fp32_mul(a,b));
          result_valid <= 1;
        end
      end
    end
  end
endmodule
