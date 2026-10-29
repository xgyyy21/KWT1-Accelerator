"""Re-run tests affected by the FFN1 idle-enable optimization. No Git writes."""
from __future__ import annotations
import argparse
import csv
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
TESTS = [
    'fp32_math_boundary_tb', 'fp32_pe_hand_2x2_tb', 'fp32_pe_kblock_tb',
    'fp32_mac_boundary_tb', 'fp32_pe_array_2x2_tb', 'fp32_pe_array_8x16_tb',
    'fp32_pe_array_k64_tb', 'fp32_array_checkpoint_tb',
    'fp32_tile_engine_2x2_tb', 'fp32_tile_cache_8x16_k64_tb',
    'fp32_tile_kblock_load_compute_tb', 'fp32_tile_kblock_load_compute_k256_tb',
    'fp32_accelerator_top_tb', 'fp32_one_tile_k64_tb',
]

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def write_json(path, data):
    path.write_text(json.dumps(data, indent=2, ensure_ascii=False)+'\n', encoding='utf-8')

def need(ok, message):
    if not ok:
        raise ValueError(message)

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True)
    parser.add_argument('--iverilog', default=str(ROOT/'.tools/iverilog/bin/iverilog.exe'))
    parser.add_argument('--vvp', default=str(ROOT/'.tools/iverilog/bin/vvp.exe'))
    parser.add_argument('--git', default='D:/Git/cmd/git.exe')
    args=parser.parse_args()
    out=Path(args.output).resolve()
    need(not out.exists(), f'refusing to overwrite {out}')
    out.mkdir(parents=True)
    records=[]; results=[]
    def command(argv, cwd, log):
        argv=list(map(str,argv)); started=time.monotonic()
        with log.open('wb') as stream:
            p=subprocess.run(argv,cwd=cwd,stdout=stream,stderr=subprocess.STDOUT)
        records.append(dict(argv=argv,cwd=str(cwd),exit_code=p.returncode,
                            elapsed_seconds=time.monotonic()-started,
                            log=str(log.relative_to(out)),log_sha256=sha(log)))
        write_json(out/'commands.json',records)
        need(p.returncode==0,f'command failed: {log}')
        return log.read_text(encoding='utf-8',errors='replace')
    rtl=[p.strip() for p in (ROOT/'rtl/files.f').read_text().splitlines() if p.strip()]
    others=[f'tb/{t}.sv' for t in TESTS]+['tb/support/fp32_idle_equivalence_tb.sv','tb/fp32_array_trace_tb.sv']
    for name in rtl+others:
        target=out/'sources'/name; target.parent.mkdir(parents=True,exist_ok=True)
        shutil.copyfile(ROOT/name,target)
    sources=[out/'sources'/p for p in rtl]
    baseline_dir=out/'sources/baseline'; baseline_dir.mkdir()
    for name in ('fp32_pe_mac','fp32_pe_array_8x16'):
        data=subprocess.check_output([args.git,'-C',str(ROOT/'build/team_handoff_repo'),
                                      'show',f'a4e810d:rtl/{name}.sv'])
        data=data.replace(b'fp32_pe_mac',b'baseline_fp32_pe_mac').replace(
            b'fp32_pe_array_8x16',b'baseline_fp32_pe_array_8x16')
        (baseline_dir/f'{name}.sv').write_bytes(data)
    bins=ROOT/'build/ffn1_completion/prerequisite_bins'; bins.mkdir(parents=True,exist_ok=True)
    command([args.iverilog,'-V'],ROOT,out/'tool_version.log')
    vector=out/'inputs/fp32_boundary_vectors.txt'; vector.parent.mkdir()
    shutil.copyfile(ROOT/'handoff/pe_special_validation_2026-10-20/fp32_boundary_vectors.txt',vector)
    for name in TESTS:
        d=out/name; d.mkdir()
        (d/'build').mkdir()  # legacy trace-only outputs use a relative build/.
        binary=bins/f'{name}.vvp'
        command([args.iverilog,'-g2012','-s',name,'-o',binary,*sources,out/'sources/tb'/f'{name}.sv'],ROOT,d/'compile.log')
        plus=[f'+VECTORS={vector.as_posix()}'] if name=='fp32_math_boundary_tb' else []
        log=command([args.vvp,'-i',binary,*plus],d,d/'simulation.log')
        need('PASS' in log, f'no PASS in {name}')
        results.append(dict(test=name,status='PASS'))
        print(f'PASS {name}',flush=True)
    for rows,cols in ((3,5),(8,16)):
        name=f'idle_equivalence_{rows}x{cols}'; d=out/name; d.mkdir()
        binary=bins/f'{name}.vvp'
        command([args.iverilog,'-g2012','-s','fp32_idle_equivalence_tb',
                 f'-Pfp32_idle_equivalence_tb.ROWS={rows}',f'-Pfp32_idle_equivalence_tb.COLS={cols}',
                 '-o',binary,*sources,baseline_dir/'fp32_pe_mac.sv',
                 baseline_dir/'fp32_pe_array_8x16.sv',out/'sources/tb/support/fp32_idle_equivalence_tb.sv'],ROOT,d/'compile.log')
        log=command([args.vvp,'-i',binary],d,d/'simulation.log')
        need('PASS: idle optimization cycle equivalence' in log,f'no equivalence PASS {name}')
        results.append(dict(test=name,status='PASS',scope='bounded cycle comparison, not formal proof'))
        print(f'PASS {name}',flush=True)
    packet=ROOT/'handoff/array_pe_trace_2026-10-20_v2'
    shutil.copytree(packet/'software_snapshot',out/'software_snapshot',ignore=shutil.ignore_patterns('__pycache__','*.pyc'))
    for spec in json.loads((packet/'cases.json').read_text()):
        name=spec['case_id']; d=out/('array_'+name); d.mkdir()
        inp=out/'inputs'/name; shutil.copytree(packet/'inputs'/name,inp)
        binary=bins/f'array_{name}.vvp'
        parameters=[f'-Pfp32_array_trace_tb.{p}={spec[p]}' for p in
                    ('ROWS','COLS','TOTAL_K','VALID_ROWS','VALID_COLS','ROW_BASE','COL_BASE')]
        command([args.iverilog,'-g2012','-s','fp32_array_trace_tb',*parameters,'-o',binary,
                 *sources,out/'sources/tb/fp32_array_trace_tb.sv'],ROOT,d/'compile.log')
        log=command([args.vvp,'-i',binary,f'+input={inp.as_posix()}',f'+output={d.as_posix()}',
                     f'+case={name}','+revision=ffn1-idle-enable-source-hashes',
                     f'+manifest={sha(inp/"manifest.json")}',
                     f'+reference={sha(inp/"expected_traces.json")}'],d,d/'simulation.log')
        need(f'PASS case={name}' in log and 'RESET_ABORT_CHECK PASS' in log,f'array assertions {name}')
        command([sys.executable,'-B','-m','software.compare_pe_trace',
                 '--expected',inp/'expected_pe_trace.csv','--actual',d/'pe_trace.csv',
                 '--compare-tile-id','--report',d/'comparison.json'],out/'software_snapshot',d/'comparison.log')
        comparison=json.loads((d/'comparison.json').read_text())
        need(comparison['status']=='BIT-EXACT-CANDIDATE',f'array numerical mismatch {name}')
        with (d/'pe_trace.csv').open(newline='') as f:
            count=sum(1 for _ in csv.DictReader(f))
        results.append(dict(test='array_'+name,status='PASS',events=count,
                            software_owner_independent_acceptance='PENDING'))
        print(f'PASS array_{name} events={count}',flush=True)
    # Verify live source did not change while the source snapshots were tested.
    need(all(sha(ROOT/p)==sha(out/'sources'/p) for p in rtl+others),'live sources changed during run')
    write_json(out/'summary.json',dict(status='PASS',passed=len(results),failed=0,tests=results,
               baseline='a4e810d',first_difference=None,
               scope='affected-RTL regression only; full FFN1 has separate evidence'))
    entries={p.relative_to(out).as_posix():sha(p) for p in sorted(out.rglob('*')) if p.is_file()}
    (out/'SHA256SUMS.txt').write_text(''.join(f'{h}  {p}\n' for p,h in entries.items()),encoding='ascii')
    print(f'PASS prerequisites={len(results)}',flush=True)

if __name__=='__main__':
    main()
