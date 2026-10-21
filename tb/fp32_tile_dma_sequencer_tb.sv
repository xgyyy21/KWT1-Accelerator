`timescale 1ns/1ps

module fp32_tile_dma_sequencer_tb;
  logic clk = 1'b0;
  always #5 clk = ~clk;
  logic rst_n = 1'b0;
  logic start = 1'b0;
  logic req_ready = 1'b1;
  logic [15:0] matrix_m, matrix_k, matrix_n;
  logic [15:0] row_base, col_base, k_base;
  logic [15:0] rows_valid, cols_valid, k_valid;
  logic busy, done, req_valid, req_write;
  logic [31:0] req_addr;
  logic [1:0] cache_bank;
  logic cache_write, cache_read;
  logic [9:0] cache_word_addr;
  logic [15:0] local_row, local_col, local_k;
  logic word_high;
  logic [2:0] phase;
  integer phase_count_a, phase_count_b, phase_count_bias, phase_count_result;

  fp32_tile_dma_sequencer dut (
    .clk(clk), .rst_n(rst_n), .start(start),
    .matrix_m(matrix_m), .matrix_k(matrix_k), .matrix_n(matrix_n),
    .row_base(row_base), .col_base(col_base), .k_base(k_base),
    .rows_valid(rows_valid), .cols_valid(cols_valid), .k_valid(k_valid),
    .a_base_word(32'd1000), .b_base_word(32'd2000),
    .bias_base_word(32'd3000), .result_base_word(32'd4000),
    .req_ready(req_ready), .busy(busy), .done(done),
    .req_valid(req_valid), .req_write(req_write), .req_addr(req_addr),
    .cache_bank(cache_bank), .cache_write(cache_write),
    .cache_read(cache_read), .cache_word_addr(cache_word_addr),
    .local_row(local_row), .local_col(local_col), .local_k(local_k),
    .word_high(word_high), .phase(phase)
  );

  task automatic run_case(
    input integer m, input integer k, input integer n,
    input integer rb, input integer cb, input integer kb,
    input integer rv, input integer cv, input integer kv,
    input integer expected_a, input integer expected_b,
    input integer expected_bias, input integer expected_result
  );
    integer total;
    begin
      matrix_m=m; matrix_k=k; matrix_n=n;
      row_base=rb; col_base=cb; k_base=kb;
      rows_valid=rv; cols_valid=cv; k_valid=kv;
      phase_count_a=0; phase_count_b=0; phase_count_bias=0; phase_count_result=0;
      @(negedge clk); start=1'b1;
      @(negedge clk); start=1'b0;
      while (!done) begin
        if (req_valid) begin
          if (!busy || !req_ready) $fatal(1, "request handshake flags incorrect");
          case (phase)
            3'd1: begin
              phase_count_a=phase_count_a+1;
              if (req_write || !cache_write || cache_read || cache_bank!==2'd0)
                $fatal(1, "A phase direction/bank mismatch");
            end
            3'd2: begin
              phase_count_b=phase_count_b+1;
              if (req_write || !cache_write || cache_read || cache_bank!==2'd1)
                $fatal(1, "B phase direction/bank mismatch");
            end
            3'd3: begin
              phase_count_bias=phase_count_bias+1;
              if (req_write || !cache_write || cache_read || cache_bank!==2'd2)
                $fatal(1, "bias phase direction/bank mismatch");
            end
            3'd4: begin
              phase_count_result=phase_count_result+1;
              if (!req_write || cache_write || !cache_read || cache_bank!==2'd2)
                $fatal(1, "result phase direction/bank mismatch");
            end
            default: $fatal(1, "invalid active DMA phase %0d", phase);
          endcase
        end
        if (!done) @(negedge clk);
      end
      if (phase_count_a !== expected_a || phase_count_b !== expected_b ||
          phase_count_bias !== expected_bias || phase_count_result !== expected_result)
        $fatal(1, "beat count mismatch A=%0d/%0d B=%0d/%0d bias=%0d/%0d result=%0d/%0d",
               phase_count_a, expected_a, phase_count_b, expected_b,
               phase_count_bias, expected_bias, phase_count_result, expected_result);
      total = expected_a + expected_b + expected_bias + expected_result;
      $display("DMA case m=%0d k=%0d n=%0d beats=%0d PASS", m, k, n, total);
      @(negedge clk);
    end
  endtask

  initial begin
    repeat (2) @(negedge clk);
    rst_n=1'b1;
    run_case(99,64,256, 0,0,0, 8,16,32, 512,1024,32,256);
    run_case(99,64,256, 96,240,32, 3,16,32, 192,1024,32,96);
    run_case(99,256,64, 96,48,224, 3,5,32, 192,320,10,30);
    $display("PASS: fp32_tile_dma_sequencer phase ordering and beat counts");
    $finish;
  end

  initial begin
    #300000;
    $fatal(1, "fp32_tile_dma_sequencer_tb timeout");
  end
endmodule
