`timescale 1ns/1ps
module fp32_math_tb;
  import fp32_math_pkg::*;
  integer fd, rc, count;
  logic [31:0] a,b,add_expected,mul_expected,actual;
  initial begin
    fd=$fopen("build/fp32_vectors.txt","r");
    if(fd==0) $fatal(1,"generate FP32 vectors before simulation");
    count=0;
    while(!$feof(fd)) begin
      rc=$fscanf(fd,"%h %h %h %h\n",a,b,add_expected,mul_expected);
      if(rc!=4) $fatal(1,"malformed golden vector at %0d",count);
      actual=fp32_add(a,b);
      if(actual!==add_expected) $fatal(1,"add a=%h b=%h got=%h expected=%h",a,b,actual,add_expected);
      actual=fp32_mul(a,b);
      if(actual!==mul_expected) $fatal(1,"mul a=%h b=%h got=%h expected=%h",a,b,actual,mul_expected);
      count=count+1;
    end
    $fclose(fd);
    if(count<20000) $fatal(1,"insufficient FP32 vectors: %0d",count);
    $display("fp32_math_tb PASS pairs=%0d",count); $finish;
  end
endmodule
