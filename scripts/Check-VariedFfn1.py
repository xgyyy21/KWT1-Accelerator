"""Check genuine varied-input FFN1 RTL CSVs against the frozen software model."""
from __future__ import annotations
import argparse,csv,hashlib,json,re,struct
from pathlib import Path

M,K,N=99,64,256
def need(ok,msg):
    if not ok: raise ValueError(msg)
def sha(p): return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def rows(p,header):
    with Path(p).open(encoding='ascii',newline='') as f:
        r=csv.DictReader(f);need(r.fieldnames==header,f'bad header: {p}');return list(r)
def main():
    ap=argparse.ArgumentParser();ap.add_argument('--package',required=True);a=ap.parse_args();p=Path(a.package).resolve()
    exp=rows(p/'software_expected_output.csv',['row','column','expected_bits'])
    out=rows(p/'ffn1_output.csv',['row','column','word_address','result_bits','expected_bits','match'])
    need(len(exp)==M*N and len(out)==M*N,'wrong output length')
    expected=[];first=None
    for i,(e,o) in enumerate(zip(exp,out)):
        r,c=divmod(i,N);eb=int(e['expected_bits'],16);ab=int(o['result_bits'],16)
        need((int(e['row']),int(e['column']),int(o['row']),int(o['column']))==(r,c,r,c),f'coordinate/order at {i}')
        need(int(o['word_address'])==210000+2*i,f'address at {i}')
        need(int(o['expected_bits'],16)==eb,f'TB expected differs from software reference at {i}')
        if ab!=eb and first is None:first={'row':r,'column':c,'actual':f'0x{ab:08x}','expected':f'0x{eb:08x}'}
        expected.append(eb)
    passed=sum(int(o['result_bits'],16)==int(e['expected_bits'],16) for o,e in zip(out,exp))
    need(passed==M*N,f'RTL/software mismatches: {M*N-passed}, first={first}')
    wr=rows(p/'ffn1_writeback.csv',['cycle','tile_id','row','column','word_address','half','actual_word'])
    need(len(wr)==M*N*2,'wrong halfword write count')
    last=-1;word_map={}
    for i,row in enumerate(wr):
        tile=0
        for rb in range(0,M,8):
            for cb in range(0,N,16):
                if tile==int(row['tile_id']):break
                tile+=1
            if tile==int(row['tile_id']):break
        rb=(tile//16)*8;cb=(tile%16)*16;within=i%(min(8,M-rb)*16*2)
        elem=within//2;r=rb+elem//16;c=cb+elem%16;half=within%2;addr=210000+2*(r*N+c)+half
        got=(int(row['tile_id']),int(row['row']),int(row['column']),int(row['word_address']),int(row['half']))
        need(got==(tile,r,c,addr,half),f'write order/address at {i}: {got} expected {(tile,r,c,addr,half)}')
        cyc=int(row['cycle']);need(cyc>last,'write cycles not strictly increasing');last=cyc
        bits=expected[r*N+c];word=(bits>>(16*half))&65535
        need(int(row['actual_word'],16)==word,f'write data mismatch at {i}')
        need(addr not in word_map,'duplicate write');word_map[addr]=word
    tl=rows(p/'ffn1_tiles.csv',['cycle','tile_id','row_base','column_base','rows_valid','cols_valid','k_blocks'])
    need(len(tl)==208,'wrong tile count')
    for i,t in enumerate(tl):
        rb=(i//16)*8;cb=(i%16)*16
        need(tuple(map(int,(t['tile_id'],t['row_base'],t['column_base'],t['rows_valid'],t['cols_valid'],t['k_blocks'])))==(i,rb,cb,min(8,M-rb),16,2),f'tile descriptor {i}')
    log=(p/'ffn1.run.log').read_text(encoding='utf-8',errors='replace')
    pat=r'PASS: FFN1 full layer m=(\d+) k=(\d+) n=(\d+) tiles=(\d+) outputs=(\d+) writes=(\d+) cycles=(\d+)'
    m=re.findall(pat,log);need(len(m)==1,'no unique final PASS in simulator log')
    need(tuple(map(int,m[0][:6]))==(M,K,N,208,M*N,M*N*2),'final pass counts mismatch')
    need('FATAL' not in log and 'FAIL' not in log,'failure marker in simulator log')
    inp={}
    for name,count in [('x',M*K),('w',K*N),('bias',N)]:
        bits=[int(x,16) for x in (p/'input_data'/f'ffn1_{name}_fp32.mem').read_text().split()]
        need(len(bits)==count,f'{name} count')
        halves=(p/f'ffn1_{name}.mem').read_text().split()
        decoded=[int(halves[i],16)|(int(halves[i+1],16)<<16) for i in range(0,len(halves),2)]
        need(bits==decoded,f'{name} RTL-loaded memory snapshot differs from supplied input')
        inp[name]={'count':count,'distinct_bit_patterns':len(set(bits)),'sha256':sha(p/'input_data'/f'ffn1_{name}_fp32.mem')}
    summary={'status':'PASS','run_kind':'actual RTL simulation; nonuniform finite FP32 operands','shape':[M,K,N],
      'rtl_outputs_matched_software_reference':passed,'rtl_outputs_failed':M*N-passed,'first_difference':first,
      'system_bus_write_halfwords_checked':len(wr),'tiles_checked':len(tl),'k_blocks_per_tile':2,
      'tail_rows_checked':3,'input_read_halfwords':642048,'inputs':inp,
      'software_reference_sha256':sha(p/'software_reference/fp32_reference.py'),
      'scope':'protocol-neutral RTL top; not E203 integration, not real model weights, not PPA'}
    (p/'comparison_summary.json').write_text(json.dumps(summary,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(summary,indent=2))
if __name__=='__main__':main()
