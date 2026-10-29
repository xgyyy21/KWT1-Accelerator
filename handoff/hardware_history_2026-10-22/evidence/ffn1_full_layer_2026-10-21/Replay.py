"""Archive/check a real FFN1 RTL run or replay fixed source snapshots.

The collector never generates actual output CSVs from software expectations.
An existing run must have been executed separately and finished successfully.
"""
from __future__ import annotations
import argparse
import copy
import csv
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import shutil
import struct
import subprocess
import sys
import tempfile
import time

ROOT=Path(__file__).resolve().parents[1]
M,K,N=99,64,256
EXPECTED=int.from_bytes(struct.pack('>f',float(K)+1.0),'big')
TB='fp32_competition_ffn1_tb'
OUTPUT_FIELDS='row,column,word_address,result_bits,expected_bits,match'.split(',')
WRITE_FIELDS='cycle,tile_id,row,column,word_address,half,actual_word'.split(',')
TILE_FIELDS='cycle,tile_id,row_base,column_base,rows_valid,cols_valid,k_blocks'.split(',')
ARTIFACTS=['ffn1_output.csv','ffn1_writeback.csv','ffn1_tiles.csv',
           'ffn1_x.mem','ffn1_w.mem','ffn1_bias.mem','ffn1.compile.log','ffn1.run.log']

def need(ok,message):
    if not ok: raise ValueError(message)

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def write_json(path,data):
    path.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')

def read_log(path):
    data=path.read_bytes()
    return data.decode('utf-16' if data[:2] in (b'\xff\xfe',b'\xfe\xff') else 'utf-8-sig',errors='replace')

def csv_rows(path,fields):
    with path.open(encoding='ascii',newline='') as stream:
        reader=csv.DictReader(stream)
        need(reader.fieldnames==fields,f'wrong CSV header: {path.name}')
        rows=list(reader)
    need(all(None not in row and None not in row.values() for row in rows),'malformed CSV')
    return rows

def check_outputs(rows):
    need(len(rows)==M*N,f'output count {len(rows)} != {M*N}')
    for i,row in enumerate(rows):
        r,c=divmod(i,N)
        need((int(row['row']),int(row['column']))==(r,c),f'output coordinate/order at {i}')
        need(int(row['word_address'])==210000+2*i,f'output address at {i}')
        need(int(row['result_bits'],16)==EXPECTED,f'actual RTL output differs at ({r},{c})')
        need(int(row['expected_bits'],16)==EXPECTED and row['match']=='1',f'expected/status differs at {i}')

def write_order():
    tile=0
    for rb in range(0,M,8):
        for cb in range(0,N,16):
            for r in range(rb,min(rb+8,M)):
                for c in range(cb,min(cb+16,N)):
                    for half in (0,1):
                        yield tile,r,c,210000+2*(r*N+c)+half,half
            tile+=1

def check_writes(rows,outputs):
    need(len(rows)==M*N*2,f'write count {len(rows)} != {M*N*2}')
    words={}; last_cycle=-1
    for i,(row,expected) in enumerate(zip(rows,write_order())):
        actual=tuple(int(row[f]) for f in ('tile_id','row','column','word_address','half'))
        need(actual==expected,f'write ordering/address differs at index {i}: {actual} != {expected}')
        cycle=int(row['cycle']);need(cycle>last_cycle,f'nonmonotonic write cycle {i}')
        last_cycle=cycle
        word=int(row['actual_word'],16)
        need(word==((EXPECTED>>(16*expected[-1]))&65535),f'actual write data differs at {i}')
        need(expected[3] not in words,f'duplicate write at {i}');words[expected[3]]=word
    for i,row in enumerate(outputs):
        addr=210000+2*i
        need(words[addr]|(words[addr+1]<<16)==int(row['result_bits'],16),f'write/final-memory differs at {i}')
    return last_cycle

def check_tiles(rows):
    need(len(rows)==208,f'tile count {len(rows)} != 208')
    previous=-1
    for i,row in enumerate(rows):
        rb=(i//16)*8;cb=(i%16)*16
        actual=tuple(int(row[f]) for f in ('tile_id','row_base','column_base','rows_valid','cols_valid','k_blocks'))
        need(actual==(i,rb,cb,min(8,M-rb),16,2),f'tile descriptor differs at {i}')
        need(int(row['cycle'])>previous,f'tile launch cycles differ at {i}')
        previous=int(row['cycle'])

def negative_controls(outputs,writes,tiles):
    controls=[]
    def rejected(name,fn):
        try: fn()
        except ValueError as error:
            controls.append(dict(test=name,status='REJECTED_AS_EXPECTED',reason=str(error)))
        else: raise ValueError(f'checker accepted corruption: {name}')
    bad=copy.deepcopy(outputs);bad[0]['result_bits']='0x00000000'
    rejected('wrong_actual_output',lambda:check_outputs(bad))
    bad2=copy.deepcopy(outputs);bad2[1]['column']='0'
    rejected('duplicate_output_coordinate',lambda:check_outputs(bad2))
    rejected('missing_write_halfword',lambda:check_writes(writes[:-1],outputs))
    bad3=copy.deepcopy(writes);bad3[0]['word_address']='0'
    rejected('out_of_window_write',lambda:check_writes(bad3,outputs))
    bad4=copy.deepcopy(tiles);bad4[-1]['rows_valid']='8'
    rejected('wrong_tail_descriptor',lambda:check_tiles(bad4))
    return controls

def check_run(run):
    outputs=csv_rows(run/'ffn1_output.csv',OUTPUT_FIELDS)
    writes=csv_rows(run/'ffn1_writeback.csv',WRITE_FIELDS)
    tiles=csv_rows(run/'ffn1_tiles.csv',TILE_FIELDS)
    check_outputs(outputs);last_write=check_writes(writes,outputs);check_tiles(tiles)
    input_files={}
    for name,count in (('x',M*K*2),('w',K*N*2),('bias',N*2)):
        path=run/f'ffn1_{name}.mem';words=path.read_text(encoding='ascii').split()
        need(len(words)==count,f'{name} input size mismatch')
        need(all(int(word,16)==(0x3f80 if i%2 else 0) for i,word in enumerate(words)),f'{name} not all FP32 1.0')
        input_files[name]=dict(halfwords=count,sha256=sha(path),format='16-bit hex, low half first')
    log=read_log(run/'ffn1.run.log')
    need('FATAL' not in log and 'FAIL' not in log,'simulation reported failure')
    pattern=r'PASS: FFN1 full layer m=(\d+) k=(\d+) n=(\d+) tiles=(\d+) outputs=(\d+) writes=(\d+) cycles=(\d+)'
    found=re.findall(pattern,log);need(len(found)==1,'missing/duplicate final full-layer PASS')
    values=tuple(map(int,found[0]));need(values[:6]==(M,K,N,208,M*N,M*N*2),'PASS count mismatch')
    timing=re.findall(r'PASS: FFN1 read_halfwords=(\d+) unique_write_halfwords=(\d+) tail_rows=(\d+) last_write_cycle=(\d+) done_cycle=(\d+)',log)
    need(len(timing)==1,'missing write visibility timing assertion')
    reads,unique,tail,logged_last,done=map(int,timing[0])
    need((reads,unique,tail)==(642048,M*N*2,3),'read/tail counts differ')
    need(logged_last==last_write and done>last_write,'DONE precedes final accepted write')
    controls=negative_controls(outputs,writes,tiles)
    return dict(status='PASS',outputs_passed=len(outputs),outputs_failed=0,
                write_halfwords=len(writes),unique_write_halfwords=len(writes),
                input_read_halfwords=reads,spatial_tiles=len(tiles),k_blocks_per_tile=2,
                tail_valid_rows=tail,simulated_wait_cycles=values[6],
                final_write_cycle=last_write,done_cycle=done,first_difference=None,
                input_files=input_files,negative_controls=controls,
                scope='one all-FP32-one FFN1 job through protocol-neutral accelerator top',
                software_owner_independent_acceptance='PENDING',
                not_verified=['varied-value full layer','full FFN2','real E203 NICE/System Bus',
                              'physical SRAM macro','physical 8/4-stage arithmetic timing or PPA'])

def software_compare(run,reference_path):
    spec=importlib.util.spec_from_file_location('fixed_fp32_reference',reference_path)
    reference=importlib.util.module_from_spec(spec);spec.loader.exec_module(reference)
    def tensor(name,rows,cols):
        words=[int(w,16) for w in (run/f'ffn1_{name}.mem').read_text().split()]
        values=[words[i]|words[i+1]<<16 for i in range(0,len(words),2)]
        return [values[r*cols:(r+1)*cols] for r in range(rows)]
    x=tensor('x',M,K);w=tensor('w',K,N);bias=tensor('bias',1,N)[0]
    expected=reference.run_ffn1_bits(x,w,bias)
    actual=csv_rows(run/'ffn1_output.csv',OUTPUT_FIELDS)
    count=0
    with (run/'software_expected_output.csv').open('w',newline='',encoding='ascii') as stream:
        writer=csv.writer(stream,lineterminator='\n');writer.writerow(['row','column','expected_bits'])
        for i,row in enumerate(actual):
            r,c=divmod(i,N);gold=expected[r][c]
            writer.writerow([r,c,f'0x{gold:08x}'])
            need(int(row['result_bits'],16)==gold,f'software reference mismatch at ({r},{c})')
            count+=1
    return dict(status='BIT_EXACT_LOCAL_COMPARE',outputs_matched=count,first_difference=None,
                reference_sha256=sha(reference_path),
                reference_origin='software branch d11d169ea6f7b8500d6a2186c803d0f1a5eba709 archived snapshot',
                independent_software_owner_acceptance='PENDING')

def seal(root):
    entries={p.relative_to(root).as_posix():sha(p) for p in sorted(root.rglob('*'))
             if p.is_file() and p.name!='SHA256SUMS.txt'}
    (root/'SHA256SUMS.txt').write_text(''.join(f'{h}  {p}\n' for p,h in entries.items()),encoding='ascii')
    return entries

def verify(root):
    seen=set()
    for line in (root/'SHA256SUMS.txt').read_text().splitlines():
        digest,name=line.split('  ',1)
        need(name not in seen,f'duplicate manifest entry: {name}');seen.add(name)
        need(sha(root/name)==digest,f'archive fingerprint mismatch: {name}')
    actual={p.relative_to(root).as_posix() for p in root.rglob('*')
            if p.is_file() and p != root/'SHA256SUMS.txt'}
    need(seen==actual,'archive has missing or extra files')

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',required=True)
    parser.add_argument('--iverilog',default=str(ROOT/'.tools/iverilog/bin/iverilog.exe'))
    parser.add_argument('--vvp',default=str(ROOT/'.tools/iverilog/bin/vvp.exe'))
    parser.add_argument('--collect-existing',help='already executed real RTL run directory')
    parser.add_argument('--observed-exit-code',type=int)
    parser.add_argument('--regression-evidence',help='affected-source regression directory to cross-check')
    parser.add_argument('--replay',action='store_true')
    args=parser.parse_args();out=Path(args.output).resolve()
    need(not out.exists(),f'refusing to overwrite {out}')
    out.mkdir(parents=True)
    records=[]
    if args.replay:
        package=Path(__file__).resolve().parent;verify(package)
        sources=package/'sources'
    else:
        sources=out/'sources';sources.mkdir()
        paths=['rtl/files.f',f'tb/{TB}.sv']+[
            p.strip() for p in (ROOT/'rtl/files.f').read_text().splitlines() if p.strip()]
        for name in paths:
            target=sources/name;target.parent.mkdir(parents=True,exist_ok=True)
            shutil.copyfile(ROOT/name,target)
        shutil.copyfile(__file__,out/'Replay.py')
        write_json(out/'source_manifest.json',{p:sha(ROOT/p) for p in paths})
        reference=out/'software_reference/fp32_reference.py';reference.parent.mkdir()
        shutil.copyfile(ROOT/'handoff/array_pe_trace_2026-10-20_v2/software_snapshot/software/fp32_reference.py',reference)
    def command(argv,cwd,log):
        argv=list(map(str,argv));start=time.monotonic()
        with log.open('wb') as f:
            p=subprocess.run(argv,cwd=cwd,stdout=f,stderr=subprocess.STDOUT)
        records.append(dict(argv=argv,cwd=str(cwd),exit_code=p.returncode,
                            elapsed_seconds=time.monotonic()-start,log=log.name))
        write_json(out/'commands.json',records)
        need(p.returncode==0,f'failed command: {log}')
    command([args.iverilog,'-V'],out,out/'tool_version.log')
    if args.regression_evidence:
        reg=Path(args.regression_evidence).resolve()
        reg_summary=json.loads((reg/'summary.json').read_text())
        need(reg_summary['status']=='PASS' and reg_summary['failed']==0,'affected regression not PASS')
        checked=[]
        for original in sorted((reg/'sources/rtl').glob('*.sv')):
            relative=original.relative_to(reg/'sources')
            need(sha(original)==sha(sources/relative),f'regression/source mismatch: {relative}')
            checked.append(dict(path=relative.as_posix(),sha256=sha(original)))
        write_json(out/'affected_regression_link.json',dict(
            directory=str(reg),summary_sha256=sha(reg/'summary.json'),
            manifest_sha256=sha(reg/'SHA256SUMS.txt'),passed=reg_summary['passed'],
            verified_source_files=checked))
    if args.collect_existing:
        need(not args.replay,'cannot collect during replay')
        need(args.observed_exit_code==0,'collector requires observed successful simulator exit')
        original=Path(args.collect_existing).resolve()
        need(all(sha(ROOT/p)==h for p,h in json.loads((out/'source_manifest.json').read_text()).items()),'source drift')
        for name in ARTIFACTS:shutil.copyfile(original/name,out/name)
        for name in ('resource_samples.jsonl','process_completion.json','checker_tests.log'):
            if (original/name).exists():shutil.copyfile(original/name,out/name)
        # Do not claim that this collector executed the already-finished run.
        write_json(out/'imported_run_provenance.json',dict(
            evidence_origin=str(original),observed_vvp_exit_code=args.observed_exit_code,
            exit_code_source='supplied by operator after observing original shell process exit',
            original_cwd=str(ROOT),
            original_compile_argv=[args.iverilog,'-g2012','-s',TB,'-o','build/ffn1_completion/ffn1.vvp',
                                   '-f','rtl/files.f',f'tb/{TB}.sv'],
            original_run_argv=[args.vvp,'-i','build/ffn1_completion/ffn1.vvp','+OUT_DIR=build/ffn1_completion'],
            compiled_vvp_sha256=sha(original/'ffn1.vvp'),
            collector_reran_simulation=False,
            source_identity='matched unchanged affected-regression snapshot; exact source hashes archived'))
    else:
        with tempfile.TemporaryDirectory(prefix='ffn1_binary_') as temp:
            binary=Path(temp)/'ffn1.vvp'
            command([args.iverilog,'-g2012','-s',TB,'-o',binary,'-f','rtl/files.f',f'tb/{TB}.sv'],sources,out/'ffn1.compile.log')
            print('Running all 208 tiles; progress is in ffn1.run.log.',flush=True)
            command([args.vvp,'-i',binary,f'+OUT_DIR={out.as_posix()}'],out,out/'ffn1.run.log')
    summary=check_run(out)
    if (out/'process_completion.json').exists():
        process=json.loads((out/'process_completion.json').read_text(encoding='utf-8-sig'))
        need(process['exit_code']==0,'process observer recorded nonzero simulator exit')
        summary['simulator_resource_use']=process
    reference=(package if args.replay else out)/'software_reference/fp32_reference.py'
    summary['software_reference_compare']=software_compare(out,reference)
    write_json(out/'summary.json',summary)
    seal(out);verify(out)
    print(json.dumps(summary,ensure_ascii=False,indent=2),flush=True)

if __name__=='__main__':
    main()
