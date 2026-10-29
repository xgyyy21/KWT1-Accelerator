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
  integer progress_cycle = 0;
  integer last_tile_seen = -1;
  integer last_write_seen = 0;
  integer output_fd, write_fd, input_fd, tile_fd;
  integer word_offset, input_reads = 0, tile_launches = 0;
  integer last_write_cycle = -1;
  bit write_seen [0:M*N*2-1];
  logic [31:0] actual_bits;
  string output_dir = ".";

  // Long full-layer runs must expose whether the scheduler is advancing or
  // stuck in one tile.  This is diagnostic output only; it does not affect
  // the protocol or result checks.
  always @(posedge clk) begin
    if (rst_n) begin
      progress_cycle = progress_cycle + 1;
      if (tile_index !== last_tile_seen) begin
        $display("PROGRESS cycle=%0d tile=%0d row=%0d col=%0d k_block=%0d writes=%0d busy=%0d error=%0d",
                 progress_cycle, tile_index, row_base, col_base,
                 k_block_index, write_count, tile_busy, accel_error);
        last_tile_seen = tile_index;
        $fflush();
      end
      if (write_count >= last_write_seen + 1024) begin
        $display("PROGRESS cycle=%0d write_halfwords=%0d tile=%0d",
                 progress_cycle, write_count, tile_index);
        last_write_seen = write_count;
        $fflush();
      end
      if ((progress_cycle % 100000) == 0) begin
        $display("HEARTBEAT cycle=%0d tile=%0d writes=%0d busy=%0d done=%0d error=%0d",
                 progress_cycle, tile_index, write_count, tile_busy,
                 accel_done, accel_error);
        $fflush();
      end
      if (tile_start) begin
        if (tile_index !== tile_launches || row_base !== (tile_launches/16)*8 ||
            col_base !== (tile_launches%16)*16 || k_base !== 0 ||
            rows_valid !== ((tile_launches/16 == 12) ? 3 : 8) ||
            cols_valid !== 16 || k_valid !== 32 || k_block_count !== 2)
          $fatal(1,"tile descriptor mismatch tile=%0d row=%0d col=%0d",tile_index,row_base,col_base);
        $fdisplay(tile_fd,"%0d,%0d,%0d,%0d,%0d,%0d,%0d",progress_cycle,tile_index,
                  row_base,col_base,rows_valid,cols_valid,k_block_count);
        tile_launches = tile_launches + 1;
      end
    end
  end

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
          if (sys_addr < 210000 || sys_addr >= 210000+M*N*2)
            $fatal(1,"write outside output region addr=%0d",sys_addr);
          word_offset = sys_addr - 210000;
          if (write_seen[word_offset]) $fatal(1,"duplicate write addr=%0d",sys_addr);
          if (sys_wdata !== (word_offset[0] ? EXPECTED_BITS[31:16] : EXPECTED_BITS[15:0]))
            $fatal(1,"write data mismatch addr=%0d got=%04h",sys_addr,sys_wdata);
          write_seen[word_offset] = 1;
          last_write_cycle = progress_cycle;
          $fdisplay(write_fd,"%0d,%0d,%0d,%0d,%0d,%0d,0x%04h",progress_cycle,tile_index,
                    word_offset/2/N,(word_offset/2)%N,sys_addr,word_offset%2,sys_wdata);
          mem[sys_addr] <= sys_wdata;
          write_count = write_count + 1;
        end else begin
          if (!((sys_addr < M*K*2) ||
                (sys_addr >= 100000 && sys_addr < 100000+K*N*2) ||
                (sys_addr >= 200000 && sys_addr < 200000+N*2)))
            $fatal(1,"read outside input regions addr=%0d",sys_addr);
          input_reads = input_reads + 1;
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
    if ($value$plusargs("OUT_DIR=%s",output_dir)) begin end
    output_fd = $fopen({output_dir,"/ffn1_output.csv"},"w");
    write_fd = $fopen({output_dir,"/ffn1_writeback.csv"},"w");
    tile_fd = $fopen({output_dir,"/ffn1_tiles.csv"},"w");
    if (!output_fd || !write_fd || !tile_fd) $fatal(1,"cannot open evidence files");
    $fdisplay(output_fd,"row,column,word_address,result_bits,expected_bits,match");
    $fdisplay(write_fd,"cycle,tile_id,row,column,word_address,half,actual_word");
    $fdisplay(tile_fd,"cycle,tile_id,row_base,column_base,rows_valid,cols_valid,k_blocks");
    for (i=0;i<M*N*2;i=i+1) write_seen[i]=0;
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
    for (i=0;i<M*N;i=i+1) write_fp32(210000,i,32'hdeadbeef);
    // Archive the exact test inputs used by this simulation, low half first.
    input_fd=$fopen({output_dir,"/ffn1_x.mem"},"w");
    if(!input_fd) $fatal(1,"cannot open X input archive");
    for(i=0;i<M*K*2;i=i+1) $fdisplay(input_fd,"%04h",mem[i]);
    $fclose(input_fd);
    input_fd=$fopen({output_dir,"/ffn1_w.mem"},"w");
    if(!input_fd) $fatal(1,"cannot open W input archive");
    for(i=0;i<K*N*2;i=i+1) $fdisplay(input_fd,"%04h",mem[100000+i]);
    $fclose(input_fd);
    input_fd=$fopen({output_dir,"/ffn1_bias.mem"},"w");
    if(!input_fd) $fatal(1,"cannot open bias input archive");
    for(i=0;i<N*2;i=i+1) $fdisplay(input_fd,"%04h",mem[200000+i]);
    $fclose(input_fd);

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
    progress_cycle = 0;
    last_tile_seen = -1;
    last_write_seen = 0;
    nice_write_reg(8'h00, 32'd1);

    guard = 0;
    while (!accel_done && guard < 12000000) begin
      @(negedge clk);
      guard = guard + 1;
      if (accel_error) $fatal(1,"accelerator error at cycle=%0d tile=%0d",guard,tile_index);
    end
    if (!accel_done || accel_error)
      $fatal(1, "FFN1 job failed done=%0d error=%0d tiles=%0d cycles=%0d",
             accel_done, accel_error, tile_index, guard);

    for (r = 0; r < M; r = r + 1)
      for (c = 0; c < N; c = c + 1) begin
        actual_bits = {mem[210000+(r*N+c)*2+1],mem[210000+(r*N+c)*2]};
        $fdisplay(output_fd,"%0d,%0d,%0d,0x%08h,0x%08h,%0d",r,c,
                  210000+(r*N+c)*2,actual_bits,EXPECTED_BITS,actual_bits===EXPECTED_BITS);
        if ({mem[210000 + (r*N+c)*2 + 1],
             mem[210000 + (r*N+c)*2]} !== EXPECTED_BITS)
          $fatal(1, "FFN1 writeback mismatch row=%0d col=%0d got=%08h expected=%08h",
                 r, c, {mem[210000 + (r*N+c)*2 + 1],
                        mem[210000 + (r*N+c)*2]}, EXPECTED_BITS);
        observed_results = observed_results + 1;
      end

    for(i=0;i<M*N*2;i=i+1)
      if (!write_seen[i]) $fatal(1,"missing write addr=%0d",210000+i);
    if(tile_launches != 208 || tile_index !== 207)
      $fatal(1,"tile count mismatch launches=%0d last_index=%0d",tile_launches,tile_index);
    if(input_reads != 642048)
      $fatal(1,"input read count mismatch got=%0d expected=642048",input_reads);
    if(last_write_cycle < 0 || progress_cycle <= last_write_cycle)
      $fatal(1,"DONE not after final accepted write");

    if (write_count != M*N*2)
      $fatal(1, "FFN1 write count mismatch got=%0d expected=%0d",
             write_count, M*N*2);
    $display("PASS: FFN1 full layer m=%0d k=%0d n=%0d tiles=%0d outputs=%0d writes=%0d cycles=%0d",
             M, K, N, tile_index + 1, observed_results, write_count, guard);
    $display("PASS: FFN1 read_halfwords=%0d unique_write_halfwords=%0d tail_rows=3 last_write_cycle=%0d done_cycle=%0d",
             input_reads,write_count,last_write_cycle,progress_cycle);
    $fclose(output_fd); $fclose(write_fd); $fclose(tile_fd);
    $finish;
  end

  initial begin
    #120000000;
    $fatal(1, "fp32_competition_ffn1_tb timeout");
  end
endmodule
