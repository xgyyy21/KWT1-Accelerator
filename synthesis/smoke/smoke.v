// Generic practice circuit only. No accelerator, technology or timing claim.
module smoke (
    input wire clk,
    input wire reset,
    input wire enable,
    input wire [7:0] a,
    input wire [7:0] b,
    output reg [8:0] q
);
    always @(posedge clk) begin
        if (reset)
            q <= 9'b0;
        else if (enable)
            q <= {1'b0, a} + {1'b0, b};
    end
endmodule
