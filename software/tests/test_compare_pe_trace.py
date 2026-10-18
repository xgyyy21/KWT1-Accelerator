"""Draft PE event comparator checks using synthetic rows, never RTL evidence."""

from __future__ import annotations

import csv
import io
from pathlib import Path
import tempfile
import unittest

from software.compare_pe_trace import TraceContractError, compare
from software.examples.fp32_trace_csv import HEADER


GOLDEN = Path(__file__).resolve().parents[1] / "examples/fp32_hand_image/expected_pe_trace_demo.csv"


def _measured_rows() -> list[dict[str, str]]:
    with GOLDEN.open(newline="", encoding="ascii") as stream:
        rows = list(csv.DictReader(stream))
    for cycle, row in enumerate(rows, start=100):
        row["source_kind"] = "rtl_measured"
        row["cycle"] = str(cycle)
        row["rtl_commit"] = "synthetic-test-only"
    return rows


def _write(path: Path, rows: list[dict[str, str]]) -> None:
    output = io.StringIO(newline="")
    writer = csv.DictWriter(output, fieldnames=HEADER, lineterminator="\n")
    writer.writeheader()
    writer.writerows(rows)
    path.write_text(output.getvalue(), encoding="ascii", newline="")


class ComparePETraceTest(unittest.TestCase):
    def test_identity_alignment_handles_interleaved_rows(self) -> None:
        rows = _measured_rows()
        rows.reverse()  # Arithmetic identity, not CSV line or cycle, decides matching.
        with tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parent) as temp:
            actual = Path(temp) / "synthetic.csv"
            _write(actual, rows)
            result = compare(GOLDEN, actual)
        self.assertEqual(result["status"], "BIT-EXACT-CANDIDATE")
        self.assertEqual((result["expected_events"], result["actual_events"]), (80, 80))

    def test_first_k32_partial_sum_error_has_exact_bit_context(self) -> None:
        rows = _measured_rows()
        faulty = next(row for row in rows if row["case_id"] == "k32_boundary"
                      and row["event"] == "mac" and row["k"] == "32")
        faulty["acc_before_bits"] = "0x00000000"
        with tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parent) as temp:
            actual = Path(temp) / "synthetic.csv"
            _write(actual, rows)
            result = compare(GOLDEN, actual, case_id="k32_boundary")
        self.assertEqual(result["status"], "MISMATCH")
        self.assertEqual(result["first_mismatch"], {
            "case_id": "k32_boundary", "row": 0, "column": 0, "event": "mac",
            "global_k": 32, "field": "acc_before_bits",
            "expected": "0x40000000", "actual": "0x00000000",
            "tile_id": 1, "cycle": 147, "rtl_commit": "synthetic-test-only",
        })

    def test_missing_bias_event_is_reported(self) -> None:
        rows = [row for row in _measured_rows() if not
                (row["case_id"] == "rounding_nonfused" and row["event"] == "bias")]
        with tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parent) as temp:
            actual = Path(temp) / "synthetic.csv"
            _write(actual, rows)
            result = compare(GOLDEN, actual, case_id="rounding_nonfused")
        self.assertEqual(result["first_mismatch"]["field"], "event")
        self.assertEqual(result["first_mismatch"]["actual"], "<absent>")

    def test_provenance_mismatch_blocks_numeric_claim(self) -> None:
        rows = _measured_rows()
        rows[0]["input_manifest_sha256"] = "0" * 64
        with tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parent) as temp:
            actual = Path(temp) / "synthetic.csv"
            _write(actual, rows)
            with self.assertRaisesRegex(TraceContractError, "provenance"):
                compare(GOLDEN, actual)

    def test_empty_measured_trace_reports_missing_first_event(self) -> None:
        with tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parent) as temp:
            actual = Path(temp) / "synthetic.csv"
            _write(actual, [])
            result = compare(GOLDEN, actual, case_id="hand_2x2")
        self.assertEqual(result["status"], "MISMATCH")
        self.assertEqual(result["first_mismatch"]["field"], "event")
        self.assertEqual(result["first_mismatch"]["actual"], "<absent>")

    def test_mixed_rtl_commits_cannot_pass(self) -> None:
        rows = _measured_rows()
        rows[1]["rtl_commit"] = "different-synthetic-commit"
        with tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parent) as temp:
            actual = Path(temp) / "synthetic.csv"
            _write(actual, rows)
            with self.assertRaisesRegex(TraceContractError, "multiple RTL commits"):
                compare(GOLDEN, actual)


if __name__ == "__main__":
    unittest.main()
