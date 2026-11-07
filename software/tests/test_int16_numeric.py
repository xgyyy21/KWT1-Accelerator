"""Checks for the new nearest-even INT16 candidate arithmetic."""

import unittest

import numpy as np

from software.precision.int16_numeric import (
    LayerFormat, evaluate_layer, round_shift_even, signed_width_for_bound,
)


class Int16NumericTests(unittest.TestCase):
    def test_integer_right_shift_rounds_half_to_even_for_both_signs(self) -> None:
        values = np.array([-7, -6, -5, -3, -2, -1, 0, 1, 2, 3, 5, 6, 7])
        np.testing.assert_array_equal(
            round_shift_even(values, 1),
            np.array([-4, -3, -2, -2, -1, 0, 0, 0, 1, 2, 2, 3, 4]),
        )

    def test_integer_mac_bias_and_channel_scales(self) -> None:
        x = np.array([[0.5, -0.25], [1.0, 0.5]])
        w = np.array([[0.5, 0.25], [1.0, -0.5]])
        bias = np.array([0.25, 0.125])
        fmt = LayerFormat(x_frac=2, w_frac=(2, 3), y_frac=2)
        result = evaluate_layer(x, w, bias, fmt)
        np.testing.assert_array_equal(result["x_q"], [[2, -1], [4, 2]])
        np.testing.assert_array_equal(result["w_q"], [[2, 2], [4, -4]])
        np.testing.assert_array_equal(result["bias_q"], [4, 4])
        # Column 0: (2*2 + -1*4 + 4)/2^2 = 1/4; row 1 = 20/4 = 5.
        # Column 1: (2*2 + -1*-4 + 4)/2^(2+3) = 12/32;
        # rescaling by 2^2 gives 1.5, which ties to the even integer 2.
        np.testing.assert_array_equal(result["y_q"], [[1, 2], [5, 0]])
        self.assertEqual(sum(result["saturation"].values()), 0)

    def test_symmetric_int16_reserves_negative_32768(self) -> None:
        result = evaluate_layer(
            np.array([[-32768.0]]), np.array([[1.0]]), np.array([0.0]),
            LayerFormat(x_frac=0, w_frac=0, y_frac=0),
        )
        self.assertEqual(int(result["x_q"][0, 0]), -32767)
        self.assertEqual(result["saturation"]["x"], 1)
        self.assertEqual(int(result["y_q"][0, 0]), -32767)

    def test_operand_halfway_uses_even_and_full_scale_needs_38_acc_bits(self) -> None:
        ties = evaluate_layer(
            np.array([[0.5, -0.5]]), np.array([[1.0], [1.0]]),
            np.array([0.0]), LayerFormat(x_frac=0, w_frac=0, y_frac=0),
        )
        np.testing.assert_array_equal(ties["x_q"], [[0, 0]])
        full_scale = evaluate_layer(
            np.full((1, 64), 32767.0), np.full((64, 1), 32767.0),
            np.array([float((1 << 31) - 1)]),
            LayerFormat(x_frac=0, w_frac=0, y_frac=0),
        )
        self.assertEqual(full_scale["accumulator"]["theoretical_max"],
                         64 * 32767**2 + (1 << 31) - 1)
        self.assertEqual(full_scale["accumulator"]["minimum_signed_bits_for_this_data"], 38)
        self.assertEqual(full_scale["saturation"]["mac"], 0)
        self.assertEqual(full_scale["saturation"]["bias_add"], 0)

    def test_accumulator_bound_width(self) -> None:
        self.assertEqual(signed_width_for_bound(0), 2)
        self.assertEqual(signed_width_for_bound(1), 2)
        self.assertEqual(signed_width_for_bound(2), 3)
        self.assertEqual(signed_width_for_bound(1 << 36), 38)
        result = evaluate_layer(
            np.array([[2.0, -3.0]]), np.array([[4.0], [5.0]]),
            np.array([1.0]), LayerFormat(x_frac=0, w_frac=0, y_frac=0),
        )
        self.assertEqual(int(result["y_q"][0, 0]), -6)
        self.assertEqual(result["accumulator"]["theoretical_max"], 24)
        self.assertEqual(result["accumulator"]["minimum_signed_bits_for_this_data"], 6)


if __name__ == "__main__":
    unittest.main()
