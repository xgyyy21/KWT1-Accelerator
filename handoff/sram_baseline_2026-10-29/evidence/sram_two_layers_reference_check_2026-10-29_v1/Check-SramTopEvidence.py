"""Recompute captured macro-mode results with the archived software FP32 model.

This is a hardware-side check using the software model, not software-side
independent acceptance. No simulator is run by this script.
"""
from __future__ import annotations
import argparse
import csv
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import sys

sys.dont_write_bytecode = True

def require(condition, message):
    if not condition:
        raise ValueError(message)

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def read_rows(path):
    with path.open(encoding="utf-8-sig", newline="") as handle:
        return list(csv.DictReader(handle))

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--reference", type=Path, required=True)
    parser.add_argument("--full-layer", action="store_true")
    parser.add_argument("--second-layer", action="store_true")
    parser.add_argument("--two-layers", action="store_true")
    args = parser.parse_args()
    require(not (args.full_layer and args.second_layer), "Choose one layer shape")
    require(sum((args.full_layer, args.second_layer, args.two_layers)) <= 1, "Choose one layer shape")
    evidence = args.evidence.resolve()
    output = args.output.resolve()
    require(not output.exists(), "Refusing to overwrite verification evidence")
    output.mkdir(parents=True)
    shutil.copy2(Path(__file__), output / Path(__file__).name)
    reference = output / "fp32_reference.py"
    shutil.copy2(args.reference, reference)
    spec = importlib.util.spec_from_file_location("frozen_sram_reference", reference)
    model = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(model)
    if args.full_layer:
        cases = [(99, 64, 256)]
    elif args.second_layer:
        cases = [(99, 256, 64)]
    elif args.two_layers:
        cases = [(99, 64, 256), (99, 256, 64)]
    else:
        cases = [(9, 64, 17), (9, 35, 17), (2, 256, 2), (1, 1, 1)]
    inputs = read_rows(evidence / "inputs.csv")
    outputs = read_rows(evidence / "outputs.csv")
    writes = read_rows(evidence / "writeback.csv")
    tiles = read_rows(evidence / "tiles.csv")
    controls = read_rows(evidence / "control.csv")
    all_rows = (inputs, outputs, writes, tiles, controls)
    for rows in all_rows:
        require(all(0 <= int(row["job"]) < len(cases) for row in rows), "Unexpected job ID")
    summaries = []
    for job, (m, k, n) in enumerate(cases):
        memory = {}
        for row in inputs:
            if int(row["job"]) != job:
                continue
            address = int(row["bus_word_addr"])
            require(address not in memory, "Duplicate input address")
            memory[address] = int(row["fp32_hex"], 16)
        addresses = set(range(0, 2*m*k, 2)) | set(range(100000, 100000+2*k*n, 2)) | set(range(200000, 200000+2*n, 2))
        require(set(memory) == addresses, "Input address/length mismatch")
        x = [[memory[2*(r*k+q)] for q in range(k)] for r in range(m)]
        w = [[memory[100000+2*(q*n+c)] for c in range(n)] for q in range(k)]
        bias = [memory[200000+2*c] for c in range(n)]
        expected = model.run_ffn1_bits(x, w, bias)
        seen = set()
        for row in outputs:
            if int(row["job"]) != job:
                continue
            r, c = int(row["row"]), int(row["col"])
            require(0 <= r < m and 0 <= c < n and (r, c) not in seen, "Output coordinate/duplicate")
            seen.add((r, c))
            require(int(row["bus_word_addr"]) == 210000+2*(r*n+c), "Output address")
            require(int(row["actual_hex"], 16) == expected[r][c], f"First result difference job={job} row={r} col={c}")
            require(int(row["expected_hex"], 16) == expected[r][c] and row["match"] == "1", "TB reference mismatch")
        require(len(seen) == m*n, "Missing output")
        job_tiles = [t for t in tiles if int(t["job"]) == job]
        require(len(job_tiles) == ((m+7)//8)*((n+15)//16), "Tile count")
        for index, tile in enumerate(job_tiles):
            rb, cb = (index//((n+15)//16))*8, (index%((n+15)//16))*16
            descriptor = tuple(int(tile[key]) for key in ("tile_id", "row_base", "col_base", "rows_valid", "cols_valid", "k_blocks"))
            require(descriptor == (index, rb, cb, min(8, m-rb), min(16, n-cb), (k+31)//32), "Tile descriptor")
        seen_words = set()
        last_cycle = -1
        for row in writes:
            if int(row["job"]) != job:
                continue
            r, c, half = int(row["row"]), int(row["col"]), int(row["half"])
            require(0 <= r < m and 0 <= c < n and half in (0, 1), "Write coordinate")
            address = 210000+2*(r*n+c)+half
            tile_id = (r//8)*((n+15)//16)+(c//16)
            require(int(row["bus_word_addr"]) == address and address not in seen_words, "Write address/duplicate")
            require(int(row["tile_id"]) == tile_id, "Write tile ID")
            require(int(row["actual_hex"], 16) == (expected[r][c] >> (16*half)) & 65535, "Write data")
            require(int(row["cycle"]) > last_cycle, "Write cycle ordering")
            last_cycle = int(row["cycle"])
            seen_words.add(address)
        require(len(seen_words) == 2*m*n, "Missing halfword write")
        status_reads = [row for row in controls if int(row["job"]) == job and row["write"] == "0" and int(row["register_hex"], 16) == 4]
        require(status_reads and any(int(row["rdata_hex"], 16) & 1 for row in status_reads), "No BUSY observation")
        require(int(status_reads[-1]["rdata_hex"], 16) == 2 and int(status_reads[-1]["cycle"]) > last_cycle, "DONE before final write or invalid status")
        summaries.append(dict(job=job, shape=[m,k,n], outputs_matched=m*n, write_halfwords_matched=2*m*n, tiles=len(job_tiles), first_difference=None))
    hashes = {name: sha(evidence/name) for name in ("inputs.csv", "outputs.csv", "writeback.csv", "tiles.csv", "control.csv")}
    summary = dict(status="PASS", jobs=summaries, failed=0, reference_sha256=sha(reference), evidence=str(evidence), input_evidence_sha256=hashes,
                   scope="Hardware-side archived software-reference recomputation; not independent software acceptance or a new RTL run")
    (output/"comparison_summary.json").write_text(json.dumps(summary, indent=2)+"\n", encoding="utf-8")
    manifest = {path.name: sha(path) for path in output.iterdir() if path.is_file()}
    (output/"sha256.json").write_text(json.dumps(manifest, indent=2)+"\n", encoding="utf-8")
    print(json.dumps(summary, indent=2))

if __name__ == "__main__":
    main()
