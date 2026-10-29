"""Verify every pinned KWT-1 runtime file before extracting reference tensors.

The companion JSON was generated from the complete recursive Git tree at
237e4097afd4f6851e0b82f0a8d65c2dfe8eae30.  Its SHA-256 is fixed here so
an accidentally edited manifest cannot silently redefine the expected blobs.
No network, TensorFlow import, or file mutation is involved in verification.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath


PINNED_COMMIT = "237e4097afd4f6851e0b82f0a8d65c2dfe8eae30"
MANIFEST_FILE = Path(__file__).with_name("kwt_runtime_blobs.json")
MANIFEST_SHA256 = "fadc11b6dc3e06f69bcf8fb8642e3ba3413db46db89b2882786503ecada3b5b2"
EXPECTED_FILE_COUNT = 30


def load_manifest() -> dict:
    """Load the fixed manifest, rejecting accidental edits or bad metadata."""
    content = MANIFEST_FILE.read_bytes()
    actual = hashlib.sha256(content).hexdigest()
    if actual != MANIFEST_SHA256:
        raise ValueError(
            f"KWT runtime manifest SHA-256 mismatch: {actual}; expected {MANIFEST_SHA256}"
        )
    data = json.loads(content.decode("utf-8"))
    if (not isinstance(data, dict) or data.get("schema_version") != 1 or
            data.get("upstream_repository") != "ARM-software/keyword-transformer" or
            data.get("upstream_commit") != PINNED_COMMIT):
        raise ValueError("KWT runtime manifest has wrong upstream identity")
    entries = data.get("files")
    if not isinstance(entries, dict) or len(entries) != EXPECTED_FILE_COUNT:
        raise ValueError(f"KWT runtime manifest must contain {EXPECTED_FILE_COUNT} files")
    for relative, info in entries.items():
        if not isinstance(relative, str) or not relative or "\\" in relative:
            raise ValueError(f"Invalid KWT runtime path: {relative!r}")
        components = PurePosixPath(relative).parts
        if (PurePosixPath(relative).is_absolute() or not components or
                any(component in ("", ".", "..") for component in components)):
            raise ValueError(f"Invalid KWT runtime path: {relative!r}")
        if (not isinstance(info, dict) or set(info) != {"git_blob_sha1", "size"} or
                not isinstance(info["git_blob_sha1"], str) or
                len(info["git_blob_sha1"]) != 40 or
                any(c not in "0123456789abcdef" for c in info["git_blob_sha1"]) or
                type(info["size"]) is not int or info["size"] < 0):
            raise ValueError(f"Invalid KWT runtime manifest entry: {relative}")
    return data


def git_blob_sha1(path: Path, size: int) -> str:
    """Compute Git's SHA-1 object ID without loading the checkpoint into RAM."""
    digest = hashlib.sha1()
    digest.update(f"blob {size}\0".encode("ascii"))
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def verify_blob_file(path: Path, expected_sha1: str, expected_size: int) -> None:
    """Check one blob's existence, byte count, and fixed Git object ID."""
    if not path.is_file():
        raise ValueError(f"Missing pinned KWT runtime file: {path}")
    size = path.stat().st_size
    if size != expected_size:
        raise ValueError(
            f"Wrong size for pinned KWT runtime file {path}: {size}; expected {expected_size}"
        )
    actual = git_blob_sha1(path, size)
    if actual != expected_sha1:
        raise ValueError(
            f"Wrong Git blob for pinned KWT runtime file {path}: "
            f"{actual}; expected {expected_sha1}"
        )


def verify_runtime_blobs(repo: Path) -> dict[str, object]:
    """Verify all 30 source/config/checkpoint files in a checkout or sparse copy.

    Return a small record suitable for embedding in an extraction manifest.
    This checks file *contents*, so it also catches uncommitted modifications
    when a full Git checkout still reports the expected HEAD commit.
    """
    data = load_manifest()
    root = repo.resolve(strict=True)
    if not root.is_dir():
        raise ValueError(f"KWT source root is not a directory: {repo}")
    for relative, info in data["files"].items():
        path = root.joinpath(*PurePosixPath(relative).parts)
        # Prevent a local symlink from redirecting an apparently pinned path.
        try:
            path.resolve().relative_to(root)
        except ValueError:
            raise ValueError(f"KWT runtime file escapes source root: {path}")
        verify_blob_file(path, info["git_blob_sha1"], info["size"])
    return {
        "upstream_commit": PINNED_COMMIT,
        "verified_runtime_files": EXPECTED_FILE_COUNT,
        "runtime_manifest_sha256": MANIFEST_SHA256,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", type=Path, required=True,
                        help="fixed KWT source root, including models_data_v2_12_labels/kwt1")
    args = parser.parse_args()
    try:
        result = verify_runtime_blobs(args.repo)
    except (OSError, ValueError, UnicodeError, json.JSONDecodeError) as exc:
        parser.exit(1, f"Error: {exc}\n")
    print(json.dumps(result, sort_keys=True))


if __name__ == "__main__":
    main()
