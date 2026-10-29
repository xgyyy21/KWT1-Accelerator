// Standalone candidate for the future platform adapter. NOT connected to
// fp32_accelerator_top. Addresses are internal 16-bit-word addresses.
// One outstanding read; responses must arrive after the accepting edge.
// Writes complete on request handshake (no posted-write completion protocol).
// Faults fail-stop until a coordinated reset, including the downstream bus.
module fp32_bus_fault_guard #(
  parameter int ADDR_WIDTH = 32,
  parameter int TIMEOUT_CYCLES = 8
) (
  input logic clk, rst_n,
  input logic req_valid, req_write,
  input logic [ADDR_WIDTH-1:0] req_addr,
  input logic [15:0] req_wdata,
  output logic req_ready, rsp_valid,
  output logic [15:0] rsp_rdata,
  output logic bus_req_valid, bus_req_write,
  output logic [ADDR_WIDTH-1:0] bus_req_addr,
  output logic [15:0] bus_req_wdata,
  input logic bus_req_ready, bus_rsp_valid,
  input logic [15:0] bus_rsp_rdata,
  input logic bus_error,
  output logic pending, error,
  // 1=request deadline, 2=read-response deadline, 3=bus error,
  // 4=unsolicited response. These codes are prototype-only.
  output logic [2:0] error_code
);
  localparam int CW = (TIMEOUT_CYCLES > 1) ? $clog2(TIMEOUT_CYCLES) : 1;
  logic [CW-1:0] wait_count;
  assign bus_req_valid = rst_n && !error && !pending && !bus_error && req_valid;
  assign req_ready = rst_n && !error && !pending && !bus_error && bus_req_ready;
  assign bus_req_write = req_write;
  assign bus_req_addr = req_addr;
  assign bus_req_wdata = req_wdata;
  assign rsp_valid = rst_n && !error && !bus_error && pending && bus_rsp_valid;
  assign rsp_rdata = bus_rsp_rdata;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      pending <= 0;
      error <= 0;
      error_code <= 0;
      wait_count <= 0;
    end else if (!error) begin
      if (bus_error || (bus_rsp_valid && !pending)) begin
        error <= 1;
        error_code <= bus_error ? 3'd3 : 3'd4;
        pending <= 0;
        wait_count <= 0;
      end else if (pending) begin
        if (bus_rsp_valid) begin
          pending <= 0;
          wait_count <= 0;
        end else if (wait_count == CW'(TIMEOUT_CYCLES-1)) begin
          error <= 1;
          error_code <= 3'd2;
          pending <= 0;
          wait_count <= 0;
        end else wait_count <= wait_count + 1'b1;
      end else if (req_valid) begin
        if (bus_req_ready) begin
          pending <= !req_write;
          wait_count <= 0;
        end else if (wait_count == CW'(TIMEOUT_CYCLES-1)) begin
          error <= 1;
          error_code <= 3'd1;
          wait_count <= 0;
        end else wait_count <= wait_count + 1'b1;
      end else wait_count <= 0;
    end
  end
`ifndef SYNTHESIS
  initial if (TIMEOUT_CYCLES < 1) $fatal(1, "TIMEOUT_CYCLES must be positive");
`endif
endmodule
