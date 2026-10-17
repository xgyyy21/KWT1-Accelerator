"""Run the pinned KWT extractor with only the KWT model source downloaded.

The original upstream model registry imports every unrelated model at import
time.  For this sparse checkout, an empty registry is injected so that the
unchanged pinned KWT model and its actual helper code can load.  The registry
is not used by KWT-1 construction.  The extractor still compares probe logits
to the official KWT-1 model and checks every X @ W + b output.
"""

from pathlib import Path
import os
import sys
import types


PROJECT = Path(__file__).resolve().parent.parent
if "--repo" in sys.argv:
    repo_argument = sys.argv.index("--repo") + 1
    if repo_argument >= len(sys.argv):
        raise SystemExit("--repo needs a sparse checkout path")
    REPO = Path(sys.argv[repo_argument]).resolve()
else:
    REPO = PROJECT / "third_party/kwt_pinned_sparse"
os.environ.setdefault("CUDA_VISIBLE_DEVICES", "-1")
os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "2")
sys.path.insert(0, str(PROJECT))
sys.path.insert(0, str(REPO))

import kws_streaming.models as model_package  # noqa: E402

registry = types.ModuleType("kws_streaming.models.models")
registry.MODELS = {}
sys.modules[registry.__name__] = registry
model_package.models = registry

from software.kwt_reference import load_flags, main  # noqa: E402


if __name__ == "__main__":
    if sys.argv[1:] == ["--check-import"]:
        from kws_streaming.models import kws_transformer
        print("Imported pinned KWT model:", kws_transformer.__file__)
    elif sys.argv[1:] == ["--check-build"]:
        import tensorflow as tf
        from kws_streaming.models import kws_transformer
        tf.compat.v1.disable_eager_execution()
        tf.compat.v1.keras.backend.set_learning_phase(0)
        flags = load_flags(REPO / "models_data_v2_12_labels/kwt1")
        model = kws_transformer.model(flags)
        print("Constructed pinned KWT model:", model.input_shape, model.output_shape)
    else:
        main()
