`timescale 1ns/1ps
module int16_pe_mac_tb;
  logic clk=0; always #5 clk=~clk;
  logic rst_n=0,start=0,valid=0,last=0;
  logic signed[15:0] a=0,b=0;
  logic signed[31:0] bias=0;
  logic[4:0] shift=0;
  wire result_valid,trace_valid,input_error;
  wire signed[15:0] result_out;
  wire signed[47:0] raw_sum,acc_before,acc_after;
  wire signed[31:0] product;
  int16_pe_mac dut(.clk(clk),.rst_n(rst_n),.start(start),.mac_valid(valid),
    .mac_last(last),.a_in(a),.b_in(b),.bias_in(bias),.out_shift(shift),
    .result_valid(result_valid),.result_out(result_out),.raw_sum_out(raw_sum),
    .input_error(input_error),
    .trace_valid(trace_valid),.trace_product(product),
    .trace_acc_before(acc_before),.trace_acc_after(acc_after));

  function automatic integer sat16(input longint signed value,input integer sh);
    longint signed mag,rounded,scaled,unit,remainder,half;
    begin
      mag=value<0 ? -value : value;
      if(sh==0) rounded=mag;
      else begin
        unit=64'sd1<<<sh; remainder=mag&(unit-1); half=unit>>>1;
        rounded=mag>>>sh;
        if((remainder>half)||((remainder==half)&&(rounded[0])))
          rounded=rounded+1;
      end
      scaled=value<0 ? -rounded : rounded;
      if(scaled>32767)sat16=32767;
      else if(scaled< -32767)sat16=-32767;
      else sat16=scaled;
    end
  endfunction

  task automatic run_constant(input integer count,input integer av,input integer bv,
      input integer biasv,input integer sh,input integer expected,input bit check_boundary);
    longint signed ref_sum,prod;
    begin
      ref_sum=0;prod=av*bv;
      for(integer k=0;k<count;k=k+1)begin
        @(negedge clk);start=(k==0);valid=1;last=(k==count-1);
        a=av;b=bv;bias=biasv;shift=sh;
        @(posedge clk);#1;
        if(input_error)$fatal(1,"unexpected input error k=%0d",k);
        if(!trace_valid||product!==prod||acc_before!==ref_sum||acc_after!==ref_sum+prod)
          $fatal(1,"trace mismatch k=%0d before=%0d after=%0d",k,acc_before,acc_after);
        if(check_boundary&&k==31&&acc_after!==32*prod)$fatal(1,"K_TILE boundary failed");
        if(check_boundary&&k==32&&acc_before!==32*prod)$fatal(1,"K_TILE continuation failed");
        ref_sum=ref_sum+prod;
        if(k==count-1)begin
          if(!result_valid||raw_sum!==ref_sum+biasv||result_out!==expected)
            $fatal(1,"result mismatch raw=%0d/%0d out=%0d/%0d",raw_sum,ref_sum+biasv,result_out,expected);
        end else if(result_valid)$fatal(1,"early result");
      end
      @(negedge clk);start=0;valid=0;last=0;a=0;b=0;bias=0;shift=0;
    end
  endtask

  initial begin
    repeat(3)@(negedge clk);rst_n=1;
    run_constant(64,123,-45,1000,4,sat16(64*123*(-45)+1000,4),1);
    run_constant(64,32767,32767,2147483647,0,32767,1);
    run_constant(64,-32767,32767,-2147483647,0,-32767,1);
    run_constant(1,3,1,0,1,2,0);
    run_constant(1,-3,1,0,1,-2,0);
    run_constant(1,1,1,0,1,0,0);
    run_constant(1,-1,1,0,1,0,0);
    run_constant(1,0,0,32767,0,32767,0);
    // 0x8000 is reserved and must be rejected without producing a result.
    @(negedge clk);start=1;valid=1;last=1;a=16'sh8000;b=1;bias=0;shift=0;
    @(posedge clk);#1;
    if(!input_error||result_valid||trace_valid)
      $fatal(1,"reserved 0x8000 input was not rejected");
    @(negedge clk);start=0;valid=0;last=0;a=0;b=0;
    $display("PASS int16_pe_mac_tb product=int32 accumulator=int48 bias=int32 output=int16 rounding=nearest_ties_even saturation=[-32767,32767] reserved_8000=error K=64 K_TILE=32");
    $finish;
  end
  initial begin #1000000;$fatal(1,"timeout");end
endmodule
