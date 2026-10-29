"""Cross-check the software FP32 draft against hardware's independent vectors.

The hardware branch's Generate-Fp32Vectors.ps1 writes one line per input pair:
``a_bits b_bits expected_add_bits expected_mul_bits``. Each field is exactly
eight hexadecimal digits. The generator uses .NET Single arithmetic; this
script never generates expected values from the software model itself.

Only finite-input, finite-output cases are covered by the current software
contract. NaN, infinity, and overflow are counted explicitly as skipped.
Passing this check says nothing about the RTL PE, array, bias, or SRAM layout.
"""

from __future__ import annotations

import argparse
from hashlib import sha256
import json
from pathlib import Path
import re
from typing import Dict, Iterator, Optional, Tuple

from software.fp32_reference import UnsupportedFP32Case, add_bits, multiply_bits


_WORD = re.compile(r"[0-9a-fA-F]{8}\Z")


def _hex(bits: int) -> str:
    return f"0x{bits:08x}"


def _special(bits: int) -> bool:
    return ((bits >> 23) & 0xFF) == 0xFF


def _parse_vectors(raw: bytes) -> Iterator[Tuple[int, int, int, int, int]]:
    try:
        lines = raw.decode("ascii").splitlines()
    except UnicodeDecodeError as exc:
        raise ValueError("vector file must contain ASCII hexadecimal text") from exc
    if not lines:
        raise ValueError("vector file is empty")
    for line_number, line in enumerate(lines, 1):
        fields = line.split()
        if len(fields) != 4 or any(_WORD.fullmatch(field) is None for field in fields):
            raise ValueError(
                f"vector line {line_number}: need four eight-digit hex words "
                "(a b expected_add expected_mul)"
            )
        a, b, expected_add, expected_mul = (int(field, 16) for field in fields)
        yield line_number, a, b, expected_add, expected_mul


def compare_vectors(path: Path, hardware_commit: Optional[str] = None) -> Dict[str, object]:
    """Check every supported operation in a four-column hardware vector file.

    ``hardware_commit`` is recorded as a caller declaration; it is not
    inferred from or cryptographically bound to the vector file.
    """
    if hardware_commit is not None and re.fullmatch(r"[0-9a-fA-F]{7,40}", hardware_commit) is None:
        raise ValueError("hardware_commit must be a 7-to-40-digit hex Git commit")
    path = Path(path)
    raw = path.read_bytes()
    counts = {
        operation: {
            "checked": 0,
            "skipped_special_input": 0,
            "skipped_nonfinite_expected": 0,
            "unexpected_rejection": 0,
            "mismatched": 0,
        }
        for operation in ("add", "mul")
    }
    first_failure = None
    pairs = 0
    for line_number, a, b, expected_add, expected_mul in _parse_vectors(raw):
        pairs += 1
        for operation, expected, calculate in (
            ("add", expected_add, add_bits),
            ("mul", expected_mul, multiply_bits),
        ):
            entry = counts[operation]
            if _special(a) or _special(b):
                entry["skipped_special_input"] += 1
                continue
            try:
                actual = calculate(a, b)
            except UnsupportedFP32Case as exc:
                if _special(expected):
                    entry["skipped_nonfinite_expected"] += 1
                    continue
                entry["unexpected_rejection"] += 1
                if first_failure is None:
                    first_failure = {
                        "kind": "unexpected_rejection", "line": line_number,
                        "operation": operation, "a_bits": _hex(a), "b_bits": _hex(b),
                        "expected_bits": _hex(expected), "reason": str(exc),
                    }
                continue
            entry["checked"] += 1
            if actual != expected:
                entry["mismatched"] += 1
                if first_failure is None:
                    first_failure = {
                        "kind": "bit_mismatch", "line": line_number,
                        "operation": operation, "a_bits": _hex(a), "b_bits": _hex(b),
                        "expected_bits": _hex(expected), "actual_bits": _hex(actual),
                    }
    checked = sum(entry["checked"] for entry in counts.values())
    failures = sum(entry["mismatched"] + entry["unexpected_rejection"]
                   for entry in counts.values())
    status = "MISMATCH" if failures else "MATCH" if checked else "NO_SUPPORTED_CASES"
    reference_path = Path(__file__).with_name("fp32_reference.py")
    return {
        "status": status,
        "vector_path": str(path.resolve()),
        "vector_sha256": sha256(raw).hexdigest(),
        "hardware_commit_user_declared": hardware_commit,
        "software_reference_sha256": sha256(reference_path.read_bytes()).hexdigest(),
        "format": "a b expected_add expected_mul; four 8-digit hex words per line",
        "pairs": pairs,
        "operations": counts,
        "first_failure": first_failure,
        "scope": ("Independent .NET golden-vector check of finite FP32 add/mul only; "
                  "not an RTL PE/array, bias, memory-layout, or SoC validation."),
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--vectors", required=True, type=Path,
                        help="four-column file from hardware's Generate-Fp32Vectors.ps1")
    parser.add_argument("--hardware-commit",
                        help="optional user-declared commit that generated these vectors")
    parser.add_argument("--report", type=Path, help="optional JSON report path")
    args = parser.parse_args()
    try:
        report = compare_vectors(args.vectors, args.hardware_commit)
    except (OSError, ValueError) as exc:
        parser.error(str(exc))
    payload = json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(payload, encoding="utf-8")
    print(payload, end="")
    if report["status"] != "MATCH":
        raise SystemExit(1)


if __name__ == "__main__":
    main()
