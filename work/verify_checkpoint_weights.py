"""Verify every exported FFN1 W/b equals the pinned checkpoint tensor.

This addresses TensorFlow's checkpoint object-reference warnings without
assuming that a successful model/probe self-comparison proves restoration.
"""

from pathlib import Path

import numpy as np
import tensorflow as tf


PREFIX = "third_party/kwt_pinned_sparse/models_data_v2_12_labels/kwt1/best_weights"
EXPORT = Path("runs/reference_smoke/zero_audio")

for layer in range(12):
    with np.load(EXPORT / f"layer_{layer:02d}.npz", allow_pickle=False) as case:
        for local_key, checkpoint_key in (
            ("w", "kernel"),
            ("b", "bias"),
        ):
            variable = (
                f"layer_with_weights-0/enc_layers/{layer}/ffn/"
                f"layer_with_weights-0/{checkpoint_key}/.ATTRIBUTES/VARIABLE_VALUE"
            )
            from_checkpoint = tf.train.load_variable(PREFIX, variable)
            np.testing.assert_array_equal(case[local_key], from_checkpoint)
print("PASS: all 12 exported FFN1 kernels and biases exactly match best_weights")
