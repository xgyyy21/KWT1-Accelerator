`timescale 1ns/1ps
module pe_array_8x16_tb;
  localparam int DW=16, AW=32, R=2, C=2;
  logic clk=0; always #5 clk=~clk;
  logic rst_n=0, clear_acc=0;
  logic valid[R][C], first_v[R][C], last_v[R][C];
  logic [DW-1:0] a[R][C], b[R][C];
  logic rv[R][C], busy[R][C]; logic [AW-1:0] result[R][C];
  integer i,j;
  pe_array_8x16 #(.DATA_WIDTH(DW),.ACC_WIDTH(AW),.ROWS(R),.COLS(C)) dut(.*,
    .in_valid(valid), .first_valid(first_v), .last_valid(last_v), .a_data(a), .b_data(b), .result_valid(rv));
  initial begin
    for(i=0;i<R;i=i+1) for(j=0;j<C;j=j+1) begin valid[i][j]=0; first_v[i][j]=0; last_v[i][j]=0; a[i][j]=3; b[i][j]=4; end
    repeat(2) @(negedge clk); rst_n=1;
    @(negedge clk); for(i=0;i<R;i=i+1) for(j=0;j<C;j=j+1) begin valid[i][j]=1; first_v[i][j]=1; end
    @(negedge clk); for(i=0;i<R;i=i+1) for(j=0;j<C;j=j+1) begin first_v[i][j]=0; last_v[i][j]=1; end
    @(negedge clk); for(i=0;i<R;i=i+1) for(j=0;j<C;j=j+1) begin valid[i][j]=0; last_v[i][j]=0; end
    for(i=0;i<R;i=i+1) for(j=0;j<C;j=j+1)
      if(result[i][j] !== 32'd24) $fatal(1,"PE array mismatch %0d",result[i][j]);
    $display("pe_array_8x16_tb PASS"); $finish;
  end
  initial begin #10000; $fatal(1,"pe_array_8x16_tb timeout"); end
endmodule
