"""Independent hand cases and boundary tests for the draft FP32 reference."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

import numpy as np

from software.examples.fp32_hand_example import (
    BIAS, EXPECTED, ROUNDING_BIAS, ROUNDING_EXPECTED, ROUNDING_W,
    ROUNDING_X, W, X, generate,
)
from software.fp32_reference import (
    UnsupportedFP32Case, add_bits, from_low16_first_words,
    low16_first_words, multiply_bits, row_major_words, run_ffn1_bits,
    to_float, trace_cell, words_to_little_endian_bytes,
)
from software.compare_fp32 import compare
from software.pack_fp32 import create_pack


class FP32ReferenceTest(unittest.TestCase):
    def test_independent_signed_bias_hand_case(self) -> None:
        self.assertEqual(run_ffn1_bits(X, W, BIAS), EXPECTED)
        trace = trace_cell(X, W, BIAS, 0, 0)
        self.assertEqual(
            trace["steps"],
            [
                {"k": 0, "product_bits": 0x40000000, "acc_bits": 0x40000000},
                {"k": 1, "product_bits": 0xC0400000, "acc_bits": 0xBF800000},
            ],
        )
        self.assertEqual(trace["result_bits"], 0xBF400000)

    def test_nonfused_product_then_add(self) -> None:
        self.assertEqual(multiply_bits(0x3F800001, 0x3F7FFFFE), 0x3F800000)
        self.assertEqual(run_ffn1_bits(ROUNDING_X, ROUNDING_W, ROUNDING_BIAS),
                         ROUNDING_EXPECTED)
        self.assertEqual(to_float(0xA8800000), -(2 ** -46))

    def test_nearest_even_and_gradual_underflow(self) -> None:
        self.assertEqual(add_bits(0x3F800000, 0x33800000), 0x3F800000)
        self.assertEqual(multiply_bits(0x00000001, 0x3F000000), 0x00000000)
        self.assertEqual(multiply_bits(0x00000003, 0x3F000000), 0x00000002)
        self.assertEqual(multiply_bits(0x80000001, 0x3F000000), 0x80000000)
        self.assertEqual(add_bits(0x80000000, 0x80000000), 0x80000000)
        self.assertEqual(add_bits(0x80000000, 0x00000000), 0x00000000)

    def test_k_order_can_change_result(self) -> None:
        one = 0x3F800000
        plus_big, minus_big = 0x4B800000, 0xCB800000  # +/- 2**24
        zero = 0x00000000
        self.assertEqual(run_ffn1_bits([[one, one, one]],
                                       [[plus_big], [minus_big], [one]], [zero]),
                         [[one]])
        self.assertEqual(run_ffn1_bits([[one, one, one]],
                                       [[plus_big], [one], [minus_big]], [zero]),
                         [[zero]])

    def test_k32_boundary_preserves_partial_sum_and_adds_bias_once(self) -> None:
        x = [[0x3F800000] * 64]
        w = [[0x00000000] for _ in range(64)]
        w[31][0] = 0x40000000  # Last product in block 0: +2.
        w[32][0] = 0xC0400000  # First product in block 1: -3.
        bias = [0x3E800000]    # +0.25, once after all products.
        trace = trace_cell(x, w, bias, 0, 0)
        self.assertEqual(trace["steps"][31]["acc_bits"], 0x40000000)
        self.assertEqual(trace["steps"][32]["acc_bits"], 0xBF800000)
        self.assertEqual(trace["steps"][63]["acc_bits"], 0xBF800000)
        self.assertEqual(trace["result_bits"], 0xBF400000)
        self.assertEqual(run_ffn1_bits(x, w, bias), [[0xBF400000]])

    def test_unfrozen_special_cases_rejected(self) -> None:
        for word in (0x7F800000, 0xFF800000, 0x7FC00000):
            with self.assertRaises(UnsupportedFP32Case):
                multiply_bits(word, 0x3F800000)
        with self.assertRaises(UnsupportedFP32Case):
            multiply_bits(0x7F7FFFFF, 0x40000000)

    def test_shapes_and_word_layout(self) -> None:
        with self.assertRaises(ValueError):
            run_ffn1_bits([[0]], [[0, 0]], [0])
        self.assertEqual(low16_first_words(0xBF400000), (0x0000, 0xBF40))
        self.assertEqual(from_low16_first_words(0x0000, 0xBF40), 0xBF400000)
        self.assertEqual(row_major_words([[0x3F800000, 0xC0000000]]),
                         [0x0000, 0x3F80, 0x0000, 0xC000])
        self.assertEqual(words_to_little_endian_bytes([0x3F80, 0xC000]),
                         bytes.fromhex("80 3f 00 c0"))

    def test_generated_image_has_hand_checked_words(self) -> None:
        with tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parent) as temp:
            directory = Path(temp) / "fp32_hand"
            generate(directory)
            self.assertEqual((directory / "expected.mem").read_text("ascii"),
                             "0000\nbf40\n0000\nc020\n0000\n40b8\n0000\n3f00\n")
            self.assertEqual((directory / "expected.bin").read_bytes(),
                             bytes.fromhex("00 00 40 bf 00 00 20 c0 00 00 b8 40 00 00 00 3f"))
            self.assertEqual((directory / "tile_expected.mem").read_text("ascii"),
                             "0000\nbf40\n")
            tile_words = (directory / "tile_w.mem").read_text("ascii").splitlines()
            self.assertEqual(len(tile_words), 128)
            self.assertEqual(tile_words[62:66], ["0000", "4000", "0000", "c040"])
            tile_rtl = Path(temp) / "tile_rtl.bin"
            tile_rtl.write_bytes((directory / "tile_expected.bin").read_bytes())
            tile_report = compare(directory, tile_rtl, expected_name="tile_expected")
            self.assertEqual(tile_report["status"], "BIT-EXACT")
            self.assertEqual(tile_report["shape"], [1, 1])
            with self.assertRaises(FileExistsError):
                generate(directory)

    def test_npz_packer_uses_own_reference_and_records_provenance(self) -> None:
        with tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parent) as temp:
            source = Path(temp) / "task.npz"
            np.savez(source, x=np.array([[1.0, -2.0], [0.5, 3.0]], dtype=np.float32),
                     w=np.array([[2.0, -1.0], [1.5, 0.5]], dtype=np.float32),
                     b=np.array([0.25, -0.5], dtype=np.float32),
                     y_float=np.zeros((2, 2), dtype=np.float32))
            image = Path(temp) / "packed"
            manifest = create_pack(source, image, "synthetic/hand-2x2", "synthetic-smoke")
            self.assertFalse(manifest["provided_y_float_used_for_expected"])
            self.assertFalse(manifest["split_verified_by_this_tool"])
            self.assertEqual((image / "expected.bin").read_bytes(),
                             bytes.fromhex("00 00 40 bf 00 00 20 c0 00 00 b8 40 00 00 00 3f"))
            with self.assertRaises(FileExistsError):
                create_pack(source, image, "synthetic/hand-2x2", "synthetic-smoke")
            with self.assertRaisesRegex(ValueError, "source_id"):
                create_pack(source, Path(temp) / "bad-source", " sample ", "unverified")
            with self.assertRaisesRegex(ValueError, "split"):
                create_pack(source, Path(temp) / "bad-split", "sample", "training")

    def test_fp32_bitwise_comparator_pinpoints_one_changed_element(self) -> None:
        with tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parent) as temp:
            image = Path(temp) / "image"
            generate(image)
            rtl = Path(temp) / "rtl_output.bin"
            rtl.write_bytes((image / "expected.bin").read_bytes())
            self.assertEqual(compare(image, rtl)["status"], "BIT-EXACT")
            changed = bytearray(rtl.read_bytes())
            changed[4] ^= 1
            rtl.write_bytes(changed)
            report = compare(image, rtl)
            self.assertEqual(report["mismatch_count"], 1)
            self.assertEqual(report["examples"], [{
                "row": 0, "column": 1,
                "expected_bits": "0xc0200000", "actual_bits": "0xc0200001",
            }])


if __name__ == "__main__":
    unittest.main()
