"""Build/replay local single-PE special-case evidence; never commit or push.

python scripts/Run-PeSpecialValidation.py --packet <new-directory>
python Replay-Special.py --replay --output <new-directory>
Python 3.10+, Icarus Verilog. Software oracle is an unchanged pinned snapshot.
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
import tempfile

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[1]
PRIOR = ROOT / 'handoff/pe_hand_2x2_formal_2026-10-20'
SOFTWARE_COMMIT = 'd11d169ea6f7b8500d6a2186c803d0f1a5eba709'
MANIFEST = '148ac9b305c34dafd033ea33d98b4f0a13edbf1306c66d29c7926ed348941e93'
REFERENCE = 'a85bb5b7d334841acab94740290933bd3a991b881acf8782615cb8c43f73553b'
HEADER = 'source_kind,case_id,tile_id,row,column,event,cycle,valid,k,x_bits,w_bits,acc_before_bits,product_bits,acc_after_bits,bias_bits,result_bits,rtl_commit,input_manifest_sha256,reference_trace_sha256'.split(',')

def require(condition, message):
    if not condition:
        raise ValueError(message)

def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def write_json(path, value):
    Path(path).write_text(json.dumps(value, ensure_ascii=False, indent=2)+'\n', encoding='utf-8', newline='\n')

def csv_write(path, rows):
    with Path(path).open('w', encoding='ascii', newline='') as stream:
        writer=csv.DictWriter(stream, HEADER, lineterminator='\n')
        writer.writeheader(); writer.writerows(rows)

def csv_read(path):
    with Path(path).open(encoding='ascii', newline='') as stream:
        reader=csv.DictReader(stream)
        rows=list(reader)
        require(all(None not in r and all(v is not None for v in r.values()) for r in rows), 'malformed CSV')
        return reader.fieldnames, rows

def import_reference(packet):
    sys.path.insert(0, str(packet/'software_snapshot'))
    return importlib.import_module('software.fp32_reference')

def verify_sums(packet):
    for line in (packet/'SHA256SUMS.txt').read_text(encoding='ascii').splitlines():
        expected, relative=line.split('  ',1)
        target=packet/relative
        require(target.resolve().is_relative_to(packet.resolve()), 'checksum path escapes packet')
        require(digest(target)==expected, f'packet checksum mismatch: {relative}')

def build_boundary_vectors(reference, output):
    # Include all signed-zero pairs, normal/subnormal transition, ties and
    # cancellation. Biased random samples deliberately oversample tiny values.
    anchors=[0,0x80000000,1,2,3,0x80000001,0x80000003,0x007fffff,
             0x807fffff,0x00800000,0x80800000,0x00800001,0x01000000,
             0x3f000000,0xbf000000,0x3f800000,0xbf800000,0x3f800001,
             0x3f7fffff,0x3f7ffffe,0x33800000,0x33000000,0x34000000,
             0x40000000,0xc0000000,0x7f7fffff,0xff7fffff]
    # Independent expected constants sanity-check the software oracle first.
    sanity=[('mul',1,0x3f000000,0),('mul',3,0x3f000000,2),
            ('mul',0x80000001,0x3f000000,0x80000000),
            ('mul',0x00800000,0x3f000000,0x00400000),
            ('add',0x007fffff,1,0x00800000),
            ('add',0x80000000,0x80000000,0x80000000),
            ('add',0x3f800000,0xbf800000,0),
            ('add',0x3f800000,0x33800000,0x3f800000),
            ('add',0x3f800001,0x33800000,0x3f800002)]
    for op,a,b,expected in sanity:
        function=reference.add_bits if op=='add' else reference.multiply_bits
        require(function(a,b)==expected, f'independent oracle sanity failure: {op} {a:x} {b:x}')
    pairs=[]
    rejected=0
    def add_pair(a,b):
        nonlocal rejected
        try:
            s=reference.add_bits(a,b); p=reference.multiply_bits(a,b)
        except reference.UnsupportedFP32Case:
            rejected+=1
            return
        pairs.append((a,b,s,p))
    for a in anchors:
        for b in anchors:
            add_pair(a,b)
    directed_count=len(pairs)
    rng=random.Random(0x4b575431)
    exponents=[0,0,0,1,1,2,3,63,126,127,128,190,250,254]
    while len(pairs)<directed_count+24000:
        operands=[(rng.getrandbits(1)<<31)|(rng.choice(exponents)<<23)|rng.getrandbits(23) for _ in range(2)]
        add_pair(*operands)
    output.write_text(''.join(f'{a:08x} {b:08x} {s:08x} {p:08x}\n' for a,b,s,p in pairs),encoding='ascii',newline='\n')
    sub=lambda v: (v&0x7f800000)==0 and (v&0x007fffff)!=0
    coverage={
        'pairs':len(pairs),'directed_pairs':directed_count,'seeded_random_pairs':24000,
        'seed':'0x4b575431','overflow_pairs_excluded':rejected,
        'pairs_with_subnormal_input':sum(sub(a) or sub(b) for a,b,_,_ in pairs),
        'subnormal_add_results':sum(sub(s) for _,_,s,_ in pairs),
        'subnormal_mul_results':sum(sub(p) for _,_,_,p in pairs),
        'negative_zero_add_results':sum(s==0x80000000 for _,_,s,_ in pairs),
        'negative_zero_mul_results':sum(p==0x80000000 for _,_,_,p in pairs),
        'independent_oracle_sanity_checks':len(sanity),
        'scope':'sampled finite non-overflow add/mul; not exhaustive binary32 coverage',
    }
    return coverage

def build_added_pe_case(packet, reference):
    directory=packet/'boundary_inputs'; directory.mkdir()
    # A single physical PE computes these logical cells in sequence. Common
    # W rows include signed zeros, +/- halves, and tiny finite operands.
    values=[0,0x80000000,1,0x80000001,2,3,0x80000003,0x007fffff,
            0x807fffff,0x00800000,0x80800000,0x00800001,
            0x3f800000,0xbf800000,0x3f800001,0x3f7fffff]
    x=[[v,0] for v in values]+[[v,v^0x80000000] for v in values]
    w=[[0x3f000000,0xbf000000,0x3f800000,0xbf800000,0,0x80000000,1,0x00800000],
       [0x3f000000,0xbf000000,0x3f800000,0xbf800000,0x80000000,0,1,0x00800000]]
    bias=[0,0x80000000,1,0x80000001,0,0x80000000,0,0]
    tensors={}
    for name,matrix in [('x',x),('w',w),('bias',[bias])]:
        words=reference.row_major_words(matrix)
        raw=reference.words_to_little_endian_bytes(words)
        (directory/f'{name}.bin').write_bytes(raw)
        (directory/f'{name}.mem').write_text(''.join(f'{v:04x}\n' for v in words),encoding='ascii',newline='\n')
        tensors[name]={'shape':[len(matrix),len(matrix[0])], 'word_count':len(words),
                       'byte_count':len(raw),'sha256_bin':digest(directory/f'{name}.bin'),
                       'words_hex':[f'{v:04x}' for v in words]}
    write_json(directory/'manifest.json',{
        'status':'hardware-added directed finite-boundary vectors; software independent acceptance pending',
        'software_reference_commit':SOFTWARE_COMMIT,'tensors':tensors})
    traces=[]
    for row in range(len(x)):
        for column in range(len(bias)):
            trace=reference.trace_cell(x,w,bias,row,column)
            traces.append(trace)
    write_json(directory/'expected_traces.json',{'scope':'hardware-added golden generated with pinned software reference; not RTL measured','cells':traces})
    mh=digest(directory/'manifest.json'); rh=digest(directory/'expected_traces.json')
    golden=[]
    for trace in traces:
        row=trace['row']; col=trace['column']; before=0
        base={'source_kind':'software_candidate','case_id':'finite_boundaries_hardware_added',
              'tile_id':0,'row':row,'column':col,'cycle':'','valid':1,'rtl_commit':'',
              'input_manifest_sha256':mh,'reference_trace_sha256':rh}
        for step in trace['steps']:
            k=step['k']
            event={**dict.fromkeys(HEADER,''),**base,'event':'mac','k':k,
                   'x_bits':f'0x{x[row][k]:08x}','w_bits':f'0x{w[k][col]:08x}',
                   'acc_before_bits':f'0x{before:08x}','product_bits':f'0x{step["product_bits"]:08x}',
                   'acc_after_bits':f'0x{step["acc_bits"]:08x}'}
            golden.append(event); before=step['acc_bits']
        golden.append({**dict.fromkeys(HEADER,''),**base,'event':'bias',
                       'acc_before_bits':f'0x{before:08x}','bias_bits':f'0x{bias[col]:08x}',
                       'acc_after_bits':f'0x{trace["result_bits"]:08x}','result_bits':f'0x{trace["result_bits"]:08x}'})
    csv_write(directory/'expected_pe_trace.csv',golden)
    return {'id':'finite_boundaries_hardware_added','rows':len(x),'cols':len(bias),'depth':2,
            'input_dir':'boundary_inputs','prefix':'','golden':'boundary_inputs/expected_pe_trace.csv',
            'manifest_sha256':mh,'reference_sha256':rh,'acceptance':'hardware-added; not independently accepted by software owner'}

def initial_build(args):
    packet=Path(args.packet).resolve()
    require(not packet.exists(), f'refusing to overwrite: {packet}')
    verify_sums(PRIOR)
    packet.mkdir(parents=True)
    shutil.copytree(PRIOR/'software_snapshot',packet/'software_snapshot')
    shutil.copytree(PRIOR/'inputs',packet/'inputs')
    require(digest(packet/'inputs/manifest.json')==MANIFEST and
            digest(packet/'inputs/expected_traces.json')==REFERENCE, 'software raw golden bytes changed')
    shutil.copyfile(ROOT/'handoff/PE_TRACE_CONTRACT_ACCEPTED_2026-10-20.md',packet/'prior_contract.md')
    sources=['rtl/fp32_math_pkg.sv','rtl/fp32_pe_mac.sv',
             'tb/fp32_pe_special_tb.sv','tb/fp32_math_boundary_tb.sv']
    compiled=[]
    for relative in sources:
        destination=packet/'sources'/relative; destination.parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(ROOT/relative,destination)
        compiled.append({'path':'sources/'+relative,'sha256':digest(destination)})
    (packet/'filelist.f').write_text(''.join(f'sources/{p}\n' for p in sources),encoding='ascii',newline='\n')
    git=args.git; repo=Path(args.repo).resolve()
    base=subprocess.check_output([git,'-C',str(repo),'rev-parse','HEAD']).decode().strip()
    matches={}
    for relative in sources[:2]:
        raw=subprocess.check_output([git,'-C',str(repo),'cat-file','blob',f'{base}:{relative}'])
        matches[relative]=hashlib.sha256(raw).hexdigest()==digest(ROOT/relative)
    write_json(packet/'provenance.json',{
        'hardware_base_commit':base,'csv_rtl_commit':base+'+dirty',
        'software_commit':SOFTWARE_COMMIT,'compiled_sources':compiled,
        'rtl_matches_base_git_blobs':matches,
        'dirty_reason':'new local testbenches and validation runner not committed; exact source snapshots supplied',
        'workspace':'D:/competition is not a Git repository; baseline from independent team clone',
        'clone_status_at_build':subprocess.check_output([git,'-C',str(repo),'status','--porcelain']).decode(),
        'scope':'functional single PE only; no commit/push performed by runner'})
    reference=import_reference(packet)
    coverage=build_boundary_vectors(reference,packet/'fp32_boundary_vectors.txt')
    write_json(packet/'boundary_vector_coverage.json',coverage)
    cases=[]
    for name,prefix,depth,rows,cols in [('hand_2x2','',2,2,2),('rounding_nonfused','rounding_',2,1,1),('k32_boundary','tile_',64,1,1)]:
        cases.append({'id':name,'rows':rows,'cols':cols,'depth':depth,'prefix':prefix,
                      'input_dir':'inputs','golden':'inputs/expected_pe_trace_demo.csv',
                      'manifest_sha256':MANIFEST,'reference_sha256':REFERENCE,
                      'acceptance':'software-provided vector; owner independent RTL acceptance pending'})
    cases.append(build_added_pe_case(packet,reference))
    write_json(packet/'cases.json',cases)
    shutil.copyfile(__file__,packet/'Replay-Special.py')
    shutil.copyfile(ROOT/'scripts/Test-PeSpecialValidator.py',packet/'Test-PeSpecialValidator.py')
    shutil.copyfile(ROOT/'handoff/PE_SPECIAL_VALIDATION_README_2026-10-20.md',packet/'README.md')
    return packet

class Runner:
    def __init__(self, output):
        self.output=output; self.commands=[]
    def run(self, command, cwd, log):
        command=[str(v) for v in command]
        self.commands.append({'argv':command,'cwd':str(cwd),'log':str(log)})
        write_json(self.output/'commands.json',self.commands)
        completed=subprocess.run(command,cwd=cwd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,
                                 env=dict(os.environ,PYTHONDONTWRITEBYTECODE='1'),timeout=60)
        Path(log).write_bytes(completed.stdout)
        require(completed.returncode==0, f'command failed ({completed.returncode}): see {log}')
        return completed.stdout.decode('utf-8',errors='replace')

def validate_inputs(packet, case):
    directory=packet/case['input_dir']
    require(digest(directory/'manifest.json')==case['manifest_sha256'], 'case manifest mismatch')
    require(digest(directory/'expected_traces.json')==case['reference_sha256'], 'case reference mismatch')
    manifest=json.loads((directory/'manifest.json').read_bytes())
    records=[]
    for name in ('x','w','bias'):
        stem=case['prefix']+name; entry=manifest['tensors'][stem]
        words=(directory/f'{stem}.mem').read_text(encoding='ascii').split()
        binary=(directory/f'{stem}.bin').read_bytes()
        require([v.lower() for v in words]==entry['words_hex'] and len(words)==entry['word_count'], 'manifest word mismatch')
        require(b''.join(int(w,16).to_bytes(2,'little') for w in words)==binary, 'mem/bin byte mismatch')
        require(digest(directory/f'{stem}.bin')==entry['sha256_bin'], 'binary manifest mismatch')
        expected_shape={'x':[case['rows'],case['depth']],'w':[case['depth'],case['cols']], 'bias':[1,case['cols']]}[name]
        require(entry['shape']==expected_shape, 'input shape mismatch')
        records.append({'loaded_by_tb':f'{case["input_dir"]}/{stem}.mem',
                        'mem_sha256':digest(directory/f'{stem}.mem'),
                        'bin_sha256':digest(directory/f'{stem}.bin'),'shape':entry['shape'],
                        'layout':'row-major; low 16-bit word first; each word little-endian'})
    return {'status':'PASS','manifest_sha256':case['manifest_sha256'],
            'reference_sha256':case['reference_sha256'],'actual_inputs':records}

def validate_measured(output, case, revision):
    fields,events=csv_read(output/'pe_trace.csv')
    require(fields==HEADER, 'wrong 19-column header')
    _,signals=csv_read(output/'signal_trace.csv')
    cycles=[int(s['cycle']) for s in signals]
    require(cycles==sorted(set(cycles)), 'duplicate/nonmonotonic signal cycle')
    require(all(s['rst_n']=='1' and s['clear_acc']=='0' for s in signals), 'reset/clear during capture')
    active=[s for s in signals if s['trace_valid']=='1' or s['trace_bias_valid']=='1']
    require(len(events)==len(active)==case['rows']*case['cols']*(case['depth']+1), 'event count mismatch')
    for event,s in zip(events,active):
        require(event['case_id']==case['id'] and event['rtl_commit']==revision and event['source_kind']=='rtl_measured', 'event identity mismatch')
        require(event['cycle']==s['cycle'] and event['row']==s['row'] and event['column']==s['column'], 'event signal alignment mismatch')
        require(event['acc_after_bits']==s['accumulator_bits']==s['acc_after_bits'], 'accumulator alignment mismatch')
        require(event['acc_before_bits']==s['acc_before_bits'], 'before alignment mismatch')
        if event['event']=='mac':
            require(s['trace_valid']=='1' and s['trace_bias_valid']==s['result_valid']==s['done']=='0','MAC signal mismatch')
            require(int(event['k'])==32*int(s['block'])+int(s['trace_local_k']), 'global K not tied to actual block/local K')
            require(int(event['tile_id'])==int(event['k'])//32, 'MAC tile mismatch')
            for field in ('x_bits','w_bits','product_bits'):
                require(event[field]==s[field],f'MAC {field} signal mismatch')
        else:
            require(s['trace_bias_valid']==s['result_valid']==s['done']=='1' and s['trace_valid']=='0' and s['busy']=='0', 'bias/result signal mismatch')
            require(int(event['tile_id'])==(case['depth']-1)//32, 'bias final tile mismatch')
            require(event['bias_bits']==s['bias_bits'] and event['result_bits']==s['result_bits'], 'bias data signal mismatch')
    boundaries=[]
    for row in range(case['rows']):
        for col in range(case['cols']):
            cell=[s for s in signals if (int(s['row']),int(s['column']))==(row,col)]
            ev=[e for e in events if (int(e['row']),int(e['column']))==(row,col)]
            mac=[e for e in ev if e['event']=='mac']; bias=[e for e in ev if e['event']=='bias']
            require([int(e['k']) for e in mac]==list(range(case['depth'])) and len(bias)==1 and ev[-1]['event']=='bias','MAC/bias ordering mismatch')
            before='0x00000000'
            for e in ev:
                require(e['acc_before_bits']==before,'cross-event accumulator chain broken')
                before=e['acc_after_bits']
            accept=[int(s['cycle']) for s in cell if s['input_accept']=='1']
            accepted_signals=[s for s in cell if s['input_accept']=='1']
            require(all(s['enable']=='1' and s['task_first']==str(int(k==0)) and
                        s['task_last']==str(int(k==case['depth']-1)) and
                        int(s['block'])==k//32 for k,s in enumerate(accepted_signals)),
                    'input task controls do not match actual K blocks')
            mul=[int(s['cycle']) for s in cell if s['mul_ready']=='1']
            issue=[int(s['cycle']) for s in cell if s['add_issue']=='1' and s['add_is_bias']=='0']
            commit=[int(e['cycle']) for e in mac]
            require(all(len(v)==case['depth'] for v in (accept,mul,issue,commit)), 'pipeline stage count mismatch')
            require(all(m-a==8 for a,m in zip(accept,mul)), 'mul latency mismatch')
            require(all(c-i==4 for i,c in zip(issue,commit)), 'add latency mismatch')
            bi=[int(s['cycle']) for s in cell if s['add_issue']=='1' and s['add_is_bias']=='1']
            require(len(bi)==1 and int(bias[0]['cycle'])-bi[0]==4 and bi[0]>commit[-1], 'bias issue timing mismatch')
            for boundary in range(32,case['depth'],32):
                prev=mac[boundary-1]; following=mac[boundary]
                wait=[s for s in cell if int(prev['cycle'])<int(s['cycle'])<accept[boundary]]
                held=[s for s in wait if s['enable']=='0']
                require(len(held)==9,'actual interblock wait must contain 9 enable-low clocks')
                require(all(s['accumulator_bits']==prev['acc_after_bits'] and s['busy']=='1' and s['trace_bias_valid']==s['result_valid']==s['done']=='0' for s in wait),'block partial sum not preserved')
                require(prev['acc_after_bits']==following['acc_before_bits'],'boundary chain mismatch')
                require(not any(int(prev['cycle'])<int(e['cycle'])<int(following['cycle']) for e in bias),'early bias across boundary')
                boundaries.append({'row':row,'column':col,'previous_global_k':boundary-1,'next_global_k':boundary,
                                   'previous_commit_cycle':int(prev['cycle']),'next_accept_cycle':accept[boundary],
                                   'next_commit_cycle':int(following['cycle']),
                                   'previous_acc_after_bits':prev['acc_after_bits'],
                                   'next_acc_before_bits':following['acc_before_bits'],
                                   'next_acc_after_bits':following['acc_after_bits'],
                                   'disabled_wait_cycles':len(held),'partial_sum_storage':'PE accumulator register; NOT SRAM'})
    return {'status':'PASS','scope':'actual RTL valid/data alignment and 8/4-clock functional boundaries',
            'mac_events':sum(e['event']=='mac' for e in events),'bias_events':sum(e['event']=='bias' for e in events),
            'actual_k32_boundaries':boundaries,'physical_timing_closed':False,'sram_save_restore_verified':False}

def replay(packet, output, args):
    require(not output.exists(), f'refusing to overwrite replay output: {output}')
    if args.replay:
        verify_sums(packet)
    output.mkdir(parents=True)
    provenance=json.loads((packet/'provenance.json').read_bytes())
    for source in provenance['compiled_sources']:
        require(digest(packet/source['path'])==source['sha256'], 'compiled source hash mismatch')
    runner=Runner(output)
    for tool,name in ((args.iverilog,'iverilog_version.log'),(args.vvp,'vvp_version.log')):
        runner.run([tool,'-V'],packet,output/name)
    write_json(output/'python_version.json',{'executable':sys.executable,'version':sys.version})
    revision=provenance['csv_rtl_commit']
    cases=json.loads((packet/'cases.json').read_bytes())
    results=[]
    with tempfile.TemporaryDirectory(dir=output,prefix='binaries_') as temp:
        binary=Path(temp)/'test.vvp'
        for case in cases:
            destination=output/case['id']; destination.mkdir()
            write_json(destination/'input_validation.json',validate_inputs(packet,case))
            command=[args.iverilog,'-g2012','-s','fp32_pe_special_tb','-o',binary,'-f','filelist.f']
            for name,value in [('ROWS',case['rows']),('COLS',case['cols']),('TOTAL_K',case['depth'])]:
                command.append(f'-Pfp32_pe_special_tb.{name}={value}')
            runner.run(command,packet,destination/'compile.log')
            command=[args.vvp,binary,f'+CASE_ID={case["id"]}',f'+OUTPUT_DIR={destination.as_posix()}',
                     f'+RTL_REVISION={revision}',f'+MANIFEST_SHA={case["manifest_sha256"]}',f'+REFERENCE_SHA={case["reference_sha256"]}']
            for name in ('x','w','bias'):
                command.append(f'+{name.upper()}_FILE={(packet/case["input_dir"]/(case["prefix"]+name+".mem")).as_posix()}')
            log=runner.run(command,packet,destination/'simulation.log')
            require('fp32_pe_special_tb PASS' in log, 'simulation missing PASS marker')
            runner.run([sys.executable,'-B','-m','software.compare_pe_trace','--expected',packet/case['golden'],
                        '--actual',destination/'pe_trace.csv','--case-id',case['id'],'--compare-tile-id',
                        '--report',destination/'compare_report.json'],packet/'software_snapshot',destination/'compare.log')
            comparison=json.loads((destination/'compare_report.json').read_bytes())
            require(comparison['status']=='BIT-EXACT-CANDIDATE' and comparison['first_mismatch'] is None, 'compare mismatch')
            timing=validate_measured(destination,case,revision)
            write_json(destination/'timing_and_boundary_report.json',timing)
            results.append({'case_id':case['id'],'status':'PASS_LOCAL_CHECK',
                            'mac_events':timing['mac_events'],'bias_events':timing['bias_events'],
                            'actual_k32_boundaries':len(timing['actual_k32_boundaries']),
                            'csv_sha256':digest(destination/'pe_trace.csv'),
                            'software_compare_status':comparison['status'], 'acceptance':case['acceptance']})
        math=output/'math_boundaries'; math.mkdir()
        runner.run([args.iverilog,'-g2012','-s','fp32_math_boundary_tb','-o',binary,'-f','filelist.f'],packet,math/'compile.log')
        log=runner.run([args.vvp,binary,f'+VECTORS={(packet/"fp32_boundary_vectors.txt").as_posix()}'],packet,math/'simulation.log')
        require('fp32_math_boundary_tb PASS' in log,'math test missing PASS marker')
    runner.run([sys.executable,'-B',packet/'Test-PeSpecialValidator.py','--packet',packet,'--results',output],
               packet,output/'validator_tests.log')
    report={'status':'PASS_SINGLE_PE_SPECIALS_LOCAL_CHECK','software_commit':SOFTWARE_COMMIT,
            'rtl_revision':revision,'cases':results,
            'math_boundary_coverage':json.loads((packet/'boundary_vector_coverage.json').read_bytes()),
            'validator_tests':'14 tests passed; corrupted COPIES only, not extra hardware evidence',
            'software_owner_independent_acceptance':'PENDING',
            'not_verified':['SRAM partial sum save/restore','array','full layer','E203/SoC',
                            '150 MHz physical timing','NaN/Inf/overflow contract','exhaustive FP32 coverage']}
    write_json(output/'run_report.json',report)
    print(json.dumps(report,indent=2,ensure_ascii=False))

def prepare_legacy_regression(packet, output, args):
    """Existing PE/array sanity tests, not a claim of whole-project regression."""
    require(not output.exists(), f'refusing to overwrite legacy check output: {output}')
    output.mkdir(parents=True)
    runner=Runner(output)
    tests=['fp32_pe_trace_tb','fp32_pe_kblock_tb','fp32_pe_hand_2x2_tb',
           'fp32_mac_boundary_tb','fp32_pe_array_2x2_tb','fp32_pe_array_k64_tb']
    results=[]
    with tempfile.TemporaryDirectory(dir=output,prefix='binaries_') as temp:
        for name in tests:
            binary=Path(temp)/(name+'.vvp')
            runner.run([args.iverilog,'-g2012','-s',name,'-o',binary,'-f','rtl/files.f',f'tb/{name}.sv'],ROOT,output/(name+'.compile.log'))
            text=runner.run([args.vvp,binary],ROOT,output/(name+'.simulation.log'))
            require('PASS' in text,f'legacy test missing PASS: {name}')
            results.append({'test':name,'status':'PASS'})
    write_json(output/'run_report.json',{'scope':'six existing single-PE and array sanity tests; NOT full-project regression','tests':results})

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--packet',default='handoff/pe_special_validation_2026-10-20')
    parser.add_argument('--repo',default='build/team_handoff_repo')
    parser.add_argument('--git',default='D:/Git/cmd/git.exe')
    parser.add_argument('--iverilog',default='D:/competition/.tools/iverilog/bin/iverilog.exe')
    parser.add_argument('--vvp',default='D:/competition/.tools/iverilog/bin/vvp.exe')
    parser.add_argument('--replay',action='store_true')
    parser.add_argument('--output')
    parser.add_argument('--legacy-output',help='also run six existing PE/array sanity tests into a new directory')
    args=parser.parse_args()
    packet=Path(__file__).resolve().parent if args.replay else initial_build(args)
    output=Path(args.output).resolve() if args.output else packet/'replay'
    replay(packet,output,args)
    if not args.replay:
        # Nested historical software checksum files are included too; only the
        # top-level list excludes itself. Validation preserves original bytes.
        files=sorted(p for p in packet.rglob('*') if p.is_file() and p!=packet/'SHA256SUMS.txt')
        (packet/'SHA256SUMS.txt').write_text(''.join(f'{digest(p)}  {p.relative_to(packet).as_posix()}\n' for p in files),encoding='ascii',newline='\n')
    if args.legacy_output:
        require(not args.replay,'legacy tests require source workspace, not portable replay')
        prepare_legacy_regression(packet,Path(args.legacy_output).resolve(),args)

if __name__=='__main__':
    main()
