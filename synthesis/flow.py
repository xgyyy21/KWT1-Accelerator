"""Stage 3A: local probes and generic Yosys practice; no official PPA backend."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime, timezone, timedelta
from uuid import uuid4

ROOT = Path(__file__).resolve().parents[1]
BASE = ROOT / "synthesis"
TZ = timezone(timedelta(hours=8))


def now():
    return datetime.now(TZ).isoformat()


def decode(value):
    if not value:
        return ""
    if value.count(b"\0") > len(value) // 5:
        return value.decode("utf-16", errors="replace").lstrip("\ufeff")
    for encoding in ("utf-8", "gb18030"):
        try:
            return value.decode(encoding)
        except UnicodeDecodeError:
            pass
    return value.decode("utf-8", errors="replace")


def execute(argv, cwd=ROOT, timeout=20):
    rec = {"argv": list(map(str, argv)), "cwd": str(cwd), "started_at": now()}
    try:
        p = subprocess.run(rec["argv"], cwd=cwd, capture_output=True, timeout=timeout)
        rec.update(returncode=p.returncode, stdout=decode(p.stdout), stderr=decode(p.stderr),
                   status="PASS" if p.returncode == 0 else "FAIL")
    except subprocess.TimeoutExpired as exc:
        rec.update(returncode=None, stdout=decode(exc.stdout), stderr=decode(exc.stderr),
                   status="FAIL", error=f"timeout after {timeout}s")
    except OSError as exc:
        rec.update(returncode=None, stdout="", stderr="", status="BLOCKED", error=str(exc))
    rec["finished_at"] = now()
    return rec


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def identity(path):
    p = Path(path).resolve()
    return {"path": str(p), "sha256": sha(p), "bytes": p.stat().st_size}


def snapshot():
    results = {k: execute(v) for k, v in {
        "commit": ["git", "rev-parse", "HEAD"],
        "branch": ["git", "branch", "--show-current"],
        "worktree": ["git", "status", "--porcelain=v1", "--untracked-files=all"],
    }.items()}
    return {"commit": results["commit"]["stdout"].strip() or None,
            "branch": results["branch"]["stdout"].strip() or None,
            "dirty": bool(results["worktree"]["stdout"].strip()), "commands": results}


def directory(kind):
    p = BASE / "runs" / (datetime.now(TZ).strftime("%Y%m%d_%H%M%S") + "_" + kind + "_" + uuid4().hex[:8])
    p.mkdir(parents=True)
    return p


def save(out, report, commands):
    report["finished_at"] = now()
    report["commands"] = commands
    (out / "report.json").write_text(json.dumps(report, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    with (out / "commands.log").open("w", encoding="utf-8") as f:
        for c in commands:
            f.write(f"\n{c['started_at']} cwd={c['cwd']}\nargv={json.dumps(c['argv'], ensure_ascii=False)}\n")
            f.write(f"status={c['status']} exit={c['returncode']} {c.get('error', '')}\n")
            f.write("STDOUT:\n" + c["stdout"] + "\nSTDERR:\n" + c["stderr"] + "\n")
    print(f"{report['status']}: {out.relative_to(ROOT).as_posix()}/report.json")
    return {"PASS": 0, "FAIL": 1, "BLOCKED": 2, "NOT_RUN": 2}[report["status"]]


def probe(args):
    out = directory("environment")
    commands = []
    report = {"schema_version": 1, "kind": "environment", "started_at": now(),
              "git": snapshot(), "runner": identity(__file__), "tools": {},
              "execution_context": args.context}
    specs = {"yosys": ["-V"], "dc_shell": ["-version"], "dc_shell-t": ["-version"],
             "genus": ["-version"], "verilator": ["--version"],
             "iverilog": ["-V"], "vvp": ["-V"], "git": ["--version"],
             "python": ["--version"], "wsl": ["--version"], "docker": ["--version"]}
    paths = {}
    for name, flags in specs.items():
        path = shutil.which(name)
        paths[name] = path
        rec = execute([path or name] + flags)
        commands.append(rec)
        report["tools"][name] = {"resolved_path": path, "version_probe": rec,
                                 "usability": "NOT_RUN" if rec["status"] == "PASS" else rec["status"]}
    for name, argv in (
        ("git", [paths["git"] or "git", "rev-parse", "--is-inside-work-tree"]),
        ("python", [paths["python"] or "python", "-c", "import sys,json,hashlib,tempfile,subprocess; print(sys.version); print(sys.executable); assert sys.version_info >= (3,11); print('PYTHON_STDLIB_OK')"]),
        ("wsl_status", [paths["wsl"] or "wsl", "--status"]),
        ("wsl_distros", [paths["wsl"] or "wsl", "--list", "--quiet"]),
        ("docker_version", [paths["docker"] or "docker", "version"]),
        ("docker_daemon", [paths["docker"] or "docker", "info", "--format", "{{.ServerVersion}} {{.OSType}}"]),
    ):
        rec = execute(argv)
        commands.append(rec)
        report["tools"].setdefault(name, {})["functional_probe"] = rec
        report["tools"][name]["usability"] = rec["status"]
    if report["tools"]["docker_daemon"]["usability"] == "PASS":
        rec = execute([paths["docker"], "image", "ls", "--format", "{{.Repository}}:{{.Tag}} {{.ID}}"])
        commands.append(rec)
        report["tools"]["docker_local_images"] = {"functional_probe": rec, "usability": rec["status"]}
    # Do not start an unregistered distro, enable WSL, start Docker or pull images.
    distros = report["tools"]["wsl_distros"]["functional_probe"]
    if distros["status"] == "PASS" and distros["stdout"].strip():
        rec = execute([paths["wsl"], "--exec", "sh", "-lc",
                       "uname -s; cat /etc/os-release; for t in yosys dc_shell genus verilator iverilog; do if command -v \"$t\"; then case \"$t\" in yosys|iverilog) \"$t\" -V;; verilator) \"$t\" --version;; *) \"$t\" -version;; esac; else printf 'MISSING %s\\n' \"$t\"; fi; done"])
        commands.append(rec)
        report["tools"]["wsl_shell"] = {"functional_probe": rec, "usability": rec["status"]}
        report["tools"]["wsl"]["usability"] = rec["status"]
    report["tools"]["docker"]["usability"] = report["tools"]["docker_daemon"]["usability"]
    if paths["iverilog"] and paths["vvp"]:
        with tempfile.TemporaryDirectory(prefix="iverilog_", dir=out) as td:
            p = Path(td)
            (p / "probe.v").write_text('module probe; initial begin $display("STAGE3A_ICARUS_OK"); $finish; end endmodule\n', encoding="ascii")
            compile_rec = execute([paths["iverilog"], "-g2012", "-s", "probe", "-o", "probe.vvp", "probe.v"], p)
            commands.append(compile_rec)
            steps = [compile_rec]
            if compile_rec["status"] == "PASS":
                run_rec = execute([paths["vvp"], "probe.vvp"], p)
                commands.append(run_rec)
                steps.append(run_rec)
            ok = len(steps) == 2 and all(c["status"] == "PASS" for c in steps) and "STAGE3A_ICARUS_OK" in steps[-1]["stdout"]
            report["tools"]["iverilog"]["usability"] = "PASS" if ok else "FAIL"
            report["tools"]["iverilog"]["compile_run"] = steps
            report["tools"]["vvp"]["usability"] = steps[-1]["status"] if len(steps) == 2 else "NOT_RUN"
    if paths["yosys"]:
        rec = execute([paths["yosys"], "-Q", "-T", "-p", "read_verilog synthesis/smoke/smoke.v; hierarchy -check -top smoke; synth -top smoke; check -assert; stat"], timeout=60)
        commands.append(rec)
        report["tools"]["yosys"]["usability"] = rec["status"]
    if paths["verilator"]:
        rec = execute([paths["verilator"], "--lint-only", "--top-module", "smoke", str(BASE / "smoke/smoke.v")])
        commands.append(rec)
        report["tools"]["verilator"]["usability"] = rec["status"]
    report["search_scope"] = "PATH and explicitly listed local candidate directories; not a whole-machine or remote-server inventory"
    candidates = [Path(x) for x in ("C:/oss-cad-suite/bin/yosys.exe", "D:/oss-cad-suite/bin/yosys.exe", "C:/tools/oss-cad-suite/bin/yosys.exe",
                  "C:/msys64/mingw64/bin/yosys.exe", "C:/msys64/ucrt64/bin/yosys.exe",
                  str(Path.home() / "scoop/apps/yosys/current/bin/yosys.exe"))]
    report["local_candidates"] = [{"path": str(p), "exists": p.is_file()} for p in candidates]
    report["assets"] = {}
    for key, folder in (("KWT_E203_DIR", "e203"), ("KWT_TECH_LIB_DIR", "techlib"), ("KWT_SRAM_LIB_DIR", "sram")):
        p = Path(os.environ.get(key, ROOT / "external" / folder)).resolve()
        report["assets"][folder] = {"path": str(p), "exists": p.is_dir(),
                                     "files": sorted(str(f.relative_to(p)) for f in p.rglob("*") if f.is_file()) if p.is_dir() else []}
    # Probe completion is distinct from readiness. Missing required tools remain BLOCKED.
    report["status"] = "PASS" if report["tools"]["yosys"]["usability"] == "PASS" else "BLOCKED"
    return save(out, report, commands)


def metric(reason):
    return {"status": "BLOCKED", "value": None, "reason": reason, "evidence": None}


def yosys_quote(path):
    s = Path(path).resolve().as_posix()
    if any(x in s for x in ('"', '\n', '\r')):
        raise ValueError("Yosys input paths must not contain quotes or newlines")
    return '"' + s + '"'


def run(args):
    out = directory("generic")
    commands = []
    report = {"schema_version": 1, "kind": "generic_logic_only", "label": args.label,
              "started_at": now(), "git": snapshot(), "runner": identity(__file__),
              "invocation": [sys.executable] + sys.argv, "status": "BLOCKED",
              "synthesis": {"status": "NOT_RUN"}, "top": args.top, "inputs": [],
              "constraints": {"status": "NOT_RUN", "version": None, "applied": False,
                              "target_frequency_mhz": 150, "target_period_ns": "1000/150",
                              "note": "Metadata only: generic synthesis does not read SDC or check timing"},
              "ppa": {"area_mm2": metric("Designated standard-cell/SRAM libraries and scope missing"),
                      "timing_slack_ns": metric("No technology mapping or STA backend"),
                      "power_mw": metric("No power backend, activity, libraries or operating conditions"),
                      "critical_path": metric("No STA backend or valid constraints applied")},
              "generic_resources": {"status": "NOT_RUN", "value": None},
              "netlist": {"status": "NOT_RUN", "value": None}}
    try:
        if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_$]*", args.top):
            raise ValueError("unsupported top identifier")
        manifest = Path(args.files).resolve()
        report["filelist"] = identity(manifest)
        sources = []
        for line in manifest.read_text(encoding="utf-8-sig").splitlines():
            name = line.strip()
            if not name or name.startswith("#"):
                continue
            if name.startswith(("+", "-")):
                raise ValueError("filelist accepts one literal source path per line, not compiler options")
            p = (manifest.parent / name).resolve()
            sources.append(p)
            report["inputs"].append(identity(p))
        if not sources:
            raise ValueError("empty filelist")
        if args.sdc:
            report["constraints"].update(identity(args.sdc), version=sha(args.sdc), status="NOT_RUN")
        tool = shutil.which(args.tool)
        report["tool"] = {"requested": args.tool, "resolved_path": tool}
        version = execute([tool or args.tool, "-V"])
        commands.append(version)
        report["tool"]["version_probe"] = version
        if version["status"] != "PASS":
            report["synthesis"]["status"] = "BLOCKED"
            report["reason"] = "Yosys unavailable; no installation/download attempted"
            return save(out, report, commands)
        script = out / "run.ys"
        script.write_text("\n".join(
            [f"read_verilog -sv {yosys_quote(p)}" for p in sources] +
            [f"hierarchy -check -top {args.top}", f"synth -top {args.top}",
             "check -assert", "tee -o stat.json stat -json", "write_verilog -noattr netlist.v", ""]), encoding="utf-8")
        report["script"] = identity(script)
        rec = execute([tool, "-Q", "-T", "-s", str(script)], out, args.timeout)
        commands.append(rec)
        report["synthesis"]["status"] = rec["status"]
        report["status"] = rec["status"]
        if rec["status"] != "PASS":
            report["netlist"]["status"] = rec["status"]
        net = out / "netlist.v"
        if rec["status"] == "PASS":
            if not net.is_file() or net.stat().st_size == 0 or not re.search(r"\bmodule\s+" + re.escape(args.top) + r"\s*\(", net.read_text(encoding="utf-8")):
                raise ValueError("Yosys returned success but expected nonempty top netlist was not generated")
            report["netlist"] = {"status": "PASS", "value": identity(net),
                                  "note": "Structural output check; not RTL/netlist functional equivalence"}
            stat = json.loads((out / "stat.json").read_text(encoding="utf-8"))
            report["generic_resources"] = {"status": "PASS", "value": stat, "evidence": "stat.json",
                                           "note": "Generic cell counts only; not official area"}
    except (OSError, ValueError) as exc:
        report.update(status="FAIL", reason=str(exc))
        if report["synthesis"]["status"] == "PASS":
            report["netlist"]["status"] = "FAIL"
    return save(out, report, commands)


def compare(args):
    reports = [json.loads(Path(p).read_text(encoding="utf-8")) for p in args.reports]
    print("| Label | Commit | Synthesis | Generic cells | Area mm2 | Slack ns | Power mW | Critical path |")
    print("|---|---|---|---|---|---|---|---|")
    for r in reports:
        resources = r.get("generic_resources", {})
        cells = resources.get("value") or {}
        count = cells.get("design", {}).get("num_cells")
        if count is None:
            count = cells.get("modules", {}).get("\\" + r.get("top", ""), {}).get("num_cells", resources.get("status", "NOT_RUN"))
        ppa = r.get("ppa", {})
        values = [p.get("value") if p.get("status") == "PASS" and p.get("value") is not None else p.get("status", "NOT_RUN")
                  for p in (ppa.get(k, {}) for k in ("area_mm2", "timing_slack_ns", "power_mw", "critical_path"))]
        fields = [r.get("label", ""), (r.get("git", {}).get("commit") or "UNKNOWN")[:12], r.get("synthesis", {}).get("status", "NOT_RUN"), count] + values
        print("| " + " | ".join(str(f).replace("|", "/").replace("\n", " ") for f in fields) + " |")
    print("\nGeneric practice only. Compare matching tools, constraints, libraries, task windows and configurations after review; no official PPA inference.")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("probe", help="Read-only local tool execution; no installation")
    p.add_argument("--context", default="current process", help="Human supplied context label, not privilege detection")
    p.set_defaults(func=probe)
    p = sub.add_parser("run", help="Generic Yosys practice only; never technology-mapped PPA")
    p.add_argument("--top", default="smoke")
    p.add_argument("--files", default=str(BASE / "smoke/files.f"))
    p.add_argument("--label", default="smoke")
    p.add_argument("--tool", default="yosys", help="Existing Yosys executable name/path")
    p.add_argument("--sdc", help="Record hash only; NOT applied in generic backend")
    p.add_argument("--timeout", type=int, default=120)
    p.set_defaults(func=run)
    p = sub.add_parser("compare", help="Print side-by-side run states without invented PPA")
    p.add_argument("reports", nargs="+")
    p.set_defaults(func=compare)
    args = parser.parse_args()
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
