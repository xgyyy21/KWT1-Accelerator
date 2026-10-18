`timescale 1ns/1ps
module word_readback_tb;
  logic clk=0; always #5 clk=~clk;
  logic rst_n=0;
  logic a_wr_en=0, b_wr_en=0, result_wr_en=0;
  logic [9:0] a_wr_addr=0,b_wr_addr=0,result_wr_addr=0;
  logic [15:0] a_wr_data=0,b_wr_data=0,result_wr_data=0;
  logic a_rd_en=0,b_rd_en=0,result_rd_en=0;
  logic [9:0] a_rd_addr=0,b_rd_addr=0,result_rd_addr=0;
  logic [15:0] a_rd_data,b_rd_data,result_rd_data;
  logic a_rd_valid,b_rd_valid,result_rd_valid;
  logic [15:0] source_words[0:255];
  integer cycle_count=0, fd, i;
  string output_path, rtl_revision, rtl_snapshot, data_dir, case_name, tensor_name, source_path, source_sha;
  string hand_x_sha, hand_w_sha, hand_bias_sha;
  string round_x_sha, round_w_sha, round_bias_sha;
  string tile_x_sha, tile_w_sha, tile_bias_sha;

  matrix_cache_manager dut(.*);

  always @(posedge clk) if (rst_n) cycle_count <= cycle_count+1;

  task automatic write_word(input integer bank, input integer address, input logic [15:0] value);
    begin
      @(negedge clk);
      a_wr_en=0; b_wr_en=0; result_wr_en=0;
      case(bank)
        0: begin a_wr_en=1; a_wr_addr=10'(address); a_wr_data=value; end
        1: begin b_wr_en=1; b_wr_addr=10'(address); b_wr_data=value; end
        default: begin result_wr_en=1; result_wr_addr=10'(address); result_wr_data=value; end
      endcase
      @(negedge clk);
      a_wr_en=0; b_wr_en=0; result_wr_en=0;
    end
  endtask

  task automatic read_word(input integer bank, input integer address,
                           output logic [15:0] value,
                           output integer request_cycle, output integer valid_cycle);
    begin
      @(negedge clk);
      a_rd_en=0; b_rd_en=0; result_rd_en=0;
      case(bank)
        0: begin a_rd_en=1; a_rd_addr=10'(address); end
        1: begin b_rd_en=1; b_rd_addr=10'(address); end
        default: begin result_rd_en=1; result_rd_addr=10'(address); end
      endcase
      request_cycle=cycle_count;
      @(negedge clk);
      a_rd_en=0; b_rd_en=0; result_rd_en=0;
      #1;
      valid_cycle=cycle_count;
      case(bank)
        0: begin if(!a_rd_valid) $fatal(1,"A read did not return valid"); value=a_rd_data; end
        1: begin if(!b_rd_valid) $fatal(1,"B read did not return valid"); value=b_rd_data; end
        default: begin if(!result_rd_valid) $fatal(1,"RESULT read did not return valid"); value=result_rd_data; end
      endcase
      if(valid_cycle!=request_cycle+1)
        $fatal(1,"cache read latency mismatch request=%0d valid=%0d",request_cycle,valid_cycle);
    end
  endtask

  task automatic run_tensor(input string test_case, input string name,
                            input string mem_file, input string input_file, input string sha,
                            input integer bank, input integer rows,
                            input integer cols, input integer elements);
    logic [15:0] low_word, high_word;
    logic [31:0] fp32_bits;
    integer element, row_index, col_index, k_index, address;
    integer low_req, low_valid, high_req, high_valid;
    string bank_name;
    begin
      case_name=test_case; tensor_name=name; source_path=input_file; source_sha=sha;
      if(elements<=0 || 2*elements>1024) $fatal(1,"tensor exceeds cache capacity");
      $readmemh(mem_file,source_words,0,2*elements-1);
      case(bank) 0: bank_name="A"; 1: bank_name="B"; default: bank_name="RESULT"; endcase
      for(element=0;element<elements;element=element+1) begin
        write_word(bank,2*element,source_words[2*element]);
        write_word(bank,2*element+1,source_words[2*element+1]);
      end
      for(element=0;element<elements;element=element+1) begin
        address=2*element;
        read_word(bank,address,low_word,low_req,low_valid);
        read_word(bank,address+1,high_word,high_req,high_valid);
        if(low_word!==source_words[address] || high_word!==source_words[address+1])
          $fatal(1,"readback mismatch case=%s tensor=%s element=%0d",test_case,name,element);
        fp32_bits={high_word,low_word};
        if(name=="X") begin row_index=element/cols; col_index=element%cols; k_index=element%cols; end
        else if(name=="W") begin row_index=element/cols; col_index=element%cols; k_index=element/cols; end
        else begin row_index=0; col_index=element; k_index=-1; end
        $fdisplay(fd,"%s,%s,%s,%s,%s,%s,%s,%s,%0d,%0d,%0d,%0d,%0d,%04h,%04h,0x%08h,%0d,%0d,%0d,%0d",
          test_case,name,source_path,sha,mem_file,rtl_revision,rtl_snapshot,bank_name,
          row_index,col_index,k_index,address,address+1,low_word,high_word,fp32_bits,
          low_req,low_valid,high_req,high_valid);
      end
    end
  endtask

  initial begin
    if(!$value$plusargs("output=%s",output_path)) $fatal(1,"missing +output");
    if(!$value$plusargs("rtl_revision=%s",rtl_revision)) rtl_revision="UNSPECIFIED";
    if(!$value$plusargs("rtl_snapshot=%s",rtl_snapshot)) rtl_snapshot="UNSPECIFIED";
    if(!$value$plusargs("data_dir=%s",data_dir)) $fatal(1,"missing +data_dir");
    if(!$value$plusargs("hand_x_sha=%s",hand_x_sha)) $fatal(1,"missing hand_x_sha");
    if(!$value$plusargs("hand_w_sha=%s",hand_w_sha)) $fatal(1,"missing hand_w_sha");
    if(!$value$plusargs("hand_bias_sha=%s",hand_bias_sha)) $fatal(1,"missing hand_bias_sha");
    if(!$value$plusargs("round_x_sha=%s",round_x_sha)) $fatal(1,"missing round_x_sha");
    if(!$value$plusargs("round_w_sha=%s",round_w_sha)) $fatal(1,"missing round_w_sha");
    if(!$value$plusargs("round_bias_sha=%s",round_bias_sha)) $fatal(1,"missing round_bias_sha");
    if(!$value$plusargs("tile_x_sha=%s",tile_x_sha)) $fatal(1,"missing tile_x_sha");
    if(!$value$plusargs("tile_w_sha=%s",tile_w_sha)) $fatal(1,"missing tile_w_sha");
    if(!$value$plusargs("tile_bias_sha=%s",tile_bias_sha)) $fatal(1,"missing tile_bias_sha");
    fd=$fopen(output_path,"w");
    if(fd==0) $fatal(1,"cannot open readback CSV");
    $fdisplay(fd,"case,tensor,input_bin,input_sha256,mem_hex_file,rtl_revision,rtl_snapshot_sha256,bank,row,column,k,low_word_address,high_word_address,word_low16,word_high16,reconstructed_fp32_bits,low_request_cycle,low_data_valid_cycle,high_request_cycle,high_data_valid_cycle");
    repeat(3) @(negedge clk); rst_n=1;

    run_tensor("hand_2x2","X",{data_dir,"/x.mem"},"x.bin",hand_x_sha,0,2,2,4);
    run_tensor("hand_2x2","W",{data_dir,"/w.mem"},"w.bin",hand_w_sha,1,2,2,4);
    run_tensor("hand_2x2","BIAS",{data_dir,"/bias.mem"},"bias.bin",hand_bias_sha,2,1,2,2);
    run_tensor("rounding_nonfused","X",{data_dir,"/rounding_x.mem"},"rounding_x.bin",round_x_sha,0,1,2,2);
    run_tensor("rounding_nonfused","W",{data_dir,"/rounding_w.mem"},"rounding_w.bin",round_w_sha,1,2,1,2);
    run_tensor("rounding_nonfused","BIAS",{data_dir,"/rounding_bias.mem"},"rounding_bias.bin",round_bias_sha,2,1,1,1);
    run_tensor("k32_boundary","X",{data_dir,"/tile_x.mem"},"tile_x.bin",tile_x_sha,0,1,64,64);
    run_tensor("k32_boundary","W",{data_dir,"/tile_w.mem"},"tile_w.bin",tile_w_sha,1,64,1,64);
    run_tensor("k32_boundary","BIAS",{data_dir,"/tile_bias.mem"},"tile_bias.bin",tile_bias_sha,2,1,1,1);
    $fclose(fd);
    $display("word_readback_tb PASS rows=%0d", 1+4+4+2+2+2+1+64+64+1);
    $finish;
  end
  initial begin #2000000; $fatal(1,"word_readback_tb timeout"); end
endmodule
