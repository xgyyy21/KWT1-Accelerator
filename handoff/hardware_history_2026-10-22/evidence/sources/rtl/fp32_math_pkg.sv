package fp32_math_pkg;
  function automatic logic [26:0] shift_right_jam27(input logic [26:0] value, input integer amount);
    logic sticky;
    integer i;
    begin
      sticky = 1'b0;
      if (amount <= 0) shift_right_jam27 = value;
      else if (amount >= 27) shift_right_jam27 = (value != 0) ? 27'd1 : 27'd0;
      else begin
        for (i=0; i<27; i=i+1) if (i<amount) sticky = sticky | value[i];
        shift_right_jam27 = value >> amount;
        shift_right_jam27[0] = shift_right_jam27[0] | sticky;
      end
    end
  endfunction

  function automatic logic [31:0] fp32_add(input logic [31:0] a, input logic [31:0] b);
    logic sa, sb, sr, stmp;
    logic [7:0] ea, eb;
    integer eae, ebe;
    logic [23:0] ma, mb;
    logic [26:0] xa, xb, xr;
    logic [27:0] sum;
    logic [24:0] rounded;
    integer expn, i;
    begin
      sa=a[31]; sb=b[31]; ea=a[30:23]; eb=b[30:23];
      if (ea==8'hff || eb==8'hff) begin
        if ((ea==8'hff && a[22:0]!=0) || (eb==8'hff && b[22:0]!=0) ||
            (ea==8'hff && eb==8'hff && sa!=sb)) fp32_add=32'h7fc00000;
        else if (ea==8'hff) fp32_add={sa,8'hff,23'b0};
        else fp32_add={sb,8'hff,23'b0};
      end else if (a[30:0]==0 && b[30:0]==0) fp32_add={sa&sb,31'b0};
      else if (a[30:0]==0) fp32_add=b;
      else if (b[30:0]==0) fp32_add=a;
      else begin
        ma={ (ea!=0), a[22:0] }; mb={ (eb!=0), b[22:0] };
        eae=(ea==0)?1:ea; ebe=(eb==0)?1:eb;
        if (eae<ebe || (eae==ebe && ma<mb)) begin
          expn=ebe; xa={mb,3'b000}; xb=shift_right_jam27({ma,3'b000},ebe-eae);
          stmp=sa; sa=sb; sb=stmp; sr=sa;
        end else begin
          expn=eae; xa={ma,3'b000}; xb=shift_right_jam27({mb,3'b000},eae-ebe); sr=sa;
        end
        if (sa==sb) begin
          sum={1'b0,xa}+{1'b0,xb};
          if (sum[27]) begin
            xr=sum[27:1]; xr[0]=xr[0] | sum[0]; expn=expn+1;
          end
          else xr=sum[26:0];
        end else begin
          xr=xa-xb;
          if (xr==0) begin fp32_add=32'b0; return fp32_add; end
          for(i=0;i<26;i=i+1)
            if (!xr[26] && expn>1) begin xr=xr<<1; expn=expn-1; end
        end
        rounded={1'b0,xr[26:3]};
        if (xr[2] && (xr[1] || xr[0] || xr[3])) rounded=rounded+1'b1;
        if (rounded[24]) begin rounded=rounded>>1; expn=expn+1; end
        if (expn>=255) fp32_add={sr,8'hff,23'b0};
        else if (expn<=1 && !rounded[23]) fp32_add={sr,8'b0,rounded[22:0]};
        else fp32_add={sr,expn[7:0],rounded[22:0]};
      end
    end
  endfunction

  function automatic logic [31:0] fp32_mul(input logic [31:0] a, input logic [31:0] b);
    logic signr;
    logic [7:0] ea, eb;
    logic [23:0] ma, mb;
    logic [47:0] product;
    logic [26:0] ext;
    logic [24:0] rounded;
    integer expn, i;
    begin
      signr=a[31]^b[31]; ea=a[30:23]; eb=b[30:23];
      if ((ea==8'hff && a[22:0]!=0) || (eb==8'hff && b[22:0]!=0)) fp32_mul=32'h7fc00000;
      else if ((ea==8'hff && b[30:0]==0) || (eb==8'hff && a[30:0]==0)) fp32_mul=32'h7fc00000;
      else if (ea==8'hff || eb==8'hff) fp32_mul={signr,8'hff,23'b0};
      else if (a[30:0]==0 || b[30:0]==0) fp32_mul={signr,31'b0};
      else begin
        ma={(ea!=0),a[22:0]}; mb={(eb!=0),b[22:0]};
        product=ma*mb;
        expn=(ea==0?1:ea)+(eb==0?1:eb)-127;
        if(product[47]) begin
          ext=product[47:21]; ext[0]=ext[0] | (|product[20:0]); expn=expn+1;
        end
        else begin
          for(i=0;i<46;i=i+1)
            if(!product[46] && product!=0) begin product=product<<1; expn=expn-1; end
          ext=product[46:20];
          ext[0]=ext[0] | (|product[19:0]);
        end
        if(expn<=0) begin ext=shift_right_jam27(ext,1-expn); expn=1; end
        rounded={1'b0,ext[26:3]};
        if(ext[2] && (ext[1] || ext[0] || ext[3])) rounded=rounded+1'b1;
        if(rounded[24]) begin rounded=rounded>>1; expn=expn+1; end
        if(expn>=255) fp32_mul={signr,8'hff,23'b0};
        else if(expn==1 && !rounded[23]) fp32_mul={signr,8'b0,rounded[22:0]};
        else fp32_mul={signr,expn[7:0],rounded[22:0]};
      end
    end
  endfunction
endpackage
