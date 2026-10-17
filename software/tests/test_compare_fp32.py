"""FP32 output checks against the independently hand-worked task image."""

from __future__ import annotations

import json
from pathlib import Path
import tempfile
import unittest

import numpy as np

from software.compare_fp32 import compare
from software.examples.fp32_hand_example import generate
from software.pack_fp32 import create_pack


class CompareFP32Test(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.image = self.root / "image"
        generate(self.image)

    def _manifest_change(self, change) -> None:
        path = self.image / "manifest.json"
        manifest = json.loads(path.read_text(encoding="utf-8"))
        change(manifest)
        path.write_text(json.dumps(manifest), encoding="utf-8")

    def test_bin_and_mem_match_same_hand_checked_fp32_values(self) -> None:
        binary = compare(self.image, self.image / "expected.bin")
        memory = compare(self.image, self.image / "expected.mem")
        self.assertEqual(binary["status"], "BIT-EXACT")
        self.assertEqual(memory["status"], "BIT-EXACT")
        self.assertEqual(binary["actual_format"], "bin")
        self.assertEqual(memory["actual_format"], "mem")
        self.assertEqual(memory["actual_sha256"], binary["actual_sha256"])
        self.assertNotEqual(memory["actual_file_sha256"], memory["actual_sha256"])

    def test_mem_one_word_fault_and_reversed_fp32_words_are_located(self) -> None:
        words = (self.image / "expected.mem").read_text(encoding="ascii").splitlines()
        words[2] = "0001"
        path = self.root / "fault.mem"
        path.write_text("\n".join(words) + "\n", encoding="ascii")
        report = compare(self.image, path)
        self.assertEqual(report["mismatch_count"], 1)
        self.assertEqual(report["examples"][0], {
            "row": 0, "column": 1,
            "expected_bits": "0xc0200000", "actual_bits": "0xc0200001",
        })
        words = (self.image / "expected.mem").read_text(encoding="ascii").splitlines()
        words[0], words[1] = words[1], words[0]
        path.write_text("\n".join(words) + "\n", encoding="ascii")
        report = compare(self.image, path)
        self.assertEqual(report["mismatch_count"], 1)
        self.assertEqual(report["examples"][0]["actual_bits"], "0x0000bf40")

    def test_rejects_truncated_or_malformed_mem(self) -> None:
        words = (self.image / "expected.mem").read_text(encoding="ascii").splitlines()
        path = self.root / "rtl.mem"
        path.write_text("\n".join(words[:-1]) + "\n", encoding="ascii")
        with self.assertRaisesRegex(ValueError, "decoded bytes"):
            compare(self.image, path)
        words[1] = "3f80 // comment"
        path.write_text("\n".join(words) + "\n", encoding="ascii")
        with self.assertRaisesRegex(ValueError, "line 2"):
            compare(self.image, path)
        words[1] = "f40"  # Missing digit is rejected rather than silently zero-extended.
        path.write_text("\n".join(words) + "\n", encoding="ascii")
        with self.assertRaisesRegex(ValueError, "line 2"):
            compare(self.image, path)

    def test_rejects_incompatible_manifest_counts_and_layout(self) -> None:
        self._manifest_change(lambda m: m.update(layout="high 16-bit word first"))
        with self.assertRaisesRegex(ValueError, "unsupported FP32 layout"):
            compare(self.image, self.image / "expected.mem")
        self._manifest_change(lambda m: m.update(layout=["invalid", "layout"]))
        with self.assertRaisesRegex(ValueError, "unsupported FP32 layout"):
            compare(self.image, self.image / "expected.mem")
        self._manifest_change(lambda m: m.update(layout=(
            "DRAFT row-major elements; each FP32 low 16-bit word first; "
            "each 16-bit word low byte first")))
        for key, value, message in (
            ("word_count", 7, "word_count"),
            ("byte_count", 14, "byte count"),
            ("element_bits", 16, "32-bit"),
            ("shape", [1, 5], "word_count"),
        ):
            path = self.image / "manifest.json"
            baseline = path.read_text(encoding="utf-8")
            self._manifest_change(lambda m: m["tensors"]["expected"].update({key: value}))
            with self.assertRaisesRegex(ValueError, message):
                compare(self.image, self.image / "expected.mem")
            path.write_text(baseline, encoding="utf-8")

    def test_rejects_manifest_words_that_disagree_with_expected_binary(self) -> None:
        self._manifest_change(lambda m: m["tensors"]["expected"]["words_hex"].__setitem__(0, "0001"))
        with self.assertRaisesRegex(ValueError, "words_hex"):
            compare(self.image, self.image / "expected.mem")

    def test_named_rounding_expected_is_independent_output(self) -> None:
        report = compare(self.image, self.image / "rounding_expected.mem",
                         expected_name="rounding_expected")
        self.assertEqual(report["status"], "BIT-EXACT")
        self.assertEqual(report["shape"], [1, 1])

    def test_packer_manifest_format_is_also_accepted(self) -> None:
        source = self.root / "source.npz"
        np.savez(source, x=np.array([[2.0]], dtype=np.float32),
                 w=np.array([[3.0]], dtype=np.float32),
                 b=np.array([0.5], dtype=np.float32))
        image = self.root / "packed"
        create_pack(source, image, "synthetic/one-cell", "synthetic-smoke")
        report = compare(image, image / "expected.mem")
        self.assertEqual(report["status"], "BIT-EXACT")
        self.assertEqual(report["shape"], [1, 1])
        self.assertEqual((image / "expected.mem").read_text(encoding="ascii"),
                         "0000\n40d0\n")  # 2*3+0.5 = 6.5, bits 0x40d00000.


if __name__ == "__main__":
    unittest.main()
