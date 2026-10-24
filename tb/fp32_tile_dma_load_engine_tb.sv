`timescale 1ns/1ps

module fp32_tile_dma_load_engine_tb;
  logic clk = 1'b0;
  always #5 clk = ~clk;
  logic rst_n = 1'b0;
  logic start = 1'b0;
  logic bus_req_valid, bus_req_write;
  logic [31:0] bus_req_addr;
  logic [15:0] bus_req_wdata;
  logic bus_req_ready = 1'b1;
  logic bus_rsp_valid = 1'b0;
  logic [15:0] bus_rsp_rdata = 16'd0;
  logic a_wr_en, b_wr_en, result_wr_en;
  logic [9:0] a_wr_addr, b_wr_addr, result_wr_addr;
  logic [15:0] a_wr_data, b_wr_data, result_wr_data;
  logic busy, load_done;

  logic a_rd_en=0, b_rd_en=0, result_rd_en=0;
  logic [9:0] a_rd_addr=0, b_rd_addr=0, result_rd_addr=0;
  logic [15:0] a_rd_data, b_rd_data, result_rd_data;
  logic a_rd_valid, b_rd_valid, result_rd_valid;
  logic [15:0] ext_mem [0:4095];
  logic bus_pending = 1'b0;
  logic [31:0] bus_pending_addr = 0;
  integer i;

  fp32_tile_dma_load_engine #(.ROW_TILE(2), .COL_TILE(2), .K_TILE(2)) dut (
    .clk(clk), .rst_n(rst_n), .start(start),
    .matrix_m(16'd2), .matrix_k(16'd2), .matrix_n(16'd2),
    .row_base(16'd0), .col_base(16'd0), .k_base(16'd0),
    .rows_valid(16'd2), .cols_valid(16'd2), .k_valid(16'd2),
    .a_base_word(32'd100), .b_base_word(32'd200),
    .bias_base_word(32'd300), .result_base_word(32'd400),
    .bus_req_valid(bus_req_valid), .bus_req_write(bus_req_write),
    .bus_req_addr(bus_req_addr), .bus_req_wdata(bus_req_wdata),
    .bus_req_ready(bus_req_ready), .bus_rsp_valid(bus_rsp_valid),
    .bus_rsp_rdata(bus_rsp_rdata), .a_wr_en(a_wr_en), .a_wr_addr(a_wr_addr),
    .a_wr_data(a_wr_data), .b_wr_en(b_wr_en), .b_wr_addr(b_wr_addr),
    .b_wr_data(b_wr_data), .result_wr_en(result_wr_en),
    .result_wr_addr(result_wr_addr), .result_wr_data(result_wr_data),
    .busy(busy), .load_done(load_done)
  );

  matrix_cache_manager cache (
    .clk(clk), .rst_n(rst_n),
    .a_wr_en(a_wr_en), .a_wr_addr(a_wr_addr), .a_wr_data(a_wr_data),
    .b_wr_en(b_wr_en), .b_wr_addr(b_wr_addr), .b_wr_data(b_wr_data),
    .result_wr_en(result_wr_en), .result_wr_addr(result_wr_addr),
    .result_wr_data(result_wr_data), .a_rd_en(a_rd_en),
    .a_rd_addr(a_rd_addr), .a_rd_data(a_rd_data), .a_rd_valid(a_rd_valid),
    .b_rd_en(b_rd_en), .b_rd_addr(b_rd_addr), .b_rd_data(b_rd_data),
    .b_rd_valid(b_rd_valid), .result_rd_en(result_rd_en),
    .result_rd_addr(result_rd_addr), .result_rd_data(result_rd_data),
    .result_rd_valid(result_rd_valid)
  );

  // One-cycle-later read response model.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      bus_pending <= 1'b0;
      bus_pending_addr <= 0;
      bus_rsp_valid <= 1'b0;
      bus_rsp_rdata <= 0;
    end else begin
      bus_rsp_valid <= bus_pending;
      if (bus_pending)
        bus_rsp_rdata <= ext_mem[bus_pending_addr];
      bus_pending <= bus_req_valid && bus_req_ready;
      if (bus_req_valid && bus_req_ready)
        bus_pending_addr <= bus_req_addr;
    end
  end

  task automatic ext_write_fp32(input integer base, input integer elem,
                                input logic [31:0] bits);
    begin
      ext_mem[base + elem*2] = bits[15:0];
      ext_mem[base + elem*2 + 1] = bits[31:16];
    end
  endtask

  task automatic read_cache_word(input integer bank, input integer addr,
                                 input logic [15:0] expected);
    logic [15:0] value;
    begin
      @(negedge clk);
      a_rd_en=0; b_rd_en=0; result_rd_en=0;
      case (bank)
        0: begin a_rd_en=1; a_rd_addr=addr[9:0]; end
        1: begin b_rd_en=1; b_rd_addr=addr[9:0]; end
        default: begin result_rd_en=1; result_rd_addr=addr[9:0]; end
      endcase
      @(negedge clk);
      a_rd_en=0; b_rd_en=0; result_rd_en=0;
      #1;
      case (bank)
        0: begin if(!a_rd_valid) $fatal(1,"A cache read invalid"); value=a_rd_data; end
        1: begin if(!b_rd_valid) $fatal(1,"B cache read invalid"); value=b_rd_data; end
        default: begin if(!result_rd_valid) $fatal(1,"bias cache read invalid"); value=result_rd_data; end
      endcase
      if (value !== expected)
        $fatal(1,"cache load mismatch bank=%0d addr=%0d got=%04h expected=%04h",
               bank, addr, value, expected);
    end
  endtask

  initial begin
    for (i=0; i<4096; i=i+1) ext_mem[i]=16'd0;
    ext_write_fp32(100,0,32'h3f800000);
    ext_write_fp32(100,1,32'h40000000);
    ext_write_fp32(100,2,32'h40400000);
    ext_write_fp32(100,3,32'h40800000);
    ext_write_fp32(200,0,32'h41200000);
    ext_write_fp32(200,1,32'h41a00000);
    ext_write_fp32(200,2,32'h41f00000);
    ext_write_fp32(200,3,32'h42200000);
    ext_write_fp32(300,0,32'h3f000000);
    ext_write_fp32(300,1,32'h3fc00000);

    repeat (2) @(negedge clk);
    rst_n=1'b1;
    @(negedge clk); start=1'b1;
    @(negedge clk); start=1'b0;
    while (!load_done) @(negedge clk);
    if (busy) $fatal(1,"load engine still busy at load_done");

    read_cache_word(0,0,16'h0000);
    read_cache_word(0,1,16'h3f80);
    read_cache_word(0,6,16'h0000);
    read_cache_word(0,7,16'h4080);
    read_cache_word(1,0,16'h0000);
    read_cache_word(1,7,16'h4220);
    read_cache_word(2,0,16'h0000);
    read_cache_word(2,3,16'h3fc0);
    $display("PASS: fp32_tile_dma_load_engine bus read-response and cache writes");
    $finish;
  end

  initial begin
    #200000;
    $fatal(1,"fp32_tile_dma_load_engine_tb timeout");
  end
endmodule
