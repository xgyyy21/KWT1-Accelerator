"""Synthetic checks for the local candidate study; no real KWT data here."""

from __future__ import annotations

import math
import json
from pathlib import Path
import tempfile
import unittest

import numpy as np

from software.ffn1_numeric import FixedPointSpec, run_ffn1_real
from software.kwt_reference import PINNED_COMMIT
from software.precision.study import (
    evaluate, file_hash, fixed_point_with_counts, load_candidates,
    sample_provenance, storage_estimate,
)


class PrecisionStudyTests(unittest.TestCase):
    def test_instrumented_arithmetic_matches_existing_model(self) -> None:
        spec = FixedPointSpec(x_bits=4, x_frac=0, w_bits=4, w_frac=0,
                              bias_bits=5, acc_bits=5, out_bits=4, out_frac=0)
        x = np.asarray([[8.0, 7.0]])
        w = np.asarray([[7.0], [7.0]])
        b = np.asarray([15.0])
        real, counts = fixed_point_with_counts(x, w, b, spec)
        expected = run_ffn1_real(x, w, b, spec).out_real
        np.testing.assert_array_equal(real, expected)
        self.assertEqual(real.item(), 7.0)
        self.assertEqual(counts["x_quantized"], 1)
        self.assertEqual(counts["mac_adds"], 2)
        self.assertEqual(counts["bias_adds"], 1)
        self.assertEqual(counts["output"], 1)

    def test_instrumented_arithmetic_matches_with_fractional_negative_values(self) -> None:
        spec = FixedPointSpec(x_bits=8, x_frac=3, w_bits=8, w_frac=2,
                              bias_bits=16, acc_bits=16, out_bits=8, out_frac=1)
        x = np.asarray([[0.25, -1.125, 2.25], [-3.5, 0.5, -0.25]])
        w = np.asarray([[1.5, -0.25], [-0.5, 2.0], [0.75, -1.0]])
        b = np.asarray([-0.25, 0.375])
        actual, _ = fixed_point_with_counts(x, w, b, spec)
        np.testing.assert_array_equal(actual, run_ffn1_real(x, w, b, spec).out_real)

    def test_storage_is_labelled_theoretical(self) -> None:
        data = storage_estimate(FixedPointSpec())
        self.assertEqual(data["tensors"]["w"]["byte_aligned_element_bytes"], 64 * 256 * 2)
        self.assertTrue(data["existing_16_bit_word_packer_compatible"])
        self.assertFalse(storage_estimate(FixedPointSpec(x_bits=12))["existing_16_bit_word_packer_compatible"])

    def test_candidate_schema(self) -> None:
        example = Path(__file__).resolve().parents[1] / "precision" / "candidates.example.json"
        candidates = load_candidates(example)
        self.assertEqual(len(candidates), 3)
        self.assertEqual(candidates[0][0], "illustrative_q8_4")

    def test_pooling_across_samples_and_incomplete_coverage(self) -> None:
        spec = FixedPointSpec(x_bits=8, x_frac=0, w_bits=8, w_frac=0,
                              bias_bits=16, acc_bits=16, out_bits=16, out_frac=0)
        with tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parent) as tmp:
            root = Path(tmp)
            x = np.zeros((99, 64))
            w = np.zeros((64, 256))
            for sample, bias in (("small", 0.49), ("large", 10.0)):
                folder = root / sample
                folder.mkdir()
                b = np.full(256, bias)
                y = np.full((99, 256), bias)
                for layer in range(12):
                    np.savez_compressed(folder / f"layer_{layer:02d}.npz",
                                        x=x, w=w, b=b, y_float=y)
            report = evaluate(root, [("candidate", spec)])
            self.assertTrue(report["all_sample_directories_have_12_layers"])
            self.assertFalse(report["all_samples_eligible_for_local_validation_screen"])
            self.assertEqual(report["sample_provenance"][0]["split"], "unknown")
            self.assertEqual(len(report["sources"]), 24)
            candidate = report["candidates"][0]
            # Pooling squared errors gives sqrt(0.49^2 / (0.49^2+10^2));
            # averaging per-sample percentages would incorrectly give 50%.
            expected = math.sqrt(0.49**2 / (0.49**2 + 10.0**2))
            self.assertAlmostEqual(candidate["maximum_12_layer_nrmse"], expected, places=10)
            self.assertEqual(len(candidate["per_task_nrmse"]), 24)
            self.assertEqual(candidate["max_single_task_nrmse"], 1.0)
            self.assertEqual(len(candidate["single_tasks_over_3_percent"]), 12)
            self.assertFalse(candidate["local_3_percent_screen"])
            (root / "small" / "layer_11.npz").unlink()
            partial = evaluate(root, [("candidate", spec)])
            self.assertFalse(partial["all_sample_directories_have_12_layers"])
            self.assertIsNone(partial["candidates"][0]["maximum_12_layer_nrmse"])
            self.assertFalse(partial["candidates"][0]["local_3_percent_screen"])

    def test_validation_screen_requires_declared_source_and_matching_npz_hashes(self) -> None:
        with tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parent) as tmp:
            root = Path(tmp)
            sample = root / "sample_001"
            sample.mkdir()
            x = np.zeros((99, 64))
            w = np.zeros((64, 256))
            b = np.ones(256)
            y = np.ones((99, 256))
            layer_records = []
            layer_hashes = {}
            for layer in range(12):
                filename = f"layer_{layer:02d}.npz"
                path = sample / filename
                np.savez_compressed(path, x=x, w=w, b=b, y_float=y)
                layer_hashes[layer] = file_hash(path)
                layer_records.append({"layer": layer, "file": filename, "sha256": layer_hashes[layer]})
            manifest = {
                "provenance": {"split": "validation", "source_id": "validation/sample_001.wav"},
                "upstream_commit": PINNED_COMMIT,
                "model": "models_data_v2_12_labels/kwt1/best_weights",
                "input_sha256": "a" * 64,
                "flags_sha256": "b" * 64,
                "checkpoint_sha256": {
                    "best_weights.index": "c" * 64,
                    "best_weights.data-00000-of-00001": "d" * 64,
                },
                "checkpoint_ffn1_tensors_exactly_verified": 24,
                "layers": layer_records,
            }
            manifest_path = sample / "manifest.json"
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            spec = FixedPointSpec()
            report = evaluate(root, [("candidate", spec)])
            self.assertTrue(report["all_samples_eligible_for_local_validation_screen"])
            self.assertTrue(report["candidates"][0]["local_3_percent_screen"])
            self.assertEqual(report["candidates"][0]["local_3_percent_screen_status"],
                             "passed_local_validation_screen")

            manifest["provenance"]["split"] = "synthetic-smoke"
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            synthetic = sample_provenance(sample, root, layer_hashes)
            self.assertEqual(synthetic["classification"], "synthetic_smoke")
            self.assertFalse(synthetic["eligible_for_local_validation_screen"])

            manifest["provenance"]["split"] = "unverified"
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            unverified = sample_provenance(sample, root, layer_hashes)
            self.assertEqual(unverified["classification"], "unverified_dataset_membership")
            self.assertFalse(unverified["eligible_for_local_validation_screen"])

            manifest["provenance"]["split"] = "validation"
            manifest["layers"][0]["sha256"] = "0" * 64
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            tampered = sample_provenance(sample, root, layer_hashes)
            self.assertFalse(tampered["eligible_for_local_validation_screen"])
            self.assertIn("layer 00 file identity or SHA-256 mismatch", tampered["reasons"])

            del manifest["provenance"]
            manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
            legacy = sample_provenance(sample, root, layer_hashes)
            self.assertEqual(legacy["split"], "unknown")
            self.assertFalse(legacy["eligible_for_local_validation_screen"])

    def test_rejects_false_float_reference(self) -> None:
        with tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parent) as tmp:
            root = Path(tmp)
            np.savez(root / "layer_00.npz", x=np.zeros((99, 64)),
                     w=np.zeros((64, 256)), b=np.zeros(256),
                     y_float=np.ones((99, 256)))
            with self.assertRaisesRegex(ValueError, "y_float does not agree"):
                evaluate(root, [("candidate", FixedPointSpec())])


if __name__ == "__main__":
    unittest.main()
