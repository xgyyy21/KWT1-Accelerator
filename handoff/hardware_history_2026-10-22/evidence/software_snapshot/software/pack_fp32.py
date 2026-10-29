"""Pack one FP32 X/W/b task and candidate sequential-FP32 expected result.

Input is NPZ with x[M,K], w[K,N], b[N], all np.float32. Optional y_float
is recorded as present but NEVER used to derive the arithmetic expected bits.
The 16-bit-word layout and arithmetic are draft software/RTL proposals.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Dict, Sequence

import numpy as np

from software.fp32_reference import (
    row_major_words, run_ffn1_bits, words_to_little_endian_bytes,
)


def _f32_bits(array: np.ndarray, name: str, dimensions: int) -> np.ndarray:
    if array.dtype != np.dtype("float32"):
        raise TypeError(f"{name} must be float32; got {array.dtype}; convert explicitly upstream")
    if array.ndim != dimensions or 0 in array.shape:
        raise ValueError(f"{name} must be a nonempty {dimensions}-D float32 array")
    if not np.all(np.isfinite(array)):
        raise ValueError(f"{name} contains NaN or infinity; policy not frozen")
    return array.astype("<f4", copy=False).view("<u4")


def _write(directory: Path, name: str, matrix: Sequence[Sequence[int]]) -> Dict[str, object]:
    words = row_major_words(matrix)
    binary = words_to_little_endian_bytes(words)
    (directory / f"{name}.bin").write_bytes(binary)
    (directory / f"{name}.mem").write_text(
        "".join(f"{word:04x}\n" for word in words), encoding="ascii")
    return {
        "shape": [len(matrix), len(matrix[0])],
        "element_bits": 32,
        "word_count": len(words),
        "bytes": len(binary),
        "sha256_bin": hashlib.sha256(binary).hexdigest(),
    }


def create_pack(source_npz: Path, output_dir: Path, source_id: str, split: str) -> Dict[str, object]:
    """Validate source, compute expected bits, then write a new image directory."""
    source_npz = Path(source_npz)
    output_dir = Path(output_dir)
    if (not isinstance(source_id, str) or not source_id.strip()
        or source_id != source_id.strip() or len(source_id) > 256
        or any(char in source_id for char in "\r\n\0")):
        raise ValueError("source_id must be a stable, nonempty identifier without surrounding whitespace")
    if split not in {"synthetic-smoke", "unverified", "train", "validation", "test"}:
        raise ValueError("split must be a declared source category")
    if output_dir.exists() and any(output_dir.iterdir()):
        raise FileExistsError(f"refusing to overwrite nonempty output directory: {output_dir}")

    with np.load(source_npz, allow_pickle=False) as data:
        missing = {"x", "w", "b"} - set(data.files)
        if missing:
            raise ValueError(f"NPZ is missing {sorted(missing)}")
        x_bits = _f32_bits(data["x"], "x", 2)
        w_bits = _f32_bits(data["w"], "w", 2)
        b_bits = _f32_bits(data["b"], "b", 1)
        provided_y_float = "y_float" in data.files
        if provided_y_float:
            claimed = _f32_bits(data["y_float"], "y_float", 2)
            if claimed.shape != (x_bits.shape[0], w_bits.shape[1]):
                raise ValueError("y_float shape differs from XW+b; not used for expected bits")

    x = [[int(v) for v in row] for row in x_bits]
    w = [[int(v) for v in row] for row in w_bits]
    b = [int(v) for v in b_bits]
    expected = run_ffn1_bits(x, w, b)
    output_dir.mkdir(parents=True, exist_ok=True)
    entries = {
        "x": _write(output_dir, "x", x),
        "w": _write(output_dir, "w", w),
        "b": _write(output_dir, "b", [b]),
        "expected": _write(output_dir, "expected", expected),
    }
    manifest: Dict[str, object] = {
        "status": "DRAFT FP32 arithmetic and memory-layout proposal; no RTL validation claim",
        "source_id": source_id,
        "split_claim": split,
        "split_verified_by_this_tool": False,
        "input_file": str(source_npz.resolve()),
        "input_sha256": hashlib.sha256(source_npz.read_bytes()).hexdigest(),
        "provided_y_float_present": provided_y_float,
        "provided_y_float_used_for_expected": False,
        "arithmetic": "finite binary32, nearest-even, gradual underflow; separate multiplication and addition rounding, k ascending, bias once",
        "layout": "DRAFT row-major, low 16-bit word first, little-endian bytes per word",
        "tensors": entries,
    }
    (output_dir / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--source-id", required=True)
    parser.add_argument("--split", required=True,
                        choices=("synthetic-smoke", "unverified", "train", "validation", "test"))
    args = parser.parse_args()
    create_pack(args.input, args.output_dir, args.source_id, args.split)
    print(args.output_dir / "manifest.json")
    print("Draft FP32 image only; compare with RTL after jointly freezing arithmetic and layout.")


if __name__ == "__main__":
    main()
