"""Build/replay a byte-pinned single-PE evidence packet. No commit or push.

Initial build: python scripts/Build-PeFormalHandoff.py --repo build/team_handoff_repo
Replay copied packet: python Replay.py --replay --output <new empty directory>
Requires Python >=3.10, Git (build only), and Icarus Verilog.
"""
from __future__ import annotations
import argparse
import csv
import hashlib
import importlib
import io
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
HW = '13a924ca77be7016e61d87cc83981752838cf8e2'
SW = 'd11d169ea6f7b8500d6a2186c803d0f1a5eba709'
MANIFEST = '148ac9b305c34dafd033ea33d98b4f0a13edbf1306c66d29c7926ed348941e93'
REFERENCE = 'a85bb5b7d334841acab94740290933bd3a991b881acf8782615cb8c43f73553b'
HEADER = 'source_kind,case_id,tile_id,row,column,event,cycle,valid,k,x_bits,w_bits,acc_before_bits,product_bits,acc_after_bits,bias_bits,result_bits,rtl_commit,input_manifest_sha256,reference_trace_sha256'.split(',')

def require(condition, message):
    if not condition:
        raise ValueError(message)

def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def write_json(path, value):
    Path(path).write_text(json.dumps(value, ensure_ascii=False, indent=2)+'\n', encoding='utf-8')

def git_blob(git, repo, commit, path):
    return subprocess.check_output([git, '-C', str(repo), 'cat-file', 'blob', f'{commit}:{path}'], stderr=subprocess.PIPE)

def git_paths(git, repo, commit, path):
    return subprocess.check_output([git, '-C', str(repo), 'ls-tree', '-r', '--name-only', commit, path]).decode('utf-8').splitlines()

def export_blob(git, repo, commit, source, target):
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(git_blob(git, repo, commit, source))

def inventory(packet):
    return {p.relative_to(packet).as_posix(): digest(p) for p in sorted(packet.rglob('*'))
            if p.is_file() and '__pycache__' not in p.parts and p.name != 'SHA256SUMS.txt'}

def validate_input(packet):
    inputs = packet/'inputs'
    require(digest(inputs/'manifest.json') == MANIFEST, 'raw manifest bytes changed')
    require(digest(inputs/'expected_traces.json') == REFERENCE, 'raw reference bytes changed')
    manifest = json.loads((inputs/'manifest.json').read_bytes())
    reports = []
    for name in ('x', 'w', 'bias'):
        entry = manifest['tensors'][name]
        raw = (inputs/f'{name}.bin').read_bytes()
        words = (inputs/f'{name}.mem').read_text(encoding='ascii').split()
        require(len(words) == entry['word_count'], f'{name} word count mismatch')
        require([w.lower() for w in words] == entry['words_hex'], f'{name} manifest words mismatch')
        require(b''.join(int(w,16).to_bytes(2,'little') for w in words) == raw, f'{name} mem/bin mismatch')
        require(digest(inputs/f'{name}.bin') == entry['sha256_bin'], f'{name} bin hash mismatch')
        reports.append({'tensor':name, 'shape':entry['shape'], 'bin_sha256':digest(inputs/f'{name}.bin'),
                        'mem_sha256':digest(inputs/f'{name}.mem'), 'loaded_by_tb':f'inputs/{name}.mem',
                        'mapping':'row-major; FP32={word[2*i+1],word[2*i]}; low 16-bit word first'})
    return reports

def initial_build(args):
    root = Path(__file__).resolve().parents[1]
    packet = Path(args.packet).resolve()
    require(not packet.exists(), f'Will not overwrite existing packet: {packet}')
    repo = Path(args.repo).resolve()
    packet.mkdir(parents=True)
    software_files = [
        'software/compare_pe_trace.py','software/fp32_reference.py',
        'software/examples/__init__.py','software/examples/fp32_trace_csv.py',
        'software/examples/fp32_step_traces.py','software/examples/fp32_hand_example.py',
        'software/tests/test_compare_pe_trace.py',
        'software/tests/test_fp32_trace_csv.py','software/tests/test_fp32_step_traces.py',
    ]
    software_files += git_paths(args.git,repo,SW,'software/examples/fp32_hand_image')
    for path in software_files:
        export_blob(args.git,repo,SW,path,packet/'software_snapshot'/path)
    for path in git_paths(args.git,repo,SW,'software/examples/fp32_hand_image'):
        export_blob(args.git,repo,SW,path,packet/'inputs'/Path(path).name)
    historical = 'handoff/fp32_hand_2x2_pe_material_2026-10-19'
    for path in git_paths(args.git,repo,HW,historical):
        export_blob(args.git,repo,HW,path,packet/'historical_18col'/Path(path).relative_to(historical))
    compiled = ['rtl/fp32_math_pkg.sv','rtl/fp32_pe_mac.sv','tb/fp32_pe_formal_tb.sv']
    source_entries = []
    for path in compiled:
        destination = packet/'sources'/path
        destination.parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(root/path,destination)
        try:
            base_hash = hashlib.sha256(git_blob(args.git,repo,HW,path)).hexdigest()
        except subprocess.CalledProcessError:
            base_hash = None
        source_entries.append({'file':f'sources/{path}', 'sha256':digest(destination),
                               'base_git_blob_sha256':base_hash,
                               'matches_base_git_blob':base_hash==digest(destination)})
    (packet/'filelist.f').write_text(''.join(f'sources/{p}\n' for p in compiled),encoding='ascii')
    shutil.copyfile(__file__,packet/'Replay.py')
    shutil.copyfile(root/'handoff/PE_TRACE_CONTRACT_ACCEPTED_2026-10-20.md',packet/'CONTRACT.md')
    shutil.copyfile(root/'handoff/PE_FORMAL_HANDOFF_README_2026-10-20.md',packet/'README.md')
    reply='KWT-1_软件回复硬件_PE_Trace合同与后续交付_2026-10-19(1).md'
    shutil.copyfile(root/reply,packet/'software_reply_original.md')
    revision = HW+'+dirty'
    write_json(packet/'provenance.json',{
        'hardware_base_commit':HW, 'software_commit':SW, 'csv_rtl_commit':revision,
        'workspace':'D:/competition is not a Git repository; hardware base taken from independent clone',
        'dirty_reason':'new formal testbench is not committed; exact compiled source snapshot is included',
        'compiled_sources':source_entries, 'input_manifest_sha256':MANIFEST,
        'reference_trace_sha256':REFERENCE,
        'git_status_of_clone':subprocess.check_output([args.git,'-C',str(repo),'status','--porcelain']).decode('utf-8'),
        'note':'A clean clone does not imply uncommitted source workspace is clean. No new commit/push made.'})
    return packet

def run_tool(command, cwd, log):
    env = dict(os.environ, PYTHONDONTWRITEBYTECODE='1')
    process = subprocess.run([str(p) for p in command],cwd=cwd,stdout=subprocess.PIPE,
                             stderr=subprocess.STDOUT,env=env)
    Path(log).write_bytes(process.stdout)
    require(process.returncode == 0, f'Command failed ({process.returncode}); see {log}')
    return process.stdout.decode('utf-8',errors='replace')

def read_csv(path):
    with Path(path).open(encoding='ascii',newline='') as stream:
        reader=csv.DictReader(stream)
        rows=list(reader)
        require(all(None not in row and all(v is not None for v in row.values()) for row in rows), 'wrong column count')
        return reader.fieldnames, rows

def validate_signals(output, revision):
    fields, rows=read_csv(output/'pe_trace.csv')
    require(fields==HEADER, '19-column header mismatch')
    require(len(rows)==12, 'expected 12 measured events')
    require(all(r['rtl_commit']==revision and r['source_kind']=='rtl_measured' for r in rows),'wrong source identity')
    _, signals=read_csv(output/'signal_trace.csv')
    require(len({r['cycle'] for r in signals})==len(signals),'duplicate signal cycle')
    require([int(r['cycle']) for r in signals]==sorted(int(r['cycle']) for r in signals),'non-monotonic cycle')
    measured=[r for r in signals if r['trace_valid']=='1' or r['trace_bias_valid']=='1']
    require(len(measured)==12, 'signal event count mismatch')
    for event, signal in zip(rows,measured):
        require(event['cycle']==signal['cycle']==signal['trace_cycle'], 'event/signal cycle mismatch')
        require(event['row']==signal['row'] and event['column']==signal['column'], 'coordinate mismatch')
        if event['event']=='mac':
            require(signal['trace_valid']=='1' and signal['trace_bias_valid']=='0' and signal['result_valid']=='0', 'MAC valid mismatch')
            require(event['k']==signal['trace_k'], 'global K mapping mismatch')
        else:
            require(signal['trace_bias_valid']=='1' and signal['trace_valid']=='0' and signal['result_valid']=='1' and signal['done']=='1', 'bias/result alignment mismatch')
        require(event['tile_id']=='0','K=2 tile_id must be zero')
    timing=[]
    for row in range(2):
        for col in range(2):
            cell=[r for r in signals if (int(r['row']),int(r['column']))==(row,col)]
            accepted=[int(r['cycle']) for r in cell if r['input_accept']=='1']
            mul=[int(r['cycle']) for r in cell if r['mul_ready']=='1']
            issue=[int(r['cycle']) for r in cell if r['add_issue']=='1' and r['add_is_bias']=='0']
            commits=[int(r['cycle']) for r in cell if r['trace_valid']=='1']
            bias_issue=[int(r['cycle']) for r in cell if r['add_issue']=='1' and r['add_is_bias']=='1']
            bias=[int(r['cycle']) for r in cell if r['trace_bias_valid']=='1']
            require(tuple(map(len,(accepted,mul,issue,commits,bias_issue,bias)))==(2,2,2,2,1,1), 'stage event count mismatch')
            require(all(b-a==8 for a,b in zip(accepted,mul)),'multiplier latency mismatch')
            require(all(b-a==4 for a,b in zip(issue,commits)) and bias[0]-bias_issue[0]==4,'adder latency mismatch')
            require(commits[1]<bias[0],'bias order mismatch')
            timing.append({'row':row,'column':col,'input_accept':accepted,'mul_buffer_write':mul,
                           'add_issue':issue,'mac_commit':commits,'bias_issue':bias_issue[0],'bias_commit':bias[0]})
    return {'status':'PASS','scope':'K=2 hand_2x2 measured valid/data alignment and 8/4 cycle functional boundaries',
            'events':12,'mac':8,'bias':4,'cells':timing,'physical_timing_closed':False}

def negative_checks(compare_module, golden, actual, output):
    _, original=read_csv(actual)
    results=[]
    with tempfile.TemporaryDirectory(dir=output,prefix='negative_test_only_') as temp:
        path=Path(temp)/'mutated_not_hardware_evidence.csv'
        for kind in ('wrong_tile','wrong_value','missing_bias','duplicate_event','wrong_manifest'):
            rows=[dict(r) for r in original]
            if kind=='wrong_tile': rows[0]['tile_id']='1'
            elif kind=='wrong_value': rows[0]['product_bits']='0x00000000'
            elif kind=='missing_bias': rows=[r for r in rows if not (r['event']=='bias' and r['row']=='0' and r['column']=='0')]
            elif kind=='duplicate_event': rows.append(dict(rows[0]))
            else: rows[0]['input_manifest_sha256']='0'*64
            with path.open('w',encoding='ascii',newline='') as stream:
                writer=csv.DictWriter(stream,HEADER,lineterminator='\n'); writer.writeheader(); writer.writerows(rows)
            try:
                report=compare_module.compare(golden,path,case_id='hand_2x2',compare_tile_id=True)
                require(report['status']=='MISMATCH',f'checker accepted negative test: {kind}')
                detail=report['first_mismatch']
            except compare_module.TraceContractError as exc:
                detail=str(exc)
            results.append({'test':kind,'status':'REJECTED_AS_EXPECTED','detail':detail})
    return {'scope':'artificial corruption of a copy; not measured hardware evidence','tests':results}

def replay(packet, output, args):
    require(not output.exists(),f'Will not overwrite replay output: {output}')
    # Full checksum validation before executing any bundled source on replay.
    sums=packet/'SHA256SUMS.txt'
    if args.replay:
        require(sums.exists(),'missing packet checksums')
        for line in sums.read_text(encoding='ascii').splitlines():
            expected,rel=line.split('  ',1)
            require(digest(packet/rel)==expected,f'packet checksum failed: {rel}')
    output.mkdir(parents=True)
    inputs=validate_input(packet)
    write_json(output/'input_validation.json',{'status':'PASS','raw_manifest_sha256':MANIFEST,'raw_reference_sha256':REFERENCE,'tensors':inputs})
    provenance=json.loads((packet/'provenance.json').read_text(encoding='utf-8'))
    for entry in provenance['compiled_sources']:
        require(digest(packet/entry['file'])==entry['sha256'], 'compiled source hash mismatch')
    revision=provenance['csv_rtl_commit']
    commands=[]
    for tool,name in ((args.iverilog,'iverilog_version.log'),(args.vvp,'vvp_version.log')):
        command=[tool,'-V']; commands.append(command)
        run_tool(command,packet,output/name)
    write_json(output/'python_version.json',{'executable':sys.executable,'version':sys.version})
    # Temporary binary is disposable and not a deliverable; sources are kept.
    with tempfile.TemporaryDirectory(dir=output,prefix='compile_') as temp:
        binary=Path(temp)/'pe.vvp'
        command=[args.iverilog,'-g2012','-s','fp32_pe_formal_tb','-o',str(binary),'-f','filelist.f']
        commands.append(command); run_tool(command,packet,output/'compile.log')
        command=[args.vvp,str(binary),f'+INPUT_DIR={(packet/"inputs").as_posix()}',
                 f'+OUTPUT_DIR={output.as_posix()}',f'+RTL_REVISION={revision}',
                 f'+MANIFEST_SHA={MANIFEST}',f'+REFERENCE_SHA={REFERENCE}']
        commands.append(command); sim=run_tool(command,packet,output/'simulation.log')
        require('fp32_pe_formal_tb PASS' in sim,'simulation did not complete')
    snapshot=packet/'software_snapshot'
    golden=snapshot/'software/examples/fp32_hand_image/expected_pe_trace_demo.csv'
    require(digest(snapshot/'software/examples/fp32_hand_image/manifest.json')==MANIFEST,'software manifest mismatch')
    require(digest(snapshot/'software/examples/fp32_hand_image/expected_traces.json')==REFERENCE,'software reference mismatch')
    command=[sys.executable,'-B','-m','software.compare_pe_trace','--expected',str(golden),
             '--actual',str(output/'pe_trace.csv'),'--case-id','hand_2x2','--compare-tile-id','--report',str(output/'compare_report.json')]
    commands.append(command); run_tool(command,snapshot,output/'compare.log')
    comparison=json.loads((output/'compare_report.json').read_text(encoding='utf-8'))
    require(comparison['status']=='BIT-EXACT-CANDIDATE' and comparison['expected_events']==12 and comparison['actual_events']==12,'unexpected comparator report')
    timing=validate_signals(output,revision)
    write_json(output/'timing_report.json',timing)
    sys.path.insert(0,str(snapshot))
    compare_module=importlib.import_module('software.compare_pe_trace')
    write_json(output/'negative_checker_report.json',negative_checks(compare_module,golden,output/'pe_trace.csv',output))
    command=[sys.executable,'-B','-m','unittest','software.tests.test_compare_pe_trace','software.tests.test_fp32_trace_csv','software.tests.test_fp32_step_traces']
    commands.append(command); run_tool(command,snapshot,output/'software_checker_tests.log')
    write_json(output/'commands.json',{'commands':commands,'cwd_compile_sim':str(packet),'cwd_software_tools':str(snapshot)})
    report={'status':'PASS_HAND_2X2_19_COLUMN_LOCAL_CHECK','scope':'single PE K=2 only; software owner independent acceptance pending',
            'csv_sha256':digest(output/'pe_trace.csv'),'csv_columns':19,'mac_events':8,'bias_events':4,
            'software_compare_status':comparison['status'],'compare_tile_id':True,
            'timing_check':'PASS functional 8-clock multiplier boundary and 4-clock dependent add boundary',
            'not_verified':['rounding_nonfused case','K32 boundary','SRAM partial sum save/restore','full subnormal/signed-zero coverage','array','SoC','150 MHz synthesis timing'],
            'rtl_revision':revision,'software_commit':SW,'input_manifest_sha256':MANIFEST,'reference_trace_sha256':REFERENCE}
    write_json(output/'run_report.json',report)
    print(json.dumps(report,ensure_ascii=False,indent=2))

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--repo',default='build/team_handoff_repo')
    parser.add_argument('--git',default='D:/Git/cmd/git.exe')
    parser.add_argument('--packet',default='handoff/pe_hand_2x2_formal_2026-10-20')
    parser.add_argument('--iverilog',default='D:/competition/.tools/iverilog/bin/iverilog.exe')
    parser.add_argument('--vvp',default='D:/competition/.tools/iverilog/bin/vvp.exe')
    parser.add_argument('--replay',action='store_true')
    parser.add_argument('--output')
    args=parser.parse_args()
    packet=Path(__file__).resolve().parent if args.replay else initial_build(args)
    output=Path(args.output).resolve() if args.output else packet/'replay'
    replay(packet,output,args)
    if not args.replay:
        (packet/'SHA256SUMS.txt').write_text(''.join(f'{sha}  {path}\n' for path,sha in inventory(packet).items()),encoding='ascii')

if __name__=='__main__':
    main()
