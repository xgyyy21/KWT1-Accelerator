"""Fetch selected pinned public KWT Git blobs through the GitHub API.

This is a fallback when Git transport is unavailable.  It verifies every
blob against the pinned commit's recursive tree, including the checkpoint.
The output has no .git directory, which kwt_reference.py explicitly supports.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
from pathlib import Path
import subprocess
import time


COMMIT = "237e4097afd4f6851e0b82f0a8d65c2dfe8eae30"
API = "https://api.github.com/repos/ARM-software/keyword-transformer/git/blobs/"
# Tested with work/run_sparse_reference.py on Python 3.8 / TF 2.4.0. This is
# the *runtime subset*, not a substitute for the entire upstream repository.
KWT1_RUNTIME_PATHS = (
    "kws_streaming/__init__.py",
    "kws_streaming/models/__init__.py",
    "kws_streaming/models/utils.py",
    "kws_streaming/models/transformer_utils.py",
    "kws_streaming/models/model_params.py",
    "kws_streaming/models/model_flags.py",
    "kws_streaming/models/models.py",
    "kws_streaming/models/kws_transformer.py",
    "kws_streaming/data/__init__.py",
    "kws_streaming/data/input_data.py",
    "kws_streaming/layers/__init__.py",
    "kws_streaming/layers/compat.py",
    "kws_streaming/layers/data_frame.py",
    "kws_streaming/layers/dct.py",
    "kws_streaming/layers/magnitude_rdft.py",
    "kws_streaming/layers/magnitude_rdft_mel.py",
    "kws_streaming/layers/mel_table.py",
    "kws_streaming/layers/modes.py",
    "kws_streaming/layers/normalizer.py",
    "kws_streaming/layers/preemphasis.py",
    "kws_streaming/layers/random_shift.py",
    "kws_streaming/layers/random_stretch_squeeze.py",
    "kws_streaming/layers/spectrogram_augment.py",
    "kws_streaming/layers/spectrogram_cutout.py",
    "kws_streaming/layers/speech_features.py",
    "kws_streaming/layers/temporal_padding.py",
    "kws_streaming/layers/windowing.py",
    "models_data_v2_12_labels/kwt1/flags.json",
    "models_data_v2_12_labels/kwt1/best_weights.index",
    "models_data_v2_12_labels/kwt1/best_weights.data-00000-of-00001",
)


def git_sha(data: bytes) -> str:
    return hashlib.sha1(b"blob " + str(len(data)).encode() + b"\0" + data).hexdigest()


def fetch_blob(sha: str) -> bytes:
    for attempt in range(4):
        try:
            result = subprocess.run(
                ["curl", "-fsSL", "--connect-timeout", "15", "--max-time", "900", API + sha],
                check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            )
            payload = json.loads(result.stdout)
            if payload.get("sha") != sha or payload.get("encoding") != "base64":
                raise ValueError(f"Unexpected GitHub API blob for {sha}")
            data = base64.b64decode(payload["content"], validate=False)
            if git_sha(data) != sha:
                raise ValueError(f"Blob hash mismatch for {sha}")
            return data
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired) as exc:
            if attempt == 3:
                raise
            time.sleep(2 ** attempt)
    raise AssertionError("unreachable")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="*", help="additional commit-relative file paths")
    parser.add_argument("--preset-kwt1", action="store_true",
                        help="fetch the tested KWT-1 runtime source, flags and best_weights")
    parser.add_argument("--tree", type=Path, default=Path("work/kwt_tree.json"))
    parser.add_argument("--output", type=Path, default=Path("third_party/kwt_pinned_sparse"))
    args = parser.parse_args()
    selected_paths = sorted(set(args.paths) | (set(KWT1_RUNTIME_PATHS) if args.preset_kwt1 else set()))
    if not selected_paths:
        parser.error("provide paths or --preset-kwt1")
    tree = json.loads(args.tree.read_text(encoding="utf-8"))
    if tree.get("sha") != COMMIT or tree.get("truncated"):
        raise ValueError("Recursive tree is not the complete pinned commit")
    entries = {row["path"]: row for row in tree["tree"] if row["type"] == "blob"}
    for path in selected_paths:
        if path not in entries:
            raise ValueError(f"No blob at pinned path: {path}")
        entry = entries[path]
        dest = args.output / path
        if dest.is_file():
            existing = dest.read_bytes()
            if git_sha(existing) == entry["sha"]:
                print("Already verified:", path)
                continue
        data = fetch_blob(entry["sha"])
        if len(data) != entry["size"]:
            raise ValueError(f"Unexpected size for {path}: {len(data)} vs {entry['size']}")
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(data)
        print("Fetched and verified:", path, len(data), "bytes", flush=True)


if __name__ == "__main__":
    main()
