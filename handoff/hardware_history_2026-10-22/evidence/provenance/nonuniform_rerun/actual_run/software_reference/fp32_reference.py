"""Draft, executable FP32 arithmetic contract for the KWT-1 first linear layer.

This module is deliberately independent of NumPy, BLAS, TensorFlow and the
host's floating-point evaluation order. It represents each *finite* binary32
operand as an exact signed integer times a power of two, then rounds every
multiplication and addition separately to binary32 (nearest, ties to even).

It is a proposal for software/RTL discussion, NOT a frozen hardware contract.
NaN, infinity and overflow are rejected because the RTL policy is unresolved.
Gradual underflow is modeled; flushing subnormals to zero would need a new
contract and new expected vectors.
"""

from __future__ import annotations

import struct
from typing import Dict, List, Sequence, Tuple


class UnsupportedFP32Case(ValueError):
    """The pending hardware numeric contract has not defined this case."""


def _word(bits: int) -> int:
    if isinstance(bits, bool) or not isinstance(bits, int) or not 0 <= bits <= 0xFFFFFFFF:
        raise ValueError("FP32 operand must be an unsigned 32-bit integer bit pattern")
    return bits


def from_float(value: float) -> int:
    """Encode a human-written finite number as IEEE binary32 bits."""
    try:
        bits = struct.unpack("<I", struct.pack("<f", float(value)))[0]
    except (OverflowError, TypeError, ValueError) as exc:
        raise UnsupportedFP32Case("input does not fit a finite binary32 value") from exc
    _decode_finite(bits)
    return bits


def to_float(bits: int) -> float:
    """Decode a finite binary32 bit pattern for display, never for arithmetic."""
    _decode_finite(bits)
    return struct.unpack("<f", struct.pack("<I", bits))[0]


def _decode_finite(bits: int) -> Tuple[int, int, bool]:
    """Return (signed mantissa, binary exponent, negative-zero flag)."""
    bits = _word(bits)
    sign = bool(bits >> 31)
    exp_field = (bits >> 23) & 0xFF
    frac = bits & 0x7FFFFF
    if exp_field == 0xFF:
        raise UnsupportedFP32Case("NaN and infinity need a jointly frozen RTL policy")
    if exp_field == 0:
        mantissa, exponent = frac, -149
    else:
        mantissa, exponent = (1 << 23) | frac, exp_field - 150
    return (-mantissa if sign else mantissa), exponent, sign and mantissa == 0


def _round_right_even(number: int, shift: int) -> int:
    """Round nonnegative number / 2**shift to nearest, ties to even."""
    if shift <= 0:
        return number << -shift
    quotient, remainder = divmod(number, 1 << shift)
    halfway = 1 << (shift - 1)
    if remainder > halfway or (remainder == halfway and (quotient & 1)):
        quotient += 1
    return quotient


def _round_dyadic(number: int, exponent: int, negative_zero: bool = False) -> int:
    """Round the exact value number * 2**exponent to finite binary32 bits."""
    if number == 0:
        return 0x80000000 if negative_zero else 0
    sign = 0x80000000 if number < 0 else 0
    magnitude = abs(number)
    leading_exponent = magnitude.bit_length() - 1 + exponent
    if leading_exponent > 127:
        raise UnsupportedFP32Case("FP32 overflow needs a jointly frozen RTL policy")

    if leading_exponent >= -126:
        # Round the exact significand to 24 bits, including the implicit 1.
        shift = magnitude.bit_length() - 24
        significand = _round_right_even(magnitude, shift)
        if significand == 1 << 24:
            significand >>= 1
            leading_exponent += 1
        if leading_exponent > 127:
            raise UnsupportedFP32Case("FP32 overflow needs a jointly frozen RTL policy")
        return sign | ((leading_exponent + 127) << 23) | (significand & 0x7FFFFF)

    # Subnormals use units of 2**-149. A rounded result of 2**23 is the
    # smallest normal value. A rounded result of zero retains the exact sign.
    scaled_shift = -(exponent + 149)
    significand = _round_right_even(magnitude, scaled_shift)
    if significand == 1 << 23:
        return sign | (1 << 23)
    return sign | significand


def multiply_bits(a_bits: int, b_bits: int) -> int:
    """One independently rounded binary32 multiplication (no FMA)."""
    a, a_exp, _ = _decode_finite(a_bits)
    b, b_exp, _ = _decode_finite(b_bits)
    negative_zero = bool((a_bits ^ b_bits) & 0x80000000)
    return _round_dyadic(a * b, a_exp + b_exp, negative_zero)


def add_bits(a_bits: int, b_bits: int) -> int:
    """One independently rounded binary32 addition (nearest, ties even)."""
    a, a_exp, a_neg_zero = _decode_finite(a_bits)
    b, b_exp, b_neg_zero = _decode_finite(b_bits)
    if a == 0 and b == 0:
        # For round-to-nearest, -0 + -0 is -0; other zero combinations are +0.
        return 0x80000000 if a_neg_zero and b_neg_zero else 0
    common_exp = min(a_exp, b_exp)
    exact_sum = (a << (a_exp - common_exp)) + (b << (b_exp - common_exp))
    return _round_dyadic(exact_sum, common_exp)


def _validate_shapes(
    x: Sequence[Sequence[int]], w: Sequence[Sequence[int]], bias: Sequence[int]
) -> Tuple[int, int, int]:
    if not x or not w or not bias:
        raise ValueError("X, W and bias must be nonempty")
    rows, depth, columns = len(x), len(w), len(bias)
    if depth != len(x[0]):
        raise ValueError("X columns must equal W rows")
    for row in x:
        if len(row) != depth:
            raise ValueError("X has ragged rows")
        for bits in row:
            _decode_finite(bits)
    for row in w:
        if len(row) != columns:
            raise ValueError("W columns must equal bias length; no ragged rows")
        for bits in row:
            _decode_finite(bits)
    for bits in bias:
        _decode_finite(bits)
    return rows, depth, columns


def run_ffn1_bits(
    x: Sequence[Sequence[int]], w: Sequence[Sequence[int]], bias: Sequence[int]
) -> List[List[int]]:
    """Compute Y=XW+b, increasing k, product/add rounded separately.

    For each output: acc starts at +0; at each k compute round32(X*W),
    then acc=round32(acc+product); after all k, round32(acc+b[j]).
    No accumulator reset is permitted at an internal K-tile boundary.
    """
    rows, depth, columns = _validate_shapes(x, w, bias)
    output = [[0] * columns for _ in range(rows)]
    for row in range(rows):
        for column in range(columns):
            acc = 0
            for k in range(depth):
                product = multiply_bits(x[row][k], w[k][column])
                acc = add_bits(acc, product)
            output[row][column] = add_bits(acc, bias[column])
    return output


def trace_cell(
    x: Sequence[Sequence[int]], w: Sequence[Sequence[int]], bias: Sequence[int],
    row: int, column: int
) -> Dict[str, object]:
    """Return each rounded product, partial sum and one final bias addition."""
    rows, depth, columns = _validate_shapes(x, w, bias)
    if not 0 <= row < rows or not 0 <= column < columns:
        raise IndexError("output coordinate is outside Y")
    acc = 0
    steps = []
    for k in range(depth):
        product = multiply_bits(x[row][k], w[k][column])
        acc = add_bits(acc, product)
        steps.append({"k": k, "product_bits": product, "acc_bits": acc})
    result = add_bits(acc, bias[column])
    return {"row": row, "column": column, "steps": steps,
            "bias_bits": bias[column], "result_bits": result}


def low16_first_words(bits: int) -> Tuple[int, int]:
    """DRAFT layout: one binary32 element in two 16-bit SRAM words."""
    bits = _word(bits)
    return bits & 0xFFFF, bits >> 16


def from_low16_first_words(low: int, high: int) -> int:
    for part in (low, high):
        if isinstance(part, bool) or not isinstance(part, int) or not 0 <= part <= 0xFFFF:
            raise ValueError("each SRAM word must be 16-bit unsigned")
    return low | (high << 16)


def row_major_words(matrix: Sequence[Sequence[int]]) -> List[int]:
    """DRAFT layout: row-major elements; low 16-bit SRAM word first."""
    words = []
    for row in matrix:
        for bits in row:
            words.extend(low16_first_words(bits))
    return words


def words_to_little_endian_bytes(words: Sequence[int]) -> bytes:
    """DRAFT .bin layout: low byte before high byte within each SRAM word."""
    result = bytearray()
    for word in words:
        if isinstance(word, bool) or not isinstance(word, int) or not 0 <= word <= 0xFFFF:
            raise ValueError("each SRAM word must be 16-bit unsigned")
        result.extend(struct.pack("<H", word))
    return bytes(result)
