"""Small, independently calculated arithmetic and serialization checks."""

from __future__ import annotations

import json
from pathlib import Path
import tempfile
import unittest

import numpy as np

from software.ffn1_numeric import (
    FixedPointSpec,
    normalized_rmse,
    quantize_real,
    run_ffn1_integer,
    run_ffn1_real,
)
from software.pack_tensors import (
    create_task_pack,
    pack_signed_to_words,
    unpack_words_to_signed,
)


class NumericTests(unittest.TestCase):
    def test_quantization_ties_and_saturation(self) -> None:
        actual = quantize_real(np.array([-100.0, -1.25, -0.25, 0.25, 1.25, 100.0]), 4, 1)
        np.testing.assert_array_equal(actual, [-8, -3, -1, 1, 3, 7])

    def test_dot_bias_and_right_shift(self) -> None:
        # 0.5*0.5 + 0.25 = 0.5. Product and bias have two frac bits;
        # output has one. All intermediate encoded values are exactly 1.
        spec = FixedPointSpec(x_bits=4, x_frac=1, w_bits=4, w_frac=1,
                              bias_bits=4, acc_bits=8, out_bits=4, out_frac=1)
        result = run_ffn1_real([[0.5]], [[0.5]], [0.25], spec)
        self.assertEqual(int(result.b_q[0]), 1)
        self.assertEqual(int(result.out_q[0, 0]), 1)
        self.assertEqual(float(result.out_real[0, 0]), 0.5)

    def test_negative_halfway_right_shift_rounds_away(self) -> None:
        spec = FixedPointSpec(x_bits=4, x_frac=1, w_bits=4, w_frac=0,
                              bias_bits=4, acc_bits=8, out_bits=4, out_frac=0)
        result = run_ffn1_real([[-0.5]], [[1.0]], [0.0], spec)
        self.assertEqual(int(result.out_q[0, 0]), -1)

    def test_saturation_happens_after_each_product(self) -> None:
        spec = FixedPointSpec(x_bits=4, x_frac=0, w_bits=4, w_frac=0,
                              bias_bits=4, acc_bits=4, out_bits=4, out_frac=0)
        x = np.array([[7, 7, -7]])
        w = np.array([[1], [1], [1]])
        out = run_ffn1_integer(x, w, np.array([0]), spec)
        # 0+7=7, 7+7 saturates to 7, 7-7=0.
        self.assertEqual(int(out[0, 0]), 0)

    def test_matrix_layout_and_bias_broadcast(self) -> None:
        spec = FixedPointSpec(x_bits=16, x_frac=0, w_bits=16, w_frac=0,
                              bias_bits=32, acc_bits=32, out_bits=32, out_frac=0)
        x = np.array([[1, 2], [3, 4]])
        w = np.array([[5, 6], [7, 8]])
        b = np.array([9, -1])
        np.testing.assert_array_equal(run_ffn1_integer(x, w, b, spec), [[28, 21], [52, 49]])

    def test_shape_and_nonfinite_rejection(self) -> None:
        with self.assertRaises(ValueError):
            run_ffn1_integer(np.ones((2, 3), dtype=int), np.ones((2, 1), dtype=int),
                             np.zeros(1, dtype=int), FixedPointSpec())
        with self.assertRaises(ValueError):
            quantize_real([np.nan], 16, 8)
        with self.assertRaises(ValueError):
            FixedPointSpec(x_frac=40, w_frac=40).validate()

    def test_normalized_rmse(self) -> None:
        self.assertAlmostEqual(normalized_rmse([2.0, 0.0], [1.0, 1.0]), 1.0)


class PackTests(unittest.TestCase):
    def test_signed_little_word_first_round_trip(self) -> None:
        values = np.array([[-1, 0x12345678]], dtype=np.int64)
        words = pack_signed_to_words(values, 32)
        np.testing.assert_array_equal(words, [0xFFFF, 0xFFFF, 0x5678, 0x1234])
        np.testing.assert_array_equal(unpack_words_to_signed(words, values.shape, 32), values)
        self.assertEqual(words.astype("<u2").tobytes(), bytes.fromhex("ffff ffff 7856 3412"))
        neg48 = pack_signed_to_words(np.array([-1]), 48)
        np.testing.assert_array_equal(neg48, [0xFFFF, 0xFFFF, 0xFFFF])
        np.testing.assert_array_equal(unpack_words_to_signed(neg48, (1,), 48), [-1])

    def test_task_pack_manifest_and_expected_words(self) -> None:
        spec = FixedPointSpec(x_bits=16, x_frac=0, w_bits=16, w_frac=0,
                              bias_bits=32, acc_bits=32, out_bits=32, out_frac=0)
        with tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parent) as temp:
            root = Path(temp)
            source = root / "sample.npz"
            dest = root / "packed"
            np.savez(source, x=np.array([[1., 2.]]), w=np.array([[3.], [4.]]),
                     b=np.array([5.]), y_float=np.array([[16.]]))
            manifest = create_task_pack(source, dest, spec)
            self.assertEqual(manifest["reference_kind"], "provided_y_float")
            self.assertEqual(manifest["normalized_rmse"], 0.0)
            self.assertEqual((dest / "expected.mem").read_text(encoding="ascii"), "0010\n0000\n")
            on_disk = json.loads((dest / "manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(on_disk["storage"]["tensor_order"], "C row-major, last index fastest")

    def test_task_pack_rejects_wrong_float_reference(self) -> None:
        with tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parent) as temp:
            root = Path(temp)
            source = root / "wrong_layer.npz"
            np.savez(source, x=np.array([[1.]]), w=np.array([[2.]]),
                     b=np.array([0.]), y_float=np.array([[5.]]))
            with self.assertRaisesRegex(ValueError, "independent X @ W"):
                create_task_pack(source, root / "packed", FixedPointSpec())
            self.assertFalse((root / "packed").exists())


if __name__ == "__main__":
    unittest.main()
