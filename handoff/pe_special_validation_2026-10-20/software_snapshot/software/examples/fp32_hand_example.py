"""Generate a small, hand-checkable FP32 image for hardware discussion.

Run from the repository root with:
    python -m software.examples.fp32_hand_example --output-dir runs/fp32_hand

The generated low-16-first layout is a DRAFT. Do not use it as a frozen E203
memory map or infer that the current RTL implements these FP32 operations.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

from software.fp32_reference import row_major_words, run_ffn1_bits, words_to_little_endian_bytes


# Independent hand-calculated values, not filled from the reference result.
# X = [[1, -2], [0.5, 3]]; W = [[2, -1], [1.5, 0.5]];
# b = [0.25, -0.5]; Y = [[-0.75, -2.5], [5.75, 0.5]].
X = [[0x3F800000, 0xC0000000], [0x3F000000, 0x40400000]]
W = [[0x40000000, 0xBF800000], [0x3FC00000, 0x3F000000]]
BIAS = [0x3E800000, 0xBF000000]
EXPECTED = [[0xBF400000, 0xC0200000], [0x40B80000, 0x3F000000]]

# This separate case catches accidental fused multiply-add. Ascending k:
# acc=-1 at k=0, rounded product(1+2^-23)*(1-2^-23)=1 at k=1,
# so round32(-1+1)=+0. A fused second MAC would retain -2^-46 instead.
ROUNDING_X = [[0xBF800000, 0x3F800001]]
ROUNDING_W = [[0x3F800000], [0x3F7FFFFE]]
ROUNDING_BIAS = [0x00000000]
ROUNDING_EXPECTED = [[0x00000000]]

# Across a proposed K=32 tile boundary: the second tile must inherit +2,
# add -3, then add +0.25 once only after all 64 products.
TILE_X = [[0x3F800000] * 64]
TILE_W = [[0x00000000] for _ in range(64)]
TILE_W[31][0] = 0x40000000
TILE_W[32][0] = 0xC0400000
TILE_BIAS = [0x3E800000]
TILE_EXPECTED = [[0xBF400000]]


def _write_tensor(directory: Path, name: str, values: list[list[int]]) -> dict:
    words = row_major_words(values)
    binary = words_to_little_endian_bytes(words)
    mem = "".join(f"{word:04x}\n" for word in words)
    (directory / f"{name}.mem").write_text(mem, encoding="ascii")
    (directory / f"{name}.bin").write_bytes(binary)
    return {
        "shape": [len(values), len(values[0])],
        "word_count": len(words),
        "byte_count": len(binary),
        "sha256_bin": hashlib.sha256(binary).hexdigest(),
        "words_hex": [f"{word:04x}" for word in words],
    }


def generate(output_dir: Path) -> Path:
    if output_dir.exists() and any(output_dir.iterdir()):
        raise FileExistsError(f"refusing to overwrite nonempty output directory: {output_dir}")
    output_dir.mkdir(parents=True, exist_ok=True)

    actual = run_ffn1_bits(X, W, BIAS)
    rounding_actual = run_ffn1_bits(ROUNDING_X, ROUNDING_W, ROUNDING_BIAS)
    tile_actual = run_ffn1_bits(TILE_X, TILE_W, TILE_BIAS)
    if (actual != EXPECTED or rounding_actual != ROUNDING_EXPECTED
            or tile_actual != TILE_EXPECTED):
        raise AssertionError("reference disagrees with independently written hand cases")

    tensors = {
        "x": X,
        "w": W,
        "bias": [BIAS],
        "expected": EXPECTED,
        "rounding_x": ROUNDING_X,
        "rounding_w": ROUNDING_W,
        "rounding_bias": [ROUNDING_BIAS],
        "rounding_expected": ROUNDING_EXPECTED,
        "tile_x": TILE_X,
        "tile_w": TILE_W,
        "tile_bias": [TILE_BIAS],
        "tile_expected": TILE_EXPECTED,
    }
    entries = {name: _write_tensor(output_dir, name, values)
               for name, values in tensors.items()}
    manifest = {
        "status": "DRAFT numeric and memory-layout proposal; not validated against RTL",
        "arithmetic": "binary32; each multiplication rounded, then each addition rounded; k ascending; bias once after all k; nearest ties even; gradual underflow; no FMA",
        "unsupported": "NaN, infinity, overflow, and any RTL-specific flush-to-zero mode",
        "layout": "DRAFT row-major elements; each FP32 low 16-bit word first; each 16-bit word low byte first",
        "tensors": entries,
    }
    manifest_path = output_dir / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return manifest_path


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", required=True, type=Path)
    args = parser.parse_args()
    print(generate(args.output_dir))


if __name__ == "__main__":
    main()
