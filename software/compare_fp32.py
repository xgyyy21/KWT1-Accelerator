"""Bitwise comparison of RTL FP32 output with a *draft-layout* task image.

This assumes row-major FP32 elements in little-endian four-byte form, which
matches the current low-16-bit-SRAM-word-first proposal. Convert the RTL image
first if the jointly frozen hardware layout is different. Equality here only
checks this task's arithmetic bits; it does not establish model accuracy.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
from typing import Dict, List


def compare(packed_dir: Path, actual_path: Path, max_examples: int = 12,
            expected_name: str = "expected") -> Dict[str, object]:
    packed_dir = Path(packed_dir)
    actual_path = Path(actual_path)
    if max_examples < 1:
        raise ValueError("max_examples must be positive")
    if (not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", expected_name)
            or not (expected_name == "expected" or expected_name.endswith("_expected"))):
        raise ValueError("expected_name must name an expected output tensor")
    manifest = json.loads((packed_dir / "manifest.json").read_text(encoding="utf-8"))
    entry = manifest["tensors"][expected_name]
    rows, columns = entry["shape"]
    if rows < 1 or columns < 1:
        raise ValueError("expected shape must be a nonempty matrix")
    byte_count = rows * columns * 4
    expected = (packed_dir / f"{expected_name}.bin").read_bytes()
    actual = actual_path.read_bytes()
    if len(expected) != byte_count or len(actual) != byte_count:
        raise ValueError(
            f"expected and RTL output must each have {byte_count} bytes; "
            f"got {len(expected)} and {len(actual)}")
    expected_hash = hashlib.sha256(expected).hexdigest()
    declared_hash = entry.get("sha256_bin")
    if declared_hash != expected_hash:
        raise ValueError(f"{expected_name}.bin SHA-256 differs from its manifest")

    examples: List[Dict[str, object]] = []
    mismatch_count = 0
    for index in range(rows * columns):
        expected_bits = struct.unpack_from("<I", expected, index * 4)[0]
        actual_bits = struct.unpack_from("<I", actual, index * 4)[0]
        if actual_bits != expected_bits:
            mismatch_count += 1
            if len(examples) < max_examples:
                examples.append({
                    "row": index // columns,
                    "column": index % columns,
                    "expected_bits": f"0x{expected_bits:08x}",
                    "actual_bits": f"0x{actual_bits:08x}",
                })
    return {
        "status": "BIT-EXACT" if mismatch_count == 0 else "MISMATCH",
        "expected_name": expected_name,
        "arithmetic_and_layout_status": "DRAFT, not jointly frozen or RTL-validated",
        "shape": [rows, columns],
        "elements": rows * columns,
        "mismatch_count": mismatch_count,
        "examples": examples,
        "expected_sha256": expected_hash,
        "actual_sha256": hashlib.sha256(actual).hexdigest(),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--packed-dir", required=True, type=Path)
    parser.add_argument("--actual", required=True, type=Path)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--max-examples", type=int, default=12)
    parser.add_argument("--expected-name", default="expected",
                        help="expected, rounding_expected, or tile_expected in the hand image")
    args = parser.parse_args()
    report = compare(args.packed_dir, args.actual, args.max_examples, args.expected_name)
    payload = json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(payload, encoding="utf-8")
    print(payload)
    if report["mismatch_count"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
