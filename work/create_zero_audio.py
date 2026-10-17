"""Create a shape-valid synthetic waveform for model-loading smoke tests only.

This is not a Speech Commands validation sample and cannot support any
competition accuracy claim.
"""

from pathlib import Path

import numpy as np


out = Path("runs/input_smoke/zeros_16k.npy")
out.parent.mkdir(parents=True, exist_ok=True)
np.save(out, np.zeros(16000, dtype=np.float32), allow_pickle=False)
print(out)
