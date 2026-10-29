"""Independently check actual RTL CSVs against the supplied expected.bin.

Never trusts the CSV's match/expected_bits as the golden result. Also checks
actual memory-load snapshots, tile/write order, final memory and DONE timing.
"""
from __future__ import annotations

import argparse
import copy
import csv
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import struct
import time
import zipfile

M, K, N = 99, 64, 256
Y_BASE = 210000  # Verified internal 16-bit-word base in the archived TB; not a CPU address.
REF_SHA = "45daa2c620dcd512ffa2380141cf762477ea25846fc0328027827cfa3842fefb"
OUTPUT_FIELDS = "row,column,word_address,result_bits,expected_bits,match".split(",")
WRITE_FIELDS = "cycle,tile_id,row,column,word_address,half,actual_word".split(",")
TILE_FIELDS = "cycle,tile_id,row_base,column_base,rows_valid,cols_valid,k_blocks".split(",")


class CheckFailure(ValueError):
    def __init__(self, message, detail=None):
        super().__init__(message)
        self.detail = detail


def need(ok, message, detail=None):
    if not ok:
        raise CheckFailure(message, detail)


def sha(p):
    return hashlib.sha256(Path(p).read_bytes()).hexdigest()


def save(p, obj):
    Path(p).write_text(json.dumps(obj, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def words32(p, count):
    data = Path(p).read_bytes()
    need(len(data) == 4 * count, "wrong binary size: " + str(p))
    return list(struct.unpack("<" + "I" * count, data))


def rows(p, fields):
    with Path(p).open(encoding="ascii", newline="") as f:
        reader = csv.DictReader(f)
        need(reader.fieldnames == fields, "unexpected CSV columns: " + str(p))
        result = list(reader)
    need(all(None not in row and None not in row.values() for row in result), "malformed CSV")
    return result


def check_outputs(output, gold):
    need(len(output) == M * N, "output count mismatch")
    first = None
    mismatches = 0
    for i, row in enumerate(output):
        r, c = divmod(i, N)
        need((int(row["row"]), int(row["column"])) == (r, c), "output coordinates/order/duplicates")
        need(int(row["word_address"]) == Y_BASE + 2 * i, "output word address mismatch")
        actual = int(row["result_bits"], 16)
        if actual != gold[i]:
            mismatches += 1
            if first is None:
                first = {"t": r, "j": c, "k": None,
                         "expected_bits": f"0x{gold[i]:08x}", "actual_bits": f"0x{actual:08x}",
                         "note": "final-output CSV does not observe individual K events"}
        need(int(row["expected_bits"], 16) == gold[i], "TB expected column differs from software binary")
    need(mismatches == 0, "RTL output bit mismatch", {"count": mismatches, "first_difference": first})


def write_order():
    tile = 0
    for rb in range(0, M, 8):
        for cb in range(0, N, 16):
            for r in range(rb, min(rb + 8, M)):
                for c in range(cb, cb + 16):
                    for half in (0, 1):
                        yield tile, r, c, Y_BASE + 2 * (r * N + c) + half, half
            tile += 1


def check_writes(writes, output, gold):
    need(len(writes) == M * N * 2, "write halfword count mismatch")
    written = {}
    last_cycle = -1
    for i, (row, expected) in enumerate(zip(writes, write_order())):
        actual = tuple(int(row[f]) for f in ("tile_id", "row", "column", "word_address", "half"))
        need(actual == expected, "write coordinate/address/order mismatch", {"index": i, "actual": actual, "expected": expected})
        tile, r, c, addr, half = expected
        cycle = int(row["cycle"])
        need(cycle > last_cycle, "write cycles not strictly increasing")
        last_cycle = cycle
        word = int(row["actual_word"], 16)
        expected_word = (gold[r * N + c] >> (half * 16)) & 0xFFFF
        need(word == expected_word, "write halfword data mismatch",
             {"t": r, "j": c, "word_address": addr, "half": half,
              "actual": f"0x{word:04x}", "expected": f"0x{expected_word:04x}"})
        need(addr not in written, "duplicate write address")
        written[addr] = word
    need(set(written) == set(range(Y_BASE, Y_BASE + M * N * 2)), "incomplete output address window")
    for i, row in enumerate(output):
        addr = Y_BASE + 2 * i
        need(written[addr] | (written[addr + 1] << 16) == int(row["result_bits"], 16),
             "accepted writes differ from final memory output")
    return last_cycle


def check_tiles(tiles):
    need(len(tiles) == 208, "wrong tile count")
    last = -1
    for i, row in enumerate(tiles):
        rb, cb = (i // 16) * 8, (i % 16) * 16
        actual = tuple(int(row[f]) for f in ("tile_id", "row_base", "column_base", "rows_valid", "cols_valid", "k_blocks"))
        need(actual == (i, rb, cb, min(8, M - rb), 16, 2), "wrong tile descriptor/tail/K block count")
        need(int(row["cycle"]) > last, "tile launch cycles not increasing")
        last = int(row["cycle"])


def check_log(text, last_write):
    need(not re.search(r"FATAL|FAIL|ERROR|WARNING", text), "simulation error/warning marker")
    found = re.findall(r"PASS: FFN1 full layer m=(\d+) k=(\d+) n=(\d+) tiles=(\d+) outputs=(\d+) writes=(\d+) cycles=(\d+)", text)
    need(len(found) == 1, "missing/duplicate final RTL PASS")
    shape = tuple(map(int, found[0]))
    need(shape[:6] == (M, K, N, 208, M * N, M * N * 2), "RTL final count mismatch")
    timing = re.findall(r"PASS: FFN1 read_halfwords=(\d+) unique_write_halfwords=(\d+) tail_rows=(\d+) last_write_cycle=(\d+) done_cycle=(\d+)", text)
    need(len(timing) == 1, "missing/duplicate RTL DONE/write timing record")
    reads, unique, tail, logged_write, done = map(int, timing[0])
    need((reads, unique, tail) == (642048, M * N * 2, 3), "RTL read/unique-write/tail count mismatch")
    need(logged_write == last_write and done > last_write, "DONE is not after final accepted write")
    return {"simulated_wait_cycles": shape[-1], "input_read_halfwords": reads,
            "final_write_cycle": last_write, "done_cycle": done}


def recompute_reference(package, gold):
    reference = package / "software_reference/fp32_reference.py"
    need(sha(reference) == REF_SHA, "software reference hash mismatch")
    spec = importlib.util.spec_from_file_location("fixed_reference", reference)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    x = words32(package / "inputs/x.bin", M * K)
    w = words32(package / "inputs/w.bin", K * N)
    b = words32(package / "inputs/b.bin", N)
    start = time.monotonic()
    result = module.run_ffn1_bits([x[i:i + K] for i in range(0, len(x), K)],
                                 [w[i:i + N] for i in range(0, len(w), N)], b)
    flat = [v for row in result for v in row]
    need(len(flat) == len(gold), "recomputed reference shape mismatch")
    for i, (v, expected) in enumerate(zip(flat, gold)):
        need(v == expected, "supplied expected.bin differs from frozen software reference",
             {"t": i // N, "j": i % N, "supplied": f"0x{expected:08x}", "recomputed": f"0x{v:08x}"})
    return {"status": "PASS", "expected_values_recomputed": len(flat), "mismatches": 0,
            "reference_sha256": REF_SHA, "elapsed_seconds": time.monotonic() - start,
            "description": "local execution of frozen software arithmetic; not software-owner independent RTL rerun"}


def negative_controls(output, writes, tiles, gold, text, last_write):
    tests = []

    def reject(name, operation):
        try:
            operation()
        except (CheckFailure, ValueError):
            tests.append({"test": name, "status": "REJECTED_AS_EXPECTED"})
        else:
            raise CheckFailure("checker accepted corrupted evidence: " + name)

    bad = copy.deepcopy(output)
    bad[0]["result_bits"] = f"0x{gold[0] ^ 1:08x}"
    reject("wrong_actual_bits_even_with_match_equal_one", lambda: check_outputs(bad, gold))
    bad = copy.deepcopy(output)
    bad[1]["column"] = "0"
    reject("duplicate_coordinate", lambda: check_outputs(bad, gold))
    reject("missing_output", lambda: check_outputs(output[:-1], gold))
    reject("missing_write", lambda: check_writes(writes[:-1], output, gold))
    badw = copy.deepcopy(writes)
    badw[0]["word_address"] = "0"
    reject("out_of_window_write", lambda: check_writes(badw, output, gold))
    badw = copy.deepcopy(writes)
    badw[0]["actual_word"] = f"0x{int(badw[0]['actual_word'], 16) ^ 1:04x}"
    reject("wrong_actual_halfword", lambda: check_writes(badw, output, gold))
    badt = copy.deepcopy(tiles)
    badt[-1]["rows_valid"] = "8"
    reject("wrong_tail_rows", lambda: check_tiles(badt))
    badt = copy.deepcopy(tiles)
    badt[0]["k_blocks"] = "1"
    reject("missing_k_block", lambda: check_tiles(badt))
    badlog = re.sub(r"done_cycle=\d+", "done_cycle=" + str(last_write), text)
    reject("done_not_after_last_write", lambda: check_log(badlog, last_write))
    return tests


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--package", required=True)
    ap.add_argument("--recompute-reference", action="store_true")
    ap.add_argument("--negative-controls", action="store_true")
    args = ap.parse_args()
    package = Path(args.package).resolve()
    summary = {"status": "RUNNING", "task": "real KWT-1 layer 00 FFN1", "shape": [M, K, N]}
    try:
        inputs, sim = package / "inputs", package / "simulation"
        validation = json.loads((package / "input_validation.json").read_text(encoding="utf-8"))
        need(sha(package / "software_input.zip") == validation["zip_sha256"], "original software ZIP changed")
        with zipfile.ZipFile(package / "software_input.zip") as archive:
            names = [n for n in archive.namelist() if not n.endswith("/")]
            prefix = names[0].split("/")[0] + "/"
            need({n[len(prefix):] for n in names} == {p.name for p in inputs.iterdir() if p.is_file()},
                 "extracted inputs differ from original ZIP file set")
            for name in names:
                need((inputs / name[len(prefix):]).read_bytes() == archive.read(name),
                     "extracted input differs from original software ZIP: " + name)
        listed = {}
        for line in (inputs / "SHA256SUMS.txt").read_text(encoding="utf-8-sig").splitlines():
            if line.strip():
                h, n = line.split(None, 1)
                listed[n.strip().lstrip("*")] = h.lower()
        need(set(listed) == {p.name for p in inputs.iterdir() if p.is_file() and p.name != "SHA256SUMS.txt"},
             "input manifest file-set mismatch")
        for name, h in listed.items():
            need(sha(inputs / name) == h, "supplied file changed: " + name)
        manifest = json.loads((package / "source_manifest.json").read_text(encoding="utf-8"))
        for name, h in manifest["files"].items():
            need(sha(package / "sources" / name) == h, "RTL/TB snapshot changed: " + name)
        completion = json.loads((package / "process_completion.json").read_text(encoding="utf-8"))
        need(completion["exit_code"] == 0, "native simulator process did not exit successfully")
        need(completion["binary_sha256"] == sha(sim / "ffn1_real_layer00.vvp"), "simulator binary changed")
        need(completion["log_sha256"] == sha(sim / "ffn1.run.log"), "simulator log changed")
        gold = words32(inputs / "expected.bin", M * N)
        snapshots = {}
        for name, binname, count in [("x", "x", M * K), ("w", "w", K * N), ("bias", "b", N)]:
            raw = [int(s, 16) for s in (sim / ("ffn1_" + name + ".mem")).read_text(encoding="ascii").split()]
            need(len(raw) == count * 2 and all(0 <= v <= 65535 for v in raw), "wrong loaded-memory halfword count")
            actual = [raw[i] | (raw[i + 1] << 16) for i in range(0, len(raw), 2)]
            need(actual == words32(inputs / (binname + ".bin"), count), "RTL loaded memory differs from supplied data: " + name)
            snapshots[name] = {"elements_checked": count, "sha256_bin": sha(inputs / (binname + ".bin")),
                               "loaded_snapshot_sha256": sha(sim / ("ffn1_" + name + ".mem"))}
        output = rows(sim / "ffn1_output.csv", OUTPUT_FIELDS)
        writes = rows(sim / "ffn1_writeback.csv", WRITE_FIELDS)
        tiles = rows(sim / "ffn1_tiles.csv", TILE_FIELDS)
        check_outputs(output, gold)
        last_write = check_writes(writes, output, gold)
        check_tiles(tiles)
        text = (sim / "ffn1.run.log").read_text(encoding="utf-8")
        timing = check_log(text, last_write)
        summary.update(rtl_outputs_passed=len(output), rtl_outputs_failed=0, first_difference=None,
                       write_halfwords_checked=len(writes), spatial_tiles_checked=len(tiles),
                       k_blocks_per_tile=2, tail_valid_rows=3, input_memory_checks=snapshots,
                       simulator_exit_code=completion["exit_code"], expected_bin_sha256=sha(inputs / "expected.bin"),
                       source_manifest_sha256=sha(package / "source_manifest.json"), **timing)
        if args.recompute_reference:
            summary["software_reference_recomputation"] = recompute_reference(package, gold)
        if args.negative_controls:
            summary["checker_negative_controls"] = negative_controls(output, writes, tiles, gold, text, last_write)
        summary.update(status="PASS", software_owner_independent_acceptance="PENDING",
                       scope="real model data, one layer-00 FFN1 job through protocol-neutral RTL top",
                       not_verified=["full 12-layer inference", "FFN2", "classification accuracy or verified dataset split",
                                     "real E203 NICE or System Bus", "CPU result visibility/cache coherency",
                                     "physical SRAM", "physical arithmetic pipeline timing", "formal PPA"])
    except Exception as exc:
        summary.update(status="FAIL", error=str(exc), detail=getattr(exc, "detail", None))
        save(package / "comparison_summary.json", summary)
        raise
    save(package / "comparison_summary.json", summary)
    print(json.dumps(summary, ensure_ascii=False, indent=2), flush=True)


if __name__ == "__main__":
    main()
