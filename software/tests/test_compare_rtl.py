"""Check that a hardware dump can be compared at the correct element position."""

from __future__ import annotations

import json
from pathlib import Path
import tempfile
import unittest

import numpy as np

from software.compare_rtl import compare_output
from software.ffn1_numeric import FixedPointSpec
from software.pack_tensors import create_task_pack


class CompareRtlTests(unittest.TestCase):
    def _pack(self, root: Path) -> Path:
        source = root / "small.npz"
        np.savez(
            source,
            x=np.array([[1, -2], [3, 4]], dtype=np.float64),
            w=np.array([[5, -6, 7], [8, 9, -10]], dtype=np.float64),
            b=np.array([-1, 2, 3], dtype=np.float64),
        )
        packed = root / "packed"
        create_task_pack(
            source, packed,
            FixedPointSpec(x_bits=16, x_frac=0, w_bits=16, w_frac=0,
                           bias_bits=32, acc_bits=48, out_bits=32, out_frac=0),
        )
        return packed

    def test_binary_match_then_locate_signed_mismatch(self) -> None:
        with tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parent) as tmp:
            root = Path(tmp)
            packed = self._pack(root)
            actual = root / "rtl.bin"
            raw = bytearray((packed / "expected.bin").read_bytes())
            actual.write_bytes(raw)
            report = compare_output(packed, actual)
            self.assertTrue(report["bit_exact"])
            self.assertEqual(report["total_elements"], 6)
            self.assertEqual(report["mismatched_elements"], 0)

            # Output [1,1] is the fifth 32-bit element in a 2x3 row-major image.
            raw[4 * (1 * 3 + 1)] ^= 0x01
            actual.write_bytes(raw)
            report = compare_output(packed, actual)
            self.assertFalse(report["bit_exact"])
            self.assertEqual(report["mismatched_elements"], 1)
            self.assertEqual((report["first_mismatch"]["row"],
                              report["first_mismatch"]["column"]), (1, 1))
            self.assertNotEqual(report["first_mismatch"]["expected_hex"],
                                report["first_mismatch"]["actual_hex"])

    def test_mem_match_and_reject_invalid_word(self) -> None:
        with tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parent) as tmp:
            root = Path(tmp)
            packed = self._pack(root)
            actual = root / "rtl.mem"
            actual.write_bytes((packed / "expected.mem").read_bytes())
            self.assertTrue(compare_output(packed, actual)["bit_exact"])
            actual.write_text("0000\nnot-a-word\n", encoding="ascii")
            with self.assertRaisesRegex(ValueError, "line 2"):
                compare_output(packed, actual)

    def test_rejects_short_dump_and_corrupted_expected(self) -> None:
        with tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parent) as tmp:
            root = Path(tmp)
            packed = self._pack(root)
            actual = root / "rtl.bin"
            expected = (packed / "expected.bin").read_bytes()
            actual.write_bytes(expected[:-2])
            with self.assertRaisesRegex(ValueError, "need"):
                compare_output(packed, actual)
            actual.write_bytes(expected)
            manifest_path = packed / "manifest.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            manifest["tensors"]["expected"]["binary_sha256"] = "0" * 64
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "SHA-256"):
                compare_output(packed, actual)


if __name__ == "__main__":
    unittest.main()
