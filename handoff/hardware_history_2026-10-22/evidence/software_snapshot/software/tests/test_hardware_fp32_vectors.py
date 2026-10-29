"""Independent anchors and failure reporting for hardware's FP32 vector format."""

from __future__ import annotations

from hashlib import sha256
from pathlib import Path
import tempfile
import unittest

from software.check_hardware_fp32_vectors import compare_vectors


# Expected columns were written from exact binary32 facts, not computed by
# fp32_reference.py. These exercise signed zero, halfway rounding, and overflow.
VECTORS = (
    "3f800000 40000000 40400000 40000000\n"  # 1+2=3; 1*2=2
    "80000000 80000000 80000000 00000000\n"  # -0+-0=-0; -0*-0=+0
    "3f800000 33800000 3f800000 33800000\n"  # 1+2^-24 ties to 1
    "7f800000 3f800000 7f800000 7f800000\n"  # Inf input: unsupported
    "7f7fffff 40000000 7f7fffff 7f800000\n"  # finite mul overflows
)


class HardwareFP32VectorCheckTests(unittest.TestCase):
    def _compare(self, root: Path, contents: str) -> dict:
        path = root / "fp32_vectors.txt"
        path.write_bytes(contents.encode("ascii"))
        return compare_vectors(path, "4448aee155f59dc895f83bec3968322160fd66a6")

    def test_finite_cases_match_and_unsupported_cases_are_counted(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            report = self._compare(Path(temp), VECTORS)
        self.assertEqual(report["status"], "MATCH")
        self.assertEqual(report["pairs"], 5)
        self.assertEqual(report["vector_sha256"], sha256(VECTORS.encode("ascii")).hexdigest())
        self.assertEqual(report["operations"]["add"], {
            "checked": 4, "skipped_special_input": 1,
            "skipped_nonfinite_expected": 0, "unexpected_rejection": 0,
            "mismatched": 0,
        })
        self.assertEqual(report["operations"]["mul"], {
            "checked": 3, "skipped_special_input": 1,
            "skipped_nonfinite_expected": 1, "unexpected_rejection": 0,
            "mismatched": 0,
        })
        self.assertIsNone(report["first_failure"])

    def test_first_bit_mismatch_and_unexpected_rejection_are_visible(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            wrong_sum = VECTORS.replace("40400000 40000000", "40400001 40000000", 1)
            report = self._compare(root, wrong_sum)
            self.assertEqual(report["status"], "MISMATCH")
            self.assertEqual(report["first_failure"], {
                "kind": "bit_mismatch", "line": 1, "operation": "add",
                "a_bits": "0x3f800000", "b_bits": "0x40000000",
                "expected_bits": "0x40400001", "actual_bits": "0x40400000",
            })
            self.assertEqual(report["operations"]["add"]["mismatched"], 1)

            wrong_overflow = VECTORS.replace(
                "7f7fffff 40000000 7f7fffff 7f800000",
                "7f7fffff 40000000 7f7fffff 00000000",
            )
            report = self._compare(root, wrong_overflow)
            self.assertEqual(report["status"], "MISMATCH")
            self.assertEqual(report["first_failure"]["kind"], "unexpected_rejection")
            self.assertEqual(report["first_failure"]["line"], 5)
            self.assertEqual(report["first_failure"]["operation"], "mul")
            self.assertEqual(report["operations"]["mul"]["unexpected_rejection"], 1)

    def test_false_infinity_expected_is_not_silently_skipped(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            report = self._compare(
                Path(temp), "3f800000 40000000 7f800000 40000000\n")
        self.assertEqual(report["status"], "MISMATCH")
        self.assertEqual(report["operations"]["add"]["skipped_nonfinite_expected"], 0)
        self.assertEqual(report["operations"]["add"]["mismatched"], 1)
        self.assertEqual(report["first_failure"]["expected_bits"], "0x7f800000")
        self.assertEqual(report["first_failure"]["actual_bits"], "0x40400000")

    def test_rejects_malformed_and_unsupported_only_files(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            for contents in ("", "3f800000 40000000 40400000\n",
                             "3f800000 40000000 40400000 zzzzzzzz\n",
                             VECTORS + "\n"):
                with self.subTest(contents=contents[:30]):
                    with self.assertRaisesRegex(ValueError, "empty|vector line"):
                        self._compare(root, contents)
            report = self._compare(
                root, "7f800000 3f800000 7f800000 7f800000\n")
            self.assertEqual(report["status"], "NO_SUPPORTED_CASES")
            with self.assertRaisesRegex(ValueError, "hardware_commit"):
                compare_vectors(root / "fp32_vectors.txt", "not-a-commit")


if __name__ == "__main__":
    unittest.main()
