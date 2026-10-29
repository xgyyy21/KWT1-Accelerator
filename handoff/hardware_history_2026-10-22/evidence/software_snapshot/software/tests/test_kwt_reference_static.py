"""Checks that do not need the legacy TensorFlow environment."""

from __future__ import annotations

import json
import tempfile
import unittest
import wave
from pathlib import Path
from types import SimpleNamespace

import numpy as np

from software import kwt_reference

WORKSPACE = Path(__file__).resolve().parents[2]
WORK_DIR = (WORKSPACE / "work").resolve()
if not WORK_DIR.is_relative_to(WORKSPACE) or not WORK_DIR.is_dir():
    raise RuntimeError("Test temporary directory is outside the workspace")


class ReferenceInputTests(unittest.TestCase):
    def test_export_requires_explicit_split_and_source_id(self):
        result = kwt_reference.validate_provenance("validation", "validation/yes.wav")
        self.assertEqual(result["split"], "validation")
        self.assertEqual(result["source_id"], "validation/yes.wav")
        self.assertEqual(
            kwt_reference.validate_provenance("unverified", "eight/sample.wav")["split"],
            "unverified",
        )
        with self.assertRaisesRegex(ValueError, "--split"):
            kwt_reference.validate_provenance("", "validation/yes.wav")
        with self.assertRaisesRegex(ValueError, "--source-id"):
            kwt_reference.validate_provenance("synthetic-smoke", "  ")

    def test_pcm16_wav_scaling(self):
        with tempfile.TemporaryDirectory(dir=WORK_DIR) as directory:
            path = Path(directory) / "input.wav"
            samples = np.zeros(16000, dtype="<i2")
            samples[0] = -32768
            samples[1] = 32767
            with wave.open(str(path), "wb") as stream:
                stream.setnchannels(1)
                stream.setsampwidth(2)
                stream.setframerate(16000)
                stream.writeframes(samples.tobytes())
            loaded = kwt_reference.load_audio(SimpleNamespace(wav=path, raw_npy=None))
            self.assertEqual(loaded.shape, (1, 16000))
            self.assertEqual(loaded.dtype, np.float32)
            self.assertEqual(float(loaded[0, 0]), -1.0)
            self.assertAlmostEqual(float(loaded[0, 1]), 32767 / 32768, places=7)

    def test_pcm16_wav_short_padding_and_long_truncation(self):
        with tempfile.TemporaryDirectory(dir=WORK_DIR) as directory:
            for frame_count in (8000, 17000):
                path = Path(directory) / f"{frame_count}.wav"
                samples = np.full(frame_count, 16384, dtype="<i2")
                with wave.open(str(path), "wb") as stream:
                    stream.setnchannels(1)
                    stream.setsampwidth(2)
                    stream.setframerate(16000)
                    stream.writeframes(samples.tobytes())
                loaded = kwt_reference.load_audio(SimpleNamespace(wav=path, raw_npy=None))
                self.assertEqual(loaded.shape, (1, 16000))
                self.assertEqual(loaded.dtype, np.float32)
                np.testing.assert_array_equal(loaded[0, :min(frame_count, 16000)], 0.5)
                if frame_count < 16000:
                    np.testing.assert_array_equal(loaded[0, frame_count:], 0.0)

    def test_rejects_wrong_model_dimensions(self):
        with tempfile.TemporaryDirectory(dir=WORK_DIR) as directory:
            model_dir = Path(directory)
            flags = {
                "model_name": "kws_transformer",
                "num_layers": 12,
                "d_model": 64,
                "mlp_dim": 128,  # wrong for the specified best_weights
                "heads": 1,
                "preprocess": "raw",
                "attention_type": "time",
                "spectrogram_length": 98,
                "desired_samples": 16000,
            }
            (model_dir / "flags.json").write_text(json.dumps(flags), encoding="utf-8")
            with self.assertRaisesRegex(ValueError, "mlp_dim"):
                kwt_reference.load_flags(model_dir)


if __name__ == "__main__":
    unittest.main()
