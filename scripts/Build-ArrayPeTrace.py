"""Build/replay measured 19-column array evidence; never commit or push.

Build: python scripts/Build-ArrayPeTrace.py --packet handoff/array_pe_trace_2026-10-20_v1
Replay: python <packet>/Replay.py --replay --output <new empty directory>
Python >=3.10; Git (build only); Icarus Verilog. No third-party Python packages.
"""
from __future__ import annotations
import argparse
import csv
import hashlib
import importlib
import json
import os
from pathlib import Path
import random
import shutil
import subprocess
import sys

sys.dont_write_bytecode = True
SW = 'd11d169ea6f7b8500d6a2186c803d0f1a5eba709'
HEADER = 'source_kind,case_id,tile_id,row,column,event,cycle,valid,k,x_bits,w_bits,acc_before_bits,product_bits,acc_after_bits,bias_bits,result_bits,rtl_commit,input_manifest_sha256,reference_trace_sha256'.split(',')
SOURCES = ['rtl/fp32_math_pkg.sv', 'rtl/fp32_pe_mac.sv', 'rtl/fp32_pe_array_8x16.sv',
           'rtl/tile_result_collector.sv', 'tb/fp32_array_trace_tb.sv']

def require(ok, message):
    if not ok:
        raise ValueError(message)

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def js(path, value):
    Path(path).write_text(json.dumps(value, indent=2, ensure_ascii=False)+'\n', encoding='utf-8')

def load(path):
    return json.loads(Path(path).read_bytes())

def read_csv(path):
    with Path(path).open(encoding='ascii', newline='') as stream:
        reader = csv.DictReader(stream)
        rows = list(reader)
        require(all(None not in r and all(v is not None for v in r.values()) for r in rows), f'malformed CSV {path}')
        return reader.fieldnames, rows

def write_csv(path, rows, fields=HEADER):
    with Path(path).open('w', encoding='ascii', newline='') as stream:
        writer = csv.DictWriter(stream, fields, lineterminator='\n')
        writer.writeheader()
        writer.writerows(rows)

def command(cmd, cwd, log, records):
    cmd = [str(s) for s in cmd]
    proc = subprocess.run(cmd, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                          env=dict(os.environ, PYTHONDONTWRITEBYTECODE='1'))
    Path(log).write_bytes(proc.stdout)
    records.append({'argv':cmd, 'cwd':str(cwd), 'exit_code':proc.returncode,
                    'log':str(log), 'log_sha256':sha(log)})
    require(proc.returncode == 0, f'command exit {proc.returncode}: {log}')
    return proc.stdout.decode('utf-8', errors='replace')

def software_modules(packet):
    sys.path.insert(0, str(packet/'software_snapshot'))
    return importlib.import_module('software.fp32_reference'), importlib.import_module('software.compare_pe_trace')

def git_blob(git, repo, commit, path):
    return subprocess.check_output([git, '-C', str(repo), 'cat-file', 'blob', f'{commit}:{path}'], stderr=subprocess.PIPE)

def bits(value):
    return f'0x{value:08x}'

def tensor(directory, name, values, shape):
    raw = b''.join(v.to_bytes(4, 'little') for v in values)
    (directory/f'{name}.bin').write_bytes(raw)
    words = [f'{int.from_bytes(raw[i:i+2], "little"):04x}' for i in range(0,len(raw),2)]
    (directory/f'{name}.mem').write_text('\n'.join(words)+'\n', encoding='ascii')
    return {'shape':shape, 'word_count':len(words), 'byte_count':len(raw),
            'sha256_bin':sha(directory/f'{name}.bin'), 'sha256_mem':sha(directory/f'{name}.mem'),
            'words_hex':words}

def make_vectors(packet, ref):
    cases = [dict(case_id='hand_2x2',ROWS=2,COLS=2,TOTAL_K=2,VALID_ROWS=2,VALID_COLS=2,ROW_BASE=0,COL_BASE=0, origin='software original'),
             dict(case_id='array_8x16_k32',ROWS=8,COLS=16,TOTAL_K=32,VALID_ROWS=8,VALID_COLS=16,ROW_BASE=0,COL_BASE=0,origin='hardware added; joint vector approval pending'),
             dict(case_id='array_8x16_k64',ROWS=8,COLS=16,TOTAL_K=64,VALID_ROWS=8,VALID_COLS=16,ROW_BASE=0,COL_BASE=0,origin='hardware added; joint vector approval pending'),
             dict(case_id='array_tail_3x5_k64',ROWS=8,COLS=16,TOTAL_K=64,VALID_ROWS=3,VALID_COLS=5,ROW_BASE=96,COL_BASE=16,origin='hardware added; joint vector approval pending')]
    for spec in cases:
        directory = packet/'inputs'/spec['case_id']
        directory.mkdir(parents=True)
        R,C,K = (spec[p] for p in ('ROWS','COLS','TOTAL_K'))
        if spec['case_id']=='hand_2x2':
            source = packet/'software_snapshot/software/examples/fp32_hand_image'
            for name in ('manifest.json','expected_traces.json','x.mem','w.mem','bias.mem','x.bin','w.bin','bias.bin'):
                shutil.copyfile(source/name, directory/name)
            _,golden = read_csv(source/'expected_pe_trace_demo.csv')
            write_csv(directory/'expected_pe_trace.csv',[r for r in golden if r['case_id']=='hand_2x2'])
            continue
        rng = random.Random(20261020+K+spec['ROW_BASE'])
        def number():
            # Normal finite operands with nontrivial mantissas and both signs.
            return (rng.randrange(2)<<31) | (rng.randrange(120,130)<<23) | rng.getrandbits(23)
        x = [[number() if r<spec['VALID_ROWS'] else 0 for k in range(K)] for r in range(R)]
        w = [[number() if c<spec['VALID_COLS'] else 0 for c in range(C)] for k in range(K)]
        bias = [number() if c<spec['VALID_COLS'] else 0 for c in range(C)]
        if K==64:
            # Distinctive boundary: (0,0) is 31 -> 33 -> 30, final 61.25.
            x[0] = [ref.from_float(1.0)]*K
            for k in range(K):
                w[k][0] = ref.from_float(2.0 if k==31 else -3.0 if k==32 else 1.0)
            bias[0] = ref.from_float(0.25)
        manifest = {'schema':'array_inputs_v1','case_id':spec['case_id'],'origin':spec['origin'],
                    'parameters':spec,'layout':'row-major; FP32 low 16-bit word first; word little endian',
                    'padding':'X invalid rows=+0; W/bias invalid columns=+0; bias broadcasts even to ignored rows',
                    'tensors':{}}
        for name, values, shape in [('x',[v for row in x for v in row],[R,K]),
                                     ('w',[v for row in w for v in row],[K,C]),('bias',bias,[C])]:
            manifest['tensors'][name] = tensor(directory,name,values,shape)
        js(directory/'manifest.json',manifest)
        values=[]
        for r in range(spec['VALID_ROWS']):
            for c in range(spec['VALID_COLS']):
                acc=0
                for k in range(K):
                    product=ref.multiply_bits(x[r][k],w[k][c]); after=ref.add_bits(acc,product)
                    values.append(dict(tile_id=str(k//32),row=str(r+spec['ROW_BASE']),column=str(c+spec['COL_BASE']),
                                       event='mac',k=str(k),x_bits=bits(x[r][k]),w_bits=bits(w[k][c]),
                                       acc_before_bits=bits(acc),product_bits=bits(product),acc_after_bits=bits(after)))
                    acc=after
                after=ref.add_bits(acc,bias[c])
                values.append(dict(tile_id=str((K-1)//32),row=str(r+spec['ROW_BASE']),column=str(c+spec['COL_BASE']),event='bias',
                                   acc_before_bits=bits(acc),acc_after_bits=bits(after),bias_bits=bits(bias[c]),result_bits=bits(after)))
        js(directory/'expected_traces.json',{'schema':'array_reference_events_v1','software_commit':SW,
            'generator':'unmodified software.fp32_reference multiply_bits/add_bits',
            'status':'hardware-generated software reference; not independently accepted by software owner',
            'case_id':spec['case_id'],'events':values})
        rows=[]
        for value in values:
            row=dict.fromkeys(HEADER,'')
            row.update(value,source_kind='software_candidate',case_id=spec['case_id'],valid='1',
                       input_manifest_sha256=sha(directory/'manifest.json'),reference_trace_sha256=sha(directory/'expected_traces.json'))
            rows.append(row)
        write_csv(directory/'expected_pe_trace.csv',rows)
    js(packet/'cases.json',cases)

def create(args):
    root=Path(__file__).resolve().parents[1]
    packet=Path(args.packet).resolve(); repo=Path(args.repo).resolve()
    require(not packet.exists(),f'will not overwrite {packet}')
    base=subprocess.check_output([args.git,'-C',str(repo),'rev-parse','HEAD']).decode().strip()
    packet.mkdir(parents=True)
    paths=subprocess.check_output([args.git,'-C',str(repo),'ls-tree','-r','--name-only',SW,'software']).decode().splitlines()
    for path in paths:
        # Export only Python source and small agreed reference vector directory.
        if not(path.endswith('.py') or path.startswith('software/examples/fp32_hand_image/')):
            continue
        destination=packet/'software_snapshot'/path
        destination.parent.mkdir(parents=True,exist_ok=True)
        destination.write_bytes(git_blob(args.git,repo,SW,path))
    entries=[]
    for path in SOURCES:
        destination=packet/'sources'/path
        destination.parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(root/path,destination)
        try:
            git_sha=hashlib.sha256(git_blob(args.git,repo,base,path)).hexdigest()
        except subprocess.CalledProcessError:
            git_sha=None
        entries.append({'file':f'sources/{path}','sha256':sha(destination),
                        'base_git_blob_sha256':git_sha,'matches_base_git_blob':git_sha==sha(destination)})
    shutil.copyfile(__file__,packet/'Replay.py')
    shutil.copyfile(root/'handoff/ARRAY_PE_TRACE_README_2026-10-20.md',packet/'README.md')
    (packet/'filelist.f').write_text(''.join(f'sources/{s}\n' for s in SOURCES),encoding='ascii')
    js(packet/'provenance.json',{'hardware_base_commit':base,'csv_rtl_commit':base+'+dirty','software_commit':SW,
        'source_workspace':'D:/competition is not a Git repository; HEAD is only the independent clone base',
        'dirty_reason':'local uncommitted RTL/testbench snapshot; not all files match the base commit',
        'compiled_sources':entries,'clone_status':subprocess.check_output([args.git,'-C',str(repo),'status','--porcelain']).decode(),
        'physical_timing':'combinational FP32 functions followed by delay registers; not physically partitioned 8/4-stage arithmetic',
        'no_commit_or_push':True})
    ref,_=software_modules(packet)
    make_vectors(packet,ref)
    return packet

def validate_inputs(packet):
    report=[]
    for spec in load(packet/'cases.json'):
        d=packet/'inputs'/spec['case_id']; manifest=load(d/'manifest.json')
        if spec['case_id']=='hand_2x2':
            require(sha(d/'manifest.json')=='148ac9b305c34dafd033ea33d98b4f0a13edbf1306c66d29c7926ed348941e93','original software manifest fingerprint changed')
            require(sha(d/'expected_traces.json')=='a85bb5b7d334841acab94740290933bd3a991b881acf8782615cb8c43f73553b','original software reference fingerprint changed')
        for name in ('x','w','bias'):
            words=(d/f'{name}.mem').read_text(encoding='ascii').split()
            tensor_info=manifest['tensors'][name]
            require(len(words)==tensor_info['word_count'],'input word count mismatch')
            require(words==tensor_info['words_hex'],'input words != manifest')
            require(b''.join(int(w,16).to_bytes(2,'little') for w in words)==(d/f'{name}.bin').read_bytes(),'mem/bin mismatch')
            require(sha(d/f'{name}.bin')==tensor_info['sha256_bin'],'input bin hash mismatch')
            if 'sha256_mem' in tensor_info:
                require(sha(d/f'{name}.mem')==tensor_info['sha256_mem'],'input mem hash mismatch')
            report.append({'case_id':spec['case_id'],'actual_tb_load':f'inputs/{spec["case_id"]}/{name}.mem',
                           'mem_sha256':sha(d/f'{name}.mem'),'bin_sha256':sha(d/f'{name}.bin')})
    return report

def validate_run(spec, directory, inputs, revision):
    fields,rows=read_csv(directory/'pe_trace.csv')
    require(fields==HEADER,'not exact 19-column header')
    K=spec['TOTAL_K']; R=spec['ROWS']; C=spec['COLS']
    count=spec['VALID_ROWS']*spec['VALID_COLS']
    require(len(rows)==count*(K+1),'missing measured events')
    _,raw=read_csv(directory/'signal_trace.csv')
    require(len(raw)==R*C*(K+1),'missing physical PE events including padding')
    mapped={}; retired={}; lastcycle={}; raw_selected={}
    for signal in raw:
        r=int(signal['physical_row']); c=int(signal['physical_column']); xy=(r,c)
        cyc=int(signal['cycle']); n=retired.get(xy,0)
        require(cyc>lastcycle.get(xy,-1),'unordered per-PE cycles'); lastcycle[xy]=cyc
        event='mac' if signal['trace_valid']=='1' else 'bias'
        require(signal['trace_bias_valid']==str(int(event=='bias')),'raw valid mismatch')
        require(signal['result_valid']==str(int(event=='bias')),'PE result valid mismatch')
        require(signal['accumulator_bits']==signal['acc_after_bits'],'real accumulator mismatch')
        if event=='mac':
            require(n<K and int(signal['local_k'])==n%32,'local/global K mismatch')
            retired[xy]=n+1; k=str(n)
        else:
            require(n==K,'bias before all MACs'); k=''
        key=(str(r+spec['ROW_BASE']),str(c+spec['COL_BASE']),event,k)
        require(key not in mapped,'duplicate physical event')
        mapped[key]=signal
        if r<spec['VALID_ROWS'] and c<spec['VALID_COLS']: raw_selected[key]=signal
    seen=set()
    for row in rows:
        key=tuple(row[f] for f in ('row','column','event','k'))
        require(key not in seen and key in raw_selected,'CSV not backed by unique live event'); seen.add(key)
        source=raw_selected[key]
        require(row['case_id']==spec['case_id'] and row['source_kind']=='rtl_measured' and row['valid']=='1','identity metadata mismatch')
        require(row['cycle']==source['cycle'] and row['rtl_commit']==revision,'cycle/revision mismatch')
        require(row['input_manifest_sha256']==sha(inputs/'manifest.json') and row['reference_trace_sha256']==sha(inputs/'expected_traces.json'),'hash metadata mismatch')
        fields_to_check=('x_bits','w_bits','acc_before_bits','product_bits','acc_after_bits') if row['event']=='mac' else ('acc_before_bits','acc_after_bits','bias_bits','result_bits')
        require(all(row[f]==source[f] for f in fields_to_check),'CSV value not from real trace')
        expected_tile=int(row['k'])//32 if row['event']=='mac' else (K-1)//32
        require(int(row['tile_id'])==expected_tile,'tile mapping mismatch')
    require(seen==set(raw_selected),'missing CSV projection')
    _,out=read_csv(directory/'result_writeout.csv')
    require(len(out)==count,'result writeout count mismatch')
    for i,row in enumerate(out):
        require((int(row['row']),int(row['column']))==(spec['ROW_BASE']+i//spec['VALID_COLS'],spec['COL_BASE']+i%spec['VALID_COLS']),'writeout ordering mismatch')
        bias=mapped[(row['row'],row['column'],'bias','')]
        require(row['result_bits']==bias['result_bits'] and int(row['cycle'])>int(bias['cycle']),'writeout data/timing mismatch')
        require(row['last']==str(int(i==count-1)),'writeout last flag mismatch')
    return rows,{'case_id':spec['case_id'],'status':'PASS','events':len(rows),'physical_events':len(raw),
                 'mac_events':count*K,'bias_events':count,'outputs':len(out),'first_difference':None,
                 'timing':'TB asserts actual mul=8 and dependent add=4; post-NBA sampling',
                 'source_projection':'all formal fields match actual trace signals',
                 'sram_save_restore':'NOT TESTED: register hold only'}

def run(packet, output, args):
    require(not output.exists(),f'will not overwrite {output}')
    output.mkdir(parents=True); commands=[]
    _,compare=software_modules(packet)
    for executable in (args.iverilog,args.vvp):
        command([executable,'-V'],packet,output/(Path(executable).stem+'_version.log'),commands)
    js(output/'python_version.json',{'executable':sys.executable,'version':sys.version})
    js(output/'input_validation.json',validate_inputs(packet))
    provenance=load(packet/'provenance.json'); revision=provenance['csv_rtl_commit']
    allrows=[]; allgold=[]; reports=[]
    for spec in load(packet/'cases.json'):
        d=output/spec['case_id']; d.mkdir(); inputs=packet/'inputs'/spec['case_id']
        cmd=[args.iverilog,'-g2012','-s','fp32_array_trace_tb','-o',d/'simulation.vvp']
        cmd += [f'-Pfp32_array_trace_tb.{p}={spec[p]}' for p in ('ROWS','COLS','TOTAL_K','VALID_ROWS','VALID_COLS','ROW_BASE','COL_BASE')]
        cmd += [packet/'sources'/s for s in SOURCES]
        command(cmd,packet,d/'compile.log',commands)
        sim=command([args.vvp,d/'simulation.vvp',f'+input={inputs.as_posix()}',f'+output={d.as_posix()}',
            f'+case={spec["case_id"]}',f'+revision={revision}',f'+manifest={sha(inputs/"manifest.json")}',
            f'+reference={sha(inputs/"expected_traces.json")}'],packet,d/'simulation.log',commands)
        require(f'PASS case={spec["case_id"]}' in sim and 'RESET_ABORT_CHECK PASS' in sim,'missing simulation assertions')
        rows,report=validate_run(spec,d,inputs,revision)
        command([sys.executable,'-B','-m','software.compare_pe_trace','--expected',inputs/'expected_pe_trace.csv',
                 '--actual',d/'pe_trace.csv','--compare-tile-id','--report',d/'comparison.json'],
                packet/'software_snapshot',d/'comparison.log',commands)
        result=load(d/'comparison.json')
        require(result['status']=='BIT-EXACT-CANDIDATE',f'first mismatch: {result["first_mismatch"]}')
        report['software_original_comparator']=result['status']; report['software_owner_independent_acceptance']='PENDING'
        reports.append(report); allrows.extend(rows); allgold.extend(read_csv(inputs/'expected_pe_trace.csv')[1])
    write_csv(output/'pe_trace.csv',allrows); write_csv(output/'expected_pe_trace.csv',allgold)
    command([sys.executable,'-B','-m','software.compare_pe_trace','--expected',output/'expected_pe_trace.csv',
             '--actual',output/'pe_trace.csv','--compare-tile-id','--report',output/'comparison.json'],
            packet/'software_snapshot',output/'comparison.log',commands)
    result=load(output/'comparison.json')
    require(result['status']=='BIT-EXACT-CANDIDATE','aggregate mismatch')
    # Negative controls prove checker rejects missing, wrong-K-tile, wrong coordinate and wrong arithmetic.
    checks=[]
    for name,field,value in [('wrong_tile','tile_id','99'),('wrong_coordinate','row','999'),('wrong_value','acc_after_bits','0x12345678'),('missing_event',None,None)]:
        changed=[dict(r) for r in allrows]
        if field: changed[0][field]=value
        else: changed.pop(0)
        path=output/f'negative_{name}.csv'; write_csv(path,changed)
        mismatch=compare.compare(output/'expected_pe_trace.csv',path,compare_tile_id=True)
        require(mismatch['status']=='MISMATCH',f'checker failed negative control {name}')
        checks.append({'test':name,'status':'PASS (corruption rejected)','first_mismatch':mismatch['first_mismatch']})
    js(output/'negative_controls.json',checks)
    js(output/'commands.json',commands)
    summary={'status':'PASS','cases_passed':len(reports),'cases_failed':0,'events':len(allrows),
             'outputs':sum(r['outputs'] for r in reports),'first_difference':None,'cases':reports,
             'negative_controls_passed':len(checks),'software_commit':SW,'csv_rtl_commit':revision,
             'not_claimed':['software-owner independent acceptance of this array packet','SRAM partial-sum save/restore',
                            'full competition layers','E203/SoC integration','physical pipeline timing or PPA']}
    js(output/'summary.json',summary)
    return summary

def seal(packet):
    files={p.relative_to(packet).as_posix():sha(p) for p in sorted(packet.rglob('*')) if p.is_file() and p.name!='SHA256SUMS.txt'}
    (packet/'SHA256SUMS.txt').write_text(''.join(f'{h}  {p}\n' for p,h in files.items()),encoding='utf-8')
    return files

def verify(packet):
    rows=(packet/'SHA256SUMS.txt').read_text(encoding='utf-8').splitlines()
    for row in rows:
        expected,path=row.split('  ',1)
        require(sha(packet/path)==expected,f'packet changed: {path}')
    return len(rows)

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--packet',default='handoff/array_pe_trace_2026-10-20_v1')
    parser.add_argument('--repo',default='build/team_handoff_repo')
    parser.add_argument('--git',default=shutil.which('git'))
    root=Path(__file__).resolve().parents[1]
    parser.add_argument('--iverilog',default=str(root/'.tools/iverilog/bin/iverilog.exe'))
    parser.add_argument('--vvp',default=str(root/'.tools/iverilog/bin/vvp.exe'))
    parser.add_argument('--replay',action='store_true')
    parser.add_argument('--output')
    args=parser.parse_args()
    if args.replay:
        packet=Path(__file__).resolve().parent
        count=verify(packet)
        require(args.output,'replay requires --output new-directory')
        result=run(packet,Path(args.output).resolve(),args)
        require(sha(Path(args.output)/'pe_trace.csv')==sha(packet/'pe_trace.csv'),'replay trace is not byte-identical')
        js(Path(args.output)/'replay_integrity.json',{'packet_files_verified':count,'trace_byte_identical':True,'packet_unchanged':verify(packet)==count})
    else:
        packet=create(args)
        result=run(packet,packet/'run',args)
        shutil.copyfile(packet/'run/pe_trace.csv',packet/'pe_trace.csv')
        shutil.copyfile(packet/'run/summary.json',packet/'summary.json')
        count=len(seal(packet)); require(verify(packet)==count,'packet hash verification failed')
    print(json.dumps(result,indent=2,ensure_ascii=False))

if __name__=='__main__':
    main()
