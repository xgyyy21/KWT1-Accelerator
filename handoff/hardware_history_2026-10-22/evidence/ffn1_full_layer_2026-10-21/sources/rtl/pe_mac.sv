module pe_mac #(
  parameter int DATA_WIDTH = 32,
  parameter int ACC_WIDTH  = 2 * DATA_WIDTH,
  parameter bit SIGNED_DATA = 1'b1
) (
  input  logic                         clk,
  input  logic                         rst_n,
  input  logic                         enable,
  input  logic                         clear_acc,
  input  logic                         task_first,
  input  logic                         task_last,
  input  logic                         in_valid,
  input  logic [DATA_WIDTH-1:0]       a_in,
  input  logic [DATA_WIDTH-1:0]       b_in,
  output logic                         a_valid_out,
  output logic                         b_valid_out,
  output logic [DATA_WIDTH-1:0]       a_out,
  output logic [DATA_WIDTH-1:0]       b_out,
  output logic                         result_valid,
  output logic [ACC_WIDTH-1:0]        result,
  output logic                         busy,
  output logic                         done
);
  logic [ACC_WIDTH-1:0] accumulator;
  logic                 active;

  // Integer functional MAC only, with wrapping accumulation. DATA_WIDTH=32
  // still means integer arithmetic, NOT FP32. Teacher-specified pipelines
  // and the FP32 mode remain separate implementation work.
  logic [2*DATA_WIDTH-1:0] product;
  logic [ACC_WIDTH-1:0] extended_product;
  logic [ACC_WIDTH-1:0] next_accumulator;
  always_comb begin
    if (SIGNED_DATA)
      product = $signed(a_in) * $signed(b_in);
    else
      product = a_in * b_in;
    // Cast before resizing so negative products sign extend into wider sums.
    if (SIGNED_DATA) extended_product = ACC_WIDTH'($signed(product));
    else extended_product = ACC_WIDTH'($unsigned(product));
    next_accumulator = (clear_acc || task_first) ? extended_product :
                       accumulator + extended_product;
  end
  assign busy = active;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      accumulator  <= '0;
      active       <= 1'b0;
      a_valid_out  <= 1'b0;
      b_valid_out  <= 1'b0;
      a_out        <= '0;
      b_out        <= '0;
      result       <= '0;
      result_valid <= 1'b0;
      done         <= 1'b0;
    end else begin
      a_valid_out  <= enable && in_valid;
      b_valid_out  <= enable && in_valid;
      a_out        <= a_in;
      b_out        <= b_in;
      result_valid <= 1'b0;
      done         <= 1'b0;

      if (clear_acc) begin
        accumulator <= '0;
        active      <= 1'b0;
      end

      if (enable && in_valid) begin
        accumulator <= next_accumulator;
        active      <= 1'b1;
      end

      if (enable && in_valid && task_last) begin
        result       <= next_accumulator;
        result_valid <= 1'b1;
        done         <= 1'b1;
        active       <= 1'b0;
      end

    end
  end
endmodule
