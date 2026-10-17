"""Measure a draft FP32 reduction-order gap on a local, unverified sample.

This is an arithmetic comparison to y_float, not speech recognition accuracy
and not an official validation-set metric. It does not import original KWT code.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def measure(root: Path) -> dict:
    layers = []
    for i in range(12):
        nn = f"{i:02d}"
        npz = root / f"layer_{nn}.npz"
        packed = root / f"fp32_layer{nn}"
        manifest = json.loads((packed / "manifest.json").read_text(encoding="utf-8"))
        if (manifest["input_sha256"] != sha256(npz)
                or manifest["split_claim"] != "unverified"
                or manifest["split_verified_by_this_tool"] is not False):
            raise ValueError(f"Layer {nn} source provenance changed")
        with np.load(npz, allow_pickle=False) as data:
            reference = data["y_float"]
        if reference.dtype != np.float32 or reference.shape != (99, 256):
            raise ValueError(f"Layer {nn} model output has unexpected type or shape")
        expected_file = packed / "expected.bin"
        expected_bytes = expected_file.read_bytes()
        if (len(expected_bytes) != 99 * 256 * 4
                or sha256(expected_file) != manifest["tensors"]["expected"]["sha256_bin"]):
            raise ValueError(f"Layer {nn} candidate output hash or length changed")
        expected = np.frombuffer(expected_bytes, dtype="<f4").reshape(99, 256)
        if not np.isfinite(reference).all() or not np.isfinite(expected).all():
            raise ValueError(f"Layer {nn} has a nonfinite value")
        difference = expected.astype(np.float64) - reference.astype(np.float64)
        rms_error = float(np.sqrt(np.mean(difference * difference)))
        reference64 = reference.astype(np.float64)
        rms_reference = float(np.sqrt(np.mean(reference64 * reference64)))
        layers.append({
            "layer": i,
            "elements": int(reference.size),
            "equal_32_bit_patterns": int(np.count_nonzero(
                expected.view("<u4") == reference.view("<u4"))),
            "max_absolute_difference": float(np.max(np.abs(difference))),
            "rmse": rms_error,
            "nrmse": rms_error / max(rms_reference, 1e-8),
            "npz_sha256": manifest["input_sha256"],
            "expected_sha256": manifest["tensors"]["expected"]["sha256_bin"],
        })
    return {
        "status": "local_single_unverified_audio_arithmetic_comparison",
        "hardware_contract_frozen": False,
        "valid_precision_claim": False,
        "layer_count": len(layers),
        "max_layer_nrmse": max(row["nrmse"] for row in layers),
        "layers": layers,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--report", required=True, type=Path)
    args = parser.parse_args()
    report = measure(args.root)
    if args.report.exists():
        raise FileExistsError(f"refusing to overwrite existing report: {args.report}")
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n",
                           encoding="utf-8")
    print(json.dumps({"report": str(args.report),
                      "layer_count": report["layer_count"],
                      "max_layer_nrmse": report["max_layer_nrmse"]}, ensure_ascii=False))


if __name__ == "__main__":
    main()
