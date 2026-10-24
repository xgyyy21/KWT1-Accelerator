"""Build/replay real 8x16 PE-array SRAM checkpoint evidence.

Build: python scripts/Run-PartialSumCheckpoint.py
Replay: python <packet>/Replay.py --replay --output <new-empty-directory>
Requires Python >=3.10 and Icarus Verilog. This does not commit or push.
"""
from __future__ import annotations
import argparse
import csv
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys

FILES = ['rtl/fp32_math_pkg.sv','rtl/fp32_pe_mac.sv','rtl/fp32_pe_array_8x16.sv',
         'rtl/matrix_cache_manager.sv','tb/fp32_array_checkpoint_tb.sv']

def need(ok, message):
    if not ok: raise ValueError(message)

def digest(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def json_write(path, value): Path(path).write_text(json.dumps(value,indent=2,ensure_ascii=False)+'\n',encoding='utf-8')

def inventory(root):
    return {p.relative_to(root).as_posix():digest(p) for p in sorted(root.rglob('*'))
            if p.is_file() and p.name!='SHA256SUMS.txt'}

def execute(argv,cwd,log,commands):
    argv=[str(x) for x in argv]
    p=subprocess.run(argv,cwd=cwd,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,
                     env=dict(os.environ,PYTHONDONTWRITEBYTECODE='1'))
    Path(log).write_bytes(p.stdout)
    commands.append({'argv':argv,'cwd':str(cwd),'exit_code':p.returncode,
                     'log':str(log),'log_sha256':digest(log)})
    need(p.returncode==0,f'command failed ({p.returncode}): {log}')
    return p.stdout.decode('utf-8',errors='replace')

def check_trace(run, simulation_log):
    path=run/'checkpoint_trace.csv'
    with path.open(encoding='ascii',newline='') as f: rows=list(csv.DictReader(f))
    need(len(rows)==1536,f'expected 1536 SRAM trace records, got {len(rows)}')
    writes=[r for r in rows if r['kind'].strip()=='write']
    reads=[r for r in rows if r['kind'].strip()=='read_request']
    responses=[r for r in rows if r['kind'].strip()=='read_response']
    need(len(writes)==len(reads)==len(responses)==512,'SRAM transaction count mismatch')
    for i,row in enumerate(writes):
        need(int(row['address'])==i and row['we']=='1',f'write address/order mismatch at {i}')
        expect=('0000','4200','0000','3f80')[i%4]
        need(row['wdata'].lower()=='0x'+expect,f'partial/bias save data mismatch at {i}')
    for i,row in enumerate(reads):
        need(int(row['address'])==i,f'read request address/order mismatch at {i}')
    for i,row in enumerate(responses):
        need(int(row['address'])==i,f'read response address/order mismatch at {i}')
        expect=('0000','4200','0000','3f80')[i%4]
        need(row['rdata'].lower()=='0x'+expect,f'read response data mismatch at {i}')
    with (run/'checkpoint_result.csv').open(encoding='ascii',newline='') as f: outputs=list(csv.DictReader(f))
    need(len(outputs)==1 and outputs[0]['result_bits'].lower()=='0x42c20000','final restored computation mismatch')
    log=Path(simulation_log).read_text(encoding='utf-8',errors='replace')
    need('PASS: SRAM checkpoint save=512 read=512 restored_cells=128 result=0x42c20000' in log,'PASS record missing')
    return {'status':'PASS','sram_write_halfwords':len(writes),'sram_read_requests':len(reads),
            'sram_read_responses':len(responses),'restored_pes':128,'final_outputs':128,
            'expected_each_output':'0x42c20000','first_mismatch':None,
            'flow':'K32 -> save partial sum and bias to SRAM -> reset PE array -> read SRAM -> restore -> K32 -> bias/complete',
            'sram_reset_behavior':'matrix_cache_manager resets read response only; stored words persist reset',
            'scope_limit':'array-level test; checkpoint port is not yet wired through the top-level tile/FSM/DMA path'}

def run(packet,out,args):
    need(not out.exists(),f'will not overwrite {out}')
    out.mkdir(parents=True)
    commands=[]
    for tool in (args.iverilog,args.vvp):
        execute([tool,'-V'],packet,out/(Path(tool).stem+'_version.log'),commands)
    json_write(out/'python_version.json',{'executable':sys.executable,'version':sys.version})
    run_dir=out/'run';run_dir.mkdir()
    exe=Path(args.iverilog)
    argv=[exe,'-g2012','-s','fp32_array_checkpoint_tb','-o',run_dir/'simulation.vvp']
    argv += [f'sources/{name}' for name in FILES]
    execute(argv,packet,out/'compile.log',commands)
    execute([args.vvp,run_dir/'simulation.vvp'],run_dir,out/'simulation.log',commands)
    summary=check_trace(run_dir,out/'simulation.log')
    json_write(out/'summary.json',summary)
    json_write(out/'commands.json',commands)
    return summary

def seal(packet):
    files=inventory(packet)
    (packet/'SHA256SUMS.txt').write_text(''.join(f'{h}  {name}\n' for name,h in files.items()),encoding='utf-8')
    return len(files)

def verify(packet):
    lines=(packet/'SHA256SUMS.txt').read_text(encoding='utf-8').splitlines()
    for line in lines:
        expected,name=line.split('  ',1)
        need(digest(packet/name)==expected,f'checksum mismatch: {name}')
    return len(lines)

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--packet',default='handoff/partial_sum_checkpoint_2026-10-20_v4')
    p.add_argument('--replay',action='store_true')
    p.add_argument('--output')
    root=Path(__file__).resolve().parents[1]
    p.add_argument('--iverilog',default=str(root/'.tools/iverilog/bin/iverilog.exe'))
    p.add_argument('--vvp',default=str(root/'.tools/iverilog/bin/vvp.exe'))
    args=p.parse_args()
    if args.replay:
        packet=Path(__file__).resolve().parent
        count=verify(packet)
        need(args.output,'--replay requires --output new directory')
        result=run(packet,Path(args.output).resolve(),args)
        for name in ('checkpoint_trace.csv','checkpoint_result.csv'):
            need(digest(Path(args.output)/'run'/name)==digest(packet/'evidence'/'run'/name),f'replay output differs: {name}')
        json_write(Path(args.output)/'replay_integrity.json',{'source_packet_files_verified':count,
            'sram_trace_byte_identical':True,'result_byte_identical':True,'summary':result})
    else:
        root=Path(__file__).resolve().parents[1]
        packet=Path(args.packet).resolve()
        need(not packet.exists(),f'will not overwrite {packet}')
        packet.mkdir(parents=True)
        sources=packet/'sources'
        for name in FILES:
            dest=sources/name;dest.parent.mkdir(parents=True,exist_ok=True)
            shutil.copyfile(root/name,dest)
        (packet/'filelist.f').write_text(''.join(f'sources/{name}\n' for name in FILES),encoding='ascii')
        shutil.copyfile(__file__,packet/'Replay.py')
        shutil.copyfile(root/'handoff/PARTIAL_SUM_CHECKPOINT_EXPERIMENTAL_2026-10-20.md',packet/'README.md')
        json_write(packet/'provenance.json',{'hardware_git_base':'241968c2989a280c04b0877bbb3d58dadc631588',
            'rtl_revision':'241968c2989a280c04b0877bbb3d58dadc631588+dirty',
            'local_workspace':'D:/competition is not a Git worktree; exact simulated source snapshot is included',
            'simulation_sources':{name:digest(sources/name) for name in FILES},
            'checkpoint_architecture':'array-level sequential 16-bit access to matrix_cache_manager result SRAM bank',
            'top_level_integration':'not connected to fp32_tile_kblock_load_compute / top FSM / DMA yet',
            'commit_or_push':False})
        summary=run(packet,packet/'evidence',args)
        count=seal(packet);need(verify(packet)==count,'packet checksum verification failed')
        print(json.dumps(summary,indent=2,ensure_ascii=False))

if __name__=='__main__': main()
