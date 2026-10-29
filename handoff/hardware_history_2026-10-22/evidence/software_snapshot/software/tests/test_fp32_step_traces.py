"""Reproducibility and independent anchors for candidate FP32 step traces."""

from __future__ import annotations

import hashlib
import json
import tempfile
import unittest
from pathlib import Path

from software.examples.fp32_step_traces import (
    HASH_NAME, TRACE_NAME, generate, render,
)


IMAGE_DIR = Path(__file__).resolve().parents[1] / "examples" / "fp32_hand_image"


class FP32StepTraceTest(unittest.TestCase):
    def test_existing_mem_and_bin_images_still_match_manifest(self) -> None:
        manifest = json.loads((IMAGE_DIR / "manifest.json").read_text("utf-8"))
        for name, entry in manifest["tensors"].items():
            with self.subTest(tensor=name):
                binary = (IMAGE_DIR / f"{name}.bin").read_bytes()
                words = (IMAGE_DIR / f"{name}.mem").read_text("ascii").splitlines()
                self.assertEqual(hashlib.sha256(binary).hexdigest(), entry["sha256_bin"])
                self.assertEqual(words, entry["words_hex"])

    def test_checked_in_trace_is_reproducible_and_hashed(self) -> None:
        payload, checksum = render()
        self.assertEqual((IMAGE_DIR / TRACE_NAME).read_bytes(), payload)
        self.assertEqual((IMAGE_DIR / HASH_NAME).read_bytes(), checksum)
        self.assertEqual(checksum.decode("ascii"),
                         f"{hashlib.sha256(payload).hexdigest()}  {TRACE_NAME}\n")
        generate(IMAGE_DIR, check=True)

        with tempfile.TemporaryDirectory(dir=Path(__file__).resolve().parent) as temp:
            generated = Path(temp)
            generate(generated)
            self.assertEqual({p.name for p in generated.iterdir()},
                             {TRACE_NAME, HASH_NAME})
            self.assertEqual((generated / TRACE_NAME).read_bytes(), payload)
            self.assertEqual((generated / HASH_NAME).read_bytes(), checksum)
            (generated / TRACE_NAME).write_bytes(payload + b"\n")
            with self.assertRaisesRegex(ValueError, "differ"):
                generate(generated, check=True)

    def test_all_cells_and_boundary_anchors(self) -> None:
        document = json.loads((IMAGE_DIR / TRACE_NAME).read_text("utf-8"))
        self.assertIn("CANDIDATE", document["status"])
        cases = document["cases"]
        hand = cases["hand_2x2"]
        self.assertEqual((hand["x_shape"], hand["w_shape"], hand["y_shape"]),
                         ([2, 2], [2, 2], [2, 2]))
        cells = {(cell["row"], cell["column"]): cell for cell in hand["cells"]}
        self.assertEqual(set(cells), {(0, 0), (0, 1), (1, 0), (1, 1)})
        self.assertEqual({key: value["result_bits"] for key, value in cells.items()}, {
            (0, 0): "0xbf400000", (0, 1): "0xc0200000",
            (1, 0): "0x40b80000", (1, 1): "0x3f000000",
        })
        self.assertEqual(cells[0, 0]["steps"], [
            {"k": 0, "x_bits": "0x3f800000", "w_bits": "0x40000000",
             "acc_before_bits": "0x00000000", "product_bits": "0x40000000",
             "acc_after_bits": "0x40000000"},
            {"k": 1, "x_bits": "0xc0000000", "w_bits": "0x3fc00000",
             "acc_before_bits": "0x40000000", "product_bits": "0xc0400000",
             "acc_after_bits": "0xbf800000"},
        ])

        rounding = cases["rounding_nonfused"]["cells"][0]
        self.assertEqual(rounding["steps"][1]["acc_before_bits"], "0xbf800000")
        self.assertEqual(rounding["steps"][1]["product_bits"], "0x3f800000")
        self.assertEqual(rounding["result_bits"], "0x00000000")

        boundary = cases["k32_boundary"]["cells"][0]
        self.assertEqual(len(boundary["steps"]), 64)
        self.assertEqual(boundary["steps"][31]["acc_after_bits"], "0x40000000")
        self.assertEqual(boundary["steps"][32]["acc_before_bits"], "0x40000000")
        self.assertEqual(boundary["steps"][32]["product_bits"], "0xc0400000")
        self.assertEqual(boundary["steps"][32]["acc_after_bits"], "0xbf800000")
        self.assertEqual(boundary["acc_before_bias_bits"], "0xbf800000")
        self.assertEqual(boundary["bias_bits"], "0x3e800000")
        self.assertEqual(boundary["result_bits"], "0xbf400000")

        for case in cases.values():
            for cell in case["cells"]:
                steps = cell["steps"]
                self.assertEqual([step["k"] for step in steps], list(range(len(steps))))
                self.assertEqual(steps[0]["acc_before_bits"], cell["initial_acc_bits"])
                for before, after in zip(steps, steps[1:]):
                    self.assertEqual(before["acc_after_bits"], after["acc_before_bits"])
                self.assertEqual(steps[-1]["acc_after_bits"],
                                 cell["acc_before_bias_bits"])


if __name__ == "__main__":
    unittest.main()
