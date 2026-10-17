"""Check that layer error pools all sample elements before normalization."""

from __future__ import annotations

import math
import json
from pathlib import Path
import tempfile
import unittest

import numpy as np

from software.evaluate_layers import evaluate_files
from software.ffn1_numeric import FixedPointSpec
from software.kwt_reference import PINNED_COMMIT
from software.precision.study import file_hash


class LayerAggregationTests(unittest.TestCase):
    def test_two_samples_pool_squared_error_before_nrmse(self) -> None:
        spec = FixedPointSpec(x_frac=0, w_frac=0, out_frac=0)
        with tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parent) as temporary:
            files = []
            for index, reference_value in enumerate((1.0, 2.0)):
                folder = Path(temporary) / f"sample_{index}"
                folder.mkdir()
                file = folder / "layer_00.npz"
                x = np.zeros((99, 64))
                w = np.zeros((64, 256))
                x[:, 0] = reference_value / 2
                w[0, :] = 2
                np.savez(file, x=x, w=w, b=np.zeros(256),
                         y_float=np.full((99, 256), reference_value))
                files.append(file)
            report = evaluate_files(files, spec)
            self.assertEqual(report["layers"]["0"]["samples"], 2)
            self.assertAlmostEqual(report["layers"]["0"]["numeric_nrmse"], 1 / math.sqrt(5))
            self.assertFalse(report["all_12_layers_present"])
            self.assertFalse(report["local_3_percent_screen"])

    def test_all_layer_names_are_not_enough_if_a_sample_is_incomplete(self) -> None:
        spec = FixedPointSpec(x_frac=0, w_frac=0, out_frac=0)
        with tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parent) as temporary:
            files = []
            x = np.zeros((99, 64))
            w = np.zeros((64, 256))
            b = np.zeros(256)
            y_float = np.zeros((99, 256))
            for name, layers in (("complete", range(12)), ("partial", (0,))):
                folder = Path(temporary) / name
                folder.mkdir()
                for layer in layers:
                    path = folder / f"layer_{layer:02d}.npz"
                    np.savez(path, x=x, w=w, b=b, y_float=y_float)
                    files.append(path)
            report = evaluate_files(files, spec)
            self.assertEqual(len(report["layers"]), 12)
            self.assertEqual(report["sample_groups"], 2)
            self.assertFalse(report["all_12_layers_present"])
            self.assertFalse(report["local_3_percent_screen"])
            self.assertEqual(len(report["incomplete_groups"]), 1)
            self.assertEqual(report["incomplete_groups"][0]["present_layers"], [0])
            self.assertEqual(report["incomplete_groups"][0]["missing_layers"], list(range(1, 12)))

    def test_rejects_y_float_that_is_not_x_matmul_w_plus_b(self) -> None:
        with tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parent) as temporary:
            path = Path(temporary) / "layer_00.npz"
            np.savez(path, x=np.zeros((99, 64)), w=np.zeros((64, 256)),
                     b=np.zeros(256), y_float=np.ones((99, 256)))
            with self.assertRaisesRegex(ValueError, "y_float disagrees"):
                evaluate_files([path], FixedPointSpec())

    def test_complete_layers_need_validation_provenance_to_pass_screen(self) -> None:
        with tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parent) as temporary:
            folder = Path(temporary) / "sample"
            folder.mkdir()
            files = []
            records = []
            for layer in range(12):
                path = folder / f"layer_{layer:02d}.npz"
                np.savez_compressed(path, x=np.zeros((99, 64)), w=np.zeros((64, 256)),
                                    b=np.ones(256), y_float=np.ones((99, 256)))
                files.append(path)
                records.append({"layer": layer, "file": path.name, "sha256": file_hash(path)})
            old = evaluate_files(files, FixedPointSpec())
            self.assertTrue(old["all_12_layers_present"])
            self.assertEqual(old["maximum_numeric_nrmse"], 0.0)
            self.assertEqual(old["sample_provenance"][0]["split"], "unknown")
            self.assertFalse(old["local_3_percent_screen"])

            manifest = {
                "provenance": {"split": "validation", "source_id": "validation/sample.wav"},
                "upstream_commit": PINNED_COMMIT,
                "model": "models_data_v2_12_labels/kwt1/best_weights",
                "input_sha256": "a" * 64, "flags_sha256": "b" * 64,
                "checkpoint_sha256": {
                    "best_weights.index": "c" * 64,
                    "best_weights.data-00000-of-00001": "d" * 64,
                },
                "checkpoint_ffn1_tensors_exactly_verified": 24,
                "layers": records,
            }
            (folder / "manifest.json").write_text(json.dumps(manifest), encoding="utf-8")
            declared = evaluate_files(files, FixedPointSpec())
            self.assertTrue(declared["all_samples_eligible_for_local_validation_screen"])
            self.assertTrue(declared["local_3_percent_screen"])


if __name__ == "__main__":
    unittest.main()
