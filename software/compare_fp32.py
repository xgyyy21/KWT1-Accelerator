"""Compare RTL FP32 output with a task image under the proposed word layout.

The input dump may be raw little-endian ``.bin`` or one 16-bit hexadecimal
word per line in ``.mem``. Both are interpreted as row-major binary32 values,
low 16-bit word first. This is a candidate contract, not an RTL sign-off.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re
import struct
from typing import Dict, List


_CANDIDATE_LAYOUTS = {
    "DRAFT row-major, low 16-bit word first, little-endian bytes per word",
    "DRAFT row-major elements; each FP32 low 16-bit word first; each 16-bit word low byte first",
}
_HEX_WORD = re.compile(r"[0-9a-fA-F]{4}")


def _sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _actual_bytes(path: Path) -> tuple[bytes, bytes, str]:
    """Return decoded bytes, original file bytes, and dump format."""
    suffix = path.suffix.lower()
    source = path.read_bytes()
    if suffix == ".bin":
        return source, source, "bin"
    if suffix != ".mem":
        raise ValueError("RTL output must have a .bin or .mem extension")
    try:
        lines = source.decode("ascii").splitlines()
    except UnicodeDecodeError as exc:
        raise ValueError(f"{path}: .mem must be ASCII text") from exc
    words: list[int] = []
    for line_number, line in enumerate(lines, 1):
        word = line.strip()
        if not word:
            continue
        if not _HEX_WORD.fullmatch(word):
            raise ValueError(f"{path}: line {line_number} must contain exactly one 4-digit hex word")
        words.append(int(word, 16))
    return b"".join(struct.pack("<H", word) for word in words), source, "mem"


def _manifest_entry(manifest: object, expected_name: str) -> tuple[int, int, dict]:
    layout = manifest.get("layout") if isinstance(manifest, dict) else None
    if not isinstance(layout, str) or layout not in _CANDIDATE_LAYOUTS:
        raise ValueError("unsupported FP32 layout; expected the documented draft low-word-first layout")
    tensors = manifest.get("tensors")
    entry = tensors.get(expected_name) if isinstance(tensors, dict) else None
    if not isinstance(entry, dict):
        raise ValueError(f"manifest lacks tensors.{expected_name}")
    shape = entry.get("shape")
    if (not isinstance(shape, list) or len(shape) != 2 or
            any(type(dim) is not int or dim <= 0 for dim in shape)):
        raise ValueError("expected output needs a positive 2D shape")
    rows, columns = shape
    if "element_bits" in entry and (type(entry["element_bits"]) is not int or
                                    entry["element_bits"] != 32):
        raise ValueError("expected output must contain 32-bit elements")
    word_count = rows * columns * 2
    byte_count = word_count * 2
    if type(entry.get("word_count")) is not int or entry["word_count"] != word_count:
        raise ValueError("manifest word_count does not match shape and FP32 width")
    # The generated pack uses `bytes`; the hand-worked image uses `byte_count`.
    # Require every count supplied by either format to agree with the shape.
    counts = [entry[key] for key in ("bytes", "byte_count") if key in entry]
    if not counts or any(type(count) is not int or count != byte_count for count in counts):
        raise ValueError("manifest byte count does not match shape and FP32 width")
    return rows, columns, entry


def compare(packed_dir: Path, actual_path: Path, max_examples: int = 12,
            expected_name: str = "expected") -> Dict[str, object]:
    packed_dir = Path(packed_dir)
    actual_path = Path(actual_path)
    if type(max_examples) is not int or max_examples < 1:
        raise ValueError("max_examples must be positive")
    if (not isinstance(expected_name, str) or
            not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", expected_name) or
            not (expected_name == "expected" or expected_name.endswith("_expected"))):
        raise ValueError("expected_name must name an expected output tensor")
    manifest_path = packed_dir / "manifest.json"
    manifest_raw = manifest_path.read_bytes()
    manifest = json.loads(manifest_raw.decode("utf-8"))
    rows, columns, entry = _manifest_entry(manifest, expected_name)
    byte_count = rows * columns * 4
    expected = (packed_dir / f"{expected_name}.bin").read_bytes()
    if len(expected) != byte_count:
        raise ValueError(f"{expected_name}.bin has {len(expected)} bytes; need {byte_count}")
    expected_hash = _sha(expected)
    if entry.get("sha256_bin") != expected_hash:
        raise ValueError(f"{expected_name}.bin SHA-256 differs from its manifest")
    words_hex = entry.get("words_hex")
    if words_hex is not None:
        decoded_words = [f"{word:04x}" for (word,) in struct.iter_unpack("<H", expected)]
        if (not isinstance(words_hex, list) or len(words_hex) != len(decoded_words) or
                any(not isinstance(word, str) or word.lower() != decoded_words[i]
                    for i, word in enumerate(words_hex))):
            raise ValueError("manifest words_hex differs from expected.bin")

    actual, actual_file, actual_format = _actual_bytes(actual_path)
    if len(actual) != byte_count:
        raise ValueError(
            f"RTL output has {len(actual)} decoded bytes; need {byte_count} "
            f"({rows * columns * 2} 16-bit words)")

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
        "packed_manifest": str(manifest_path.resolve()),
        "packed_manifest_sha256": _sha(manifest_raw),
        "expected_sha256": expected_hash,
        "actual_file": str(actual_path.resolve()),
        "actual_format": actual_format,
        "actual_file_sha256": _sha(actual_file),
        "actual_sha256": _sha(actual),
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
    try:
        report = compare(args.packed_dir, args.actual, args.max_examples, args.expected_name)
    except (OSError, ValueError, TypeError, KeyError, json.JSONDecodeError) as exc:
        parser.error(str(exc))
    payload = json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(payload, encoding="utf-8")
    print(payload)
    if report["mismatch_count"]:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
