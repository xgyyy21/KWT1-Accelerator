"""Verify two 12-layer INT16 handoff manifests and their image bytes."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_verified(root: Path) -> list[dict]:
    manifest = json.loads((root / "manifest.json").read_text(encoding="utf-8"))
    layers = manifest["layers"]
    if len(layers) != 12 or [row["layer"] for row in layers] != list(range(12)):
        raise ValueError(f"{root}: incomplete or unordered layers")
    for row in layers:
        folder = root / f"layer_{row['layer']:02d}"
        if set(row["files"]) != {"x", "w", "bias", "y_expected"}:
            raise ValueError(f"{folder}: unexpected image set")
        for key, expected_words in (("x", 6336), ("w", 16384),
                                    ("bias", 512), ("y_expected", 25344)):
            record = row["files"][key]
            path = folder / record["file"]
            words = path.read_text(encoding="ascii").splitlines()
            if len(words) != expected_words or record["word_count"] != expected_words:
                raise ValueError(f"{path}: wrong word count")
            if any(len(word) != 4 or any(c not in "0123456789abcdef" for c in word)
                   for word in words):
                raise ValueError(f"{path}: malformed hexadecimal word")
            if digest(path) != record["sha256"]:
                raise ValueError(f"{path}: SHA-256 mismatch")
    return layers


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("original", type=Path)
    parser.add_argument("regenerated", type=Path)
    args = parser.parse_args()
    original = load_verified(args.original)
    regenerated = load_verified(args.regenerated)
    for old, new in zip(original, regenerated):
        for key in ("x", "w", "bias", "y_expected"):
            if old["files"][key]["sha256"] != new["files"][key]["sha256"]:
                raise ValueError(f"layer {old['layer']:02d} {key}: changed image bytes")
    print("PASS 12 layers, 48 checked files, all regenerated image hashes unchanged")


if __name__ == "__main__":
    main()
