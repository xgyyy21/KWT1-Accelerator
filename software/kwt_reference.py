"""Extract the 12 KWT-1 FFN-first-linear reference cases.

This tool intentionally imports the pinned upstream implementation instead of
reimplementing MFCC, attention, or layer normalization.  The only copied
operation order is the pinned post-norm TransformerBlock forward path, used to
expose intermediate tensors that the original model does not return.

The script targets ARM-software/keyword-transformer at commit 237e4097.  The
TensorFlow environment required by that 2021 repository is not bundled here.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
import wave
from pathlib import Path
from types import SimpleNamespace

import numpy as np

try:
    from .kwt_source_integrity import verify_runtime_blobs
except ImportError:  # direct `python software/kwt_reference.py` execution
    from kwt_source_integrity import verify_runtime_blobs


PINNED_COMMIT = "237e4097afd4f6851e0b82f0a8d65c2dfe8eae30"
PINNED_BLOBS = {
    "kws_streaming/models/transformer_utils.py": "ff597a2d6d15d9ae61304667da62931c14338c58",
    "kws_streaming/models/kws_transformer.py": "ff323b04786cea200bba7d62288673e1ebe48657",
    "models_data_v2_12_labels/kwt1/flags.json": "008af2047e217bdad9e84ff5e5b70e69bac423c3",
    "models_data_v2_12_labels/kwt1/best_weights.index": "900be3e4a2e3ccc0182b98de43a8fe21e72b6491",
    "models_data_v2_12_labels/kwt1/best_weights.data-00000-of-00001": "9c38f9653119383f7a303a94689c85a2a1c79b6b",
}
LAYER_COUNT = 12
X_SHAPE = (99, 64)
W_SHAPE = (64, 256)
B_SHAPE = (256,)
Y_SHAPE = (99, 256)
PROVENANCE_SPLITS = ("train", "validation", "test", "unverified", "synthetic-smoke")


def validate_provenance(split: str, source_id: str) -> dict[str, str]:
    """Record the operator's dataset claim; never infer a split from a path."""
    if split not in PROVENANCE_SPLITS:
        raise ValueError(f"--split must be one of {PROVENANCE_SPLITS}")
    if not isinstance(source_id, str) or not source_id.strip() or len(source_id) > 256:
        raise ValueError("--source-id must be a nonempty identifier of at most 256 characters")
    if source_id != source_id.strip() or any(char in source_id for char in "\r\n\0"):
        raise ValueError("--source-id must not have surrounding whitespace or control line breaks")
    return {
        "split": split,
        "source_id": source_id,
        "declaration": "operator supplied; verify against the dataset manifest separately",
    }


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def git_blob_sha1(path: Path) -> str:
    """Check source identity even when it came from a GitHub archive."""
    digest = hashlib.sha1()
    digest.update(f"blob {path.stat().st_size}\0".encode("ascii"))
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def check_checkout(repo: Path) -> dict[str, object]:
    # A pinned Git HEAD does not detect uncommitted edits. The sparse copy has
    # no .git at all. Verify every source/config/checkpoint blob used by this
    # KWT-1 runtime before importing TensorFlow or producing a reference.
    runtime_integrity = verify_runtime_blobs(repo)
    for relative_path, expected in PINNED_BLOBS.items():
        path = repo / relative_path
        if not path.is_file():
            raise ValueError(f"Missing official source/model file: {path}")
        actual = git_blob_sha1(path)
        if actual != expected:
            raise ValueError(f"Wrong content for {relative_path}: Git blob {actual}; expected {expected}")
    if (repo / ".git").exists():
        try:
            commit = subprocess.check_output(
                ["git", "-C", str(repo), "rev-parse", "HEAD"],
                text=True,
                stderr=subprocess.PIPE,
            ).strip()
        except (OSError, subprocess.CalledProcessError) as exc:
            raise ValueError("Cannot read the upstream Git commit") from exc
        if commit != PINNED_COMMIT:
            raise ValueError(f"Wrong upstream commit: {commit}; expected {PINNED_COMMIT}")
    return runtime_integrity


def load_flags(model_dir: Path) -> SimpleNamespace:
    flags_path = model_dir / "flags.json"
    data = json.loads(flags_path.read_text(encoding="utf-8"))
    required = {
        "model_name": "kws_transformer",
        "num_layers": LAYER_COUNT,
        "d_model": X_SHAPE[1],
        "mlp_dim": W_SHAPE[1],
        "heads": 1,
        "preprocess": "raw",
        "attention_type": "time",
        "spectrogram_length": 98,
        "desired_samples": 16000,
    }
    for key, expected in required.items():
        if data.get(key) != expected:
            raise ValueError(f"Unexpected flags.json {key}: {data.get(key)!r}; expected {expected!r}")
    # The saved training flags have training=true and batch_size=512.  Inference
    # must use batch 1, no dropout, no audio augmentation, no distillation
    # token, and no softmax. The pinned training flags enable SpecAugment.
    data.update(
        batch_size=1,
        training=False,
        use_spec_augment=0,
        use_spec_cutout=0,
        sp_time_shift_ms=0.0,
        sp_resample=0.0,
        prenorm=False,
        approximate_gelu=False,
        distill_teacher_json="",
        return_softmax=0,
    )
    return SimpleNamespace(**data)


def load_audio(args: argparse.Namespace) -> np.ndarray:
    if args.raw_npy:
        samples = np.load(args.raw_npy, allow_pickle=False)
        if samples.shape != (16000,) or samples.dtype != np.float32:
            raise ValueError("--raw-npy must contain one float32 waveform of shape (16000,)")
    else:
        with wave.open(str(args.wav), "rb") as wav:
            properties = (wav.getnchannels(), wav.getframerate(), wav.getsampwidth())
            if properties != (1, 16000, 2):
                raise ValueError(
                    "--wav must be mono 16 kHz PCM16 "
                    f"(got channels, Hz, bytes/sample = {properties})"
                )
            # The pinned input_data.py decodes with desired_samples=16000:
            # shorter WAVs are zero-padded and longer WAVs are truncated.
            samples = np.frombuffer(wav.readframes(16000), dtype="<i2").astype(np.float32) / 32768.0
            if samples.size < 16000:
                samples = np.pad(samples, (0, 16000 - samples.size))
    if not np.isfinite(samples).all():
        raise ValueError("Input waveform contains NaN or infinity")
    return samples[None, :]


def build_probe(tf, model):
    """Reuse loaded official layers; expose X and pre-GELU Y at all 12 blocks.

    Operation order is copied from TransformerBlock.call and
    KWSTransformer.call at the pinned commit. The final-classifier equality
    check in main() makes a discrepancy with the official path fatal.
    """
    features = model.get_layer("speech_features").output
    transformer = model.get_layer("kws_transformer")
    if len(transformer.enc_layers) != LAYER_COUNT:
        raise ValueError("The loaded transformer does not have 12 encoder layers")
    if transformer.distill_emb is not None or any(block.prenorm for block in transformer.enc_layers):
        raise ValueError("Expected the non-distilled post-norm KWT-1 architecture")

    batch_size = tf.shape(features)[0]
    x = transformer.patch_proj(features)
    cls = tf.broadcast_to(transformer.class_emb, [batch_size, 1, transformer.d_model])
    x = tf.concat([cls, x], axis=1) + transformer.pos_emb
    x_values = []
    y_values = []
    dense_layers = []

    for block in transformer.enc_layers:
        # Exact pinned post-norm path: attention -> residual -> LayerNorm ->
        # FFN Dense -> GELU -> Dense -> residual -> LayerNorm.
        attention, _ = block.att(x)
        attention = block.dropout1(attention, training=False)
        ffn_input = block.layernorm1(x + attention)
        first_dense, activation, second_dense = block.ffn.layers
        linear_output = first_dense(ffn_input)
        ffn_output = second_dense(activation(linear_output))
        ffn_output = block.dropout2(ffn_output, training=False)
        x = block.layernorm2(ffn_input + ffn_output)
        x_values.append(ffn_input)
        y_values.append(linear_output)
        dense_layers.append(first_dense)

    # The official kws_transformer.model appends one Sequential classifier.
    head = model.layers[-1]
    logits = head(x[:, 0])
    probe = tf.keras.Model(inputs=model.inputs, outputs=x_values + y_values + [logits])
    return probe, dense_layers


def extract(args: argparse.Namespace) -> None:
    provenance = validate_provenance(args.split, args.source_id)
    repo = args.repo.resolve()
    runtime_integrity = check_checkout(repo)
    model_dir = repo / "models_data_v2_12_labels/kwt1"
    checkpoint = model_dir / "best_weights"
    checkpoint_files = [checkpoint.with_suffix(".index"), *sorted(model_dir.glob("best_weights.data-*"))]
    if len(checkpoint_files) < 2 or any(not path.is_file() for path in checkpoint_files):
        raise ValueError(f"Missing KWT-1 best_weights checkpoint in {model_dir}")
    flags = load_flags(model_dir)
    raw = load_audio(args)

    # Official source is imported only after the checkout and files are checked.
    sys.path.insert(0, str(repo))
    try:
        import tensorflow as tf  # type: ignore
    except ImportError as exc:
        raise RuntimeError("TensorFlow is missing; use the pinned upstream Python environment") from exc
    import tensorflow_addons as tfa  # type: ignore
    tf.compat.v1.disable_eager_execution()
    tf.compat.v1.keras.backend.set_learning_phase(0)
    try:
        from kws_streaming.models import kws_transformer  # type: ignore
    except ImportError as exc:
        raise RuntimeError("Cannot import the pinned KWT source; install its requirements") from exc

    session = tf.compat.v1.Session()
    tf.compat.v1.keras.backend.set_session(session)
    try:
        official = kws_transformer.model(flags)
        restore = official.load_weights(str(checkpoint))
        # A classifier/probe agreement alone would also pass if both paths
        # accidentally used randomly initialized weights.
        restore.assert_existing_objects_matched()
        restore.expect_partial()
        probe, dense_layers = build_probe(tf, official)

        # Both models use the same SpeechFeatures node and weights.  Check that
        # the reconstructed path really gives the official classification.
        official_prediction = official.predict(raw)
        if isinstance(official_prediction, list):
            if len(official_prediction) != 1:
                raise ValueError("Unexpected multiple official classifier outputs")
            official_prediction = official_prediction[0]
        exposed = probe.predict(raw)
        if len(exposed) != 2 * LAYER_COUNT + 1:
            raise ValueError("Probe returned the wrong number of tensors")
        repeated = probe.predict(raw)
        if len(repeated) != len(exposed):
            raise ValueError("Repeated probe returned a different number of tensors")
        for tensor_index, (first, second) in enumerate(zip(exposed, repeated)):
            np.testing.assert_allclose(
                first, second, rtol=1e-6, atol=1e-6,
                err_msg=f"Probe tensor {tensor_index} changes between inference runs",
            )
        probe_logits = np.asarray(exposed[-1])
        np.testing.assert_allclose(
            probe_logits,
            np.asarray(official_prediction),
            rtol=1e-5,
            atol=1e-5,
            err_msg="Probe differs from the official classifier; do not use exported tensors",
        )

        if args.output.exists() and any(args.output.iterdir()):
            raise ValueError(f"Output directory is not empty: {args.output}")
        layers = []
        pending_files = []
        for layer_index, dense in enumerate(dense_layers):
            x = np.asarray(exposed[layer_index][0], dtype=np.float32)
            y = np.asarray(exposed[LAYER_COUNT + layer_index][0], dtype=np.float32)
            w, b = (np.asarray(tensor, dtype=np.float32) for tensor in dense.get_weights())
            # A Keras restore can warn about object references while still
            # populating the right variables. Compare the exported values
            # directly to the named checkpoint tensors to prove which weights
            # were actually used, instead of relying on self-consistency alone.
            checkpoint_base = (
                f"layer_with_weights-0/enc_layers/{layer_index}/ffn/layer_with_weights-0"
            )
            checkpoint_w = tf.train.load_variable(
                str(checkpoint), checkpoint_base + "/kernel/.ATTRIBUTES/VARIABLE_VALUE"
            )
            checkpoint_b = tf.train.load_variable(
                str(checkpoint), checkpoint_base + "/bias/.ATTRIBUTES/VARIABLE_VALUE"
            )
            np.testing.assert_array_equal(w, checkpoint_w,
                                          err_msg=f"Layer {layer_index}: FFN1 kernel was not restored")
            np.testing.assert_array_equal(b, checkpoint_b,
                                          err_msg=f"Layer {layer_index}: FFN1 bias was not restored")
            shapes = ((x.shape, X_SHAPE), (w.shape, W_SHAPE), (b.shape, B_SHAPE), (y.shape, Y_SHAPE))
            if any(actual != expected for actual, expected in shapes):
                raise ValueError(f"Layer {layer_index}: unexpected x/w/b/y shape: {shapes}")
            if not all(np.isfinite(array).all() for array in (x, w, b, y)):
                raise ValueError(f"Layer {layer_index}: nonfinite reference value")

            # NumPy may use a different matmul reduction order from TensorFlow;
            # this checks the intended indexing, not bitwise FP equivalence.
            recomputed = x @ w + b
            max_abs = float(np.max(np.abs(recomputed - y)))
            np.testing.assert_allclose(
                recomputed, y, rtol=1e-4, atol=1e-4,
                err_msg=f"Layer {layer_index}: X @ W + b differs from official Dense",
            )
            filename = f"layer_{layer_index:02d}.npz"
            pending_files.append((filename, x, w, b, y))
            layers.append({"layer": layer_index, "file": filename, "max_abs_numpy_vs_dense": max_abs})

        source = args.raw_npy if args.raw_npy else args.wav
        manifest = {
            "provenance": provenance,
            "upstream_commit": PINNED_COMMIT,
            "runtime_source_integrity": runtime_integrity,
            "model": "models_data_v2_12_labels/kwt1/best_weights",
            "flags_sha256": sha256(model_dir / "flags.json"),
            "checkpoint_sha256": {path.name: sha256(path) for path in checkpoint_files},
            "input_file": str(source.resolve()),
            "input_sha256": sha256(source),
            "tensorflow_version": tf.__version__,
            "tensorflow_addons_version": tfa.__version__,
            "numpy_version": np.__version__,
            "checkpoint_ffn1_tensors_exactly_verified": 2 * LAYER_COUNT,
            "inference_overrides": {
                "batch_size": 1,
                "training": False,
                "use_spec_augment": 0,
                "use_spec_cutout": 0,
                "sp_time_shift_ms": 0.0,
                "sp_resample": 0.0,
                "prenorm": False,
                "approximate_gelu": False,
                "distill_teacher_json": "",
                "return_softmax": 0,
            },
            "classifier_max_abs_error": float(np.max(np.abs(probe_logits - official_prediction))),
            "layers": layers,
            "array_contract": {"x": X_SHAPE, "w": W_SHAPE, "b": B_SHAPE, "y_float": Y_SHAPE},
        }
        args.output.mkdir(parents=True, exist_ok=True)
        for filename, x, w, b, y in pending_files:
            np.savez_compressed(args.output / filename, x=x, w=w, b=b, y_float=y)
        for layer in layers:
            layer["sha256"] = sha256(args.output / layer["file"])
        (args.output / "manifest.json").write_text(
            json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
        )
        print(f"Exported {len(layers)} layer cases to {args.output}")
    finally:
        session.close()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, required=True, help="KWT Git checkout or archive at pinned commit")
    parser.add_argument("--output", type=Path, required=True, help="Directory for 12 NPZ files")
    parser.add_argument("--split", choices=PROVENANCE_SPLITS, required=True,
                        help="declared dataset split; use unverified for real audio with unconfirmed membership, synthetic-smoke for artificial audio")
    parser.add_argument("--source-id", required=True,
                        help="stable sample identifier in the declared data source, e.g. relative WAV path")
    source = parser.add_mutually_exclusive_group(required=True)
    source.add_argument("--raw-npy", type=Path, help="float32 .npy, one official 16000-sample raw input")
    source.add_argument("--wav", type=Path, help="one-second mono 16 kHz PCM16 WAV smoke test")
    args = parser.parse_args()
    try:
        extract(args)
    except (AssertionError, OSError, RuntimeError, ValueError) as exc:
        parser.exit(1, f"Error: {exc}\n")


if __name__ == "__main__":
    main()
