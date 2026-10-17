"""Compare the extractor's PCM16 loader with upstream TF decode_wav semantics.

Run in the isolated Python 3.8 / TensorFlow 2.4 environment. This is a
diagnostic for short, exact-length, and long mono WAVs, not a dataset test.
"""

from __future__ import annotations

from pathlib import Path
from tempfile import TemporaryDirectory
from types import SimpleNamespace
import wave

import numpy as np
import tensorflow as tf

from software.kwt_reference import load_audio


PROJECT = Path(__file__).resolve().parent.parent


def main() -> None:
    with TemporaryDirectory(dir=PROJECT / "work") as directory:
        for frames in (8000, 16000, 17000):
            path = Path(directory) / f"{frames}.wav"
            integers = np.zeros(frames, dtype="<i2")
            integers[:min(frames, 4)] = (-32768, -1, 1, 32767)
            if frames > 16000:
                integers[16000:] = 12345  # must be truncated
            with wave.open(str(path), "wb") as stream:
                stream.setnchannels(1)
                stream.setsampwidth(2)
                stream.setframerate(16000)
                stream.writeframes(integers.tobytes())
            actual = load_audio(SimpleNamespace(wav=path, raw_npy=None))[0]
            official_decode = tf.audio.decode_wav(
                tf.constant(path.read_bytes()), desired_channels=1, desired_samples=16000
            ).audio.numpy()[:, 0]
            np.testing.assert_array_equal(actual, official_decode)
            print(f"{frames} input frames: exact match with TF decode_wav desired_samples=16000")


if __name__ == "__main__":
    main()
