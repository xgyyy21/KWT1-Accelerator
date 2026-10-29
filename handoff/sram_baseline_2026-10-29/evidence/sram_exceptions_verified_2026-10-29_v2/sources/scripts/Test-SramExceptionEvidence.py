"""Snapshot and actually simulate SRAM, fault-prototype and register tests."""
import argparse
import csv
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parent.parent
TESTS = {
    "sram_fp32_cache_adapter": ["rtl/sram_1024x16_adapter.sv", "rtl/sram_fp32_cache_adapter.sv",
        "tb/support/ramsp128x16_functional_model.sv", "tb/sram_fp32_cache_adapter_tb.sv"],
    "fp32_bus_fault_guard": ["rtl/prototype/fp32_bus_fault_guard.sv", "tb/fp32_bus_fault_guard_tb.sv"],
    "fp32_tile_soc_bus_adapter": ["rtl/fp32_tile_soc_bus_adapter.sv", "tb/fp32_tile_soc_bus_adapter_tb.sv"],
    "ai_engine_regs": ["rtl/ai_engine_pkg.sv", "rtl/ai_engine_regs.sv", "tb/ai_engine_regs_tb.sv"],
    "fp32_tile_kblock_fsm": ["rtl/fp32_tile_kblock_fsm.sv", "tb/fp32_tile_kblock_fsm_tb.sv"],
}
PASS_MARKERS = {
    "sram_fp32_cache_adapter": "PASS sram_fp32_cache_adapter ",
    "fp32_bus_fault_guard": "PASS fp32_bus_fault_guard ",
    "fp32_tile_soc_bus_adapter": "fp32_tile_soc_bus_adapter_tb PASS ",
    "ai_engine_regs": "ai_engine_regs_tb PASS",
    "fp32_tile_kblock_fsm": "PASS: fp32_tile_kblock_fsm ",
}

def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def manifest(base, name):
    with (base / name).open("w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["Path", "Bytes", "SHA256"])
        for p in sorted(base.rglob("*")):
            if p.is_file() and p != base / name:
                w.writerow([p.relative_to(base).as_posix(), p.stat().st_size, digest(p)])

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", required=True)
    parser.add_argument("--icarus-bin", default=".tools/iverilog/bin")
    args = parser.parse_args()
    out = (ROOT / args.output).resolve()
    if not out.is_relative_to(ROOT) or out == ROOT:
        raise ValueError("output must be a new child directory of project root")
    out.mkdir(exist_ok=False, parents=True)
    snap = out / "sources"
    sources = sorted({s for paths in TESTS.values() for s in paths} |
                     {"scripts/Test-SramExceptionEvidence.py"})
    for name in sources:
        target = snap / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(ROOT / name, target)
        if digest(target) != digest(ROOT / name):
            raise RuntimeError("source copy mismatch: " + name)
    manifest(snap, "source_manifest.csv")
    binpath = (ROOT / args.icarus_bin).resolve()
    iv, vvp = str(binpath / "iverilog.exe"), str(binpath / "vvp.exe")
    commands = []
    def run(cmd, log):
        commands.append({"cwd": str(snap), "argv": cmd})
        with log.open("w", encoding="utf-8") as f:
            result = subprocess.run(cmd, cwd=snap, stdout=f, stderr=subprocess.STDOUT)
        return result.returncode
    run([iv, "-V"], out / "iverilog_version.log")
    run([vvp, "-V"], out / "vvp_version.log")
    results = []
    for name, paths in TESTS.items():
        image = out / (name + ".vvp")
        compile_rc = run([iv, "-g2012", "-Wall", "-s", name + "_tb", "-o", str(image)] + paths,
                         out / (name + ".compile.log"))
        sim_rc = None
        passed = False
        if compile_rc == 0:
            log = out / (name + ".simulation.log")
            sim_rc = run([vvp, str(image), "+trace=" + str(out / (name + ".trace.csv"))], log)
            passed = sim_rc == 0 and PASS_MARKERS[name] in log.read_text(encoding="utf-8")
        results.append({"test": name, "compile_exit_code": compile_rc,
                        "simulation_exit_code": sim_rc, "pass": passed})
        print(json.dumps(results[-1]), flush=True)
    status = {"tests": results, "passed": sum(x["pass"] for x in results),
              "failed": sum(not x["pass"] for x in results),
              "scope": "Functional models and standalone fault guard; no vendor timing or E203",
              "fault_guard_integrated_in_accelerator_top": False}
    (out / "commands.json").write_text(json.dumps(commands, indent=2), encoding="utf-8")
    (out / "status.json").write_text(json.dumps(status, indent=2), encoding="utf-8")
    manifest(out, "evidence_sha256.csv")
    return 0 if not status["failed"] else 1

if __name__ == "__main__":
    sys.exit(main())
