`timescale 1ns/1ps

// Protocol-level shared-SRAM loading evidence.
// The loader writes the platform memory model one 16-bit word per cycle before
// START. The accelerator then fetches and writes back through its System Bus.
// This is not a substitute for a real E203/NICE platform simulation.
module kwt_shared_sram_loader_tb;
  localparam int SHARED_WORDS = 262144;
  localparam int M = 2;
  localparam int K = 4;
  localparam int N = 2;
  localparam logic [31:0] A_BASE = 32'h0000_1000;
  localparam logic [31:0] B_BASE = 32'h0000_4000;
  localparam logic [31:0] BIAS_BASE = 32'h0000_c000;
  localparam logic [31:0] Y_BASE = 32'h0001_0000;
  localparam logic [31:0] ONE = 32'h3f80_0000;
  localparam logic [31:0] EXPECTED = 32'h40a0_0000;

  logic clk = 1'b0;
  always #5 clk = ~clk;
  logic rst_n = 1'b0;
  logic [15:0] mem [0:SHARED_WORDS-1];

  logic [2:0] cache_standby = 3'b000;
  logic [23:0] macro_cen, macro_gwen, macro_ret1n;
  logic [23:0][15:0] macro_wen, macro_d;
  logic [23:0][6:0] macro_a;
  logic [23:0][15:0] macro_q = '0;
  logic [23:0][2:0] macro_ema;
  logic [23:0][1:0] macro_emaw;
  logic nice_req_valid = 1'b0, nice_req_write = 1'b0;
  logic [31:0] nice_req_addr = '0, nice_req_wdata = '0;
  logic nice_req_ready, nice_rsp_valid;
  logic [31:0] nice_rsp_rdata;
  logic sys_req_valid, sys_req_write;
  logic [31:0] sys_req_addr;
  logic [15:0] sys_req_wdata;
  logic sys_req_ready = 1'b0, sys_rsp_valid = 1'b0;
  logic [15:0] sys_rsp_rdata = '0;
  logic tile_start, tile_busy, accel_done, accel_error;
  logic [31:0] tile_index;
  logic [15:0] row_base, col_base, k_base, rows_valid, cols_valid, k_valid;
  logic task_first, task_last;
  logic [15:0] k_block_index, k_block_count;

  integer cycle = 0;
  integer load_words = 0;
  integer bus_reads = 0;
  integer bus_writes = 0;
  integer first_load_cycle = -1;
  integer last_write_cycle = -1;
  logic read_pending = 1'b0;
  logic [31:0] pending_addr = '0;

  fp32_accelerator_top #(
    .STRICT_COMPETITION_SHAPES(1'b0),
    .USE_SRAM_MACROS(1'b0)
  ) dut (
    .clk(clk), .rst_n(rst_n), .cache_standby(cache_standby),
    .macro_cen(macro_cen), .macro_gwen(macro_gwen), .macro_wen(macro_wen),
    .macro_a(macro_a), .macro_d(macro_d), .macro_q(macro_q),
    .macro_ema(macro_ema), .macro_emaw(macro_emaw), .macro_ret1n(macro_ret1n),
    .nice_req_valid(nice_req_valid), .nice_req_write(nice_req_write),
    .nice_req_addr(nice_req_addr), .nice_req_wdata(nice_req_wdata),
    .nice_req_ready(nice_req_ready), .nice_rsp_valid(nice_rsp_valid),
    .nice_rsp_rdata(nice_rsp_rdata), .sys_req_valid(sys_req_valid),
    .sys_req_write(sys_req_write), .sys_req_addr(sys_req_addr),
    .sys_req_wdata(sys_req_wdata), .sys_req_ready(sys_req_ready),
    .sys_rsp_valid(sys_rsp_valid), .sys_rsp_rdata(sys_rsp_rdata),
    .tile_start(tile_start), .tile_busy(tile_busy), .accel_done(accel_done),
    .accel_error(accel_error), .tile_index(tile_index), .row_base(row_base),
    .col_base(col_base), .k_base(k_base), .rows_valid(rows_valid),
    .cols_valid(cols_valid), .k_valid(k_valid), .task_first(task_first),
    .task_last(task_last), .k_block_index(k_block_index),
    .k_block_count(k_block_count)
  );

  always @(posedge clk) begin
    cycle <= cycle + 1;
    // A deterministic ready pattern proves that requests survive wait states.
    sys_req_ready <= (cycle % 7 != 0) && (cycle % 7 != 1);
    sys_rsp_valid <= read_pending;
    if (read_pending)
      sys_rsp_rdata <= mem[pending_addr];
    read_pending <= 1'b0;
    if (sys_req_valid && sys_req_ready) begin
      if (sys_req_write) begin
        mem[sys_req_addr] <= sys_req_wdata;
        bus_writes <= bus_writes + 1;
        last_write_cycle <= cycle;
      end else begin
        pending_addr <= sys_req_addr;
        read_pending <= 1'b1;
        bus_reads <= bus_reads + 1;
      end
    end
  end

  task automatic platform_write_word(input logic [31:0] address,
                                     input logic [15:0] data);
    begin
      if (address >= SHARED_WORDS) $fatal(1, "loader address out of range");
      @(negedge clk);
      @(posedge clk);
      #1;
      mem[address] = data;
      if (first_load_cycle < 0) first_load_cycle = cycle;
      load_words = load_words + 1;
    end
  endtask

  task automatic platform_write_fp32(input logic [31:0] address,
                                     input logic [31:0] value);
    begin
      platform_write_word(address, value[15:0]);
      platform_write_word(address + 1, value[31:16]);
    end
  endtask

  task automatic nice_write(input logic [31:0] address,
                            input logic [31:0] data);
    begin
      @(negedge clk);
      while (!nice_req_ready) @(negedge clk);
      nice_req_valid = 1'b1;
      nice_req_write = 1'b1;
      nice_req_addr = address;
      nice_req_wdata = data;
      @(posedge clk);
      #1;
      nice_req_valid = 1'b0;
      nice_req_write = 1'b0;
      nice_req_addr = '0;
      nice_req_wdata = '0;
    end
  endtask

  function automatic integer fp32_word_address(input integer base,
                                               input integer element,
                                               input integer half);
    fp32_word_address = base + (2 * element) + half;
  endfunction

  integer r, k, c, element;
  integer timeout;
  initial begin
    for (element = 0; element < SHARED_WORDS; element = element + 1)
      mem[element] = 16'h0000;

    repeat (3) @(negedge clk);
    rst_n = 1'b1;

    // Platform loader model: one 16-bit word transfer per cycle.
    for (r = 0; r < M; r = r + 1)
      for (k = 0; k < K; k = k + 1)
        platform_write_fp32(A_BASE + 2 * (r * K + k), ONE);
    for (k = 0; k < K; k = k + 1)
      for (c = 0; c < N; c = c + 1)
        platform_write_fp32(B_BASE + 2 * (k * N + c), ONE);
    for (c = 0; c < N; c = c + 1)
      platform_write_fp32(BIAS_BASE + 2 * c, ONE);

    nice_write(32'h08, A_BASE);
    nice_write(32'h0c, B_BASE);
    nice_write(32'h10, Y_BASE);
    nice_write(32'h14, M);
    nice_write(32'h18, K);
    nice_write(32'h1c, N);
    nice_write(32'h20, BIAS_BASE);
    nice_write(32'h00, 32'h0000_0001);

    timeout = 0;
    while (!accel_done && !accel_error && timeout < 200000) begin
      @(posedge clk);
      #1;
      timeout = timeout + 1;
    end
    if (timeout >= 200000) $fatal(1, "shared SRAM loader test timeout");
    if (accel_error) $fatal(1, "accelerator raised ERROR");
    if (!accel_done) $fatal(1, "accelerator did not assert DONE");
    if (mem[Y_BASE] !== EXPECTED[15:0] || mem[Y_BASE + 1] !== EXPECTED[31:16])
      $fatal(1, "Y[0,0] mismatch: %h_%h", mem[Y_BASE + 1], mem[Y_BASE]);
    if (mem[Y_BASE + 2] !== EXPECTED[15:0] || mem[Y_BASE + 3] !== EXPECTED[31:16])
      $fatal(1, "Y[0,1] mismatch");
    if (load_words != (M * K + K * N + N) * 2)
      $fatal(1, "unexpected loader word count: %0d", load_words);
    if (bus_reads == 0 || bus_writes == 0 || last_write_cycle < first_load_cycle)
      $fatal(1, "missing bus activity or invalid timing markers");

    $display("kwt_shared_sram_loader_tb PASS loader_words=%0d bus_reads=%0d bus_writes=%0d first_load_cycle=%0d last_write_cycle=%0d elapsed=%0d",
             load_words, bus_reads, bus_writes, first_load_cycle,
             last_write_cycle, last_write_cycle - first_load_cycle);
    $finish;
  end

  initial begin
    #5000000;
    $fatal(1, "kwt_shared_sram_loader_tb timeout");
  end
endmodule
