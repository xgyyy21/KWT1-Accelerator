`timescale 1ns/1ps

// Standalone end-to-end check for the protocol-neutral top.  The memory model
// is a 16-bit-word SRAM: reads return one cycle after acceptance and writes are
// accepted immediately.  This deliberately tests the same NICE/System-Bus
// split that will later be wrapped by the E203 platform.
module fp32_accelerator_top_tb;
  localparam logic [31:0] ONE = 32'h3f800000;
  localparam integer MEM_WORDS = 300000;

  logic clk = 1'b0;
  always #5 clk = ~clk;
  logic rst_n = 1'b0;

  logic nice_valid = 1'b0, nice_write = 1'b0;
  logic [31:0] nice_addr = 0, nice_wdata = 0;
  logic nice_ready, nice_rsp_valid;
  logic [31:0] nice_rsp_rdata;
  logic sys_valid, sys_write, sys_ready = 1'b1, sys_rsp_valid;
  logic [31:0] sys_addr;
  logic [15:0] sys_wdata, sys_rsp_rdata;
  logic accel_done, accel_error, tile_start, tile_busy;
  logic [31:0] tile_index;
  logic [15:0] row_base, col_base, k_base, rows_valid, cols_valid, k_valid;
  logic task_first, task_last;
  logic [15:0] k_block_index, k_block_count;

  logic [15:0] mem [0:MEM_WORDS-1];
  logic read_pending = 1'b0;
  logic [31:0] pending_addr = 0;
  integer write_count = 0;
  integer i, r, c;

  fp32_accelerator_top #(.STRICT_COMPETITION_SHAPES(1'b0)) dut (
    .clk(clk), .rst_n(rst_n),
    .nice_req_valid(nice_valid), .nice_req_write(nice_write),
    .nice_req_addr(nice_addr), .nice_req_wdata(nice_wdata),
    .nice_req_ready(nice_ready), .nice_rsp_valid(nice_rsp_valid),
    .nice_rsp_rdata(nice_rsp_rdata), .sys_req_valid(sys_valid),
    .sys_req_write(sys_write), .sys_req_addr(sys_addr),
    .sys_req_wdata(sys_wdata), .sys_req_ready(sys_ready),
    .sys_rsp_valid(sys_rsp_valid), .sys_rsp_rdata(sys_rsp_rdata),
    .tile_start(tile_start), .tile_busy(tile_busy), .accel_done(accel_done),
    .accel_error(accel_error), .tile_index(tile_index), .row_base(row_base),
    .col_base(col_base), .k_base(k_base), .rows_valid(rows_valid),
    .cols_valid(cols_valid), .k_valid(k_valid), .task_first(task_first),
    .task_last(task_last), .k_block_index(k_block_index),
    .k_block_count(k_block_count)
  );

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      read_pending <= 1'b0;
      pending_addr <= 0;
      sys_rsp_valid <= 1'b0;
      sys_rsp_rdata <= 0;
    end else begin
      sys_rsp_valid <= read_pending;
      if (read_pending)
        sys_rsp_rdata <= mem[pending_addr];
      read_pending <= 1'b0;
      if (sys_valid && sys_ready) begin
        if (sys_addr >= MEM_WORDS)
          $fatal(1, "System-Bus address out of model range: %0d", sys_addr);
        if (sys_write) begin
          mem[sys_addr] <= sys_wdata;
          write_count = write_count + 1;
        end else begin
          read_pending <= 1'b1;
          pending_addr <= sys_addr;
        end
      end
    end
  end

  task automatic write_fp32(input integer base, input integer elem,
                            input logic [31:0] bits);
    begin
      mem[base + elem*2] = bits[15:0];
      mem[base + elem*2 + 1] = bits[31:16];
    end
  endtask

  task automatic clear_region(input integer base, input integer words);
    integer q;
    begin
      for (q = 0; q < words; q = q + 1)
        mem[base + q] = 16'd0;
    end
  endtask

  task automatic nice_write_reg(input logic [7:0] addr, input logic [31:0] data);
    begin
      @(negedge clk);
      nice_addr = {24'd0, addr};
      nice_wdata = data;
      nice_write = 1'b1;
      nice_valid = 1'b1;
      @(negedge clk);
      nice_valid = 1'b0;
      nice_write = 1'b0;
      nice_addr = 0;
      nice_wdata = 0;
    end
  endtask

  task automatic run_case(input integer m, input integer k, input integer n,
                          input integer a_base, input integer b_base,
                          input integer bias_base, input integer result_base,
                          input logic [31:0] expected);
    integer guard, result_words;
    integer rr, cc, kk;
    logic [31:0] got;
    begin
      result_words = m*n*2;
      clear_region(result_base, result_words);
      for (rr = 0; rr < m; rr = rr + 1)
        for (kk = 0; kk < k; kk = kk + 1)
          write_fp32(a_base, rr*k + kk, ONE);
      for (rr = 0; rr < k; rr = rr + 1)
        for (cc = 0; cc < n; cc = cc + 1)
          write_fp32(b_base, rr*n + cc, ONE);
      for (cc = 0; cc < n; cc = cc + 1)
        write_fp32(bias_base, cc, ONE);

      nice_write_reg(8'h08, a_base);
      nice_write_reg(8'h0c, b_base);
      nice_write_reg(8'h20, bias_base);
      nice_write_reg(8'h10, result_base);
      nice_write_reg(8'h14, m);
      nice_write_reg(8'h18, k);
      nice_write_reg(8'h1c, n);
      write_count = 0;
      nice_write_reg(8'h00, 32'd1);

      guard = 0;
      while (!accel_done && guard < 2000000) begin
        @(posedge clk);
        guard = guard + 1;
      end
      if (!accel_done || accel_error)
        $fatal(1, "top job failed m=%0d k=%0d n=%0d done=%0d error=%0d tiles=%0d",
               m, k, n, accel_done, accel_error, tile_index);
      for (rr = 0; rr < m; rr = rr + 1)
        for (cc = 0; cc < n; cc = cc + 1) begin
          got = {mem[result_base + (rr*n+cc)*2 + 1],
                 mem[result_base + (rr*n+cc)*2]};
          if (got !== expected)
            $fatal(1, "writeback mismatch m=%0d k=%0d n=%0d row=%0d col=%0d got=%08h expected=%08h",
                   m, k, n, rr, cc, got, expected);
        end
      if (write_count != result_words)
        $fatal(1, "write count mismatch m=%0d k=%0d n=%0d got=%0d expected=%0d",
               m, k, n, write_count, result_words);
      $display("fp32_accelerator_top_tb PASS m=%0d k=%0d n=%0d tiles=%0d writes=%0d",
               m, k, n, tile_index + 1, write_count);
      @(posedge clk);
    end
  endtask

  initial begin
    for (i = 0; i < MEM_WORDS; i = i + 1)
      mem[i] = 16'd0;
    repeat (3) @(negedge clk);
    rst_n = 1'b1;
    // Four spatial tiles exercise partial row/column boundaries and K=64.
    run_case(9, 64, 17, 1000, 100000, 180000, 200000, 32'h42820000);
    // A small second job exercises runtime selection of all 8 K blocks.
    run_case(2, 256, 2, 3000, 110000, 190000, 210000, 32'h43808000);
    $display("fp32_accelerator_top_tb PASS end_to_end_jobs=2");
    $finish;
  end

  initial begin
    #300000000;
    $fatal(1, "fp32_accelerator_top_tb timeout");
  end
endmodule
