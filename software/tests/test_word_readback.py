"""Focused checks for the hardware cache readback handoff format."""

from __future__ import annotations

import csv
import hashlib
import tempfile
import unittest
from pathlib import Path

from software.check_word_readback import FIELDS, ReadbackError, check_readback


IMAGE_DIR = Path(__file__).resolve().parents[1] / "examples" / "fp32_hand_image"
ONE_GROUP = {("hand_2x2", "X"): "x"}


class WordReadbackTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp = tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parent)
        self.addCleanup(self.temp.cleanup)
        self.csv_path = Path(self.temp.name) / "word_readback.csv"
        binary = (IMAGE_DIR / "x.bin").read_bytes()
        digest = hashlib.sha256(binary).hexdigest()
        words = [int.from_bytes(binary[i:i + 2], "little") for i in range(0, len(binary), 2)]
        self.rows = []
        for element in range(4):
            low_req = 17 + 4 * element
            low, high = words[2 * element:2 * element + 2]
            self.rows.append({
                "case": "hand_2x2", "tensor": "X", "input_bin": "x.bin",
                "input_sha256": digest, "mem_hex_file": "D:/old-machine/x.mem",
                "rtl_revision": "abc123+dirty", "rtl_snapshot_sha256": "a" * 64,
                "bank": "A", "row": str(element // 2), "column": str(element % 2),
                "k": str(element % 2), "low_word_address": str(2 * element),
                "high_word_address": str(2 * element + 1),
                "word_low16": f"{low:04x}", "word_high16": f"{high:04x}",
                "reconstructed_fp32_bits": f"0x{(high << 16) | low:08x}",
                "low_request_cycle": str(low_req), "low_data_valid_cycle": str(low_req + 1),
                "high_request_cycle": str(low_req + 2),
                "high_data_valid_cycle": str(low_req + 3),
            })

    def write_rows(self, rows=None) -> None:
        with self.csv_path.open("w", encoding="utf-8", newline="") as stream:
            writer = csv.DictWriter(stream, fieldnames=FIELDS)
            writer.writeheader()
            writer.writerows(self.rows if rows is None else rows)

    def check(self) -> dict:
        return check_readback(self.csv_path, IMAGE_DIR, ONE_GROUP)

    def test_valid_low_word_first_readback(self) -> None:
        self.write_rows()
        result = self.check()
        self.assertEqual(result["status"], "PASS")
        self.assertEqual(result["records_checked"], 4)
        self.assertEqual(result["groups"][0]["elements_checked"], 4)
        self.assertIn("no arithmetic/DMA/SoC validation", result["scope"])

    def test_one_bit_corruption_is_detected(self) -> None:
        self.rows[0]["word_high16"] = "3f81"
        self.write_rows()
        with self.assertRaisesRegex(ReadbackError, "line 2: readback words disagree"):
            self.check()

    def test_low_and_high_words_cannot_be_swapped(self) -> None:
        self.rows[0]["word_low16"], self.rows[0]["word_high16"] = (
            self.rows[0]["word_high16"], self.rows[0]["word_low16"]
        )
        self.write_rows()
        with self.assertRaisesRegex(ReadbackError, "readback words disagree"):
            self.check()

    def test_one_cycle_read_latency_is_checked(self) -> None:
        self.rows[0]["low_data_valid_cycle"] = "19"
        self.write_rows()
        with self.assertRaisesRegex(ReadbackError, "not valid one cycle"):
            self.check()

    def test_missing_record_is_rejected(self) -> None:
        self.write_rows(self.rows[:-1])
        with self.assertRaisesRegex(ReadbackError, "expected 4"):
            self.check()

    def test_duplicate_coordinate_is_rejected(self) -> None:
        self.rows[1]["row"] = self.rows[0]["row"]
        self.rows[1]["column"] = self.rows[0]["column"]
        self.write_rows()
        with self.assertRaisesRegex(ReadbackError, "duplicate"):
            self.check()

    def test_input_hash_is_checked(self) -> None:
        self.rows[0]["input_sha256"] = "0" * 64
        self.write_rows()
        with self.assertRaisesRegex(ReadbackError, "input SHA-256 disagrees"):
            self.check()


if __name__ == "__main__":
    unittest.main()
