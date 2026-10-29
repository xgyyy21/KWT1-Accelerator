`timescale 1ns/1ps

// Environment check only: this does not validate accelerator functionality.
module verilator_environment_smoke_tb;
  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic [7:0] counter = '0;

  always #5 clk = ~clk;
  always_ff @(posedge clk) begin
    if (!rst_n) counter <= '0;
    else counter <= counter + 1'b1;
  end

  initial begin
    repeat (2) @(negedge clk);
    rst_n = 1'b1;
    repeat (4) @(negedge clk);
    if (counter !== 8'd4) $fatal(1, "Counter mismatch: %0d", counter);
    $display("verilator_environment_smoke_tb PASS counter=%0d", counter);
    $finish;
  end

  initial begin
    #1000;
    $fatal(1, "Environment smoke test timeout");
  end
endmodule
