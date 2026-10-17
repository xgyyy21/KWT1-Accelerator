"""Pack one FFN1 task into auditable 16-bit-word images for RTL/driver tests.

Input NPZ requires ``x`` [M,K], ``w`` [K,N], and ``b`` [N] as real arrays.
Optional ``y_float`` [M,N] is the official floating reference captured from
the specified model. Without it, the reported comparison is merely to local
NumPy ``x @ w + b`` and is NOT a competition accuracy measurement.

Storage convention is a *prototype*: signed two's-complement elements, C-order
(last index fastest), each element split into 16-bit words low-word first.
Each ``.mem`` line is one 16-bit hex word, matching the binary files' word
sequence; each binary word's two bytes are little-endian. The eventual E203
memory map/weight tiling must be agreed with RTL and may need a new packer.
"""

from __future__ import annotations

import argparse
from dataclasses import asdict
from hashlib import sha256
import json
from pathlib import Path

import numpy as np

try:
    from .ffn1_numeric import FixedPointSpec, normalized_rmse, run_ffn1_real, signed_limits
except ImportError:  # allows direct ``python software/pack_tensors.py`` invocation
    from ffn1_numeric import FixedPointSpec, normalized_rmse, run_ffn1_real, signed_limits


WORD_BITS = 16


def pack_signed_to_words(values: np.ndarray, bits: int) -> np.ndarray:
    """Flatten signed elements in C order, low 16-bit word first per element."""
    if bits % WORD_BITS:
        raise ValueError("serialized element width must be a multiple of 16")
    lo, hi = signed_limits(bits)
    array = np.asarray(values)
    if array.dtype.kind not in "iu":
        raise TypeError("packing requires integer values")
    flat = array.reshape(-1, order="C")
    if np.any(flat < lo) or np.any(flat > hi):
        raise ValueError(f"value does not fit signed {bits}-bit range")
    mask = (1 << bits) - 1
    words: list[int] = []
    for value in flat:
        encoded = int(value) & mask
        words.extend((encoded >> shift) & 0xFFFF for shift in range(0, bits, WORD_BITS))
    return np.asarray(words, dtype=np.uint16)


def unpack_words_to_signed(words: np.ndarray, shape: tuple[int, ...], bits: int) -> np.ndarray:
    """Inverse of :func:`pack_signed_to_words`; useful for driver/RTL checks."""
    if bits % WORD_BITS:
        raise ValueError("serialized element width must be a multiple of 16")
    signed_limits(bits)
    sequence = np.asarray(words)
    if sequence.dtype.kind not in "iu" or np.any(sequence > 0xFFFF) or np.any(sequence < 0):
        raise ValueError("words must be unsigned 16-bit values")
    count = int(np.prod(shape))
    words_per_element = bits // WORD_BITS
    if sequence.size != count * words_per_element:
        raise ValueError("word count does not match shape and element width")
    decoded: list[int] = []
    sign = 1 << (bits - 1)
    full = 1 << bits
    flat = sequence.reshape(-1)
    for offset in range(0, flat.size, words_per_element):
        encoded = 0
        for index in range(words_per_element):
            encoded |= int(flat[offset + index]) << (WORD_BITS * index)
        decoded.append(encoded - full if encoded & sign else encoded)
    return np.asarray(decoded, dtype=np.int64).reshape(shape, order="C")


def _write_tensor(directory: Path, name: str, array: np.ndarray, bits: int) -> dict[str, object]:
    words = pack_signed_to_words(array, bits)
    # Explicit little-endian dtype: host byte order must not change the file.
    binary = words.astype("<u2", copy=False).tobytes()
    (directory / f"{name}.bin").write_bytes(binary)
    (directory / f"{name}.mem").write_text(
        "".join(f"{int(word):04x}\n" for word in words), encoding="ascii"
    )
    return {
        "shape": list(array.shape),
        "element_bits": bits,
        "element_count": int(array.size),
        "word_count": int(words.size),
        "binary_file": f"{name}.bin",
        "readmemh_file": f"{name}.mem",
        "binary_sha256": sha256(binary).hexdigest(),
    }


def create_task_pack(source_npz: Path, output_dir: Path, spec: FixedPointSpec) -> dict[str, object]:
    """Quantize one task, write images and return its self-describing manifest."""
    spec.validate()
    for name in ("x_bits", "w_bits", "bias_bits", "out_bits"):
        if getattr(spec, name) % WORD_BITS:
            raise ValueError(f"{name} must be a multiple of 16 for the word-image format")
    source_npz = Path(source_npz)
    output_dir = Path(output_dir)
    with np.load(source_npz, allow_pickle=False) as data:
        missing = {"x", "w", "b"}.difference(data.files)
        if missing:
            raise ValueError(f"NPZ is missing {sorted(missing)}")
        x = np.asarray(data["x"], dtype=np.float64)
        w = np.asarray(data["w"], dtype=np.float64)
        b = np.asarray(data["b"], dtype=np.float64)
        provided_ref = "y_float" in data.files
        reference = np.asarray(data["y_float"], dtype=np.float64) if provided_ref else x @ w + b

    # A provided array is a reference *claim*. Check its arithmetic before
    # turning it into packed files or reporting any error against it. This
    # catches a wrong layer, transposed weights, and post-GELU outputs.
    independent_float = x @ w + b
    if reference.shape != independent_float.shape or not np.all(np.isfinite(reference)):
        raise ValueError("y_float has the wrong shape or a nonfinite value")
    if provided_ref and not np.allclose(independent_float, reference, rtol=1e-4, atol=1e-4):
        raise ValueError("provided y_float does not agree with independent X @ W + b")
    independent_float_max_abs_error = float(np.max(np.abs(independent_float - reference)))

    result = run_ffn1_real(x, w, b, spec)
    if result.out_real.shape != reference.shape:
        raise ValueError(f"reference shape {reference.shape} != output shape {result.out_real.shape}")
    error = normalized_rmse(result.out_real, reference)

    output_dir.mkdir(parents=True, exist_ok=True)
    tensors = {
        "x": _write_tensor(output_dir, "x", result.x_q, spec.x_bits),
        "w": _write_tensor(output_dir, "w", result.w_q, spec.w_bits),
        "b": _write_tensor(output_dir, "b", result.b_q, spec.bias_bits),
        "expected": _write_tensor(output_dir, "expected", result.out_q, spec.out_bits),
    }
    np.save(output_dir / "expected_dequantized.npy", result.out_real)
    manifest: dict[str, object] = {
        "status": "prototype numeric and memory contract; review with RTL team before freezing",
        "source_file": str(source_npz.resolve()),
        "source_sha256": sha256(source_npz.read_bytes()).hexdigest(),
        "arithmetic": spec.as_dict(),
        "storage": {
            "word_bits": WORD_BITS,
            "word_byte_order": "little-endian",
            "element_word_order": "least-significant 16-bit word first",
            "element_signedness": "two's complement signed",
            "tensor_order": "C row-major, last index fastest",
            "x_index": "x[row,k]",
            "w_index": "w[k,column]",
            "b_index": "b[column]",
            "expected_index": "expected[row,column]",
        },
        "tensors": tensors,
        "reference_kind": "provided_y_float" if provided_ref else "local_numpy_x_matmul_w_plus_b",
        "independent_float_max_abs_error": independent_float_max_abs_error,
        "normalized_rmse": error,
        "accuracy_note": "A single pack does not prove the maximum error across all 12 model layers or the unseen evaluation samples.",
    }
    (output_dir / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=False, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return manifest


def main() -> None:
    default = FixedPointSpec()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, required=True, help="NPZ with x, w, b and optionally y_float")
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--spec", type=Path, help="JSON with all FixedPointSpec fields")
    for field in ("x_bits", "x_frac", "w_bits", "w_frac", "bias_bits", "acc_bits", "out_bits", "out_frac"):
        parser.add_argument(f"--{field.replace('_', '-')}", type=int, default=None)
    args = parser.parse_args()
    fields = asdict(default)
    if args.spec is not None:
        loaded = json.loads(args.spec.read_text(encoding="utf-8"))
        if set(loaded) != set(fields):
            parser.error(f"--spec must contain exactly {tuple(fields)}")
        fields.update(loaded)
    for field in fields:
        override = getattr(args, field)
        if override is not None:
            fields[field] = override
    spec = FixedPointSpec(**fields)
    manifest = create_task_pack(args.input, args.output_dir, spec)
    print(f"Wrote {args.output_dir / 'manifest.json'}")
    print(f"NRMSE against {manifest['reference_kind']}: {manifest['normalized_rmse']:.6%}")
    print("Prototype format only; verify all 12 layers and agree arithmetic/storage with RTL.")


if __name__ == "__main__":
    main()
