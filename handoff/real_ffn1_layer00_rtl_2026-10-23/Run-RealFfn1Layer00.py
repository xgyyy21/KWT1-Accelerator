"""Run the unchanged FFN1 RTL with a hash-identified real layer-00 handoff.

Uses only the standard library. Never writes expectations into RTL outputs.
Refuses to reuse an output directory, and records native subprocess exits.
"""
from __future__ import annotations

import argparse
import ast
from datetime import datetime
import hashlib
import io
import json
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import time
import zipfile

ROOT = Path(__file__).resolve().parents[1]
TB = "fp32_competition_ffn1_tb"
REF_SHA = "45daa2c620dcd512ffa2380141cf762477ea25846fc0328027827cfa3842fefb"


def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def need(ok, message):
    if not ok:
        raise ValueError(message)


def save(p, value):
    Path(p).write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def now():
    return datetime.now().astimezone().isoformat()


def inspect_input(archive, dest):
    """Copy unmodified zip entries only after checking paths and checksums."""
    with zipfile.ZipFile(archive) as z:
        need(z.testzip() is None, "input ZIP CRC error")
        entries = [e for e in z.infolist() if not e.is_dir()]
        roots = {e.filename.split("/")[0] for e in entries}
        need(len(roots) == 1, "expected one ZIP root")
        prefix = roots.pop() + "/"
        data = {}
        for e in entries:
            name = e.filename[len(prefix):]
            need(name and "/" not in name and "\\" not in name and ":" not in name,
                 "unsafe or unexpected input ZIP path")
            need(name not in data, "duplicate ZIP filename")
            need(e.file_size <= 10_000_000, "unexpectedly large input file")
            data[name] = z.read(e)
    listed = {}
    for line in data["SHA256SUMS.txt"].decode("utf-8-sig").splitlines():
        if line.strip():
            digest, name = line.split(None, 1)
            name = name.strip().lstrip("*")
            need(name not in listed, "duplicate input checksum entry")
            listed[name] = digest.lower()
    need(set(listed) == set(data) - {"SHA256SUMS.txt"}, "input manifest file-set mismatch")
    for name, digest in listed.items():
        need(hashlib.sha256(data[name]).hexdigest() == digest, "input hash mismatch: " + name)
    model = json.loads(data["model_export_manifest.json"])
    pack = json.loads(data["pack_manifest.json"])
    need(hashlib.sha256(data["layer_00.npz"]).hexdigest() == model["layers"][0]["sha256"],
         "NPZ differs from model export record")
    need(hashlib.sha256(data["source_audio.wav"]).hexdigest() == model["input_sha256"],
         "audio differs from export record")
    tensors = {}
    shapes = {"x": (99, 64), "w": (64, 256), "b": (256,)}
    with zipfile.ZipFile(io.BytesIO(data["layer_00.npz"])) as npz:
        for key, shape in shapes.items():
            raw = npz.read(key + ".npy")
            need(raw[:6] == b"\x93NUMPY", "bad NPY magic")
            off = 10 if raw[6] == 1 else 12
            length = int.from_bytes(raw[8:off], "little")
            header = ast.literal_eval(raw[off:off + length].decode("latin1").strip())
            need(header == {"descr": "<f4", "fortran_order": False, "shape": shape},
                 "unexpected NPZ dtype/layout/shape: " + key)
            need(raw[off + length:] == data[key + ".bin"], "NPZ/bin mismatch: " + key)
    for name, count, tbfile in [("x", 6336, "x_fp32.mem"), ("w", 16384, "w_fp32.mem"),
                                 ("b", 256, "bias_fp32.mem"), ("expected", 25344, "expected_fp32.mem")]:
        raw = data[name + ".bin"]
        need(len(raw) == count * 4, "wrong tensor size: " + name)
        bits = list(struct.unpack("<" + "I" * count, raw))
        halves = list(struct.unpack("<" + "H" * (count * 2), raw))
        lines16 = data[name + ".mem"].decode("ascii").splitlines()
        lines32 = data[tbfile].decode("ascii").splitlines()
        need(all(len(s) == 4 for s in lines16), "wrong 16-bit entry width")
        need(all(len(s) == 8 for s in lines32), "wrong 32-bit entry width")
        need(halves == [int(s, 16) for s in lines16], "16-bit/bin mismatch: " + name)
        need(bits == [int(s, 16) for s in lines32], "TB32/bin mismatch: " + name)
        need(all((v & 0x7F800000) != 0x7F800000 for v in bits), "nonfinite input/expectation")
        need(hashlib.sha256(raw).hexdigest() == pack["tensors"][name]["sha256_bin"],
             "pack manifest bin mismatch")
        tensors[name] = {"fp32_elements": count, "halfwords": count * 2,
                         "tb_file": tbfile, "sha256_bin": hashlib.sha256(raw).hexdigest()}
    dest.mkdir()
    for name, contents in data.items():
        (dest / name).write_bytes(contents)
    return {"status": "PASS", "zip_files": len(data), "checksum_entries": len(listed),
            "zip_sha256": sha(archive), "tensors": tensors,
            "entry_check": "32-bit x/w/bias/expected plusargs; low-half-first 16-bit bus memory",
            "scope": "archive internal consistency; no new upstream model/TensorFlow verification"}


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--input-zip", required=True)
    ap.add_argument("--output", required=True)
    a = ap.parse_args()
    archive, out = Path(a.input_zip).resolve(), Path(a.output).resolve()
    need(archive.is_file(), "input ZIP missing")
    need(not out.exists(), "refusing to overwrite output directory")
    out.mkdir(parents=True)
    save(out / "status.json", {"status": "PREPARING", "started_at": now()})
    commands = []

    def command(argv, cwd, log, progress=False):
        argv = [str(x) for x in argv]
        start, tick = now(), time.monotonic()
        record = {"argv": argv, "cwd": str(cwd), "started_at": start,
                  "log": str(log.relative_to(out)), "status": "RUNNING"}
        commands.append(record)
        save(out / "commands.json", commands)
        with log.open("wb") as stream:
            proc = subprocess.Popen(argv, cwd=cwd, stdout=stream, stderr=subprocess.STDOUT)
            record["pid"] = proc.pid
            save(out / "commands.json", commands)
            while True:
                try:
                    code = proc.wait(timeout=30)
                    break
                except subprocess.TimeoutExpired:
                    if progress:
                        tail = log.read_bytes()[-1600:].decode("utf-8", errors="replace").splitlines()
                        print(json.dumps({"elapsed_seconds": round(time.monotonic() - tick, 1),
                                          "pid": proc.pid, "last_log_lines": tail[-2:]}), flush=True)
        record.update(exit_code=code, ended_at=now(), elapsed_seconds=time.monotonic() - tick,
                      status="PASS" if code == 0 else "FAIL", log_sha256=sha(log))
        save(out / "commands.json", commands)
        return record

    try:
        inputs = out / "inputs"
        validation = inspect_input(archive, inputs)
        shutil.copyfile(archive, out / "software_input.zip")
        save(out / "input_validation.json", validation)
        sources = out / "sources"
        paths = ["rtl/files.f", "tb/" + TB + ".sv"] + [
            p.strip() for p in (ROOT / "rtl/files.f").read_text().splitlines() if p.strip()]
        manifest = {}
        for name in paths:
            target = sources / name
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(ROOT / name, target)
            manifest[name] = sha(target)
        save(out / "source_manifest.json", {"identity": "SHA-256 source snapshot; project root is not a Git worktree",
                                            "files": manifest})
        ref = ROOT / "handoff/array_pe_trace_2026-10-20_v2/software_snapshot/software/fp32_reference.py"
        need(sha(ref) == REF_SHA, "fixed software reference hash mismatch")
        (out / "software_reference").mkdir()
        shutil.copyfile(ref, out / "software_reference/fp32_reference.py")
        shutil.copyfile(__file__, out / "Run-RealFfn1Layer00.py")
        sim = out / "simulation"
        sim.mkdir()
        iverilog = ROOT / ".tools/iverilog/bin/iverilog.exe"
        vvp = ROOT / ".tools/iverilog/bin/vvp.exe"
        for tool in [iverilog, vvp]:
            r = command([tool, "-V"], out, out / (tool.stem + "_version.log"))
            need(r["exit_code"] == 0, "tool version command failed")
        binary = sim / "ffn1_real_layer00.vvp"
        r = command([iverilog, "-g2012", "-s", TB, "-o", binary, "-f", "rtl/files.f",
                     "tb/" + TB + ".sv"], sources, sim / "compile.log")
        need(r["exit_code"] == 0, "RTL compile failed")
        save(out / "status.json", {"status": "RTL_RUNNING", "started_at": now(),
                                  "compiled_binary_sha256": sha(binary)})
        argv = [vvp, "-i", binary, "+OUT_DIR=" + sim.as_posix()]
        for arg, name in [("X", "x"), ("W", "w"), ("BIAS", "bias"), ("EXPECTED", "expected")]:
            argv.append("+" + arg + "_FILE=" + (inputs / (name + "_fp32.mem")).as_posix())
        print("Real layer-00 RTL compiled; starting all 208 tiles.", flush=True)
        run = command(argv, out, sim / "ffn1.run.log", progress=True)
        run["binary_sha256"] = sha(binary)
        save(out / "process_completion.json", run)
        need(run["exit_code"] == 0, "RTL simulation failed; see actual log and process_completion.json")
        checker = ROOT / "scripts/Check-RealFfn1Layer00.py"
        need(checker.is_file(), "independent checker is missing")
        shutil.copyfile(checker, out / checker.name)
        check = command([sys.executable, "-B", checker, "--package", out,
                         "--recompute-reference", "--negative-controls"], out, out / "checker.log")
        need(check["exit_code"] == 0, "independent output/reference check failed")
        save(out / "status.json", {"status": "PASS", "completed_at": now(),
                                  "rtl_simulator_exit_code": run["exit_code"],
                                  "checker_exit_code": check["exit_code"],
                                  "software_owner_independent_acceptance": "PENDING"})
        entries = {p.relative_to(out).as_posix(): sha(p) for p in sorted(out.rglob("*"))
                   if p.is_file() and p != out / "SHA256SUMS.txt"}
        (out / "SHA256SUMS.txt").write_text("".join(h + "  " + p + "\n" for p, h in entries.items()), encoding="utf-8")
        print(json.dumps({"status": "PASS", "output": str(out), "files_hashed": len(entries)}), flush=True)
    except Exception as exc:
        save(out / "status.json", {"status": "FAIL", "recorded_at": now(), "error": str(exc),
                                  "actual_artifacts_retained": True})
        raise


if __name__ == "__main__":
    main()
