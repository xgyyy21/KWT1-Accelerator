`timescale 1ns/1ps
// Project-authored, zero-delay FUNCTIONAL model based on the 11 screenshots.
// NOT an ARM-delivered model, timing model, macro implementation or PPA evidence.
// Only normal mode and full 16-bit writes are covered by this model/contract.
module ramsp128x16_functional_model (
  input wire CLK,
  input wire CEN,
  input wire GWEN,
  input wire [15:0] WEN,
  input wire [6:0] A,
  input wire [15:0] D,
  output logic [15:0] Q,
  input wire [2:0] EMA,
  input wire [1:0] EMAW,
  input wire RET1N
);
  logic [15:0] mem [0:127]; // Intentionally uninitialized, no reset.
  always @(posedge CLK) begin
    if (RET1N !== 1'b1)
      $fatal(1, "Functional model does not implement retention transitions");
    if (CEN === 1'b0) begin
      if (GWEN === 1'b0) begin
        if (WEN !== 16'h0000)
          $fatal(1, "Functional model only supports full-word writes");
        mem[A] <= D;
        // write_thru=off: Q remains the preceding output, not mem[A].
      end else if (GWEN === 1'b1) begin
        Q <= mem[A];
      end else begin
        $fatal(1, "Unknown global write control");
      end
    end else if (CEN !== 1'b1) begin
      $fatal(1, "Unknown chip enable");
    end
  end
endmodule
