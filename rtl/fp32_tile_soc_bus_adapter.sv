// Protocol-neutral bridge between the tile DMA request channel and a SoC
// memory bus.  The tile side is a 16-bit request/response channel with no
// response-ready signal; the SoC side has ready on requests and returns one
// read response later.  At most one read is outstanding.
module fp32_tile_soc_bus_adapter #(
  parameter int ADDR_WIDTH = 32
) (
  input  logic                   clk,
  input  logic                   rst_n,

  input  logic                   tile_req_valid,
  input  logic                   tile_req_write,
  input  logic [ADDR_WIDTH-1:0]  tile_req_addr,
  input  logic [15:0]            tile_req_wdata,
  output logic                   tile_req_ready,
  output logic                   tile_rsp_valid,
  output logic [15:0]            tile_rsp_rdata,

  output logic                   soc_req_valid,
  output logic                   soc_req_write,
  output logic [ADDR_WIDTH-1:0]  soc_req_addr,
  output logic [15:0]            soc_req_wdata,
  input  logic                   soc_req_ready,
  input  logic                   soc_rsp_valid,
  input  logic [15:0]            soc_rsp_rdata,

  output logic                   busy,
  output logic                   error
);
  logic read_pending;

  // The request channel is stalled while a read response is outstanding.
  // Writes do not create a pending response and can complete immediately.
  assign busy = read_pending;
  assign tile_req_ready = !read_pending && soc_req_ready;
  assign soc_req_valid = tile_req_valid && !read_pending;
  assign soc_req_write = tile_req_write;
  assign soc_req_addr = tile_req_addr;
  assign soc_req_wdata = tile_req_wdata;
  assign tile_rsp_valid = soc_rsp_valid && read_pending;
  assign tile_rsp_rdata = soc_rsp_rdata;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      read_pending <= 1'b0;
      error <= 1'b0;
    end else begin
      // A response without an accepted read indicates a bus integration
      // error. Keep the flag until reset so software can observe it.
      if (soc_rsp_valid && !read_pending)
        error <= 1'b1;
      if (tile_req_valid && tile_req_ready && !tile_req_write)
        read_pending <= 1'b1;
      if (soc_rsp_valid && read_pending)
        read_pending <= 1'b0;
    end
  end
endmodule
