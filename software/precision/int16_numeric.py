"""Candidate INT16 FFN1 arithmetic with integer MACs and nearest-even rounding.

This is separate from the historical Q16.8 prototype, whose ties-away rule is
kept intact. The current candidate uses power-of-two scales, so its output
requantization is an integer shift rather than a floating-point multiplier.
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np

from software.ffn1_numeric import signed_limits


SYMMETRIC_LIMIT = 32767  # -32768 is deliberately reserved, never emitted.


@dataclass(frozen=True)
class LayerFormat:
    x_frac: int
    w_frac: int | tuple[int, ...]
    y_frac: int
    bias_bits: int = 32
    acc_bits: int = 38

    def validate(self, columns: int) -> np.ndarray:
        if not isinstance(self.x_frac, int) or not 0 <= self.x_frac <= 30:
            raise ValueError("x_frac must be 0..30")
        if not isinstance(self.y_frac, int) or not 0 <= self.y_frac <= 30:
            raise ValueError("y_frac must be 0..30")
        if not isinstance(self.bias_bits, int) or not 2 <= self.bias_bits <= 52:
            raise ValueError("bias_bits must be 2..52")
        if not isinstance(self.acc_bits, int) or not self.bias_bits <= self.acc_bits <= 52:
            raise ValueError("acc_bits must be bias_bits..52")
        if isinstance(self.w_frac, int):
            fracs = np.full(columns, self.w_frac, dtype=np.int64)
        else:
            if len(self.w_frac) != columns or any(not isinstance(v, int) for v in self.w_frac):
                raise ValueError("w_frac must have one integer per output channel")
            fracs = np.asarray(self.w_frac, dtype=np.int64)
        if np.any((fracs < 0) | (fracs > 30)):
            raise ValueError("w_frac must be 0..30")
        if np.any(self.x_frac + fracs > 40):
            raise ValueError("x_frac+w_frac must be <=40")
        if np.any(self.x_frac + fracs < self.y_frac):
            raise ValueError("output scale cannot exceed product scale")
        return fracs


def _quantize(values: np.ndarray, fractional_bits: np.ndarray | int,
              low: int, high: int) -> tuple[np.ndarray, int]:
    array = np.asarray(values, dtype=np.float64)
    if not np.isfinite(array).all():
        raise ValueError("quantization input contains NaN or Inf")
    rounded = np.rint(array * np.exp2(fractional_bits))  # IEEE ties to even.
    clips = int(np.count_nonzero((rounded < low) | (rounded > high)))
    return np.clip(rounded, low, high).astype(np.int64), clips


def round_shift_even(values: np.ndarray, shift: int) -> np.ndarray:
    """Bit-exact signed right shift with ties-to-even, for bounded int64 data."""
    if not isinstance(shift, int) or not 0 <= shift <= 40:
        raise ValueError("shift must be 0..40")
    array = np.asarray(values, dtype=np.int64)
    if shift == 0:
        return array.copy()
    if np.any(array == np.iinfo(np.int64).min):
        raise ValueError("int64 minimum cannot be safely negated")
    mag = np.abs(array)
    whole = mag >> shift
    rem = mag & ((1 << shift) - 1)
    half = 1 << (shift - 1)
    up = (rem > half) | ((rem == half) & ((whole & 1) != 0))
    rounded = whole + up.astype(np.int64)
    return np.where(array < 0, -rounded, rounded)


def signed_width_for_bound(bound: int) -> int:
    """Minimum signed two's-complement width containing [-bound,+bound]."""
    if bound < 0:
        raise ValueError("bound must be nonnegative")
    return max(2, int(bound).bit_length() + 1)


def evaluate_layer(x: np.ndarray, w: np.ndarray, bias: np.ndarray,
                   fmt: LayerFormat) -> dict[str, object]:
    """Quantize operands, compute every integer MAC, and decode INT16 output."""
    x = np.asarray(x, dtype=np.float64)
    w = np.asarray(w, dtype=np.float64)
    bias = np.asarray(bias, dtype=np.float64)
    if x.ndim != 2 or w.ndim != 2 or bias.ndim != 1 or x.shape[1] != w.shape[0] or w.shape[1] != bias.size:
        raise ValueError("expected X[rows,K], W[K,columns], bias[columns]")
    if not all(np.isfinite(v).all() for v in (x, w, bias)):
        raise ValueError("inputs must be finite")
    w_frac = fmt.validate(w.shape[1])
    product_frac = fmt.x_frac + w_frac
    x_q, x_clips = _quantize(x, fmt.x_frac, -SYMMETRIC_LIMIT, SYMMETRIC_LIMIT)
    w_q, w_clips = _quantize(w, w_frac[np.newaxis, :], -SYMMETRIC_LIMIT, SYMMETRIC_LIMIT)
    b_lo, b_hi = signed_limits(fmt.bias_bits)
    b_q, b_clips = _quantize(bias, product_frac, b_lo, b_hi)
    acc_lo, acc_hi = signed_limits(fmt.acc_bits)
    acc = np.zeros((x.shape[0], w.shape[1]), dtype=np.int64)
    mac_clips = 0
    observed_min = 0
    observed_max = 0
    for k in range(x.shape[1]):
        raw = acc + x_q[:, k : k + 1] * w_q[k : k + 1, :]
        mac_clips += int(np.count_nonzero((raw < acc_lo) | (raw > acc_hi)))
        acc = np.clip(raw, acc_lo, acc_hi)
        observed_min = min(observed_min, int(acc.min()))
        observed_max = max(observed_max, int(acc.max()))
    raw = acc + b_q[np.newaxis, :]
    bias_clips = int(np.count_nonzero((raw < acc_lo) | (raw > acc_hi)))
    acc = np.clip(raw, acc_lo, acc_hi)
    observed_min = min(observed_min, int(acc.min()))
    observed_max = max(observed_max, int(acc.max()))
    output = np.empty_like(acc)
    for shift in np.unique(product_frac - fmt.y_frac):
        mask = (product_frac - fmt.y_frac) == shift
        output[:, mask] = round_shift_even(acc[:, mask], int(shift))
    output_clips = int(np.count_nonzero((output < -SYMMETRIC_LIMIT) | (output > SYMMETRIC_LIMIT)))
    output = np.clip(output, -SYMMETRIC_LIMIT, SYMMETRIC_LIMIT)
    # For any ordering of these K signed terms, the sum of absolute products
    # plus |bias| bounds every partial and final sum for each output element.
    abs_sum = np.abs(x_q) @ np.abs(w_q) + np.abs(b_q)[np.newaxis, :]
    bound = int(abs_sum.max())
    return {
        "x_q": x_q, "w_q": w_q, "bias_q": b_q,
        "y_q": output, "y_real": output.astype(np.float64) / float(1 << fmt.y_frac),
        "saturation": {"x": x_clips, "w": w_clips, "bias": b_clips,
                       "mac": mac_clips, "bias_add": bias_clips, "y": output_clips},
        "accumulator": {"observed_min": observed_min, "observed_max": observed_max,
                        "theoretical_min": -bound, "theoretical_max": bound,
                        "minimum_signed_bits_for_this_data": signed_width_for_bound(bound),
                        "configured_bits": fmt.acc_bits},
    }
