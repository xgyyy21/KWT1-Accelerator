`timescale 1ns/1ps

// Minimal E203-facing INT16 integration test.
//
// This is a behavioral ext2dtcm model, not a real E203 or SRAM macro model.
// It checks the adapter's byte-address translation, response holding, the
// non-strict M=1/K=64/N=16 path, and the 0x8000 address-bit alias case.
module int16_e203_minimal_tb;
  localparam logic [31:0] CTRL_BASE = 32'h1100_0000;
  localparam logic [31:0] DTCM_BASE = 32'h9000_0000;
  localparam logic [31:0] A_BASE_0 = 32'h9000_0000;
  localparam logic [31:0] A_BASE_1 = 32'h9000_8000;
  localparam logic [31:0] B_BASE = 32'h9000_0100;
  localparam logic [31:0] BIAS_BASE = 32'h9000_0900;
  localparam logic [31:0] DST_BASE = 32'h9000_0980;
  localparam int MEM_HALFWORDS = 131072; // 256 KiB / 2 bytes

  logic clk = 1'b0;
  always #5 clk = ~clk;
  logic rst_n = 1'b0;

  logic sys_cmd_valid = 1'b0;
  logic sys_cmd_read = 1'b0;
  logic [31:0] sys_cmd_addr = '0;
  logic [31:0] sys_cmd_wdata = '0;
  logic [3:0] sys_cmd_wmask = 4'hf;
  logic sys_rsp_ready = 1'b1;
  wire sys_cmd_ready, sys_rsp_valid, sys_rsp_err;
  wire [31:0] sys_rsp_rdata;

  wire ext_cmd_valid, ext_cmd_read;
  wire [17:0] ext_cmd_addr;
  wire [31:0] ext_cmd_wdata;
  wire [3:0] ext_cmd_wmask;
  logic ext_cmd_ready;
  logic ext_rsp_valid = 1'b0;
  logic ext_rsp_err = 1'b0;
  logic [31:0] ext_rsp_rdata = '0;
  wire ext_rsp_ready;
  wire busy, done, error;

  logic [15:0] memory [0:MEM_HALFWORDS-1];
  logic ext_response_pending;
  logic [31:0] ext_pending_rdata;
  logic ext_pending_err;
  integer cycle_count;
  integer command_count;
  integer response_count;
  integer output_write_count;
  integer error_response_count;
  integer trace_fd;
  integer status_fd;
  string vec_dir;
  string trace_file;
  string status_file;

  logic [15:0] x_words [0:63];
  logic [15:0] w_words [0:1023];
  logic [15:0] bias_words [0:31];
  logic [15:0] y_expected [0:15];

  int16_e203_system_bus_adapter #(
    .CTRL_BASE(CTRL_BASE), .DTCM_BASE(DTCM_BASE),
    .STRICT_COMPETITION_SHAPES(1'b0)
  ) dut (
    .clk(clk), .rst_n(rst_n),
    .sysper_icb_cmd_valid(sys_cmd_valid),
    .sysper_icb_cmd_ready(sys_cmd_ready),
    .sysper_icb_cmd_addr(sys_cmd_addr),
    .sysper_icb_cmd_read(sys_cmd_read),
    .sysper_icb_cmd_wdata(sys_cmd_wdata),
    .sysper_icb_cmd_wmask(sys_cmd_wmask),
    .sysper_icb_rsp_valid(sys_rsp_valid),
    .sysper_icb_rsp_ready(sys_rsp_ready),
    .sysper_icb_rsp_rdata(sys_rsp_rdata),
    .sysper_icb_rsp_err(sys_rsp_err),
    .ext2dtcm_icb_cmd_valid(ext_cmd_valid),
    .ext2dtcm_icb_cmd_ready(ext_cmd_ready),
    .ext2dtcm_icb_cmd_addr(ext_cmd_addr),
    .ext2dtcm_icb_cmd_read(ext_cmd_read),
    .ext2dtcm_icb_cmd_wdata(ext_cmd_wdata),
    .ext2dtcm_icb_cmd_wmask(ext_cmd_wmask),
    .ext2dtcm_icb_rsp_valid(ext_rsp_valid),
    .ext2dtcm_icb_rsp_ready(ext_rsp_ready),
    .ext2dtcm_icb_rsp_rdata(ext_rsp_rdata),
    .ext2dtcm_icb_rsp_err(ext_rsp_err),
    .accel_busy(busy), .accel_done(done), .accel_error(error)
  );

  // One outstanding request and a deterministic one-cycle response delay.
  // Every fifth cycle is blocked to exercise command backpressure. Every
  // response is held for two cycles to exercise response backpressure.
  always_comb begin
    ext_cmd_ready = rst_n && !ext_response_pending && !ext_rsp_valid &&
                    ((cycle_count % 5) != 0);
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      ext_response_pending <= 1'b0;
      ext_pending_rdata <= '0;
      ext_pending_err <= 1'b0;
      ext_rsp_valid <= 1'b0;
      ext_rsp_rdata <= '0;
      ext_rsp_err <= 1'b0;
      cycle_count <= 0;
      command_count <= 0;
      response_count <= 0;
      output_write_count <= 0;
      error_response_count <= 0;
    end else begin
      cycle_count <= cycle_count + 1;
      if (ext_rsp_valid && ext_rsp_ready) begin
        ext_rsp_valid <= 1'b0;
        ext_response_pending <= 1'b0;
        response_count <= response_count + 1;
        if (ext_rsp_err) error_response_count <= error_response_count + 1;
      end
      if (ext_cmd_valid && ext_cmd_ready) begin
        command_count <= command_count + 1;
        if (!ext_cmd_read && ext_cmd_addr >= (DST_BASE-DTCM_BASE) &&
            ext_cmd_addr < (DST_BASE-DTCM_BASE+32))
          output_write_count <= output_write_count + 1;
        if (ext_cmd_read) begin
          ext_pending_rdata <= {memory[(ext_cmd_addr >> 1) + 1],
                                memory[ext_cmd_addr >> 1]};
          ext_pending_err <= 1'b0;
        end else begin
          if (ext_cmd_wmask[1:0] == 2'b11)
            memory[ext_cmd_addr >> 1] <= ext_cmd_wdata[15:0];
          if (ext_cmd_wmask[3:2] == 2'b11)
            memory[(ext_cmd_addr >> 1) + 1] <= ext_cmd_wdata[31:16];
          ext_pending_rdata <= '0;
          ext_pending_err <= 1'b0;
        end
        ext_response_pending <= 1'b1;
      end
      if (ext_response_pending && !ext_rsp_valid) begin
        ext_rsp_valid <= 1'b1;
        ext_rsp_rdata <= ext_pending_rdata;
        ext_rsp_err <= ext_pending_err;
      end
    end
  end

  always_ff @(posedge clk) begin
    if (rst_n && trace_fd != 0) begin
      if (ext_cmd_valid && ext_cmd_ready)
        $fdisplay(trace_fd, "%0d,ext_cmd,%0d,%h,%h,%h,%b",
          cycle_count, ext_cmd_read, ext_cmd_addr, ext_cmd_wdata,
          ext_cmd_wmask, 1'b0);
      if (ext_rsp_valid)
        $fdisplay(trace_fd, "%0d,ext_rsp,%0d,%h,%h,%b,%b",
          cycle_count, 0, 0, ext_rsp_rdata, 4'h0, ext_rsp_err);
      if (sys_cmd_valid && sys_cmd_ready)
        $fdisplay(trace_fd, "%0d,sys_cmd,%0d,%h,%h,%h,%b",
          cycle_count, sys_cmd_read, sys_cmd_addr, sys_cmd_wdata,
          sys_cmd_wmask, 1'b0);
      if (sys_rsp_valid)
        $fdisplay(trace_fd, "%0d,sys_rsp,%0d,%h,%h,%b,%b",
          cycle_count, 0, 0, sys_rsp_rdata, 4'h0, sys_rsp_err);
    end
    if (rst_n && status_fd != 0)
      $fdisplay(status_fd, "%0d,%b,%b,%b", cycle_count, busy, done, error);
  end

  task automatic mmio_write(input logic [7:0] offset,
                            input logic [31:0] value);
    begin
      @(negedge clk);
      sys_cmd_valid = 1'b1;
      sys_cmd_read = 1'b0;
      sys_cmd_addr = CTRL_BASE + offset;
      sys_cmd_wdata = value;
      sys_cmd_wmask = 4'hf;
      do @(posedge clk); while (!sys_cmd_ready);
      @(negedge clk);
      sys_cmd_valid = 1'b0;
      sys_cmd_addr = '0;
      sys_cmd_wdata = '0;
      while (!sys_rsp_valid) @(posedge clk);
      if (sys_rsp_err) $fatal(1, "MMIO write error offset=%h", offset);
    end
  endtask

  task automatic load_words(input logic [31:0] a_base, input integer a_value);
    begin
      for (integer i = 0; i < 64; i = i + 1)
        memory[((a_base-DTCM_BASE) >> 1) + i] = a_value[15:0];
      for (integer i = 0; i < 1024; i = i + 1)
        memory[((B_BASE-DTCM_BASE) >> 1) + i] = w_words[i];
      for (integer i = 0; i < 32; i = i + 1)
        memory[((BIAS_BASE-DTCM_BASE) >> 1) + i] = bias_words[i];
      for (integer i = 0; i < 16; i = i + 1)
        memory[((DST_BASE-DTCM_BASE) >> 1) + i] = 16'h55aa;
    end
  endtask

  task automatic configure_and_start(input logic [31:0] a_base);
    begin
      mmio_write(8'h08, a_base);
      mmio_write(8'h0c, B_BASE);
      mmio_write(8'h20, BIAS_BASE);
      mmio_write(8'h10, DST_BASE);
      mmio_write(8'h14, 1);
      mmio_write(8'h18, 64);
      mmio_write(8'h1c, 16);
      mmio_write(8'h24, 0);
      mmio_write(8'h00, 1);
      while (!done && !error) @(posedge clk);
      if (error) $fatal(1, "minimal task entered ERROR, A=%h", a_base);
      repeat (3) @(posedge clk);
    end
  endtask

  initial begin
    if (!$value$plusargs("vec_dir=%s", vec_dir))
      vec_dir = "handoff/int16_e203_minimal_2026-11-03";
    if (!$value$plusargs("trace=%s", trace_file))
      trace_file = "int16_e203_minimal_trace.csv";
    if (!$value$plusargs("status=%s", status_file))
      status_file = "int16_e203_minimal_status.csv";
    $readmemh({vec_dir, "/x.mem"}, x_words);
    $readmemh({vec_dir, "/w.mem"}, w_words);
    $readmemh({vec_dir, "/bias.mem"}, bias_words);
    $readmemh({vec_dir, "/y_expected.mem"}, y_expected);
    for (integer i = 0; i < MEM_HALFWORDS; i = i + 1) memory[i] = '0;
    for (integer i = 0; i < 64; i = i + 1)
      memory[((A_BASE_0-DTCM_BASE) >> 1) + i] = x_words[i];
    for (integer i = 0; i < 1024; i = i + 1)
      memory[((B_BASE-DTCM_BASE) >> 1) + i] = w_words[i];
    for (integer i = 0; i < 32; i = i + 1)
      memory[((BIAS_BASE-DTCM_BASE) >> 1) + i] = bias_words[i];

    trace_fd = $fopen(trace_file, "w");
    status_fd = $fopen(status_file, "w");
    $fdisplay(trace_fd, "cycle,kind,read,addr_or_zero,data,mask,error");
    $fdisplay(status_fd, "cycle,busy,done,error");
    repeat (4) @(negedge clk);
    rst_n = 1'b1;

    // Software vector: all ones, so every output is 64 (0040).
    configure_and_start(A_BASE_0);
    for (integer i = 0; i < 16; i = i + 1)
      if (memory[((DST_BASE-DTCM_BASE) >> 1) + i] !== y_expected[i])
        $fatal(1, "first task mismatch index=%0d got=%h expected=%h", i,
          memory[((DST_BASE-DTCM_BASE) >> 1) + i], y_expected[i]);

    // Address mirror test: same task at +0x8000 with all twos, expected 128.
    load_words(A_BASE_1, 2);
    configure_and_start(A_BASE_1);
    for (integer i = 0; i < 16; i = i + 1)
      if (memory[((DST_BASE-DTCM_BASE) >> 1) + i] !== 16'd128)
        $fatal(1, "address mirror detected index=%0d got=%h expected=0080", i,
          memory[((DST_BASE-DTCM_BASE) >> 1) + i]);

    // Out-of-window address must be completed with an error, not truncated.
    mmio_write(8'h08, 32'h9004_0000);
    mmio_write(8'h00, 1);
    while (!done && !error) @(posedge clk);
    if (!error) $fatal(1, "out-of-window address was not rejected");

    if (output_write_count != 16)
      $fatal(1, "unexpected output write count=%0d", output_write_count);
    $display("PASS int16_e203_minimal_tb first=16x0040 mirror_test=16x0080 out_of_window=ERROR commands=%0d responses=%0d", command_count, response_count);
    $fclose(trace_fd);
    $fclose(status_fd);
    $finish;
  end

  initial begin
    #2000000;
    $fatal(1, "timeout busy=%b done=%b error=%b commands=%0d responses=%0d", busy, done, error, command_count, response_count);
  end
endmodule
