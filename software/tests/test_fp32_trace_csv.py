"""Check the handoff CSV against independent hand calculations and provenance."""

from __future__ import annotations

import csv
from hashlib import sha256
import io
from pathlib import Path
import tempfile
import unittest

from software.examples.fp32_trace_csv import render, write


IMAGE = Path(__file__).resolve().parents[1] / "examples" / "fp32_hand_image"


class FP32TraceCSVTest(unittest.TestCase):
    def test_demo_is_reproducible_and_only_software_labeled(self) -> None:
        payload, checksum = render()
        self.assertEqual((IMAGE / "expected_pe_trace_demo.csv").read_bytes(), payload)
        self.assertEqual((IMAGE / "expected_pe_trace_demo.sha256").read_bytes(), checksum)
        self.assertEqual(checksum.decode("ascii").split()[0], sha256(payload).hexdigest())
        rows = list(csv.DictReader(io.StringIO(payload.decode("ascii"))))
        self.assertEqual(len(rows), 80)  # 8+4, 2+1, and 64+1 events.
        self.assertEqual({row["source_kind"] for row in rows}, {"software_candidate"})
        self.assertEqual({row["cycle"] for row in rows}, {""})
        self.assertEqual({row["rtl_commit"] for row in rows}, {""})
        self.assertEqual({row["input_manifest_sha256"] for row in rows},
                         {sha256((IMAGE / "manifest.json").read_bytes()).hexdigest()})
        self.assertEqual(rows[0]["event"], "mac")
        self.assertEqual((rows[0]["x_bits"], rows[0]["w_bits"],
                          rows[0]["acc_before_bits"], rows[0]["product_bits"],
                          rows[0]["acc_after_bits"]),
                         ("0x3f800000", "0x40000000", "0x00000000",
                          "0x40000000", "0x40000000"))
        first_cell_bias = next(row for row in rows if row["case_id"] == "hand_2x2"
                               and row["row"] == "0" and row["column"] == "0"
                               and row["event"] == "bias")
        self.assertEqual((first_cell_bias["acc_before_bits"], first_cell_bias["bias_bits"],
                          first_cell_bias["result_bits"]),
                         ("0xbf800000", "0x3e800000", "0xbf400000"))
        boundary = [row for row in rows if row["case_id"] == "k32_boundary"
                    and row["event"] == "mac"]
        self.assertEqual((boundary[31]["tile_id"], boundary[31]["acc_after_bits"]),
                         ("0", "0x40000000"))
        self.assertEqual((boundary[32]["tile_id"], boundary[32]["acc_before_bits"],
                          boundary[32]["acc_after_bits"]),
                         ("1", "0x40000000", "0xbf800000"))

    def test_check_rejects_modified_demonstration(self) -> None:
        with tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parent) as temp:
            directory = Path(temp)
            csv_path, _ = write(directory)
            write(directory, check=True)
            csv_path.write_bytes(csv_path.read_bytes().replace(b"software_candidate", b"rtl", 1))
            with self.assertRaisesRegex(ValueError, "differs"):
                write(directory, check=True)


if __name__ == "__main__":
    unittest.main()
