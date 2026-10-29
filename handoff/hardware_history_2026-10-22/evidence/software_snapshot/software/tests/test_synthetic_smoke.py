"""Full-size RTL smoke vectors: independent byte/word and hand-value checks."""

from __future__ import annotations

import json
from pathlib import Path
import struct
import tempfile
import unittest

import numpy as np

from software.synthetic_smoke import generate


WORK_DIR = Path(__file__).resolve().parents[2] / "work"


def _output_word(raw: bytes, row: int, column: int) -> int:
    # Independent of the project's pack/unpack helpers: C-order int32 bytes.
    return struct.unpack_from("<i", raw, 4 * (row * 256 + column))[0]


class SyntheticSmokeTests(unittest.TestCase):
    def test_three_cases_are_full_size_and_explicitly_synthetic(self) -> None:
        with tempfile.TemporaryDirectory(dir=WORK_DIR) as temporary:
            root = Path(temporary) / "smoke"
            top = generate(root)
            self.assertEqual(top["purpose"], "SYNTHETIC_RTL_SMOKE_ONLY")
            self.assertEqual(top["model_reference_kind"], "none")
            self.assertEqual(top["shapes"], {
                "x": [99, 64], "w": [64, 256], "b": [256], "expected": [99, 256]
            })
            self.assertEqual([item["name"] for item in top["cases"]],
                             ["all_zero", "sentinels", "address_pattern"])

            for item in top["cases"]:
                case = root / item["name"]
                with np.load(case / "source.npz", allow_pickle=False) as source:
                    self.assertEqual(set(source.files), {"x", "w", "b"})
                    self.assertEqual(source["x"].shape, (99, 64))
                    self.assertEqual(source["w"].shape, (64, 256))
                    self.assertEqual(source["b"].shape, (256,))
                pack = json.loads((case / "packed" / "manifest.json").read_text(encoding="utf-8"))
                self.assertEqual(pack["purpose"], "SYNTHETIC_RTL_SMOKE_ONLY")
                self.assertEqual(pack["data_origin"], "deterministic_synthetic_operands_not_official_kwt")
                self.assertEqual(pack["reference_kind"], "local_numpy_x_matmul_w_plus_b")
                self.assertEqual(len((case / "packed" / "x.bin").read_bytes()), 99 * 64 * 2)
                self.assertEqual(len((case / "packed" / "w.bin").read_bytes()), 64 * 256 * 2)
                self.assertEqual(len((case / "packed" / "b.bin").read_bytes()), 256 * 6)
                self.assertEqual(len((case / "packed" / "expected.bin").read_bytes()), 99 * 256 * 4)

            zeros = (root / "all_zero" / "packed" / "expected.bin").read_bytes()
            self.assertEqual(zeros, bytes(len(zeros)))
            with self.assertRaisesRegex(ValueError, "not empty"):
                generate(root)

    def test_sentinel_outputs_match_hand_calculation_and_tail_layout(self) -> None:
        with tempfile.TemporaryDirectory(dir=WORK_DIR) as temporary:
            root = Path(temporary) / "smoke"
            generate(root)
            packed = root / "sentinels" / "packed"
            raw = (packed / "expected.bin").read_bytes()
            self.assertEqual(_output_word(raw, 0, 0), 320)      # bias 1.25 * 256
            self.assertEqual(_output_word(raw, 98, 0), 320)     # broadcast into last row
            self.assertEqual(_output_word(raw, 0, 1), 256)      # +1 * +1
            self.assertEqual(_output_word(raw, 98, 1), 512)     # +2 * +1
            self.assertEqual(_output_word(raw, 1, 4), -576)     # (-3 + 0.5 + .25) * 256
            self.assertEqual(_output_word(raw, 2, 7), 1)       # +0.5 LSB rounds up
            self.assertEqual(_output_word(raw, 3, 8), -1)      # -0.5 LSB rounds down
            self.assertEqual(_output_word(raw, 0, 255), -128)  # last-column bias
            self.assertEqual(_output_word(raw, 98, 255), -1664)  # +3*(-2)-.5

            x_bytes = (packed / "x.bin").read_bytes()
            w_bytes = (packed / "w.bin").read_bytes()
            b_bytes = (packed / "b.bin").read_bytes()
            self.assertEqual(struct.unpack_from("<h", x_bytes, 2 * (98 * 64 + 63))[0], 768)
            self.assertEqual(struct.unpack_from("<h", w_bytes, 2 * (63 * 256 + 255))[0], -512)
            self.assertEqual(b_bytes[-6:], bytes.fromhex("00 80 ff ff ff ff"))

    def test_dense_pattern_repeats_semantically(self) -> None:
        with tempfile.TemporaryDirectory(dir=WORK_DIR) as temporary:
            base = Path(temporary)
            first = generate(base / "first")
            second = generate(base / "second")
            self.assertEqual(
                [case["expected_sha256"] for case in first["cases"]],
                [case["expected_sha256"] for case in second["cases"]],
            )
            raw = (base / "first" / "address_pattern" / "packed" / "expected.bin").read_bytes()
            values = struct.unpack("<" + "i" * (99 * 256), raw)
            self.assertGreater(len(set(values)), 30)
            self.assertNotEqual(_output_word(raw, 0, 0), _output_word(raw, 98, 255))
            with np.load(base / "first" / "address_pattern" / "source.npz", allow_pickle=False) as data:
                self.assertAlmostEqual(float(data["x"][98, 63]),
                                       (((98 * 13 + 63 * 7) % 19) - 9) * 32 / 256)
                self.assertAlmostEqual(float(data["w"][63, 255]),
                                       (((63 * 11 + 255 * 5) % 17) - 8) * 16 / 256)


if __name__ == "__main__":
    unittest.main()
