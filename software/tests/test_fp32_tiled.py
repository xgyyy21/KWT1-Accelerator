"""Checks for the draft FP32 tile capacity and arithmetic schedule."""

import unittest

from software.fp32_reference import from_float, run_ffn1_bits
from software.innovation.fp32_tiled import plan_fp32_tiles, run_tiled_bits


class FP32TileTests(unittest.TestCase):
    def test_k32_and_three_buffer_budget(self):
        plan = plan_fp32_tiles(99, 64, 256)
        self.assertEqual(plan["groups"], {"rows": 13, "depth": 2, "columns": 16})
        self.assertEqual(plan["peak_buffer_bytes"],
                         {"x": 2048, "w": 2048, "partial": 512})
        self.assertEqual(plan["multiplications"], 1622016)
        self.assertEqual(plan["baseline_logical_bytes"]["total"], 6716160)
        self.assertEqual(plan["candidate_logical_bytes"]["total"], 1080064)
        self.assertEqual(plan["isolated_w_read_saving_bytes"], 5636096)

    def test_full_k_weight_tile_does_not_fit_one_buffer(self):
        with self.assertRaisesRegex(ValueError, "w tile needs 4096 bytes"):
            plan_fp32_tiles(99, 64, 256, depth_tile=64)

    def test_tails_and_k_boundary_keep_partial_sum(self):
        x_float = [[0.0] * 33 for _ in range(3)]
        x_float[0][31], x_float[0][32] = 1.0, 2.0
        x_float[1][31], x_float[1][32] = -4.0, 0.5
        x_float[2][0], x_float[2][32] = 2.0, -1.0
        w_float = [[0.0] * 5 for _ in range(33)]
        w_float[31] = [1.0, 2.0, -1.0, 0.5, 3.0]
        w_float[32] = [1.0, -3.0, 2.0, 1.0, -2.0]
        w_float[0] = [0.25, 0.5, 1.0, -1.0, 2.0]
        b_float = [3.0, -1.0, 2.0, 0.0, 1.0]
        x = [[from_float(v) for v in row] for row in x_float]
        w = [[from_float(v) for v in row] for row in w_float]
        b = [from_float(v) for v in b_float]
        self.assertEqual(run_tiled_bits(x, w, b, row_tile=2, depth_tile=32,
                                        column_tile=3), run_ffn1_bits(x, w, b))
        self.assertEqual(run_tiled_bits(x, w, b)[0][0], from_float(6.0))

    def test_invalid_tile_or_capacity_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "row_tile"):
            plan_fp32_tiles(99, 64, 256, row_tile=0)
        with self.assertRaisesRegex(ValueError, "x tile needs 2048 bytes"):
            plan_fp32_tiles(99, 64, 256, x_capacity=1024)


if __name__ == "__main__":
    unittest.main()
