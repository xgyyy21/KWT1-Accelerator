`timescale 1ns/1ps

module fp32_tile_dma_writeback_engine_tb;
  logic clk=0; always #5 clk=~clk;
  logic rst_n=0, start=0, bus_req_valid, bus_req_write, bus_req_ready=1;
  logic [31:0] bus_req_addr;
  logic [15:0] bus_req_wdata;
  logic result_rd_en, result_rd_valid;
  logic [9:0] result_rd_addr;
  logic [15:0] result_rd_data;
  logic busy, done;
  logic result_wr_en;
  logic [9:0] result_wr_addr;
  logic [15:0] result_wr_data;
  logic a_wr_en=0, b_wr_en=0;
  logic [9:0] a_wr_addr=0,b_wr_addr=0;
  logic [15:0] a_wr_data=0,b_wr_data=0;
  logic a_rd_en=0,b_rd_en=0,result_cache_rd_en;
  logic [9:0] a_rd_addr=0,b_rd_addr=0,result_cache_rd_addr;
  logic [15:0] a_rd_data,b_rd_data,result_cache_rd_data;
  logic a_rd_valid,b_rd_valid,result_cache_rd_valid;
  logic [15:0] ext_mem [0:65535];
  integer i;

  fp32_tile_dma_writeback_engine #(.ROW_TILE(8),.COL_TILE(16),.K_TILE(32)) dut (
    .clk(clk), .rst_n(rst_n), .start(start),
    .matrix_m(16'd99), .matrix_k(16'd256), .matrix_n(16'd64),
    .row_base(16'd96), .col_base(16'd61),
    .rows_valid(16'd2), .cols_valid(16'd3), .result_base_word(32'd4000),
    .result_rd_en(result_cache_rd_en), .result_rd_addr(result_cache_rd_addr),
    .result_rd_data(result_cache_rd_data), .result_rd_valid(result_cache_rd_valid),
    .bus_req_valid(bus_req_valid), .bus_req_write(bus_req_write),
    .bus_req_addr(bus_req_addr), .bus_req_wdata(bus_req_wdata),
    .bus_req_ready(bus_req_ready), .busy(busy), .done(done)
  );

  matrix_cache_manager cache (
    .clk(clk), .rst_n(rst_n),
    .a_wr_en(a_wr_en), .a_wr_addr(a_wr_addr), .a_wr_data(a_wr_data),
    .b_wr_en(b_wr_en), .b_wr_addr(b_wr_addr), .b_wr_data(b_wr_data),
    .result_wr_en(result_wr_en), .result_wr_addr(result_wr_addr),
    .result_wr_data(result_wr_data), .a_rd_en(a_rd_en), .a_rd_addr(a_rd_addr),
    .a_rd_data(a_rd_data), .a_rd_valid(a_rd_valid), .b_rd_en(b_rd_en),
    .b_rd_addr(b_rd_addr), .b_rd_data(b_rd_data), .b_rd_valid(b_rd_valid),
    .result_rd_en(result_cache_rd_en), .result_rd_addr(result_cache_rd_addr),
    .result_rd_data(result_cache_rd_data), .result_rd_valid(result_cache_rd_valid)
  );

  always @(posedge clk) begin
    if (bus_req_valid && bus_req_write && bus_req_ready) begin
      if (!bus_req_write) $fatal(1,"writeback request not marked write");
      ext_mem[bus_req_addr] <= bus_req_wdata;
    end
  end

  task automatic write_result_word(input integer addr, input logic [15:0] value);
    begin
      @(negedge clk); result_wr_en=1; result_wr_addr=addr[9:0]; result_wr_data=value;
      @(negedge clk); result_wr_en=0;
    end
  endtask

  initial begin
    for (i=0;i<65536;i=i+1) ext_mem[i]=16'hdead;
    repeat (2) @(negedge clk); rst_n=1;
    // Local result tile has two rows and three columns, low/high words first.
    for (i=0;i<6;i=i+1) begin
      write_result_word(((i/3)*16+(i%3))*2, 16'h1000+i);
      write_result_word(((i/3)*16+(i%3))*2+1, 16'h2000+i);
    end
    @(negedge clk); start=1;
    @(negedge clk); start=0;
    while (!done) @(negedge clk);
    if (busy) $fatal(1,"writeback remains busy at done");

    // Global row 96..97, columns 61..63, row-major result layout.
    for (i=0;i<6;i=i+1) begin
      integer r,c,base_addr;
      r=i/3; c=i%3;
      base_addr=4000 + ((((96+r)*64)+(61+c))*2);
      if (ext_mem[base_addr] !== 16'h1000+i ||
          ext_mem[base_addr+1] !== 16'h2000+i)
        $fatal(1,"writeback mismatch elem=%0d addr=%0d got=%04h/%04h",
               i,base_addr,ext_mem[base_addr],ext_mem[base_addr+1]);
    end
    $display("PASS: fp32_tile_dma_writeback_engine result read and bus writes");
    $finish;
  end

  initial begin #100000; $fatal(1,"fp32_tile_dma_writeback_engine_tb timeout"); end
endmodule
