#!/usr/bin/env python3
"""Validate decimal CSV tensors and emit deterministic signed hex images."""
import argparse
import csv
import hashlib
import json
import re
from pathlib import Path


def sha256(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def read_csv(path, rows, cols, minimum, maximum):
    values = []
    with path.open(newline="", encoding="utf-8-sig") as stream:
        for row_no, row in enumerate(csv.reader(stream), 1):
            if not row or all(not cell.strip() for cell in row):
                continue
            if len(row) != cols:
                raise ValueError(f"{path}: row {row_no} has {len(row)} columns, expected {cols}")
            for col_no, cell in enumerate(row, 1):
                text = cell.strip()
                if not re.fullmatch(r"[+-]?[0-9]+", text):
                    raise ValueError(f"{path}: expected integer at row {row_no}, column {col_no}")
                value = int(text)
                if not minimum <= value <= maximum:
                    raise ValueError(f"{path}: {value} outside [{minimum}, {maximum}]")
                values.append(value)
    if len(values) != rows * cols:
        raise ValueError(f"{path}: found {len(values)} values, expected {rows * cols}")
    return values


def write_hex(path, values, bits):
    width = bits // 4
    mask = (1 << bits) - 1
    path.write_text("".join(f"{value & mask:0{width}x}\n" for value in values),
                    encoding="ascii", newline="\n")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", required=True, type=Path)
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args()
    if args.out.exists() and any(args.out.iterdir()):
        raise SystemExit(f"refusing to overwrite non-empty output directory: {args.out}")
    args.out.mkdir(parents=True, exist_ok=True)
    manifest_path = args.manifest.resolve()
    spec = json.loads(manifest_path.read_text(encoding="utf-8"))
    required = {"version", "m", "k", "n", "out_shift", "a_csv", "b_csv",
                "bias_csv", "expected_csv"}
    missing = sorted(required - set(spec))
    if missing:
        raise SystemExit("manifest missing: " + ", ".join(missing))
    if spec["version"] != 1:
        raise SystemExit("only manifest version 1 is supported")
    m, k, n, shift = (int(spec[key]) for key in ("m", "k", "n", "out_shift"))
    if m <= 0 or n <= 0 or k not in (64, 256) or not 0 <= shift <= 31:
        raise SystemExit("unsupported M/K/N or out_shift")
    contract = {
        "input_dtype": "int16", "weight_dtype": "int16",
        "bias_dtype": "int32", "output_dtype": "int16",
        "layout": "row_major", "rounding": "nearest_ties_away",
        "overflow": "saturate",
    }
    for key, expected in contract.items():
        if spec.get(key) != expected:
            raise SystemExit(f"manifest {key} must be {expected!r}")
    source = {key: (manifest_path.parent / spec[key]).resolve()
              for key in ("a_csv", "b_csv", "bias_csv", "expected_csv")}
    for path in source.values():
        if not path.is_file():
            raise SystemExit(f"missing CSV input: {path}")
    a = read_csv(source["a_csv"], m, k, -32768, 32767)
    b = read_csv(source["b_csv"], k, n, -32768, 32767)
    bias = read_csv(source["bias_csv"], n, 1, -(1 << 31), (1 << 31) - 1)
    expected = read_csv(source["expected_csv"], m, n, -32768, 32767)
    outputs = {
        "a_int16.mem": (a, 16), "b_int16.mem": (b, 16),
        "bias_int32.mem": (bias, 32), "expected_int16.mem": (expected, 16),
    }
    for name, (values, bits) in outputs.items():
        write_hex(args.out / name, values, bits)
    result = {
        "format_version": 1, "dimensions": {"m": m, "k": k, "n": n},
        "out_shift": shift,
        "contract": {**contract, "product_dtype": "int32",
                     "accumulator_dtype": "int48", "k_tile": 32},
        "source_manifest": {
            key: {"path": str(path), "sha256": sha256(path)}
            for key, path in source.items()
        },
        "prepared_files": {
            name: {"count": len(values), "sha256": sha256(args.out / name)}
            for name, (values, _) in outputs.items()
        },
    }
    (args.out / "prepared_manifest.json").write_text(
        json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"prepared INT16 data: M={m} K={k} N={n} out_shift={shift}")


if __name__ == "__main__":
    main()
