"""Build two local, hash-verified handoff archives without Git operations."""
import csv
import hashlib
import json
from pathlib import Path
import shutil
import zipfile

ROOT = Path(__file__).resolve().parent.parent
FULL = "build/sram_two_layers_verilator_2026-10-29_v1"
CHECK = "build/sram_two_layers_reference_check_2026-10-29_v1"
EXCEPT = "build/sram_exceptions_verified_2026-10-29_v2"
LINT = "build/sram_macro_mode_lint_2026-10-29_v1"
DOCS = ["SRAM宏规格基线_2026-10-28.md", "SRAM_16位单端口协议与适配层_2026-10-28.md",
        "SRAM_FP32_容量与地址映射_2026-10-28.md", "memory_layout_v1_2026-10-25.md",
        "control_interface_v1_2026-10-25.md", "给软件同学_连续任务与16位SRAM联调材料_2026-10-29.md",
        "给综合同学_固定RTL与16位SRAM交接材料_2026-10-29.md"]

def stream_sha(f):
    h = hashlib.sha256()
    for block in iter(lambda: f.read(1024*1024), b""):
        h.update(block)
    return h.hexdigest()

def sha(p):
    with p.open("rb") as f:
        return stream_sha(f)

def copy(source, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists():
        if sha(destination) != sha(source):
            raise RuntimeError("Conflicting source copies: " + str(destination))
        return
    shutil.copyfile(source, destination)
    if sha(source) != sha(destination):
        raise RuntimeError("Copy mismatch: " + str(source))

def copy_tree(source, destination):
    for p in sorted(source.rglob("*")):
        if p.is_file():
            copy(p, destination / p.relative_to(source))

def write_manifest(base, target, files):
    rows = []
    for p in sorted(files):
        rows.append(dict(Path=p.relative_to(base).as_posix(), Bytes=p.stat().st_size, SHA256=sha(p)))
    with target.open("w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=["Path", "Bytes", "SHA256"])
        writer.writeheader()
        writer.writerows(rows)
    return rows

def verify_manifest(base, path, file_key="Path"):
    with path.open(encoding="utf-8-sig", newline="") as f:
        rows = list(csv.DictReader(f))
    for row in rows:
        p = base / row[file_key]
        if not p.is_file() or sha(p).lower() != row["SHA256"].lower():
            raise RuntimeError("Manifest mismatch: " + str(p))
    return len(rows)

def main():
    # Validate existing frozen evidence before exporting it.
    counts = {}
    counts["full_run"] = verify_manifest(ROOT/FULL, ROOT/FULL/"evidence_sha256.csv")
    counts["full_sources"] = verify_manifest(ROOT/FULL/"sources", ROOT/FULL/"source_manifest.csv")
    counts["exception_run"] = verify_manifest(ROOT/EXCEPT, ROOT/EXCEPT/"evidence_sha256.csv")
    counts["exception_sources"] = verify_manifest(ROOT/EXCEPT/"sources", ROOT/EXCEPT/"sources/source_manifest.csv")
    old_manifest = json.loads((ROOT/CHECK/"sha256.json").read_text(encoding="utf-8"))
    for name, expected in old_manifest.items():
        if sha(ROOT/CHECK/name) != expected:
            raise RuntimeError("Reference archive hash mismatch: " + name)
    for p in (ROOT/FULL/"sources/rtl").rglob("*"):
        if p.is_file() and sha(p) != sha(ROOT/"rtl"/p.relative_to(ROOT/FULL/"sources/rtl")):
            raise RuntimeError("Main RTL changed since full run: " + str(p))
    required = sum(p.stat().st_size for dirname in (FULL,CHECK,EXCEPT,LINT)
                   for p in (ROOT/dirname).rglob("*") if p.is_file()) * 5
    if shutil.disk_usage(ROOT).free < required:
        raise RuntimeError("Insufficient space for copies, ZIPs and verification")
    outputs = []
    for role, readme in (
        ("software", "给软件同学_连续任务与16位SRAM联调材料_2026-10-29.md"),
        ("synthesis", "给综合同学_固定RTL与16位SRAM交接材料_2026-10-29.md"),
    ):
        destination = ROOT/"handoff"/(role+"_sram_delivery_2026-10-29_v2")
        archive = destination.with_suffix(".zip")
        if destination.exists() or archive.exists():
            raise RuntimeError("Refusing to overwrite delivery: " + str(destination))
        destination.mkdir()
        copy_tree(ROOT/FULL/"sources", destination)
        # Only additions or byte-identical RTL may overlay the full-run tree.
        # Exception TB updates were compiled from this separate frozen source.
        copy_tree(ROOT/EXCEPT/"sources", destination)
        for name in ("scripts/Check-SramTopEvidence.py", "scripts/Run-SramSynthesisLint.sh",
                     "scripts/Package-SramDelivery.py"):
            copy(ROOT/name, destination/name)
        copy(ROOT/CHECK/"fp32_reference.py", destination/"reference/fp32_reference.py")
        copy_tree(ROOT/"things about sram", destination/"reference/sram_manual")
        copy(ROOT/"handoff/constraints/fp32_sram_exploratory.sdc", destination/"constraints/fp32_sram_exploratory.sdc")
        for dirname in (FULL,CHECK,EXCEPT,LINT):
            copy_tree(ROOT/dirname, destination/dirname)
        for name in DOCS:
            copy(ROOT/"handoff"/name, destination/"docs"/name)
        copy(ROOT/"handoff"/readme, destination/"README.md")
        # Root manifest generated here must not collide with nested evidence manifests.
        source_files = [p for name in ("rtl","tb","scripts","reference","constraints")
                        for p in (destination/name).rglob("*") if p.is_file()]
        # copy_tree above brought an exception-source manifest to the root.
        # Retain it under docs instead of confusing it with the whole-source manifest.
        existing_manifest = destination/"source_manifest.csv"
        if existing_manifest.exists():
            copy(existing_manifest, destination/"docs/exception_source_manifest.csv")
        write_manifest(destination, existing_manifest, source_files)
        identity = sha(existing_manifest)
        version = {"id": "local-sram-2026-10-29-"+identity[:12], "git_commit": None,
                   "source_manifest_sha256": identity, "main_rtl_matches_full_simulation": True,
                   "macro_mode": True, "top": "fp32_accelerator_top", "filelist": "rtl/files.f",
                   "parameters": {"ADDR_WIDTH":32,"DATA_WIDTH":32,"USE_SRAM_MACROS":1,
                                  "STRICT_COMPETITION_SHAPES":1},
                   "prototype_fault_guard_in_main_top": False}
        (destination/"VERSION.json").write_text(json.dumps(version,indent=2)+"\n",encoding="utf-8")
        (destination/"verification.json").write_text(json.dumps({
            "original_evidence_manifest_entries_verified":counts,
            "scope":"Archive integrity; not a new RTL simulation or software-independent acceptance",
            "two_job_outputs_matched":31680, "two_job_halfwords_matched":63360,
            "targeted_tests_passed":5,"targeted_tests_failed":0,
            "lint_exit_code":int((ROOT/LINT/"exit_code.txt").read_text().strip()),
            "vendor_timing_model":False,"e203_integration":False},indent=2)+"\n",encoding="utf-8")
        inventory = write_manifest(destination, destination/"package_manifest.csv",
                                   [p for p in destination.rglob("*") if p.is_file()])
        verify_manifest(destination, destination/"package_manifest.csv")
        print("Copy hashes verified: "+role+", files="+str(len(inventory)),flush=True)
        with zipfile.ZipFile(archive,"x",compression=zipfile.ZIP_DEFLATED,compresslevel=6) as z:
            for p in sorted(destination.rglob("*")):
                if p.is_file():
                    z.write(p,p.relative_to(destination).as_posix())
        with zipfile.ZipFile(archive) as z:
            expected_names = {r["Path"] for r in inventory}|{"package_manifest.csv"}
            if set(z.namelist()) != expected_names:
                raise RuntimeError("ZIP inventory mismatch")
            for row in inventory:
                with z.open(row["Path"]) as f:
                    if stream_sha(f) != row["SHA256"]:
                        raise RuntimeError("ZIP payload hash mismatch: "+row["Path"])
            with z.open("package_manifest.csv") as f:
                if stream_sha(f) != sha(destination/"package_manifest.csv"):
                    raise RuntimeError("ZIP manifest hash mismatch")
        outputs.append({"file":archive.name,"bytes":archive.stat().st_size,"sha256":sha(archive),
                        "version":version["id"],"files":len(inventory)+1,"zip_payloads_verified":True})
        print(json.dumps(outputs[-1]),flush=True)
    (ROOT/"handoff/delivery_packages_2026-10-29_v2.sha256").write_text(
        "".join(x["sha256"]+"  "+x["file"]+"\n" for x in outputs),encoding="utf-8")
    (ROOT/"handoff/delivery_packages_2026-10-29_v2.json").write_text(
        json.dumps(outputs,indent=2)+"\n",encoding="utf-8")

if __name__ == "__main__":
    main()
