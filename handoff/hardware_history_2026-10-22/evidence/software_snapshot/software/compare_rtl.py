"""Compare one RTL output image against the packed software integer reference.

This checks the prototype packer's element/word layout. It does not establish
floating-point accuracy or claim that any particular hardware has been run.
Once the team freezes a different memory layout, adapt this reader to that
layout instead of silently interpreting an incompatible dump.
"""

from __future__ import annotations

import argparse
from hashlib import sha256
import json
from pathlib import Path
import re

import numpy as np

try:
    from .pack_tensors import unpack_words_to_signed
except ImportError:
    from pack_tensors import unpack_words_to_signed


_HEX_WORD = re.compile(r"[0-9a-fA-F]{1,4}")


def _sha(data: bytes) -> str:
    return sha256(data).hexdigest()


def _actual_bytes(path: Path) -> bytes:
    if path.suffix.lower() != ".mem":
        return path.read_bytes()
    words: list[int] = []
    for line_number, line in enumerate(path.read_text(encoding="ascii").splitlines(), 1):
        word = line.strip()
        if not word:
            continue
        if not _HEX_WORD.fullmatch(word):
            raise ValueError(f"{path}: line {line_number} is not a single 16-bit hex word")
        words.append(int(word, 16))
    return np.asarray(words, dtype="<u2").tobytes()


def compare_output(packed_dir: Path, actual_path: Path) -> dict[str, object]:
    """Return element-level equality and first mismatch for one packed task.

    ``actual_path`` is a raw little-endian output ``.bin`` or a ``.mem`` file
    containing one 16-bit hex word per line, in the packer's expected order.
    Raises ValueError if lengths, hashes, or the layout contract are invalid.
    """
    packed_dir = Path(packed_dir)
    actual_path = Path(actual_path)
    manifest_path = packed_dir / "manifest.json"
    manifest_raw = manifest_path.read_bytes()
    manifest = json.loads(manifest_raw.decode("utf-8"))
    if not isinstance(manifest, dict):
        raise ValueError("manifest.json must contain an object")
    storage = manifest.get("storage")
    if not isinstance(storage, dict) or any(
        storage.get(key) != value for key, value in {
            "word_bits": 16,
            "word_byte_order": "little-endian",
            "element_word_order": "least-significant 16-bit word first",
            "element_signedness": "two's complement signed",
            "tensor_order": "C row-major, last index fastest",
        }.items()
    ):
        raise ValueError("unsupported output storage layout; expected the prototype packer format")
    tensors = manifest.get("tensors")
    info = tensors.get("expected") if isinstance(tensors, dict) else None
    if not isinstance(info, dict):
        raise ValueError("manifest lacks tensors.expected")
    shape = info.get("shape")
    bits = info.get("element_bits")
    if (not isinstance(shape, list) or len(shape) != 2 or
            any(type(dim) is not int or dim <= 0 for dim in shape) or
            type(bits) is not int or bits < 16 or bits > 60 or bits % 16):
        raise ValueError("expected output needs a positive 2D shape and 16-bit-aligned width")
    element_count = shape[0] * shape[1]
    byte_count = element_count * bits // 8
    if info.get("element_count") != element_count or info.get("word_count") != byte_count // 2:
        raise ValueError("expected output manifest count does not match shape and width")
    if info.get("binary_file") != "expected.bin":
        raise ValueError("this comparison expects the packer's expected.bin")
    expected_raw = (packed_dir / "expected.bin").read_bytes()
    if len(expected_raw) != byte_count:
        raise ValueError(f"expected.bin has {len(expected_raw)} bytes; need {byte_count}")
    if not isinstance(info.get("binary_sha256"), str) or _sha(expected_raw) != info["binary_sha256"]:
        raise ValueError("expected.bin SHA-256 does not match manifest")

    actual_raw = _actual_bytes(actual_path)
    if len(actual_raw) != byte_count:
        raise ValueError(f"RTL output has {len(actual_raw)} bytes; need {byte_count}")
    expected = unpack_words_to_signed(np.frombuffer(expected_raw, dtype="<u2"), tuple(shape), bits)
    actual = unpack_words_to_signed(np.frombuffer(actual_raw, dtype="<u2"), tuple(shape), bits)
    different = np.argwhere(expected != actual)
    first = None
    if len(different):
        row, column = (int(v) for v in different[0])
        mask = (1 << bits) - 1
        first = {
            "row": row,
            "column": column,
            "expected_signed": int(expected[row, column]),
            "actual_signed": int(actual[row, column]),
            "expected_hex": f"0x{int(expected[row, column]) & mask:0{bits // 4}x}",
            "actual_hex": f"0x{int(actual[row, column]) & mask:0{bits // 4}x}",
        }
    return {
        "bit_exact": first is None,
        "mismatched_elements": int(len(different)),
        "total_elements": element_count,
        "shape": shape,
        "element_bits": bits,
        "first_mismatch": first,
        "packed_manifest": str(manifest_path.resolve()),
        "packed_manifest_sha256": _sha(manifest_raw),
        "expected_sha256": _sha(expected_raw),
        "actual_file": str(actual_path.resolve()),
        "actual_sha256": _sha(actual_raw),
        "note": "This compares integer output words only; it does not measure KWT-1 float accuracy.",
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--packed-dir", type=Path, required=True,
                        help="directory produced by software/pack_tensors.py")
    parser.add_argument("--actual", type=Path, required=True,
                        help="RTL output .bin or one-16-bit-word-per-line .mem")
    parser.add_argument("--report", type=Path, help="optional JSON report path")
    args = parser.parse_args()
    try:
        result = compare_output(args.packed_dir, args.actual)
    except (OSError, ValueError, TypeError, json.JSONDecodeError) as exc:
        parser.error(str(exc))
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if result["bit_exact"]:
        print(f"BIT-EXACT: all {result['total_elements']} output elements match")
    else:
        print(f"MISMATCH: {result['mismatched_elements']} of {result['total_elements']} elements differ")
        print("First mismatch:", json.dumps(result["first_mismatch"], ensure_ascii=False))
        raise SystemExit(1)


if __name__ == "__main__":
    main()
