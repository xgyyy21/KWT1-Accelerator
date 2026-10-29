"""Evaluate FFN1 numeric error across samples, grouped by the 12 encoder layers.

Input files are NPZ archives named ``layer_00.npz`` ... ``layer_11.npz``.
They may live in separate per-sample directories. Each file contains the
official-model ``x``, ``w``, ``b``, and ``y_float`` arrays. This script checks
the independent floating calculation, then runs the configurable *prototype*
numeric model. A report from local samples is not the hidden contest result.
"""

from __future__ import annotations

import argparse
from collections import defaultdict
from dataclasses import asdict
import json
from pathlib import Path
import re
import sys

import numpy as np

if __package__:
    from .ffn1_numeric import FixedPointSpec, run_ffn1_real
    from .precision.study import file_hash, sample_provenance
else:  # direct script invocation from the project directory
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
    from software.ffn1_numeric import FixedPointSpec, run_ffn1_real
    from software.precision.study import file_hash, sample_provenance


LAYER_RE = re.compile(r"layer_(\d{2})\.npz$")
SPEC_FIELDS = tuple(asdict(FixedPointSpec()).keys())
EXPECTED_SHAPES = {"x": (99, 64), "w": (64, 256), "b": (256,), "y_float": (99, 256)}


def _load_spec(path: Path | None) -> FixedPointSpec:
    if path is None:
        spec = FixedPointSpec()
    else:
        raw = json.loads(path.read_text(encoding="utf-8"))
        if set(raw) != set(SPEC_FIELDS):
            raise ValueError(f"spec JSON must contain exactly {SPEC_FIELDS}")
        spec = FixedPointSpec(**raw)
    spec.validate()
    return spec


def _read_sample(path: Path) -> dict[str, np.ndarray]:
    with np.load(path, allow_pickle=False) as archive:
        missing = set(EXPECTED_SHAPES) - set(archive.files)
        if missing:
            raise ValueError(f"{path}: missing {sorted(missing)}")
        values = {name: np.asarray(archive[name], dtype=np.float64) for name in EXPECTED_SHAPES}
    for name, shape in EXPECTED_SHAPES.items():
        if values[name].shape != shape:
            raise ValueError(f"{path}: {name} shape {values[name].shape}, expected {shape}")
        if not np.all(np.isfinite(values[name])):
            raise ValueError(f"{path}: {name} contains NaN or infinity")
    return values


def _nrmse_from_sums(error_sq: float, reference_sq: float, count: int) -> float:
    return float(np.sqrt(error_sq / count) / max(np.sqrt(reference_sq / count), 1e-8))


def evaluate_files(files: list[Path], spec: FixedPointSpec) -> dict[str, object]:
    """Aggregate squared errors by layer after validating sample completeness."""
    if not files:
        raise ValueError("no layer_XX.npz files supplied")
    spec.validate()
    sums: dict[int, dict[str, float | int]] = defaultdict(
        lambda: {"count": 0, "samples": 0, "reference_sq": 0.0,
                 "float_error_sq": 0.0, "numeric_error_sq": 0.0,
                 "float_max_abs": 0.0}
    )
    sample_layers: dict[Path, set[int]] = defaultdict(set)
    sample_hashes: dict[Path, dict[int, str]] = defaultdict(dict)
    for path in sorted(files):
        match = LAYER_RE.fullmatch(path.name)
        if not match or int(match.group(1)) not in range(12):
            raise ValueError(f"expected layer_00.npz ... layer_11.npz, got {path}")
        layer = int(match.group(1))
        directory = path.parent.resolve()
        sample_layers[directory].add(layer)
        sample_hashes[directory][layer] = file_hash(path)
        arrays = _read_sample(path)
        ref = arrays["y_float"]
        independent_float = arrays["x"] @ arrays["w"] + arrays["b"]
        if not np.allclose(independent_float, ref, rtol=1e-4, atol=1e-4):
            max_abs = float(np.max(np.abs(independent_float - ref)))
            raise ValueError(
                f"{path}: y_float disagrees with independent X @ W + b "
                f"(max absolute difference {max_abs:.6g}; rtol=1e-4, atol=1e-4)"
            )
        numeric = run_ffn1_real(arrays["x"], arrays["w"], arrays["b"], spec).out_real
        row = sums[layer]
        row["count"] += int(ref.size)
        row["samples"] += 1
        row["reference_sq"] += float(np.sum(np.square(ref)))
        row["float_error_sq"] += float(np.sum(np.square(independent_float - ref)))
        row["numeric_error_sq"] += float(np.sum(np.square(numeric - ref)))
        row["float_max_abs"] = max(row["float_max_abs"], float(np.max(np.abs(independent_float - ref))))

    layers: dict[str, dict[str, float | int]] = {}
    for layer, row in sorted(sums.items()):
        count = int(row["count"])
        reference_sq = float(row["reference_sq"])
        layers[str(layer)] = {
            "samples": int(row["samples"]),
            "values": count,
            "independent_float_nrmse": _nrmse_from_sums(float(row["float_error_sq"]), reference_sq, count),
            "independent_float_max_abs": float(row["float_max_abs"]),
            "numeric_nrmse": _nrmse_from_sums(float(row["numeric_error_sq"]), reference_sq, count),
        }
    max_numeric = max(float(row["numeric_nrmse"]) for row in layers.values())
    required_layers = set(range(12))
    incomplete_groups = [
        {
            "directory": str(directory),
            "present_layers": sorted(present),
            "missing_layers": sorted(required_layers - present),
        }
        for directory, present in sorted(sample_layers.items())
        if present != required_layers
    ]
    all_layers_present = bool(sample_layers) and not incomplete_groups
    provenance = [
        sample_provenance(directory, directory.parent, sample_hashes[directory])
        for directory in sorted(sample_layers)
    ]
    seen_ids: set[str] = set()
    for item in provenance:
        source_id = item["source_id"]
        if item["split"] == "validation" and isinstance(source_id, str):
            if source_id in seen_ids:
                item["eligible_for_local_validation_screen"] = False
                item["classification"] = "declared_validation_unverified"
                item["reasons"].append("duplicate source ID in this report")
            seen_ids.add(source_id)
    provenance_eligible = bool(provenance) and all(
        bool(item["eligible_for_local_validation_screen"]) for item in provenance
    )
    return {
        "status": "prototype numeric model; local samples only",
        "metric_definition": "sqrt(sum((numeric-reference)^2)/N) / max(sqrt(sum(reference^2)/N), 1e-8); aggregate N within each layer",
        "format": spec.as_dict(),
        "files": [str(p.resolve()) for p in sorted(files)],
        "layers": layers,
        "sample_groups": len(sample_layers),
        "incomplete_groups": incomplete_groups,
        "all_12_layers_present": all_layers_present,
        "sample_provenance": provenance,
        "all_samples_eligible_for_local_validation_screen": provenance_eligible,
        "maximum_numeric_nrmse": max_numeric,
        "local_3_percent_screen": bool(all_layers_present and provenance_eligible and max_numeric <= 0.03),
        "local_3_percent_screen_status": (
            "incomplete_12_layer_coverage" if not all_layers_present else
            "ineligible_sample_provenance" if not provenance_eligible else
            "passed_local_validation_screen" if max_numeric <= 0.03 else
            "failed_numeric_threshold"
        ),
        "note": "The formula matches the 2026 undergraduate guide p. 10. A passing local screen needs complete declared validation exports with matching file hashes; the split is operator supplied and still must be checked against the original dataset. This is not the organizer's evaluation set; RTL bit-exact comparison is separate.",
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-root", required=True, type=Path,
                        help="recursively find layer_00.npz ... layer_11.npz")
    parser.add_argument("--spec", type=Path, help="JSON with all FixedPointSpec fields; default is illustrative")
    parser.add_argument("--report", required=True, type=Path)
    args = parser.parse_args()
    files = list(args.input_root.rglob("layer_??.npz"))
    report = evaluate_files(files, _load_spec(args.spec))
    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Wrote {args.report}")
    print(f"Layers present: {len(report['layers'])}/12; max local NRMSE: {report['maximum_numeric_nrmse']:.3%}")
    if not report["all_12_layers_present"]:
        print("Incomplete layer coverage: do not use this as a 12-layer accuracy claim.")
    if not report["all_samples_eligible_for_local_validation_screen"]:
        print("Sample provenance is not eligible; no local 3% validation pass is claimed.")


if __name__ == "__main__":
    main()
