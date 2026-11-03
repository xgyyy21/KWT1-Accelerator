// Minimal signed INT16 PE. One MAC may be accepted per clock.
// The signed 48-bit accumulator is retained across K_TILE=32 boundaries.
module int16_pe_mac #(
  parameter int ACC_WIDTH = 48
) (
  input  logic                        clk,
  input  logic                        rst_n,
  input  logic                        start,
  input  logic                        mac_valid,
  input  logic                        mac_last,
  input  logic signed [15:0]          a_in,
  input  logic signed [15:0]          b_in,
  input  logic signed [31:0]          bias_in,
  input  logic [4:0]                  out_shift,
  output logic                        result_valid,
  output logic signed [15:0]          result_out,
  output logic signed [ACC_WIDTH-1:0] raw_sum_out,
  output logic                        input_error,
  output logic                        trace_valid,
  output logic signed [31:0]          trace_product,
  output logic signed [ACC_WIDTH-1:0] trace_acc_before,
  output logic signed [ACC_WIDTH-1:0] trace_acc_after
);
  logic signed [ACC_WIDTH-1:0] accumulator;
  logic signed [31:0] product_comb;
  logic signed [ACC_WIDTH-1:0] product_ext;
  logic signed [ACC_WIDTH-1:0] acc_before_comb;
  logic signed [ACC_WIDTH-1:0] acc_after_comb;
  logic signed [ACC_WIDTH-1:0] bias_ext;
  logic signed [ACC_WIDTH-1:0] biased_sum_comb;

  // Round to nearest, ties to even, then saturate to the software range.
  function automatic logic signed [15:0] requantize_sat16(
    input logic signed [ACC_WIDTH-1:0] value,
    input logic [4:0] shift
  );
    logic signed [ACC_WIDTH-1:0] magnitude;
    logic [ACC_WIDTH-1:0] rounded_magnitude;
    logic [ACC_WIDTH-1:0] unit;
    logic [ACC_WIDTH-1:0] remainder;
    logic [ACC_WIDTH-1:0] half;
    logic signed [ACC_WIDTH-1:0] scaled;
    begin
      magnitude = (value < 0) ? -value : value;
      unit = '0;
      unit[0] = 1'b1;
      if (shift == 0) begin
        rounded_magnitude = magnitude;
      end else begin
        unit = unit <<< shift;
        remainder = magnitude & (unit - 1'b1);
        half = unit >>> 1;
        rounded_magnitude = magnitude >>> shift;
        if ((remainder > half) ||
            ((remainder == half) && rounded_magnitude[0]))
          rounded_magnitude = rounded_magnitude + 1'b1;
      end
      scaled = (value < 0) ? -$signed(rounded_magnitude) :
        $signed(rounded_magnitude);
      if (scaled > 32767)
        requantize_sat16 = 16'sh7fff;
      else if (scaled < -32767)
        requantize_sat16 = -16'sd32767;
      else
        requantize_sat16 = scaled[15:0];
    end
  endfunction

  always_comb begin
    product_comb = $signed(a_in) * $signed(b_in);
    product_ext = {{(ACC_WIDTH-32){product_comb[31]}}, product_comb};
    bias_ext = {{(ACC_WIDTH-32){bias_in[31]}}, bias_in};
    acc_before_comb = start ? '0 : accumulator;
    acc_after_comb = acc_before_comb + product_ext;
    biased_sum_comb = acc_after_comb + bias_ext;
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      accumulator <= '0;
      result_valid <= 1'b0;
      result_out <= '0;
      raw_sum_out <= '0;
      trace_valid <= 1'b0;
      trace_product <= '0;
      trace_acc_before <= '0;
      trace_acc_after <= '0;
    end else begin
      result_valid <= 1'b0;
      trace_valid <= 1'b0;
      if (start && !mac_valid)
        accumulator <= '0;
      if (mac_valid) begin
        if (!input_error) begin
          accumulator <= acc_after_comb;
          trace_valid <= 1'b1;
          trace_product <= product_comb;
          trace_acc_before <= acc_before_comb;
          trace_acc_after <= acc_after_comb;
          if (mac_last) begin
            raw_sum_out <= biased_sum_comb;
            result_out <= requantize_sat16(biased_sum_comb, out_shift);
            result_valid <= 1'b1;
          end
        end
      end
    end
  end

  // 0x8000 is reserved by the software contract and is never a legal
  // quantized operand. Keep the error visible for the complete MAC cycle.
  always_comb begin
    input_error = mac_valid &&
      ((a_in == 16'sh8000) || (b_in == 16'sh8000));
  end
endmodule
