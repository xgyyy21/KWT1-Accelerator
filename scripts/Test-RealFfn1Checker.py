"""Synthetic unit tests of the evidence checker, NOT RTL test results."""
from __future__ import annotations

import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("real_checker", Path(__file__).with_name("Check-RealFfn1Layer00.py"))
checker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(checker)


class EvidenceCheckerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.gold = [0x3F800000 ^ (i % 31) for i in range(checker.M * checker.N)]
        cls.output = []
        for i, value in enumerate(cls.gold):
            r, c = divmod(i, checker.N)
            cls.output.append(dict(row=str(r), column=str(c), word_address=str(checker.Y_BASE + 2 * i),
                                   result_bits=f"0x{value:08x}", expected_bits=f"0x{value:08x}", match="1"))
        cls.writes = []
        for i, (tile, r, c, addr, half) in enumerate(checker.write_order()):
            word = (cls.gold[r * checker.N + c] >> (16 * half)) & 65535
            cls.writes.append(dict(cycle=str(2 * i + 1), tile_id=str(tile), row=str(r), column=str(c),
                                   word_address=str(addr), half=str(half), actual_word=f"0x{word:04x}"))
        cls.tiles = []
        for i in range(208):
            rb = (i // 16) * 8
            cls.tiles.append(dict(cycle=str(i + 1), tile_id=str(i), row_base=str(rb),
                                  column_base=str((i % 16) * 16), rows_valid=str(min(8, checker.M - rb)),
                                  cols_valid="16", k_blocks="2"))
        cls.last = int(cls.writes[-1]["cycle"])
        cls.log = ("PASS: FFN1 full layer m=99 k=64 n=256 tiles=208 outputs=25344 writes=50688 cycles=2587777\n"
                   "PASS: FFN1 read_halfwords=642048 unique_write_halfwords=50688 tail_rows=3 "
                   f"last_write_cycle={cls.last} done_cycle={cls.last + 2}\n")

    def test_valid_outputs(self):
        checker.check_outputs(self.output, self.gold)

    def test_valid_writes_and_final_memory(self):
        self.assertEqual(checker.check_writes(self.writes, self.output, self.gold), self.last)

    def test_valid_tiles(self):
        checker.check_tiles(self.tiles)

    def test_valid_log(self):
        self.assertEqual(checker.check_log(self.log, self.last)["done_cycle"], self.last + 2)

    def test_detects_nine_corruptions(self):
        result = checker.negative_controls(self.output, self.writes, self.tiles, self.gold, self.log, self.last)
        self.assertEqual(len(result), 9)
        self.assertTrue(all(r["status"] == "REJECTED_AS_EXPECTED" for r in result))

    def test_match_column_is_not_golden(self):
        row = self.output[0].copy()
        original = self.output[0]
        row["match"] = "0"
        self.output[0] = row
        try:
            checker.check_outputs(self.output, self.gold)
        finally:
            self.output[0] = original

    def test_reports_first_difference(self):
        bad = [r.copy() for r in self.output]
        bad[17]["result_bits"] = "0x00000000"
        with self.assertRaises(checker.CheckFailure) as captured:
            checker.check_outputs(bad, self.gold)
        detail = captured.exception.detail
        self.assertEqual(detail["first_difference"]["t"], 0)
        self.assertEqual(detail["first_difference"]["j"], 17)
        self.assertEqual(detail["count"], 1)

    def test_fatal_log_is_rejected(self):
        with self.assertRaises(checker.CheckFailure):
            checker.check_log(self.log + "FATAL: synthetic corruption\n", self.last)


if __name__ == "__main__":
    print("Synthetic evidence-checker unit tests only; not a hardware simulation.", flush=True)
    unittest.main(verbosity=2)
