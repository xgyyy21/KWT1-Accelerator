"""Check two independent zero-waveform probe runs have identical arrays."""

from pathlib import Path
import numpy as np


roots = [Path("runs/reference_smoke/zero_audio"), Path("runs/reference_smoke/zero_audio_verified")]
for layer in range(12):
    with np.load(roots[0] / f"layer_{layer:02d}.npz", allow_pickle=False) as first, np.load(
        roots[1] / f"layer_{layer:02d}.npz", allow_pickle=False
    ) as second:
        for name in ("x", "w", "b", "y_float"):
            np.testing.assert_array_equal(first[name], second[name],
                                          err_msg=f"layer {layer} {name} changed")
print("PASS: 12 layers x/w/b/y_float exactly match across independent runs")
