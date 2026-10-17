"""List KWT-1 checkpoint tensor names for the restore audit."""

from pathlib import Path
import tensorflow as tf

prefix = Path("third_party/kwt_pinned_sparse/models_data_v2_12_labels/kwt1/best_weights")
variables = tf.train.list_variables(str(prefix))
print("Checkpoint variable count:", len(variables))
for name, shape in variables[:100]:
    print(name, shape)
