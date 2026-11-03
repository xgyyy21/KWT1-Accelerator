// Active sixteen-lane signed INT16 dot-product array.
module int16_pe_array_16 #(
  parameter int LANES=16,
  parameter int ACC_WIDTH=48
) (
  input logic clk,rst_n,start,mac_valid,mac_last,
  input logic signed [15:0] a_in,
  input logic signed [15:0] b_in [LANES],
  input logic signed [31:0] bias_in [LANES],
  input logic [4:0] out_shift,
  output logic result_valid,
  output logic signed [15:0] result [LANES],
  output logic signed [ACC_WIDTH-1:0] raw_sum [LANES]
);
  logic lane_valid[LANES];
  for(genvar i=0;i<LANES;i=i+1)begin:g_pe
    int16_pe_mac #(.ACC_WIDTH(ACC_WIDTH)) u_pe(
      .clk(clk),.rst_n(rst_n),.start(start),.mac_valid(mac_valid),
      .mac_last(mac_last),.a_in(a_in),.b_in(b_in[i]),.bias_in(bias_in[i]),
      .out_shift(out_shift),.result_valid(lane_valid[i]),
      .result_out(result[i]),.raw_sum_out(raw_sum[i]),.trace_valid(),
      .trace_product(),.trace_acc_before(),.trace_acc_after());
  end
  always_comb begin
    result_valid=lane_valid[0];
    for(integer i=1;i<LANES;i=i+1) result_valid=result_valid&lane_valid[i];
  end
  initial if(LANES!=16)$fatal(1,"INT16 v1 requires 16 PE lanes");
endmodule
