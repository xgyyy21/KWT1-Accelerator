`timescale 1ns/1ps

module pe_mac_tb;
  localparam int DATA_WIDTH = 16;
  localparam int ACC_WIDTH  = 32;

  logic clk = 1'b0;
  always #5 clk = ~clk;

  logic rst_n = 1'b0;
  logic enable = 1'b0;
  logic clear_acc = 1'b0;
  logic task_first = 1'b0;
  logic task_last = 1'b0;
  logic in_valid = 1'b0;
  logic [DATA_WIDTH-1:0] a_in = '0;
  logic [DATA_WIDTH-1:0] b_in = '0;
  logic a_valid_out, b_valid_out;
  logic [DATA_WIDTH-1:0] a_out, b_out;
  logic result_valid;
  logic [ACC_WIDTH-1:0] result;
  logic busy, done;

  pe_mac #(.DATA_WIDTH(DATA_WIDTH), .ACC_WIDTH(ACC_WIDTH), .SIGNED_DATA(1'b0)) dut (.*);

  task automatic drive_product(input int unsigned av, input int unsigned bv,
                               input bit first, input bit last);
    @(negedge clk);
    a_in = av[DATA_WIDTH-1:0];
    b_in = bv[DATA_WIDTH-1:0];
    task_first = first;
    task_last = last;
    in_valid = 1'b1;
    enable = 1'b1;
    @(negedge clk);
    in_valid = 1'b0;
    task_first = 1'b0;
    task_last = 1'b0;
  endtask

  initial begin
    repeat (2) @(negedge clk);
    rst_n = 1'b1;

    drive_product(3, 4, 1'b1, 1'b0);
    drive_product(5, 6, 1'b0, 1'b1);
    if (!result_valid || result != 32'd42)
      $fatal(1, "MAC mismatch: valid=%0d result=%0d expected=42", result_valid, result);

    drive_product(7, 8, 1'b1, 1'b1);
    if (!result_valid || result != 32'd56)
      $fatal(1, "single-cycle mismatch: valid=%0d result=%0d expected=56", result_valid, result);

    $display("pe_mac_tb PASS");
    $finish;
  end
  initial begin #10000; $fatal(1,"pe_mac_tb timeout"); end
endmodule
