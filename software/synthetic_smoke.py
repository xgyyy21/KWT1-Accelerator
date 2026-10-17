"""Generate full-size, synthetic FFN1 task images for early RTL bring-up.

These deterministic vectors are NOT KWT-1 activations, weights, or evidence of
model accuracy. They exercise the prototype arithmetic and word layout while
the real model environment and the hardware protocol are still being prepared.

Usage from the project root::

    python software/synthetic_smoke.py --output-dir runs/synthetic_smoke

Each case saves float operands in ``source.npz`` without ``y_float``. The
existing packer writes integer inputs, expected outputs, and a hash manifest.
The lack of ``y_float`` deliberately makes its reference_kind say that the
comparison uses local NumPy arithmetic rather than an official model output.
"""

from __future__ import annotations

import argparse
from hashlib import sha256
import json
from pathlib import Path

import numpy as np

try:
    from .ffn1_numeric import FixedPointSpec
    from .pack_tensors import create_task_pack, unpack_words_to_signed
except ImportError:  # direct script execution
    from ffn1_numeric import FixedPointSpec
    from pack_tensors import create_task_pack, unpack_words_to_signed


ROWS, INNER, COLUMNS = 99, 64, 256
CASE_NAMES = ("all_zero", "sentinels", "address_pattern")
PURPOSE = "SYNTHETIC_RTL_SMOKE_ONLY"


def _real_from_encoded(encoded: np.ndarray, frac: int) -> np.ndarray:
    # Every chosen encoded value is small enough to convert exactly to float64.
    return encoded.astype(np.float64) / (1 << frac)


def build_integer_cases() -> dict[str, tuple[np.ndarray, np.ndarray, np.ndarray]]:
    """Construct three deterministic prototype-format operand sets.

    Values are encoded Q-format integers here, so exact half-way cases remain
    exact through the conversion to real input and subsequent requantization.
    """
    def zeros() -> tuple[np.ndarray, np.ndarray, np.ndarray]:
        return (
            np.zeros((ROWS, INNER), dtype=np.int64),
            np.zeros((INNER, COLUMNS), dtype=np.int64),
            np.zeros(COLUMNS, dtype=np.int64),
        )

    all_zero = zeros()

    x, w, b = zeros()
    # Two distinct rows at the first K index and an early output column.
    x[0, 0] = 256             # +1.0, in Q8
    x[98, 0] = 512            # +2.0, last row
    w[0, 1] = 256             # +1.0
    # Signed two-term accumulation and bias. Row 1, column 4 is -2.25.
    x[1, 2] = -512           # -2.0
    w[2, 4] = 384            # +1.5
    x[1, 5] = 256            # +1.0
    w[5, 4] = 128            # +0.5
    b[4] = 16384             # +0.25, in product Q16
    # Bias-only output checks broadcast to every row.
    b[0] = 81920             # +1.25
    # Accumulator = +/-128 in Q16; shifting to Q8 is an exact half-way tie.
    x[2, 7] = 128            # +0.5
    w[7, 7] = 1              # +1/256
    x[3, 8] = -128           # -0.5
    w[8, 8] = 1
    # Simultaneously touch the last row, last K index, last output column.
    x[98, 63] = 768          # +3.0
    w[63, 255] = -512        # -2.0
    b[255] = -32768          # -0.5
    sentinels = (x, w, b)

    # A dense, signed, periodic pattern exercises every address and most word
    # positions. All constants and operations are deterministic, with no RNG.
    row = np.arange(ROWS, dtype=np.int64)[:, None]
    k = np.arange(INNER, dtype=np.int64)
    column = np.arange(COLUMNS, dtype=np.int64)[None, :]
    x = (((row * 13 + k[None, :] * 7) % 19) - 9) * 32
    w = (((k[:, None] * 11 + column * 5) % 17) - 8) * 16
    b = (((np.arange(COLUMNS, dtype=np.int64) * 3) % 23) - 11) * 1024
    address_pattern = (x, w, b)

    return dict(zip(CASE_NAMES, (all_zero, sentinels, address_pattern)))


# These are hand-calculated Q8 output words, independent of the packer's
# expected tensor. They provide a quick, explicit hardware/debugging checklist.
SENTINEL_EXPECTED_Q8 = {
    (0, 0): 320,       # +1.25 bias only
    (98, 0): 320,      # bias reaches final row
    (0, 1): 256,       # first row / first K index
    (98, 1): 512,      # final row / first K index
    (0, 4): 64,        # +0.25 bias without data product
    (1, 4): -576,      # -2*1.5 + 1*0.5 + 0.25 = -2.25
    (2, 7): 1,         # +0.5 LSB rounds away from zero
    (3, 8): -1,        # -0.5 LSB rounds away from zero
    (0, 255): -128,    # -0.5 bias at last output column
    (98, 255): -1664,  # +3*(-2) - 0.5 = -6.5, last indices
}


def _read_expected(path: Path, spec: FixedPointSpec) -> np.ndarray:
    binary = path.read_bytes()
    words = np.frombuffer(binary, dtype="<u2")
    return unpack_words_to_signed(words, (ROWS, COLUMNS), spec.out_bits)


def generate(output_dir: Path) -> dict[str, object]:
    """Write all full-size cases; refuse to overwrite a nonempty directory."""
    output_dir = Path(output_dir)
    if output_dir.exists() and any(output_dir.iterdir()):
        raise ValueError(f"Output directory is not empty: {output_dir}")

    spec = FixedPointSpec()  # The published prototype; not a final RTL choice.
    spec.validate()
    cases = build_integer_cases()
    output_dir.mkdir(parents=True, exist_ok=True)
    results = []
    for name in CASE_NAMES:
        x_q, w_q, b_q = cases[name]
        case_dir = output_dir / name
        case_dir.mkdir()
        source = case_dir / "source.npz"
        np.savez_compressed(
            source,
            x=_real_from_encoded(x_q, spec.x_frac),
            w=_real_from_encoded(w_q, spec.w_frac),
            b=_real_from_encoded(b_q, spec.acc_frac),
        )
        packed_dir = case_dir / "packed"
        packed = create_task_pack(source, packed_dir, spec)
        if packed["reference_kind"] != "local_numpy_x_matmul_w_plus_b":
            raise AssertionError("synthetic source must not claim official y_float")
        packed["purpose"] = PURPOSE
        packed["data_origin"] = "deterministic_synthetic_operands_not_official_kwt"
        packed["accuracy_note"] = (
            "Synthetic full-size RTL bring-up vector only; this NRMSE is not "
            "a KWT-1 12-layer or competition precision result."
        )
        (packed_dir / "manifest.json").write_text(
            json.dumps(packed, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        expected = _read_expected(packed_dir / "expected.bin", spec)
        if name == "all_zero" and np.count_nonzero(expected):
            raise AssertionError("all-zero case produced a nonzero output")
        if name == "sentinels":
            for (row, column), hand_value in SENTINEL_EXPECTED_Q8.items():
                if int(expected[row, column]) != hand_value:
                    raise AssertionError(
                        f"sentinel [{row},{column}] is {expected[row, column]}, "
                        f"but hand calculation gives {hand_value}"
                    )
        results.append({
            "name": name,
            "source": f"{name}/source.npz",
            "packed_manifest": f"{name}/packed/manifest.json",
            "expected_sha256": sha256((packed_dir / "expected.bin").read_bytes()).hexdigest(),
            "description": {
                "all_zero": "zero input/weights/bias; catches stale or unwritten output",
                "sentinels": "signed products, bias broadcast, final row/K/column, positive and negative rounding ties",
                "address_pattern": "dense deterministic signed values across all rows, K positions, and columns",
            }[name],
        })

    manifest: dict[str, object] = {
        "purpose": PURPOSE,
        "warning": "Synthetic RTL smoke only. No official KWT-1 model or speech data was used; do not cite this as 12-layer precision evidence.",
        "model_reference_kind": "none",
        "prototype_numeric_spec": spec.as_dict(),
        "shapes": {"x": [ROWS, INNER], "w": [INNER, COLUMNS], "b": [COLUMNS], "expected": [ROWS, COLUMNS]},
        "sentinel_expected_q8": {f"{row},{column}": value for (row, column), value in SENTINEL_EXPECTED_Q8.items()},
        "cases": results,
    }
    (output_dir / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    try:
        result = generate(args.output_dir)
    except (OSError, ValueError, AssertionError) as exc:
        parser.error(str(exc))
    print(f"Generated {len(result['cases'])} synthetic full-size RTL smoke tasks in {args.output_dir}")
    print("SYNTHETIC ONLY: not official KWT-1 data or precision evidence.")


if __name__ == "__main__":
    main()
