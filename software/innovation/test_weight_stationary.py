"""Independent checks for weight tile order, provenance, and traffic maths."""

from __future__ import annotations

from hashlib import sha256
import json
from pathlib import Path
import tempfile
import unittest

import numpy as np

from software.ffn1_numeric import FixedPointSpec, run_ffn1_integer
from software.innovation.weight_stationary import estimate_traffic, export_weight_tiles
from software.pack_tensors import create_task_pack, unpack_words_to_signed


class WeightStationaryTests(unittest.TestCase):
    def _make_pack(self, root: Path, *, w_bits: int = 16) -> tuple[Path, np.ndarray]:
        packed = root / "packed"
        source = root / "source.npz"
        weights = np.array([[11, -12, 13, 14, 15], [21, 22, -23, 24, 25]], dtype=np.int64)
        np.savez(
            source,
            x=np.array([[1, 2], [3, 4], [5, 6]], dtype=np.float64),
            w=weights.astype(np.float64),
            b=np.array([3, -4, 5, -6, 7], dtype=np.float64),
        )
        spec = FixedPointSpec(
            x_bits=16, x_frac=0, w_bits=w_bits, w_frac=0,
            bias_bits=32, acc_bits=48, out_bits=32, out_frac=0,
        )
        create_task_pack(source, packed, spec)
        return packed, weights

    def test_export_reconstructs_each_w_element_and_counts_bytes(self) -> None:
        with tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parent) as tmp:
            root = Path(tmp)
            packed, weights = self._make_pack(root)
            output = root / "tiled"
            schedule = export_weight_tiles(
                packed, output, tile_columns=2, weight_buffer_bytes=8
            )
            self.assertEqual([t["columns"] for t in schedule["tiles"]], [2, 2, 1])
            self.assertEqual([t["byte_count"] for t in schedule["tiles"]], [8, 8, 4])
            self.assertEqual(schedule["weight_buffer"]["largest_tile_bytes"], 8)
            reconstructed = np.empty_like(weights)
            for tile in schedule["tiles"]:
                binary = (output / tile["binary_file"]).read_bytes()
                self.assertEqual(sha256(binary).hexdigest(), tile["binary_sha256"])
                words = np.frombuffer(binary, dtype="<u2")
                decoded = unpack_words_to_signed(
                    words, tuple(tile["shape_k_by_columns"]), 16
                )
                first = tile["column_start_inclusive"]
                last = tile["column_end_exclusive"]
                reconstructed[:, first:last] = decoded
                mem_words = (output / tile["readmemh_file"]).read_text(
                    encoding="ascii"
                ).splitlines()
                self.assertEqual(mem_words, [f"{int(v):04x}" for v in words])
            np.testing.assert_array_equal(reconstructed, weights)
            self.assertEqual(
                (output / schedule["tiles"][0]["binary_file"]).read_bytes(),
                np.array([11, -12, 21, 22], dtype="<i2").tobytes(),
            )
            on_disk = json.loads((output / "schedule_manifest.json").read_text(encoding="utf-8"))
            self.assertEqual(on_disk["source"]["w_binary_sha256"],
                             sha256((packed / "w.bin").read_bytes()).hexdigest())
            traffic = schedule["analytical_shared_memory_traffic"]
            self.assertEqual(traffic["multiply_accumulate_count_both"], 30)
            self.assertEqual(traffic["row_first"]["total_bytes"], 152)
            self.assertEqual(traffic["tile_first_weight_stationary"]["total_bytes"], 136)
            self.assertEqual(traffic["estimated_saved_bytes"], 16)

    def test_multiword_weights_keep_low_word_first(self) -> None:
        with tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parent) as tmp:
            root = Path(tmp)
            packed, weights = self._make_pack(root, w_bits=32)
            schedule = export_weight_tiles(
                packed, root / "tiled", tile_columns=2, weight_buffer_bytes=16
            )
            reconstructed = np.empty_like(weights)
            for tile in schedule["tiles"]:
                raw = (root / "tiled" / tile["binary_file"]).read_bytes()
                decoded = unpack_words_to_signed(
                    np.frombuffer(raw, dtype="<u2"),
                    tuple(tile["shape_k_by_columns"]), 32,
                )
                reconstructed[:, tile["column_start_inclusive"]:tile["column_end_exclusive"]] = decoded
            np.testing.assert_array_equal(reconstructed, weights)

    def test_tiled_integer_compute_matches_full_layer_bit_for_bit(self) -> None:
        with tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parent) as tmp:
            root = Path(tmp)
            packed, weights = self._make_pack(root)
            output = root / "tiled"
            schedule = export_weight_tiles(
                packed, output, tile_columns=2, weight_buffer_bytes=8
            )
            spec = FixedPointSpec(
                x_bits=16, x_frac=0, w_bits=16, w_frac=0,
                bias_bits=32, acc_bits=48, out_bits=32, out_frac=0,
            )
            x_q = np.array([[1, 2], [3, 4], [5, 6]], dtype=np.int64)
            b_q = np.array([3, -4, 5, -6, 7], dtype=np.int64)
            full = run_ffn1_integer(x_q, weights, b_q, spec)
            tiled = np.empty_like(full)
            for tile in schedule["tiles"]:
                start = tile["column_start_inclusive"]
                stop = tile["column_end_exclusive"]
                words = np.frombuffer(
                    (output / tile["binary_file"]).read_bytes(), dtype="<u2"
                )
                tile_w = unpack_words_to_signed(
                    words, tuple(tile["shape_k_by_columns"]), 16
                )
                tiled[:, start:stop] = run_ffn1_integer(
                    x_q, tile_w, b_q[start:stop], spec
                )
            np.testing.assert_array_equal(tiled, full)
            packed_expected = unpack_words_to_signed(
                np.frombuffer((packed / "expected.bin").read_bytes(), dtype="<u2"),
                full.shape, 32,
            )
            np.testing.assert_array_equal(tiled, packed_expected)

    def test_rejects_capacity_corruption_and_wrong_length(self) -> None:
        with tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parent) as tmp:
            root = Path(tmp)
            packed, _ = self._make_pack(root)
            with self.assertRaisesRegex(ValueError, "at most 1 full output columns fit"):
                export_weight_tiles(packed, root / "too_wide", tile_columns=2,
                                    weight_buffer_bytes=6)
            self.assertFalse((root / "too_wide").exists())
            original = (packed / "w.bin").read_bytes()
            tampered = bytearray(original)
            tampered[0] ^= 0x01
            (packed / "w.bin").write_bytes(tampered)
            with self.assertRaisesRegex(ValueError, "SHA-256"):
                export_weight_tiles(packed, root / "tampered", tile_columns=2,
                                    weight_buffer_bytes=8)
            (packed / "w.bin").write_bytes(original[:-2])
            with self.assertRaisesRegex(ValueError, "length"):
                export_weight_tiles(packed, root / "short", tile_columns=2,
                                    weight_buffer_bytes=8)

    def test_canonical_ffn1_traffic_is_formula_not_ppa(self) -> None:
        traffic = estimate_traffic(
            rows=99, inner=64, columns=256, tile_columns=16,
            x_element_bytes=2, w_element_bytes=2,
            bias_element_bytes=6, output_element_bytes=4,
        )
        self.assertEqual(traffic["tile_count"], 16)
        self.assertEqual(traffic["multiply_accumulate_count_both"], 1_622_016)
        self.assertEqual(traffic["row_first"]["total_bytes"], 3_359_616)
        self.assertEqual(traffic["tile_first_weight_stationary"]["total_bytes"], 338_432)
        self.assertEqual(traffic["estimated_saved_bytes"], 3_021_184)


if __name__ == "__main__":
    unittest.main()
