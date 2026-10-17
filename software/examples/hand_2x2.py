"""Generate a hand-calculated 2x2 FFN1 task using the *prototype* contract.

Run from the project root with::

    python -m software.examples.hand_2x2 --output-dir runs/hand_2x2

This is synthetic arithmetic/address bring-up data, not KWT-1 accuracy data.
The independent literal checks make the example useful for detecting mistakes
in either the numeric model or the image serialization.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np

from software.ffn1_numeric import FixedPointSpec
from software.pack_tensors import create_task_pack


X = np.array([[1.0, -2.0], [0.5, 3.0]], dtype=np.float64)
W = np.array([[2.0, -1.0], [1.5, 0.5]], dtype=np.float64)
B = np.array([0.25, -0.5], dtype=np.float64)

# These literals are calculated by hand from the table in HAND_2X2.md.
EXPECTED_WORDS = {
    "x.mem": "0100\nfe00\n0080\n0300\n",
    "w.mem": "0200\nff00\n0180\n0080\n",
    "b.mem": "4000\n0000\n0000\n8000\nffff\nffff\n",
    "expected.mem": "ff40\nffff\nfd80\nffff\n05c0\n0000\n0080\n0000\n",
}
EXPECTED_BINARY = {
    "x.bin": "000100fe80000003",
    "w.bin": "000200ff80018000",
    "b.bin": "0040000000000080ffffffff",
    "expected.bin": "40ffffff80fdffffc005000080000000",
}


def generate(output_dir: Path) -> Path:
    output_dir = Path(output_dir)
    if output_dir.exists() and any(output_dir.iterdir()):
        raise ValueError(f"output directory is not empty: {output_dir}")
    output_dir.mkdir(parents=True, exist_ok=True)
    source = output_dir / "source.npz"
    np.savez_compressed(source, x=X, w=W, b=B)
    packed_dir = output_dir / "packed"
    manifest = create_task_pack(source, packed_dir, FixedPointSpec())
    if manifest["reference_kind"] != "local_numpy_x_matmul_w_plus_b":
        raise AssertionError("synthetic example must not claim a model reference")

    for name, expected in EXPECTED_WORDS.items():
        actual = (packed_dir / name).read_text(encoding="ascii")
        if actual != expected:
            raise AssertionError(f"{name} differs from the hand-calculated words")
    for name, expected in EXPECTED_BINARY.items():
        actual = (packed_dir / name).read_bytes().hex()
        if actual != expected:
            raise AssertionError(f"{name} differs from the hand-calculated bytes")

    manifest["purpose"] = "SYNTHETIC_HAND_CALCULATED_RTL_BRINGUP_ONLY"
    manifest["data_split"] = "synthetic-smoke"
    manifest["source_id"] = "software/examples/hand_2x2.py"
    manifest["accuracy_note"] = (
        "This 2x2 synthetic arithmetic example is not a KWT-1 precision result."
    )
    (packed_dir / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return packed_dir


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", required=True, type=Path)
    args = parser.parse_args()
    try:
        packed_dir = generate(args.output_dir)
    except (OSError, ValueError, AssertionError) as exc:
        parser.error(str(exc))
    print(f"Hand-checked prototype images: {packed_dir}")
    print("SYNTHETIC ONLY: not KWT-1 model or accuracy evidence.")


if __name__ == "__main__":
    main()
