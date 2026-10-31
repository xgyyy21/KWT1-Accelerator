`timescale 1ns/1ps
// Real tile RTL + macro-pin adapters + project-authored functional SRAM models.
// Reference uses exact integer arithmetic in units of 1/128, not fp32_math_pkg.
module fp32_sram_compute_integration_tb;
  logic clk = 0;
  always #5 clk = ~clk;
  logic rst_n = 1, start = 0;
  logic [15:0] matrix_m, matrix_k, matrix_n, row_base, col_base, rows_valid, cols_valid;
  wire bus_req_valid, bus_req_write;
  wire [31:0] bus_req_addr;
  wire [15:0] bus_req_wdata;
  logic bus_req_ready = 0, bus_rsp_valid = 0;
  logic [15:0] bus_rsp_rdata = 0;
  wire result_valid, result_last, busy, done, error, load_busy, stream_busy;
  wire [31:0] result_data;
  wire [15:0] result_row, result_col;
  logic [2:0] standby = 0;
  wire [23:0] macro_cen, macro_gwen, macro_ret1n;
  wire [23:0][15:0] macro_wen, macro_d, macro_q;
  wire [23:0][6:0] macro_a;
  wire [23:0][2:0] macro_ema;
  wire [23:0][1:0] macro_emaw;
  localparam int A_BASE = 1000, B_BASE = 5000, C_BASE = 9000, Y_BASE = 12000;
  logic [15:0] ext_mem [0:16383];
  logic [15:0] shadow [0:2][0:1023];
  bit shadow_valid [0:2][0:1023];
  bit seen_output [0:7][0:15], seen_write [0:255];
  bit pending_read [0:2], expected_known [0:2];
  logic [15:0] expected_read [0:2];
  integer requested_addr [0:2];
  bit held_write [0:2], held_read [0:2];
  logic [9:0] held_write_addr [0:2], held_read_addr [0:2];
  logic [15:0] held_write_data [0:2];
  bit accepted_cache_req [0:2], accepted_cache_write [0:2];
  logic [9:0] accepted_cache_addr [0:2];
  logic [15:0] accepted_cache_data [0:2];
  integer cycle = 0, job = -1, result_count = 0, write_count = 0, read_count = 0;
  integer total_results = 0, total_writes = 0, macro_writes = 0, macro_reads = 0, macro_responses = 0;
  integer dma_waits = 0, stream_waits = 0, bus_waits = 0, nonzero_low_words = 0;
  integer last_count = 0, bus_delay = 0;
  bit bus_pending = 0;
  logic [31:0] pending_bus_addr;
  integer access_fd, result_fd, input_fd;
  string trace_dir;

  fp32_tile_kblock_load_compute #(.USE_SRAM_MACROS(1'b1)) dut (
    .clk(clk), .rst_n(rst_n), .start(start), .k_block_count(16'd2),
    .matrix_m(matrix_m), .matrix_k(matrix_k), .matrix_n(matrix_n),
    .row_base(row_base), .col_base(col_base), .k_base(16'd0),
    .rows_valid(rows_valid), .cols_valid(cols_valid), .k_valid_block(16'd32),
    .a_base_word(A_BASE), .b_base_word(B_BASE), .bias_base_word(C_BASE), .result_base_word(Y_BASE),
    .bus_req_ready(bus_req_ready), .bus_rsp_valid(bus_rsp_valid), .bus_rsp_rdata(bus_rsp_rdata),
    .bus_req_valid(bus_req_valid), .bus_req_write(bus_req_write),
    .bus_req_addr(bus_req_addr), .bus_req_wdata(bus_req_wdata),
    .cache_standby(standby), .macro_cen(macro_cen), .macro_gwen(macro_gwen),
    .macro_wen(macro_wen), .macro_a(macro_a), .macro_d(macro_d), .macro_q(macro_q),
    .macro_ema(macro_ema), .macro_emaw(macro_emaw), .macro_ret1n(macro_ret1n),
    .error_in(1'b0), .load_busy(load_busy), .stream_busy(stream_busy),
    .result_valid(result_valid), .result_last(result_last), .result_data(result_data),
    .result_row(result_row), .result_col(result_col), .busy(busy), .done(done), .error(error)
  );
  for (genvar m = 0; m < 24; m++) begin : g_memory
    ramsp128x16_functional_model u_mem (
      .CLK(clk), .CEN(macro_cen[m]), .GWEN(macro_gwen[m]), .WEN(macro_wen[m]),
      .A(macro_a[m]), .D(macro_d[m]), .Q(macro_q[m]),
      .EMA(macro_ema[m]), .EMAW(macro_emaw[m]), .RET1N(macro_ret1n[m])
    );
  end

  initial begin
    #1 rst_n = 0;
  end

  // An exact signed integer times 2**(-fraction_bits), for these small inputs.
  function automatic logic [31:0] encode_exact(input integer value, input integer fraction_bits);
    integer magnitude, msb, exponent_value;
    logic [31:0] normalized;
    begin
      if (value == 0) encode_exact = 0;
      else begin
        magnitude = value < 0 ? -value : value;
        msb = 0;
        for (int b = 0; b < 31; b++) if ((magnitude >> b) != 0) msb = b;
        exponent_value = 127 + msb - fraction_bits;
        normalized = magnitude << (23-msb);
        encode_exact = {1'b0, 8'd0, normalized[22:0]};
        encode_exact[31] = (value < 0);
        encode_exact[30:23] = exponent_value;
      end
    end
  endfunction
  function automatic integer x_units(input integer r, input integer k);
    x_units = (((r*11 + k*7 + job*3) % 19) - 9)*8192 + ((k+r)%13)-6;
  endfunction
  function automatic integer w_integer(input integer k, input integer c);
    w_integer = ((k*5 + c*3 + job) % 7) - 3;
  endfunction
  function automatic integer bias_units(input integer c);
    bias_units = c*3 + job + 1;
  endfunction
  function automatic logic [31:0] expected_output(input integer r, input integer c);
    integer sum;
    begin
      sum = bias_units(c);
      for (int k = 0; k < matrix_k; k++) sum += x_units(r,k)*w_integer(k,c);
      expected_output = encode_exact(sum, 7);
    end
  endfunction
  task automatic put_fp32(input integer addr, input logic [31:0] data);
    ext_mem[addr] = data[15:0];
    ext_mem[addr+1] = data[31:16];
    $fdisplay(input_fd, "%0d,%0d,%04h", job, addr, data[15:0]);
    $fdisplay(input_fd, "%0d,%0d,%04h", job, addr+1, data[31:16]);
  endtask

  // Change stimulus away from the sampling edge. Standby is ordinary CEN
  // suppression, NOT a retention transition (RET1N remains 1).
  always @(negedge clk) begin
    if (rst_n) begin
      bus_req_ready = (cycle % 7 != 0) && (cycle % 7 != 1);
      standby[0] = (cycle % 17 < 5);
      standby[1] = (cycle % 19 < 6);
      standby[2] = (cycle % 13 < 4);
    end
  end
  always @(posedge clk) begin : p_bus_and_checks
    integer offset, elem, r, c, addr, selected;
    logic [31:0] expected;
    cycle = cycle + 1;
    if (rst_n) begin
      bus_rsp_valid <= 0;
      if (bus_pending) begin
        if (bus_delay == 0) begin
          bus_rsp_rdata <= ext_mem[pending_bus_addr];
          bus_rsp_valid <= 1;
          bus_pending = 0;
        end else bus_delay = bus_delay - 1;
      end
      if (bus_req_valid && !bus_req_ready) bus_waits++;
      if (bus_req_valid && bus_req_ready) begin
        if (bus_req_write) begin
          offset = bus_req_addr - Y_BASE;
          elem = offset / 2;
          r = elem / matrix_n;
          c = elem % matrix_n;
          if (offset < 0 || r < row_base || r >= row_base+rows_valid ||
              c < col_base || c >= col_base+cols_valid)
            $fatal(1, "Write outside valid output tile addr=%0d", bus_req_addr);
          addr = 2*((r-row_base)*16+(c-col_base)) + (offset & 1);
          if (seen_write[addr]) $fatal(1, "Duplicate output half-word");
          seen_write[addr] = 1;
          expected = expected_output(r,c);
          if (bus_req_wdata !== ((offset & 1) ? expected[31:16] : expected[15:0]))
            $fatal(1, "Writeback data mismatch job=%0d addr=%0d", job, bus_req_addr);
          ext_mem[bus_req_addr] = bus_req_wdata;
          write_count++;
          total_writes++;
          $fdisplay(result_fd, "%0d,%0d,write,%0d,%0d,%0d,%04h", cycle,job,r,c,bus_req_addr,bus_req_wdata);
        end else begin
          if (bus_pending) $fatal(1, "Multiple outstanding bus requests");
          if (!((bus_req_addr >= A_BASE && bus_req_addr < A_BASE+2*matrix_m*matrix_k) ||
                (bus_req_addr >= B_BASE && bus_req_addr < B_BASE+2*matrix_k*matrix_n) ||
                (bus_req_addr >= C_BASE && bus_req_addr < C_BASE+2*matrix_n)))
            $fatal(1, "Out of range bus read");
          bus_pending = 1;
          pending_bus_addr = bus_req_addr;
          bus_delay = cycle % 4;
          read_count++;
        end
      end
      if (result_valid) begin
        if (result_row >= rows_valid || result_col >= cols_valid)
          $fatal(1, "Result outside valid tile");
        if (seen_output[result_row][result_col]) $fatal(1, "Duplicate result");
        seen_output[result_row][result_col] = 1;
        expected = expected_output(row_base+result_row, col_base+result_col);
        if (result_data !== expected)
          $fatal(1, "Result mismatch job=%0d r=%0d c=%0d got=%h expected=%h",
                 job,result_row,result_col,result_data,expected);
        result_count++;
        total_results++;
        if (result_last) last_count++;
        if (result_data[15:0] != 0) nonzero_low_words++;
        $fdisplay(result_fd, "%0d,%0d,result,%0d,%0d,-1,%08h",cycle,job,result_row,result_col,result_data);
      end
      for (int bank = 0; bank < 3; bank++) begin
        // Macro pins now carry the request accepted on the previous rising
        // edge. The adapter presents them on the falling edge and the SRAM
        // samples them at this rising edge.
        // A prior stall must preserve valid/address and write data.
        if (held_write[bank] && (!dut.u_cache.wr_valid[bank] ||
            dut.u_cache.wr_addr[bank] !== held_write_addr[bank] ||
            dut.u_cache.wr_data[bank] !== held_write_data[bank]))
          $fatal(1, "DMA write lost during stall");
        if (held_read[bank] && (!dut.u_cache.rd_valid[bank] ||
            dut.u_cache.rd_addr[bank] !== held_read_addr[bank]))
          $fatal(1, "Streamer read skipped during stall");
        held_write[bank] = dut.u_cache.wr_valid[bank] && !dut.u_cache.wr_ready[bank];
        held_read[bank] = dut.u_cache.rd_valid[bank] && !dut.u_cache.rd_ready[bank];
        held_write_addr[bank] = dut.u_cache.wr_addr[bank];
        held_write_data[bank] = dut.u_cache.wr_data[bank];
        held_read_addr[bank] = dut.u_cache.rd_addr[bank];
        if (held_write[bank]) dma_waits++;
        if (held_read[bank]) stream_waits++;
        if (dut.u_cache.rsp_valid[bank] !== pending_read[bank])
          $fatal(1, "Macro response count/timing mismatch bank=%0d", bank);
        if (pending_read[bank]) begin
          if (expected_known[bank] && dut.u_cache.rsp_data[bank] !== expected_read[bank])
            $fatal(1, "SRAM read mismatch bank=%0d addr=%0d", bank, requested_addr[bank]);
          macro_responses++;
          $fdisplay(access_fd,"%0d,%0d,%0d,response,%0d,%04h,%0d",
                    cycle,job,bank,requested_addr[bank],dut.u_cache.rsp_data[bank],expected_known[bank]);
        end
        pending_read[bank] = 0;
        selected = 0;
        for (int slot = 0; slot < 8; slot++) begin
          if (!macro_cen[bank*8+slot]) begin
            selected++;
            addr = slot*128 + macro_a[bank*8+slot];
            if (standby[bank] && !accepted_cache_req[bank])
              $fatal(1, "SRAM issued a new access during standby");
            if (!macro_gwen[bank*8+slot]) begin
              if (!accepted_cache_req[bank] || !accepted_cache_write[bank] ||
                  addr != accepted_cache_addr[bank] ||
                  macro_d[bank*8+slot] !== accepted_cache_data[bank])
                $fatal(1, "Macro write does not match prior accepted DMA request");
              shadow[bank][addr] = macro_d[bank*8+slot];
              shadow_valid[bank][addr] = 1;
              macro_writes++;
              $fdisplay(access_fd,"%0d,%0d,%0d,write,%0d,%04h,1",cycle,job,bank,addr,macro_d[bank*8+slot]);
            end else begin
              if (!accepted_cache_req[bank] || accepted_cache_write[bank] ||
                  addr != accepted_cache_addr[bank])
                $fatal(1, "Macro read does not match prior accepted streamer request");
              pending_read[bank] = 1;
              requested_addr[bank] = addr;
              expected_read[bank] = shadow[bank][addr];
              expected_known[bank] = shadow_valid[bank][addr];
              macro_reads++;
              $fdisplay(access_fd,"%0d,%0d,%0d,read,%0d,0000,%0d",cycle,job,bank,addr,shadow_valid[bank][addr]);
            end
          end
        end
        if (selected > 1) $fatal(1, "More than one 16-bit access per bank per clock");
        if (selected != accepted_cache_req[bank])
          $fatal(1, "Prior accepted cache request missing at macro pins");
        accepted_cache_req[bank] =
          (dut.u_cache.wr_valid[bank] && dut.u_cache.wr_ready[bank]) ||
          (dut.u_cache.rd_valid[bank] && dut.u_cache.rd_ready[bank]);
        if (dut.u_cache.wr_valid[bank] && dut.u_cache.wr_ready[bank]) begin
          accepted_cache_write[bank] = 1;
          accepted_cache_addr[bank] = dut.u_cache.wr_addr[bank];
          accepted_cache_data[bank] = dut.u_cache.wr_data[bank];
        end else if (dut.u_cache.rd_valid[bank] && dut.u_cache.rd_ready[bank]) begin
          accepted_cache_write[bank] = 0;
          accepted_cache_addr[bank] = dut.u_cache.rd_addr[bank];
          accepted_cache_data[bank] = 0;
        end
      end
    end
  end

  task automatic run_job(input integer id, input integer m, input integer k,
                         input integer n, input integer rb, input integer cb,
                         input integer rv, input integer cv);
    begin
      @(negedge clk);
      job = id; matrix_m = m; matrix_k = k; matrix_n = n;
      row_base = rb; col_base = cb; rows_valid = rv; cols_valid = cv;
      result_count = 0; write_count = 0; read_count = 0; last_count = 0;
      for (int r = 0; r < 8; r++)
        for (int c = 0; c < 16; c++) seen_output[r][c] = 0;
      for (int a = 0; a < 256; a++) seen_write[a] = 0;
      for (int r = 0; r < m; r++)
        for (int q = 0; q < k; q++) put_fp32(A_BASE+2*(r*k+q), encode_exact(x_units(r,q),7));
      for (int q = 0; q < k; q++)
        for (int c = 0; c < n; c++) put_fp32(B_BASE+2*(q*n+c), encode_exact(w_integer(q,c),0));
      for (int c = 0; c < n; c++) put_fp32(C_BASE+2*c, encode_exact(bias_units(c),7));
      start = 1;
      @(negedge clk); start = 0;
      wait(done);
      @(negedge clk);
      if (error || busy || result_count != rv*cv || write_count != 2*rv*cv ||
          last_count != 1 || read_count != 2*(rv*k+k*cv+2*cv))
        $fatal(1,"Job incomplete id=%0d results=%0d writes=%0d reads=%0d",id,result_count,write_count,read_count);
      $display("JOB PASS id=%0d rows=%0d cols=%0d K=%0d results=%0d write_halfwords=%0d bus_reads=%0d",
               id,rv,cv,k,result_count,write_count,read_count);
      repeat (4) @(negedge clk);
    end
  endtask

  initial begin
    if (!$value$plusargs("trace_dir=%s", trace_dir)) trace_dir = ".";
    access_fd = $fopen({trace_dir,"/macro_access.csv"},"w");
    result_fd = $fopen({trace_dir,"/results_writeback.csv"},"w");
    input_fd = $fopen({trace_dir,"/bus_inputs.csv"},"w");
    if (!access_fd || !result_fd || !input_fd) $fatal(1,"Cannot open evidence CSV");
    $fdisplay(access_fd,"cycle,job,bank,event,word_addr,data_hex,initialized");
    $fdisplay(result_fd,"cycle,job,event,row,col,bus_word_addr,data_hex");
    $fdisplay(input_fd,"job,bus_word_addr,data_hex");
    for (int b = 0; b < 3; b++) begin
      pending_read[b] = 0; held_write[b] = 0; held_read[b] = 0;
      for (int a = 0; a < 1024; a++) shadow_valid[b][a] = 0;
    end
    repeat (3) @(negedge clk);
    rst_n = 1;
    run_job(0,8,64,16,0,0,8,16);
    // No reset, smaller matrix/tile and partial final K block; stale SRAM is retained.
    run_job(1,6,35,9,3,4,3,5);
    if (macro_writes != 3716 || macro_reads != 6272 || macro_responses != macro_reads ||
        total_results != 143 || total_writes != 286 || dma_waits == 0 ||
        stream_waits == 0 || bus_waits == 0 || nonzero_low_words == 0)
      $fatal(1,"Missing access/stall coverage");
    $display("PASS sram_compute_integration jobs=2 results=%0d write_halfwords=%0d macro_writes=%0d macro_reads=%0d macro_responses=%0d dma_waits=%0d stream_waits=%0d bus_waits=%0d nonzero_output_lowwords=%0d",
             total_results,total_writes,macro_writes,macro_reads,macro_responses,dma_waits,stream_waits,bus_waits,nonzero_low_words);
    $fclose(access_fd); $fclose(result_fd); $fclose(input_fd);
    $finish;
  end
  initial begin
    #3000000;
    $fatal(1,"SRAM compute integration timeout cycle=%0d state=%0d",cycle,dut.state);
  end
endmodule
