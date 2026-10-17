"""Print the isolated KWT-1 runtime versions and import errors."""

import numpy as np
import tensorflow as tf
import tensorflow_addons as tfa

print("TensorFlow:", tf.__version__)
print("TensorFlow Addons:", tfa.__version__)
print("NumPy:", np.__version__)
