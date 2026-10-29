"""Reference integer arithmetic for a *prototype* FFN1 fixed-point datapath.

This is an executable agreement to be reviewed with the RTL team. It is not the
competition's required number format and does not itself establish the 3% goal.

For Y = X @ W + b, each real operand is quantized by multiplying by 2**frac,
rounding half away from zero, and saturating to a signed two's-complement range.
The bias is stored in the product domain (frac = x_frac + w_frac). Each signed
product is added to a zero-initialized accumulator in increasing k order, with
saturation after every add. Bias is added afterward, again with saturation.
The final accumulator is shifted to the output frac, rounding right shifts half
away from zero, then saturated to the output width. No clocking is modeled.

The per-add saturation order is deliberate: RTL must perform the same order or
the team's agreed numeric specification must be changed on both sides.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass

import numpy as np


@dataclass(frozen=True)
class FixedPointSpec:
    """Signed integer widths and binary-point positions for one FFN1 task.

    Default values are a working example, not a precision recommendation.
    Bias and accumulator share x_frac + w_frac fractional bits.
    """

    x_bits: int = 16
    x_frac: int = 8
    w_bits: int = 16
    w_frac: int = 8
    bias_bits: int = 48
    acc_bits: int = 48
    out_bits: int = 32
    out_frac: int = 8

    @property
    def acc_frac(self) -> int:
        return self.x_frac + self.w_frac

    def validate(self) -> None:
        for name in ("x_bits", "w_bits", "bias_bits", "acc_bits", "out_bits"):
            width = getattr(self, name)
            if not isinstance(width, int) or not 2 <= width <= 60:
                raise ValueError(f"{name} must be an integer in [2, 60]")
        for name in ("x_frac", "w_frac", "out_frac"):
            frac = getattr(self, name)
            if not isinstance(frac, int) or not 0 <= frac <= 40:
                raise ValueError(f"{name} must be an integer in [0, 40]")
        if self.acc_frac > 40:
            raise ValueError("x_frac + w_frac must not exceed 40 for safe bias quantization and rounding")
        if self.bias_bits > self.acc_bits:
            raise ValueError("bias_bits must not exceed acc_bits")
        if max(self.acc_bits, self.x_bits + self.w_bits) + 1 > 62:
            raise ValueError("widths may overflow the int64 intermediate")
        if self.out_frac > self.acc_frac:
            left_shift = self.out_frac - self.acc_frac
            if self.acc_bits + left_shift > 61:
                raise ValueError("output left shift may overflow int64")

    def as_dict(self) -> dict[str, int | str]:
        values: dict[str, int | str] = asdict(self)
        values["acc_frac"] = self.acc_frac
        values["rounding"] = "nearest, ties away from zero"
        values["overflow"] = "signed saturation after quantization and every accumulator addition"
        values["dot_order"] = "k ascending; bias added after all products"
        return values


def signed_limits(bits: int) -> tuple[int, int]:
    if not isinstance(bits, int) or not 2 <= bits <= 60:
        raise ValueError("bits must be an integer in [2, 60]")
    return -(1 << (bits - 1)), (1 << (bits - 1)) - 1


def quantize_real(values: np.ndarray, bits: int, frac: int) -> np.ndarray:
    """Quantize finite reals to signed int64 with nearest/ties-away rounding."""
    lo, hi = signed_limits(bits)
    if bits > 53:
        raise ValueError("float64 cannot safely quantize every integer above 53 bits")
    if not isinstance(frac, int) or not 0 <= frac <= 40:
        raise ValueError("frac must be an integer in [0, 40]")
    array = np.asarray(values, dtype=np.float64)
    if not np.all(np.isfinite(array)):
        raise ValueError("input contains NaN or infinity")
    scaled = np.abs(array) * float(1 << frac)
    rounded = np.copysign(np.floor(scaled + 0.5), array)
    return np.clip(rounded, lo, hi).astype(np.int64)


def _require_integer_array(values: np.ndarray, bits: int, name: str) -> np.ndarray:
    array = np.asarray(values)
    if array.dtype.kind not in "iu":
        raise TypeError(f"{name} must contain integer values")
    lo, hi = signed_limits(bits)
    if np.any(array < lo) or np.any(array > hi):
        raise ValueError(f"{name} contains a value outside signed {bits}-bit range")
    return array.astype(np.int64, copy=False)


def _round_shift_away(values: np.ndarray, shift: int) -> np.ndarray:
    """Arithmetic scale change; unlike >>, negative halfway values go away."""
    if shift < 0:
        return np.left_shift(values, -shift)
    if shift == 0:
        return values.copy()
    half = 1 << (shift - 1)
    magnitude = np.abs(values)
    rounded = np.right_shift(magnitude + half, shift)
    return np.where(values < 0, -rounded, rounded)


def run_ffn1_integer(
    x_q: np.ndarray, w_q: np.ndarray, b_q: np.ndarray, spec: FixedPointSpec
) -> np.ndarray:
    """Return bit-exact signed output words for prequantized X, W and bias.

    Shapes are (rows, k), (k, columns), (columns,). The routine accepts small
    dimensions for unit tests and the official (99,64) x (64,256) task.
    """
    spec.validate()
    x = _require_integer_array(x_q, spec.x_bits, "x_q")
    w = _require_integer_array(w_q, spec.w_bits, "w_q")
    b = _require_integer_array(b_q, spec.bias_bits, "b_q")
    if x.ndim != 2 or w.ndim != 2 or b.ndim != 1:
        raise ValueError("expected x[rows,k], w[k,columns], b[columns]")
    if x.shape[1] != w.shape[0] or w.shape[1] != b.shape[0]:
        raise ValueError(f"incompatible shapes: x{x.shape}, w{w.shape}, b{b.shape}")

    lo, hi = signed_limits(spec.acc_bits)
    acc = np.zeros((x.shape[0], w.shape[1]), dtype=np.int64)
    for k in range(x.shape[1]):
        product = x[:, k : k + 1] * w[k : k + 1, :]
        acc = np.clip(acc + product, lo, hi)
    acc = np.clip(acc + b[np.newaxis, :], lo, hi)

    shifted = _round_shift_away(acc, spec.acc_frac - spec.out_frac)
    out_lo, out_hi = signed_limits(spec.out_bits)
    return np.clip(shifted, out_lo, out_hi).astype(np.int64)


@dataclass(frozen=True)
class FFN1Result:
    x_q: np.ndarray
    w_q: np.ndarray
    b_q: np.ndarray
    out_q: np.ndarray
    out_real: np.ndarray


def run_ffn1_real(
    x: np.ndarray, w: np.ndarray, b: np.ndarray, spec: FixedPointSpec
) -> FFN1Result:
    """Quantize real operands, run the integer datapath and decode its output."""
    spec.validate()
    x_q = quantize_real(x, spec.x_bits, spec.x_frac)
    w_q = quantize_real(w, spec.w_bits, spec.w_frac)
    b_q = quantize_real(b, spec.bias_bits, spec.acc_frac)
    out_q = run_ffn1_integer(x_q, w_q, b_q, spec)
    return FFN1Result(x_q, w_q, b_q, out_q, out_q.astype(np.float64) / (1 << spec.out_frac))


def normalized_rmse(actual: np.ndarray, reference: np.ndarray) -> float:
    """Contest per-layer formula: RMSE / max(RMS(float reference), 1e-8).

    See the 2026 undergraduate chip-design guide, p. 10. Local samples do
    not establish the score on the organizer's evaluation set.
    """
    got = np.asarray(actual, dtype=np.float64)
    ref = np.asarray(reference, dtype=np.float64)
    if got.shape != ref.shape or got.size == 0:
        raise ValueError("actual and reference need equal, nonempty shapes")
    if not np.all(np.isfinite(got)) or not np.all(np.isfinite(ref)):
        raise ValueError("metric inputs must be finite")
    rmse = float(np.sqrt(np.mean(np.square(got - ref))))
    rms_ref = float(np.sqrt(np.mean(np.square(ref))))
    return rmse / max(rms_ref, 1e-8)
