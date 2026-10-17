"""Offline tests for the complete pinned KWT-1 runtime-file guard."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from software import kwt_source_integrity as guard


ROOT = Path(__file__).resolve().parents[2]


class KwtRuntimeIntegrityTests(unittest.TestCase):
    def test_manifest_is_fixed_and_matches_pinned_tree(self) -> None:
        manifest = guard.load_manifest()
        self.assertEqual(manifest["upstream_commit"], guard.PINNED_COMMIT)
        self.assertEqual(len(manifest["files"]), 30)
        tree_path = ROOT / "work" / "kwt_tree.json"
        if not tree_path.is_file():
            self.skipTest("the acquisition-time Git tree is not installed")
        tree = json.loads(tree_path.read_text(encoding="utf-8"))
        self.assertEqual(tree["sha"], guard.PINNED_COMMIT)
        self.assertFalse(tree["truncated"])
        entries = {item["path"]: item for item in tree["tree"] if item["type"] == "blob"}
        for relative, info in manifest["files"].items():
            with self.subTest(file=relative):
                self.assertEqual(info["git_blob_sha1"], entries[relative]["sha"])
                self.assertEqual(info["size"], entries[relative]["size"])

    def test_manifest_edit_cannot_redefine_expected_blobs(self) -> None:
        with patch.object(guard, "MANIFEST_SHA256", "0" * 64):
            with self.assertRaisesRegex(ValueError, "manifest SHA-256 mismatch"):
                guard.load_manifest()

    def test_blob_file_rejects_same_size_change_and_missing_file(self) -> None:
        original = b"pin this dependency\n"
        expected = hashlib.sha1(b"blob " + str(len(original)).encode() + b"\0" + original).hexdigest()
        with tempfile.TemporaryDirectory(dir=ROOT / "work") as temporary:
            path = Path(temporary) / "speech_features.py"
            path.write_bytes(original)
            guard.verify_blob_file(path, expected, len(original))
            path.write_bytes(b"xin this dependency\n")
            with self.assertRaisesRegex(ValueError, "Wrong Git blob"):
                guard.verify_blob_file(path, expected, len(original))
            with self.assertRaisesRegex(ValueError, "Wrong size"):
                guard.verify_blob_file(path, expected, len(original) + 1)
            path.unlink()
            with self.assertRaisesRegex(ValueError, "Missing pinned"):
                guard.verify_blob_file(path, expected, len(original))

    def test_sparse_checkout_if_available(self) -> None:
        repo = ROOT / "third_party" / "kwt_pinned_sparse"
        if not repo.is_dir():
            self.skipTest("pinned sparse checkout is not installed")
        record = guard.verify_runtime_blobs(repo)
        self.assertEqual(record["verified_runtime_files"], 30)
        self.assertEqual(record["runtime_manifest_sha256"], guard.MANIFEST_SHA256)


if __name__ == "__main__":
    unittest.main()
