`timescale 1ns/1ps

// Full-size functional check for the mandatory undergraduate layer:
//   [99 x 64] * [64 x 256] + bias[256] -> [99 x 256]
// All operands are one, so every valid output is 65.0 (0x42820000).
// This is a protocol-neutral NICE/System-Bus model; it is not an E203 test.
module fp32_competition_ffn1_tb;
  localparam logic [31:0] ONE_BITS = 32'h3f800000;
  localparam logic [31:0] EXPECTED_BITS = 32'h42820000;
  localparam integer M = 99;
  localparam integer K = 64;
  localparam integer N = 256;
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
  integer i, r, c, guard;
  integer observed_results = 0;

  fp32_accelerator_top #(.STRICT_COMPETITION_SHAPES(1'b1)) dut (
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

  initial begin
    for (i = 0; i < MEM_WORDS; i = i + 1)
      mem[i] = 16'd0;

    // Keep the regions separate and word-addressed, matching memory_layout_v1.
    // A: 0, B: 100000, bias: 200000, Y: 210000.
    for (r = 0; r < M; r = r + 1)
      for (c = 0; c < K; c = c + 1)
        write_fp32(0, r*K + c, ONE_BITS);
    for (r = 0; r < K; r = r + 1)
      for (c = 0; c < N; c = c + 1)
        write_fp32(100000, r*N + c, ONE_BITS);
    for (c = 0; c < N; c = c + 1)
      write_fp32(200000, c, ONE_BITS);

    repeat (3) @(negedge clk);
    rst_n = 1'b1;
    nice_write_reg(8'h08, 32'd0);
    nice_write_reg(8'h0c, 32'd100000);
    nice_write_reg(8'h20, 32'd200000);
    nice_write_reg(8'h10, 32'd210000);
    nice_write_reg(8'h14, M);
    nice_write_reg(8'h18, K);
    nice_write_reg(8'h1c, N);
    write_count = 0;
    nice_write_reg(8'h00, 32'd1);

    guard = 0;
    while (!accel_done && guard < 12000000) begin
      @(posedge clk);
      guard = guard + 1;
    end
    if (!accel_done || accel_error)
      $fatal(1, "FFN1 job failed done=%0d error=%0d tiles=%0d cycles=%0d",
             accel_done, accel_error, tile_index, guard);

    for (r = 0; r < M; r = r + 1)
      for (c = 0; c < N; c = c + 1) begin
        if ({mem[210000 + (r*N+c)*2 + 1],
             mem[210000 + (r*N+c)*2]} !== EXPECTED_BITS)
          $fatal(1, "FFN1 writeback mismatch row=%0d col=%0d got=%08h expected=%08h",
                 r, c, {mem[210000 + (r*N+c)*2 + 1],
                        mem[210000 + (r*N+c)*2]}, EXPECTED_BITS);
        observed_results = observed_results + 1;
      end

    if (write_count != M*N*2)
      $fatal(1, "FFN1 write count mismatch got=%0d expected=%0d",
             write_count, M*N*2);
    $display("PASS: FFN1 full layer m=%0d k=%0d n=%0d tiles=%0d outputs=%0d writes=%0d cycles=%0d",
             M, K, N, tile_index + 1, observed_results, write_count, guard);
    $finish;
  end

  initial begin
    #120000000;
    $fatal(1, "fp32_competition_ffn1_tb timeout");
  end
endmodule
