`timescale 1ns/1ps
// Internal prototype only: real accelerator RTL and macro pins, project SRAM
// functional models, no E203 or vendor timing model. Exact integer reference
// in units of 1/128; all intermediate values stay below 2**24.
module fp32_sram_accelerator_top_tb #(
  parameter bit FULL_LAYER = 0,
  parameter bit SECOND_LAYER = 0,
  parameter bit TWO_LAYERS = 0
);
  localparam int MEM_WORDS=300000, A_BASE=0, B_BASE=100000,
                 C_BASE=200000, Y_BASE=210000, MAX_RESULTS=25344;
  logic clk=0, rst_n=0;
  always #5 clk=~clk;
  logic nice_valid=0, nice_write=0;
  logic [31:0] nice_addr=0, nice_wdata=0;
  wire nice_ready, nice_rsp_valid;
  wire [31:0] nice_rsp_rdata;
  wire sys_valid, sys_write;
  wire [31:0] sys_addr;
  wire [15:0] sys_wdata;
  logic sys_ready=0, sys_rsp_valid=0;
  logic [15:0] sys_rsp_rdata=0;
  wire tile_start, tile_busy, accel_done, accel_error;
  wire [31:0] tile_index;
  wire [15:0] row_base,col_base,k_base,rows_valid,cols_valid,k_valid;
  wire task_first,task_last;
  wire [15:0] k_block_index,k_block_count;
  logic [2:0] standby=0;
  wire [23:0] macro_cen,macro_gwen,macro_ret1n;
  wire [23:0][15:0] macro_wen,macro_d,macro_q;
  wire [23:0][6:0] macro_a;
  wire [23:0][2:0] macro_ema;
  wire [23:0][1:0] macro_emaw;
  logic [15:0] mem[0:MEM_WORDS-1];
  logic [31:0] expected[0:MAX_RESULTS-1];
  bit seen[0:2*MAX_RESULTS-1];
  integer job=-1, m_dim,k_dim,n_dim,cycle=0,tiles=0,writes=0,reads=0;
  integer total_outputs=0,total_writes=0,total_tiles=0,last_write=-1;
  integer expected_reads=0,expected_macro_reads=0;
  integer macro_reads=0,macro_writes=0,bus_waits=0,standby_cycles=0,low_nonzero=0;
  integer macro_read_start,macro_write_start;
  bit bus_pending=0,held_bus=0;
  logic held_bus_write;
  logic [31:0] pending_addr,held_bus_addr;
  logic [15:0] held_bus_data;
  integer delay_left=0;
  integer input_fd,output_fd,write_fd,tile_fd,control_fd;
  string output_dir;

  fp32_accelerator_top #(.STRICT_COMPETITION_SHAPES(FULL_LAYER || SECOND_LAYER || TWO_LAYERS),.USE_SRAM_MACROS(1)) dut (
    .clk(clk),.rst_n(rst_n),.cache_standby(standby),
    .macro_cen(macro_cen),.macro_gwen(macro_gwen),.macro_wen(macro_wen),
    .macro_a(macro_a),.macro_d(macro_d),.macro_q(macro_q),
    .macro_ema(macro_ema),.macro_emaw(macro_emaw),.macro_ret1n(macro_ret1n),
    .nice_req_valid(nice_valid),.nice_req_write(nice_write),.nice_req_addr(nice_addr),
    .nice_req_wdata(nice_wdata),.nice_req_ready(nice_ready),
    .nice_rsp_valid(nice_rsp_valid),.nice_rsp_rdata(nice_rsp_rdata),
    .sys_req_valid(sys_valid),.sys_req_write(sys_write),.sys_req_addr(sys_addr),
    .sys_req_wdata(sys_wdata),.sys_req_ready(sys_ready),.sys_rsp_valid(sys_rsp_valid),
    .sys_rsp_rdata(sys_rsp_rdata),.tile_start(tile_start),.tile_busy(tile_busy),
    .accel_done(accel_done),.accel_error(accel_error),.tile_index(tile_index),
    .row_base(row_base),.col_base(col_base),.k_base(k_base),.rows_valid(rows_valid),
    .cols_valid(cols_valid),.k_valid(k_valid),.task_first(task_first),.task_last(task_last),
    .k_block_index(k_block_index),.k_block_count(k_block_count)
  );
  for(genvar s=0;s<24;s++) begin:g_sram
    ramsp128x16_functional_model u_mem(
      .CLK(clk),.CEN(macro_cen[s]),.GWEN(macro_gwen[s]),.WEN(macro_wen[s]),
      .A(macro_a[s]),.D(macro_d[s]),.Q(macro_q[s]),
      .EMA(macro_ema[s]),.EMAW(macro_emaw[s]),.RET1N(macro_ret1n[s]));
  end
  function automatic logic [31:0] encode_exact(input integer value,input integer fraction_bits);
    integer magnitude,msb;
    logic [31:0] normalized;
    begin
      encode_exact=0;
      if(value!=0) begin
        magnitude=value<0 ? -value : value;
        if(magnitude>=16777216) $fatal(1,"Reference outside exact integer range");
        msb=0;
        for(int b=0;b<24;b++) if((magnitude>>b)!=0) msb=b;
        normalized=magnitude<<(23-msb);
        encode_exact[31]=(value<0);
        encode_exact[30:23]=127+msb-fraction_bits;
        encode_exact[22:0]=normalized[22:0];
      end
    end
  endfunction
  function automatic integer x_units(input integer r,input integer k);
    x_units=(((r*11+k*7+job*3)%19)-9)*1024+((r+k)%13)-6;
  endfunction
  function automatic integer w_integer(input integer k,input integer c);
    w_integer=((k*5+c*3+job)%7)-3;
  endfunction
  function automatic integer bias_units(input integer c);
    bias_units=c*3+job+1;
  endfunction
  task automatic put_fp32(input integer addr,input logic[31:0] value);
    mem[addr]=value[15:0]; mem[addr+1]=value[31:16];
    $fdisplay(input_fd,"%0d,%0d,%08h",job,addr,value);
  endtask
  task automatic nice_transfer(input bit wr,input integer addr,input logic[31:0] value,
                               output logic[31:0] result);
    @(negedge clk);
    nice_valid=1; nice_write=wr; nice_addr=addr; nice_wdata=value;
    @(posedge clk);
    while(!nice_ready) @(posedge clk);
    @(negedge clk);
    result=0;
    if(!wr) begin
      if(!nice_rsp_valid) $fatal(1,"Missing control read response");
      result=nice_rsp_rdata;
    end
    $fdisplay(control_fd,"%0d,%0d,%0d,%02h,%08h,%08h",cycle,job,wr,addr,value,result);
    nice_valid=0; nice_write=0;
  endtask
  task automatic write_reg(input integer addr,input logic[31:0] value);
    logic[31:0] unused_result;
    nice_transfer(1,addr,value,unused_result);
  endtask

  always @(negedge clk) if(rst_n) begin
    sys_ready=(cycle%7!=0)&&(cycle%7!=1);
    standby[0]=(cycle%17<5);
    standby[1]=(cycle%19<6);
    standby[2]=(cycle%13<4);
  end
  always @(posedge clk) begin:p_monitor
    integer offset,elem,selected,rb,cb,rv,cv;
    cycle=cycle+1;
    if(rst_n) begin
      sys_rsp_valid<=0;
      if(bus_pending) begin
        if(delay_left==0) begin
          sys_rsp_rdata<=mem[pending_addr]; sys_rsp_valid<=1; bus_pending=0;
        end else delay_left--;
      end
      if(held_bus && (!sys_valid || sys_write!==held_bus_write ||
          sys_addr!==held_bus_addr || sys_wdata!==held_bus_data))
        $fatal(1,"System request changed while stalled");
      held_bus=sys_valid&&!sys_ready;
      held_bus_write=sys_write; held_bus_addr=sys_addr; held_bus_data=sys_wdata;
      if(held_bus) bus_waits++;
      if(sys_valid&&sys_ready) begin
        if(sys_addr>=MEM_WORDS) $fatal(1,"Bus address outside memory");
        if(sys_write) begin
          offset=sys_addr-Y_BASE;
          if(offset<0 || offset>=2*m_dim*n_dim) $fatal(1,"Write outside output");
          elem=offset/2;
          if(seen[offset]) $fatal(1,"Duplicate write");
          if(sys_wdata!==(offset%2 ? expected[elem][31:16] : expected[elem][15:0]))
            $fatal(1,"Write mismatch job=%0d addr=%0d got=%h expected=%h",job,sys_addr,sys_wdata,expected[elem]);
          if(elem/n_dim<row_base || elem/n_dim>=row_base+rows_valid ||
             elem%n_dim<col_base || elem%n_dim>=col_base+cols_valid)
            $fatal(1,"Write outside current tile");
          seen[offset]=1; mem[sys_addr]=sys_wdata; writes++; last_write=cycle;
          $fdisplay(write_fd,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,%04h",cycle,job,tile_index,
                    elem/n_dim,elem%n_dim,sys_addr,offset%2,sys_wdata);
        end else begin
          if(bus_pending) $fatal(1,"Multiple outstanding reads");
          if(!((sys_addr>=A_BASE && sys_addr<A_BASE+2*m_dim*k_dim)||
               (sys_addr>=B_BASE && sys_addr<B_BASE+2*k_dim*n_dim)||
               (sys_addr>=C_BASE && sys_addr<C_BASE+2*n_dim)))
            $fatal(1,"Read outside input");
          bus_pending=1; pending_addr=sys_addr; delay_left=cycle%4; reads++;
        end
      end
      if(tile_start) begin
        rb=(tiles/((n_dim+15)/16))*8; cb=(tiles%((n_dim+15)/16))*16;
        rv=(m_dim-rb<8)?m_dim-rb:8; cv=(n_dim-cb<16)?n_dim-cb:16;
        if(tile_index!==tiles || row_base!==rb || col_base!==cb || rows_valid!==rv ||
           cols_valid!==cv || k_base!==0 || k_valid!==((k_dim<32)?k_dim:32) ||
           k_block_count!==((k_dim+31)/32)) $fatal(1,"Wrong tile descriptor");
        expected_reads+=2*(rv*k_dim+k_dim*cv+cv*((k_dim+31)/32));
        expected_macro_reads+=1568*((k_dim+31)/32);
        $fdisplay(tile_fd,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d",cycle,job,tiles,rb,cb,rv,cv,k_block_count);
        tiles++;
        if((FULL_LAYER || SECOND_LAYER || TWO_LAYERS) && (tiles%16==0 || tiles==1)) begin
          $display("PROGRESS SRAM %s tile=%0d/%0d cycle=%0d writes=%0d",
                   SECOND_LAYER ? "FFN2" : "FFN1",
                   tiles,((m_dim+7)/8)*((n_dim+15)/16),cycle,writes);
          $fflush();
        end
      end
      for(int bank=0;bank<3;bank++) begin
        selected=0;
        if(standby[bank]) standby_cycles++;
        for(int s=0;s<8;s++) if(!macro_cen[8*bank+s]) begin
          selected++;
          if(standby[bank]) $fatal(1,"Macro active in standby");
          if(!macro_gwen[8*bank+s]) macro_writes++; else macro_reads++;
        end
        if(selected>1) $fatal(1,"More than one 16-bit operation per bank per cycle");
      end
      if(accel_error) $fatal(1,"Unexpected accelerator error job=%0d tile=%0d",job,tile_index);
    end
  end

  task automatic run_job(input integer id,input integer m,input integer k,input integer n);
    integer sum,guard;
    logic[31:0] status_value,actual;
    bit busy_observed;
    begin
      @(negedge clk);
      job=id; m_dim=m; k_dim=k; n_dim=n;
      tiles=0; writes=0; reads=0; expected_reads=0; expected_macro_reads=0;
      macro_read_start=macro_reads; macro_write_start=macro_writes;
      last_write=-1; busy_observed=0;
      for(int r=0;r<m;r++) for(int q=0;q<k;q++)
        put_fp32(A_BASE+2*(r*k+q),encode_exact(x_units(r,q),7));
      for(int q=0;q<k;q++) for(int c=0;c<n;c++)
        put_fp32(B_BASE+2*(q*n+c),encode_exact(w_integer(q,c),0));
      for(int c=0;c<n;c++) put_fp32(C_BASE+2*c,encode_exact(bias_units(c),7));
      for(int r=0;r<m;r++) for(int c=0;c<n;c++) begin
        sum=0;
        for(int q=0;q<k;q++) begin
          sum+=x_units(r,q)*w_integer(q,c);
          if(sum<=-16777216 || sum>=16777216) $fatal(1,"Inexact reference intermediate");
        end
        expected[r*n+c]=encode_exact(sum+bias_units(c),7);
        mem[Y_BASE+2*(r*n+c)]=16'hbeef; mem[Y_BASE+2*(r*n+c)+1]=16'hdead;
        seen[2*(r*n+c)]=0; seen[2*(r*n+c)+1]=0;
      end
      write_reg('h08,A_BASE); write_reg('h0c,B_BASE); write_reg('h20,C_BASE);
      write_reg('h10,Y_BASE); write_reg('h14,m); write_reg('h18,k); write_reg('h1c,n);
      nice_transfer(0,'h18,0,status_value);
      if(status_value!==k) $fatal(1,"Configuration readback mismatch");
      write_reg('h00,1);
      guard=0;
      // Poll the actual internal control interface, not just a hierarchical done.
      status_value=0;
      while(!status_value[1] && guard<6000000) begin
        repeat(31) @(negedge clk);
        nice_transfer(0,'h04,0,status_value);
        if(status_value[2]) $fatal(1,"Control ERROR reported");
        if(status_value[0]) busy_observed=1;
        guard+=33;
      end
      if(!status_value[1] || status_value[0] || !busy_observed || last_write<0 || cycle<=last_write)
        $fatal(1,"Invalid BUSY/DONE/write ordering status=%h",status_value);
      if(tiles!=((m+7)/8)*((n+15)/16) || writes!=2*m*n || reads!=expected_reads ||
         macro_writes-macro_write_start!=reads || macro_reads-macro_read_start!=expected_macro_reads || bus_pending)
        $fatal(1,"Job count mismatch job=%0d tiles=%0d writes=%0d reads=%0d expected_reads=%0d macroR=%0d expectedR=%0d",
               job,tiles,writes,reads,expected_reads,macro_reads-macro_read_start,expected_macro_reads);
      for(int r=0;r<m;r++) for(int c=0;c<n;c++) begin
        actual={mem[Y_BASE+2*(r*n+c)+1],mem[Y_BASE+2*(r*n+c)]};
        if(actual!==expected[r*n+c] || !seen[2*(r*n+c)] || !seen[2*(r*n+c)+1])
          $fatal(1,"Result not visible in modeled system memory after DONE");
        if(actual[15:0]!=0) low_nonzero++;
        $fdisplay(output_fd,"%0d,%0d,%0d,%0d,%08h,%08h,1",job,r,c,Y_BASE+2*(r*n+c),actual,expected[r*n+c]);
      end
      // A new START must clear the previous job's sticky DONE. No reset or
      // SRAM clear occurs between run_job calls; data is deliberately replaced.
      total_outputs+=m*n; total_writes+=writes; total_tiles+=tiles;
      $display("JOB PASS id=%0d M=%0d K=%0d N=%0d tiles=%0d outputs=%0d writes=%0d reads=%0d done_observed_cycle=%0d last_write=%0d",
               job,m,k,n,tiles,m*n,writes,reads,cycle,last_write);
      $fflush();
    end
  endtask
  initial begin
    if(!$value$plusargs("OUT_DIR=%s",output_dir)) output_dir=".";
    input_fd=$fopen({output_dir,"/inputs.csv"},"w");
    output_fd=$fopen({output_dir,"/outputs.csv"},"w");
    write_fd=$fopen({output_dir,"/writeback.csv"},"w");
    tile_fd=$fopen({output_dir,"/tiles.csv"},"w");
    control_fd=$fopen({output_dir,"/control.csv"},"w");
    if(!input_fd||!output_fd||!write_fd||!tile_fd||!control_fd) $fatal(1,"Cannot open evidence");
    $fdisplay(input_fd,"job,bus_word_addr,fp32_hex");
    $fdisplay(output_fd,"job,row,col,bus_word_addr,actual_hex,expected_hex,match");
    $fdisplay(write_fd,"cycle,job,tile_id,row,col,bus_word_addr,half,actual_hex");
    $fdisplay(tile_fd,"cycle,job,tile_id,row_base,col_base,rows_valid,cols_valid,k_blocks");
    $fdisplay(control_fd,"cycle,job,write,register_hex,wdata_hex,rdata_hex");
    repeat(3) @(negedge clk); rst_n=1;
    if(TWO_LAYERS) begin
      run_job(0,99,64,256);
      run_job(1,99,256,64);
    end else if(FULL_LAYER) run_job(0,99,64,256);
    else if(SECOND_LAYER) run_job(0,99,256,64);
    else begin
      run_job(0,9,64,17);
      run_job(1,9,35,17);
      run_job(2,2,256,2);
      run_job(3,1,1,1);
    end
    if(bus_waits==0 || standby_cycles==0 || low_nonzero==0) $fatal(1,"Missing stimulus coverage");
    if (TWO_LAYERS)
      $display("PASS sram_accelerator_top two_layers=1 jobs=%0d outputs=%0d writes=%0d tiles=%0d macro_reads=%0d macro_writes=%0d bus_waits=%0d standby_bank_cycles=%0d nonzero_lowwords=%0d",
               job+1,total_outputs,total_writes,total_tiles,macro_reads,macro_writes,bus_waits,standby_cycles,low_nonzero);
    else if (SECOND_LAYER)
      $display("PASS sram_accelerator_top second_layer=1 jobs=%0d outputs=%0d writes=%0d tiles=%0d macro_reads=%0d macro_writes=%0d bus_waits=%0d standby_bank_cycles=%0d nonzero_lowwords=%0d",
               job+1,total_outputs,total_writes,total_tiles,macro_reads,macro_writes,bus_waits,standby_cycles,low_nonzero);
    else
      $display("PASS sram_accelerator_top full_layer=%0d jobs=%0d outputs=%0d writes=%0d tiles=%0d macro_reads=%0d macro_writes=%0d bus_waits=%0d standby_bank_cycles=%0d nonzero_lowwords=%0d",
               FULL_LAYER,job+1,total_outputs,total_writes,total_tiles,macro_reads,macro_writes,bus_waits,standby_cycles,low_nonzero);
    $fclose(input_fd); $fclose(output_fd); $fclose(write_fd); $fclose(tile_fd); $fclose(control_fd);
    $finish;
  end
  initial begin
    #120000000;
    $fatal(1,"SRAM top timeout cycle=%0d tile=%0d",cycle,tile_index);
  end
endmodule
