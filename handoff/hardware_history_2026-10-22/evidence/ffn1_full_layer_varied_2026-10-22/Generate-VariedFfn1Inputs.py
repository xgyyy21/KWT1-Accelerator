"""Generate deterministic, finite, nonuniform FFN1 operands and exact FP32 reference."""
from __future__ import annotations
import argparse, hashlib, importlib.util, json
from pathlib import Path

M,K,N=99,64,256
ROOT=Path(__file__).resolve().parents[1]
REF=ROOT/'handoff/ffn1_full_layer_2026-10-21/software_reference/fp32_reference.py'
VALUES=(0.0,0.125,-0.25,0.5,-0.75,1.0,1.25,-1.5,2.0,-2.25,0.375,-0.625)

def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
def enc(value):
    import struct
    return struct.unpack('<I',struct.pack('<f',value))[0]

def main():
    p=argparse.ArgumentParser();p.add_argument('--output',required=True);a=p.parse_args()
    out=Path(a.output).resolve();out.mkdir(parents=True,exist_ok=False)
    spec=importlib.util.spec_from_file_location('fp32_reference',REF)
    ref=importlib.util.module_from_spec(spec);spec.loader.exec_module(ref)
    x=[[enc(VALUES[(r*7+k*5+(r//3))%len(VALUES)]) for k in range(K)] for r in range(M)]
    w=[[enc(VALUES[(k*11+c*3+(c//7))%len(VALUES)]) for c in range(N)] for k in range(K)]
    bias=[enc(VALUES[(c*5+c//9+2)%len(VALUES)]) for c in range(N)]
    y=ref.run_ffn1_bits(x,w,bias)
    tensors={'x':sum(x,[]),'w':sum(w,[]),'bias':bias}
    for name,values in tensors.items():
        (out/f'ffn1_{name}_fp32.mem').write_text(''.join(f'{v:08x}\n' for v in values),encoding='ascii')
    (out/'ffn1_expected_fp32.mem').write_text(''.join(f'{v:08x}\n' for row in y for v in row),encoding='ascii')
    import csv
    with (out/'software_expected_output.csv').open('w',newline='',encoding='ascii') as f:
        wr=csv.writer(f,lineterminator='\n');wr.writerow(['row','column','expected_bits'])
        for r,row in enumerate(y):
            for c,bits in enumerate(row): wr.writerow([r,c,f'0x{bits:08x}'])
    summary={'shape':{'m':M,'k':K,'n':N},'reference_path':str(REF),'reference_sha256':sha(REF),
      'generator_sha256':sha(Path(__file__)),'patterns':list(VALUES),'finite_values_only':True,
      'rounding_contract':'separately rounded FP32 multiply/add, increasing K, bias once after K=64',
      'input_counts':{'x':M*K,'w':K*N,'bias':N},'output_count':M*N,
      'distinct_fp32_patterns':{name:len(set(values)) for name,values in tensors.items()},
      'distinct_expected_outputs':len({v for row in y for v in row}),
      'files':{p.name:sha(p) for p in sorted(out.iterdir()) if p.is_file()}}
    (out/'generation_summary.json').write_text(json.dumps(summary,indent=2)+'\n',encoding='utf-8')
    print(json.dumps(summary,indent=2))
if __name__=='__main__':main()
