"""Stage 4A adapter: run the hardware team's unchanged PowerShell regression.

Offline, stdlib only. Sources are hash-checked then copied to unique scratch space.
The native-tool proxy records commands/exit codes; it contains no test logic.
"""
from __future__ import annotations

import argparse
from collections import Counter
from datetime import datetime, timedelta, timezone
import hashlib
import json
from pathlib import Path
import re
import shutil
import subprocess
import sys
from uuid import uuid4

ROOT = Path(__file__).resolve().parents[1]
TZ = timezone(timedelta(hours=8))


def now():
    return datetime.now(TZ).isoformat()


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def execute(argv, cwd, timeout=120):
    rec = {"argv": list(map(str, argv)), "cwd": str(cwd), "started_at": now()}
    try:
        p = subprocess.run(rec["argv"], cwd=cwd, capture_output=True, timeout=timeout)
        rec.update(returncode=p.returncode,
                   stdout=p.stdout.decode("utf-8", errors="replace"),
                   stderr=p.stderr.decode("utf-8", errors="replace"))
    except subprocess.TimeoutExpired as exc:
        rec.update(returncode=None, error=f"timeout after {timeout}s",
                   stdout=(exc.stdout or b"").decode("utf-8", errors="replace"),
                   stderr=(exc.stderr or b"").decode("utf-8", errors="replace"))
    except OSError as exc:
        rec.update(returncode=None, error=str(exc), stdout="", stderr="")
    rec["finished_at"] = now()
    return rec


def capture_native():
    # Called by generated .cmd wrappers, sequentially by the original script.
    tool, log, *args = sys.argv[2:]
    rec = execute([tool, *args], Path.cwd())
    with Path(log).open("a", encoding="utf-8") as stream:
        stream.write(json.dumps(rec, ensure_ascii=False) + "\n")
    sys.stdout.buffer.write(rec["stdout"].encode("utf-8"))
    sys.stderr.buffer.write(rec["stderr"].encode("utf-8"))
    return rec["returncode"] if rec["returncode"] is not None else 2


def classify(name, compile_rec, sim_rec):
    if compile_rec is None:
        return "BLOCKED"
    if compile_rec["returncode"] is None:
        return "BLOCKED" if "timeout" not in compile_rec.get("error", "") else "FAIL"
    if compile_rec["returncode"] != 0:
        return "FAIL"
    if sim_rec is None:
        return "BLOCKED"
    marker = re.search(rf"(?m)^{re.escape(name)} PASS(?:\s|$)", sim_rec["stdout"])
    return "PASS" if sim_rec["returncode"] == 0 and marker else "FAIL"


def run(source, manifest, iverilog=None, vvp=None, context="unspecified"):
    stamp = datetime.now(TZ).strftime("%Y%m%d_%H%M%S") + "_" + uuid4().hex[:8]
    out = ROOT / "reports/stage4a/runs" / stamp
    out.mkdir(parents=True)
    scratch = ROOT / "tmp/stage4a_runs" / stamp
    scratch.mkdir(parents=True)
    source, manifest = Path(source).resolve(), Path(manifest).resolve()
    report = {"schema_version": 1, "scope": "hardware module regression only",
              "started_at": now(), "execution_context": context,
              "status": "BLOCKED", "source": str(source), "scratch": str(scratch),
              "adapter_sha256": sha(__file__), "commands": [], "tests": [],
              "coverage_exclusions": ["complete FP32 array", "FFN1 with bias/cross-K",
                                      "E203 integration", "12 layers", "synthesis/PPA"],
              "report_path": str(out / "report.json")}
    report["integration_git"] = {key: execute(argv, ROOT) for key, argv in {
        "head": ["git", "rev-parse", "HEAD"],
        "branch": ["git", "branch", "--show-current"],
        "status": ["git", "status", "--porcelain=v1", "--untracked-files=all"],
    }.items()}
    try:
        metadata = json.loads(manifest.read_text(encoding="utf-8"))
        report.update(hardware_commit=metadata["commit"], hardware_tree=metadata["tree"],
                      manifest=str(manifest), manifest_sha256=sha(manifest))
        selected = []
        for folder in ("rtl", "tb", "scripts"):
            selected.extend(p for p in (source / folder).rglob("*") if p.is_file())
        selected.append(source / "docs/HARDWARE_IMPORT_HANDOFF.md")
        required = {"rtl/files.f", "scripts/Run-Regression.ps1", "scripts/Generate-Fp32Vectors.ps1"}
        paths = {p.relative_to(source).as_posix() for p in selected}
        if not required <= paths or not list((source / "tb").glob("*_tb.sv")):
            raise ValueError("Missing hardware scripts, file list, or testbenches")
        inputs = {}
        for p in sorted(selected):
            relative = p.relative_to(source).as_posix()
            if p.is_symlink() or not p.resolve().is_relative_to(source):
                raise ValueError(f"Unsupported source link: {relative}")
            digest = sha(p)
            if digest != metadata["files"][relative]["sha256"]:
                raise ValueError(f"Input differs from commit manifest: {relative}")
            inputs[relative] = digest
            target = scratch / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(p, target)
        report["inputs_sha256"] = inputs
        report["input_verification"] = "PASS"
        tests = sorted(p.stem for p in (scratch / "tb").glob("*_tb.sv"))
        report["discovered_tests"] = tests
        tools = {"iverilog": iverilog or shutil.which("iverilog"),
                 "vvp": vvp or shutil.which("vvp"),
                 "powershell": shutil.which("powershell")}
        report["tools"] = tools
        if not all(tools.values()):
            raise ValueError("Missing tools: " + ", ".join(k for k, v in tools.items() if not v))
        report["versions"] = {name: execute([tools[name], "-V"], scratch)
                              for name in ("iverilog", "vvp")}
        report["powershell_version"] = execute(
            [tools["powershell"], "-NoProfile", "-Command", "$PSVersionTable | Out-String"], scratch)
        # This explicit generation with cwd=scratch follows the handoff workaround.
        generate = [tools["powershell"], "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
                    str(scratch / "scripts/Generate-Fp32Vectors.ps1"),
                    "-OutputPath", str(scratch / "build/fp32_vectors.txt")]
        report["commands"].append(execute(generate, scratch))
        native_log = out / "native_commands.jsonl"
        wrappers = {}
        for name in ("iverilog", "vvp"):
            wrapper = scratch / (name + "_capture.cmd")
            parts = [sys.executable, str(Path(__file__).resolve()), "_capture", tools[name], str(native_log)]
            # All wrapper paths are local trusted inputs; cmd metacharacters are rejected.
            if any(any(c in part for c in '\r\n"%&|<>^!') for part in parts):
                raise ValueError("Tool/wrapper path contains unsupported cmd characters")
            wrapper.write_text("@echo off\n@" + " ".join('"' + p + '"' for p in parts) +
                               " %*\n@exit /b %errorlevel%\n", encoding="utf-8")
            wrappers[name] = str(wrapper)
        regression = [tools["powershell"], "-NoProfile", "-ExecutionPolicy", "Bypass", "-File",
                      str(scratch / "scripts/Run-Regression.ps1"),
                      "-Iverilog", wrappers["iverilog"], "-Vvp", wrappers["vvp"]]
        # Individual native children have a 120s timeout; original TBs also have watchdogs.
        report["commands"].append(execute(regression, scratch, timeout=max(300, len(tests) * 250)))
        native = ([json.loads(line) for line in native_log.read_text(encoding="utf-8").splitlines()]
                  if native_log.exists() else [])
        for name in tests:
            comp = next((c for c in native if "-s" in c["argv"] and
                         c["argv"][c["argv"].index("-s") + 1] == name), None)
            sim = next((c for c in native if len(c["argv"]) == 2 and
                        c["argv"][1].replace("\\", "/") == f"build/{name}.vvp"), None)
            report["tests"].append({"name": name, "status": classify(name, comp, sim),
                                    "compile_exit": comp["returncode"] if comp else None,
                                    "simulation_exit": sim["returncode"] if sim else None,
                                    "logs": [str(p) for p in (out / "logs").glob(name + ".*.log")]})
        soc = next((c for c in native if "ai_engine_soc_adapter" in c["argv"]), None)
        report["soc_elaboration"] = {"status": "PASS" if soc and soc["returncode"] == 0 else "FAIL",
                                     "returncode": soc["returncode"] if soc else None,
                                     "scope": "compile/elaboration only; no E203 simulation"}
        vectors = scratch / "build/fp32_vectors.txt"
        if vectors.exists():
            report["vectors"] = {"path": str(vectors), "sha256": sha(vectors),
                                 "pairs": len(vectors.read_text().splitlines()),
                                 "generator": "scripts/Generate-Fp32Vectors.ps1",
                                 "seed": "0x12345678", "edge_pairs": "21 x 21",
                                 "random_pairs_default": 20000,
                                 "reference": ".NET Single separate add/mul, canonical NaN"}
        logs = scratch / "build/logs"
        if logs.exists():
            shutil.copytree(logs, out / "logs")
        for t in report["tests"]:
            t["logs"] = [str(p) for p in (out / "logs").glob(t["name"] + ".*.log")]
        report["source_unchanged"] = all(sha(source / p) == h and sha(scratch / p) == h
                                         for p, h in inputs.items())
        statuses = [t["status"] for t in report["tests"]]
        report["status"] = ("FAIL" if "FAIL" in statuses or not report["source_unchanged"] or
                            report["soc_elaboration"]["status"] == "FAIL" else
                            "BLOCKED" if "BLOCKED" in statuses else "PASS")
        if report["commands"][-1]["returncode"] != 0 and report["status"] == "PASS":
            report["status"] = "FAIL"
        if report["commands"][0]["returncode"] != 0:
            report["status"] = "FAIL"
    except (OSError, ValueError, KeyError) as exc:
        report["error"] = str(exc)
    report["counts"] = {s: sum(t["status"] == s for t in report["tests"])
                        for s in ("PASS", "FAIL", "BLOCKED", "NOT_RUN")}
    report["test_count"] = len(report.get("discovered_tests", []))
    report["failed_modules"] = [t["name"] for t in report["tests"] if t["status"] == "FAIL"]
    report["exit_code"] = {"PASS": 0, "FAIL": 1, "BLOCKED": 2}[report["status"]]
    report["finished_at"] = now()
    (out / "report.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (out / "commands.log").write_text("\n\n".join(json.dumps(c, ensure_ascii=False, indent=2)
                                                for c in report["commands"]) + "\n", encoding="utf-8")
    print(f"Hardware modules: {report['status']}; tests={report['test_count']}; {report['counts']}")
    print(f"Report: {out / 'report.json'}")
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--manifest", type=Path, default=ROOT / "reports/stage4a/hardware_manifest.json")
    parser.add_argument("--iverilog")
    parser.add_argument("--vvp")
    parser.add_argument("--context", default="unspecified")
    args = parser.parse_args()
    return run(args.source, args.manifest, args.iverilog, args.vvp, args.context)["exit_code"]


if __name__ == "__main__":
    raise SystemExit(capture_native() if sys.argv[1:2] == ["_capture"] else main())
