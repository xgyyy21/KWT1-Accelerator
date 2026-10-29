"""Compare proposed FFN1 number formats on exported KWT-1 layer cases.

Run from the repository root with ``python -m software.precision.study``.
Each sample directory must contain layer_00.npz ... layer_11.npz, with x, w,
b, and an independently exported y_float. This tool neither loads TensorFlow
nor claims a result on the organizer's hidden evaluation set.
"""

from __future__ import annotations

import argparse
from collections import defaultdict
from dataclasses import asdict
from hashlib import sha256
import json
from math import ceil
from pathlib import Path
import re

import numpy as np

from software.ffn1_numeric import (
    FixedPointSpec,
    _round_shift_away,
    quantize_real,
    signed_limits,
)
from software.kwt_reference import LAYER_COUNT, PINNED_COMMIT


LAYER_RE = re.compile(r"layer_(\d{2})\.npz$")
SHAPES = {"x": (99, 64), "w": (64, 256), "b": (256,), "y_float": (99, 256)}
SPEC_FIELDS = set(asdict(FixedPointSpec()))
CLIP_KEYS = ("x_quantized", "w_quantized", "b_quantized", "mac_adds", "bias_adds", "output")
OFFICIAL_MODEL = "models_data_v2_12_labels/kwt1/best_weights"


def _is_sha256(value: object) -> bool:
    return isinstance(value, str) and re.fullmatch(r"[0-9a-f]{64}", value) is not None


def sample_provenance(
    directory: Path, root: Path, layer_hashes: dict[int, str]
) -> dict[str, object]:
    """Audit an export declaration and its file hashes, without certifying a dataset."""
    manifest_path = directory / "manifest.json"
    result: dict[str, object] = {
        "sample_directory": str(directory.relative_to(root)),
        "split": "unknown",
        "source_id": None,
        "manifest_sha256": file_hash(manifest_path) if manifest_path.is_file() else None,
        "classification": "unknown",
        "eligible_for_local_validation_screen": False,
        "reasons": [],
    }
    reasons: list[str] = result["reasons"]  # type: ignore[assignment]
    if not manifest_path.is_file():
        reasons.append("missing export manifest")
        return result
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (UnicodeError, json.JSONDecodeError):
        reasons.append("unreadable export manifest")
        return result
    if not isinstance(manifest, dict):
        reasons.append("export manifest is not an object")
        return result

    provenance = manifest.get("provenance")
    if not isinstance(provenance, dict):
        reasons.append("missing provenance (legacy manifest is unknown)")
        return result
    split = provenance.get("split")
    source_id = provenance.get("source_id")
    if split in ("train", "validation", "test", "unverified", "synthetic-smoke"):
        result["split"] = split
    else:
        reasons.append("unrecognized declared split")
    if (isinstance(source_id, str) and source_id.strip() == source_id
        and source_id and len(source_id) <= 256
        and not any(char in source_id for char in "\r\n\0")):
        result["source_id"] = source_id
    else:
        reasons.append("missing or invalid source ID")
    if split == "synthetic-smoke":
        result["classification"] = "synthetic_smoke"
        reasons.append("synthetic input cannot establish validation precision")
        return result
    if split == "unverified":
        result["classification"] = "unverified_dataset_membership"
        reasons.append("real input has no verified membership in the original dataset split list")
        return result
    if split != "validation":
        result["classification"] = str(result["split"])
        reasons.append("only declared validation samples qualify for the local screen")
        return result

    result["classification"] = "declared_validation_unverified"
    if manifest.get("upstream_commit") != PINNED_COMMIT or manifest.get("model") != OFFICIAL_MODEL:
        reasons.append("pinned model identity missing or different")
    if not _is_sha256(manifest.get("input_sha256")):
        reasons.append("input SHA-256 missing or invalid")
    if not _is_sha256(manifest.get("flags_sha256")):
        reasons.append("model flags SHA-256 missing or invalid")
    checkpoints = manifest.get("checkpoint_sha256")
    if not isinstance(checkpoints, dict) or not all(
        _is_sha256(checkpoints.get(name))
        for name in ("best_weights.index", "best_weights.data-00000-of-00001")
    ):
        reasons.append("checkpoint SHA-256 values missing or invalid")
    if manifest.get("checkpoint_ffn1_tensors_exactly_verified") != 2 * LAYER_COUNT:
        reasons.append("checkpoint FFN1 tensor verification missing")
    layer_records = manifest.get("layers")
    if not isinstance(layer_records, list) or len(layer_records) != LAYER_COUNT:
        reasons.append("complete per-layer export records missing")
    else:
        valid_records = all(
            isinstance(record, dict) and type(record.get("layer")) is int
            for record in layer_records
        )
        by_layer = (
            {record["layer"]: record for record in layer_records}
            if valid_records else {}
        )
        if set(by_layer) != set(range(LAYER_COUNT)):
            reasons.append("per-layer export indices are incomplete or duplicated")
        else:
            for layer in range(LAYER_COUNT):
                record = by_layer[layer]
                if (record.get("file") != f"layer_{layer:02d}.npz"
                    or record.get("sha256") != layer_hashes.get(layer)):
                    reasons.append(f"layer {layer:02d} file identity or SHA-256 mismatch")
    if not reasons:
        result["classification"] = "declared_validation_integrity_checked"
        result["eligible_for_local_validation_screen"] = True
    return result


def file_hash(path: Path) -> str:
    digest = sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def load_candidates(path: Path) -> list[tuple[str, FixedPointSpec]]:
    """Read explicitly named candidate formats; never infer a final RTL format."""
    raw = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(raw, dict) or set(raw) != {"candidates"} or not isinstance(raw["candidates"], list):
        raise ValueError("candidate JSON must contain one 'candidates' list")
    if not raw["candidates"]:
        raise ValueError("candidate list is empty")
    result: list[tuple[str, FixedPointSpec]] = []
    names: set[str] = set()
    for item in raw["candidates"]:
        if not isinstance(item, dict) or set(item) != SPEC_FIELDS | {"name"}:
            raise ValueError(f"each candidate needs name and exactly {sorted(SPEC_FIELDS)}")
        name = item["name"]
        if not isinstance(name, str) or not name or name in names:
            raise ValueError("candidate names must be nonempty and unique")
        names.add(name)
        spec = FixedPointSpec(**{key: item[key] for key in SPEC_FIELDS})
        spec.validate()
        result.append((name, spec))
    return result


def load_case(path: Path) -> dict[str, np.ndarray]:
    """Require the official-model export's four arrays and FFN1 dimensions."""
    with np.load(path, allow_pickle=False) as archive:
        if not set(SHAPES) <= set(archive.files):
            raise ValueError(f"{path}: missing one of {sorted(SHAPES)}")
        data = {key: np.asarray(archive[key], dtype=np.float64) for key in SHAPES}
    for key, expected in SHAPES.items():
        if data[key].shape != expected:
            raise ValueError(f"{path}: {key} shape {data[key].shape}; expected {expected}")
        if not np.isfinite(data[key]).all():
            raise ValueError(f"{path}: {key} contains NaN or infinity")
    independent = data["x"] @ data["w"] + data["b"]
    if not np.isfinite(independent).all() or not np.allclose(
        independent, data["y_float"], rtol=1e-4, atol=1e-4
    ):
        raise ValueError(f"{path}: y_float does not agree with independent X @ W + b")
    return data


def _quantization_clips(values: np.ndarray, bits: int, frac: int) -> int:
    """Count operands whose rounded mathematical value exceeds the format."""
    lo, hi = signed_limits(bits)
    scaled = np.abs(values) * float(1 << frac)
    rounded = np.copysign(np.floor(scaled + 0.5), values)
    return int(np.count_nonzero((rounded < lo) | (rounded > hi)))


def fixed_point_with_counts(
    x: np.ndarray, w: np.ndarray, b: np.ndarray, spec: FixedPointSpec
) -> tuple[np.ndarray, dict[str, int]]:
    """Run the existing model's operation order while counting saturation.

    A MAC clip is counted *each time* an accumulator update is outside its
    signed range, even if the same output element clips again at a later k.
    """
    spec.validate()
    x_q = quantize_real(x, spec.x_bits, spec.x_frac)
    w_q = quantize_real(w, spec.w_bits, spec.w_frac)
    b_q = quantize_real(b, spec.bias_bits, spec.acc_frac)
    clips = {
        "x_quantized": _quantization_clips(x, spec.x_bits, spec.x_frac),
        "w_quantized": _quantization_clips(w, spec.w_bits, spec.w_frac),
        "b_quantized": _quantization_clips(b, spec.bias_bits, spec.acc_frac),
        "mac_adds": 0,
        "bias_adds": 0,
        "output": 0,
    }
    lo, hi = signed_limits(spec.acc_bits)
    acc = np.zeros((x.shape[0], w.shape[1]), dtype=np.int64)
    for k in range(x.shape[1]):
        raw = acc + x_q[:, k : k + 1] * w_q[k : k + 1, :]
        clips["mac_adds"] += int(np.count_nonzero((raw < lo) | (raw > hi)))
        acc = np.clip(raw, lo, hi)
    raw = acc + b_q[np.newaxis, :]
    clips["bias_adds"] = int(np.count_nonzero((raw < lo) | (raw > hi)))
    acc = np.clip(raw, lo, hi)
    shifted = _round_shift_away(acc, spec.acc_frac - spec.out_frac)
    out_lo, out_hi = signed_limits(spec.out_bits)
    clips["output"] = int(np.count_nonzero((shifted < out_lo) | (shifted > out_hi)))
    out_q = np.clip(shifted, out_lo, out_hi)
    return out_q.astype(np.float64) / (1 << spec.out_frac), clips


def storage_estimate(spec: FixedPointSpec) -> dict[str, object]:
    """Per-FFN1-task tensor sizes; excludes bus traffic and internal buffers."""
    counts = {"x": 99 * 64, "w": 64 * 256, "b": 256, "output": 99 * 256}
    widths = {"x": spec.x_bits, "w": spec.w_bits, "b": spec.bias_bits, "output": spec.out_bits}
    tensors = {
        key: {
            "elements": counts[key],
            "element_bits": widths[key],
            "ideal_packed_bytes": ceil(counts[key] * widths[key] / 8),
            "byte_aligned_element_bytes": counts[key] * ceil(widths[key] / 8),
        }
        for key in counts
    }
    return {
        "scope": "one 99x64 by 64x256 FFN1 invocation; no repeated loads, addresses, SRAM or DMA overhead",
        "tensors": tensors,
        "ideal_packed_total_bytes": sum(int(item["ideal_packed_bytes"]) for item in tensors.values()),
        "byte_aligned_element_total_bytes": sum(
            int(item["byte_aligned_element_bytes"]) for item in tensors.values()
        ),
        "existing_16_bit_word_packer_compatible": all(width % 16 == 0 for width in widths.values()),
    }


def _layer_nrmse(squared_error: float, squared_reference: float, count: int) -> float:
    return float(np.sqrt(squared_error / count) / max(np.sqrt(squared_reference / count), 1e-8))


def evaluate(
    input_root: Path, candidates: list[tuple[str, FixedPointSpec]]
) -> dict[str, object]:
    """Pool squared errors within each layer, then take the worst layer."""
    root = input_root.resolve()
    if not root.is_dir():
        raise ValueError(f"input root is not a directory: {root}")
    files = sorted(root.rglob("layer_??.npz"))
    if not files:
        raise ValueError(f"no layer_XX.npz files in {root}; real model data is not available")
    if not candidates:
        raise ValueError("at least one candidate is required")
    by_sample: dict[Path, set[int]] = defaultdict(set)
    sources: list[dict[str, str | int]] = []
    # Candidate accumulator: sample totals and output SSE per layer.
    totals: dict[str, dict[int, dict[str, object]]] = {
        name: defaultdict(lambda: {"samples": 0, "values": 0, "reference_sq": 0.0,
                                    "error_sq": 0.0, "clips": {key: 0 for key in CLIP_KEYS}})
        for name, _ in candidates
    }
    task_diagnostics: dict[str, list[dict[str, object]]] = {name: [] for name, _ in candidates}
    for path in files:
        match = LAYER_RE.fullmatch(path.name)
        if match is None or int(match.group(1)) >= LAYER_COUNT:
            raise ValueError(f"unexpected layer file {path}; expected layer_00 ... layer_11")
        layer = int(match.group(1))
        by_sample[path.parent.resolve()].add(layer)
        data = load_case(path)
        ref = data["y_float"]
        sources.append({"file": str(path.relative_to(root)), "layer": layer, "sha256": file_hash(path)})
        for name, spec in candidates:
            decoded, clips = fixed_point_with_counts(data["x"], data["w"], data["b"], spec)
            row = totals[name][layer]
            row["samples"] = int(row["samples"]) + 1
            row["values"] = int(row["values"]) + int(ref.size)
            row["reference_sq"] = float(row["reference_sq"]) + float(np.sum(np.square(ref)))
            row["error_sq"] = float(row["error_sq"]) + float(np.sum(np.square(decoded - ref)))
            task_nrmse = _layer_nrmse(
                float(np.sum(np.square(decoded - ref))),
                float(np.sum(np.square(ref))), int(ref.size),
            )
            task_diagnostics[name].append({
                "file": str(path.relative_to(root)), "layer": layer,
                "nrmse": task_nrmse,
            })
            existing_clips = row["clips"]
            assert isinstance(existing_clips, dict)
            for key in CLIP_KEYS:
                existing_clips[key] += clips[key]

    required = set(range(LAYER_COUNT))
    incomplete = [
        {"sample_directory": str(directory.relative_to(root)), "missing_layers": sorted(required - layers)}
        for directory, layers in sorted(by_sample.items()) if layers != required
    ]
    manifest_sources = [
        {"file": str((directory / "manifest.json").relative_to(root)),
         "sha256": file_hash(directory / "manifest.json")}
        for directory in sorted(by_sample) if (directory / "manifest.json").is_file()
    ]
    hashes_by_sample: dict[Path, dict[int, str]] = defaultdict(dict)
    for item in sources:
        path = root / str(item["file"])
        hashes_by_sample[path.parent.resolve()][int(item["layer"])] = str(item["sha256"])
    provenance = [
        sample_provenance(directory, root, hashes_by_sample[directory])
        for directory in sorted(by_sample)
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
    complete = not incomplete and bool(by_sample)
    reports = []
    for name, spec in candidates:
        layers: dict[str, dict[str, object]] = {}
        total_clips = {key: 0 for key in CLIP_KEYS}
        for layer, row in sorted(totals[name].items()):
            row_clips = row["clips"]
            assert isinstance(row_clips, dict)
            for key in CLIP_KEYS:
                total_clips[key] += int(row_clips[key])
            layers[f"{layer:02d}"] = {
                "samples": int(row["samples"]),
                "values": int(row["values"]),
                "nrmse": _layer_nrmse(float(row["error_sq"]), float(row["reference_sq"]), int(row["values"])),
                "saturation_counts": row_clips,
            }
        maximum_present = max(float(row["nrmse"]) for row in layers.values())
        spec_json = json.dumps(asdict(spec), sort_keys=True, separators=(",", ":"))
        reports.append({
            "name": name,
            "spec": spec.as_dict(),
            "spec_sha256": sha256(spec_json.encode("utf-8")).hexdigest(),
            "storage_estimate": storage_estimate(spec),
            "layers": layers,
            "saturation_counts_over_invocations": total_clips,
            "maximum_present_layer_nrmse": maximum_present,
            "maximum_12_layer_nrmse": maximum_present if complete else None,
            "per_task_nrmse": task_diagnostics[name],
            "max_single_task_nrmse": max(float(task["nrmse"]) for task in task_diagnostics[name]),
            "single_tasks_over_3_percent": [
                task for task in task_diagnostics[name] if float(task["nrmse"]) > 0.03
            ],
            "local_3_percent_screen": bool(complete and provenance_eligible and maximum_present <= 0.03),
            "local_3_percent_screen_status": (
                "incomplete_12_layer_coverage" if not complete else
                "ineligible_sample_provenance" if not provenance_eligible else
                "passed_local_validation_screen" if maximum_present <= 0.03 else
                "failed_numeric_threshold"
            ),
        })
    return {
        "status": "local candidate study only; not an organizer evaluation or RTL result",
        "metric": "for each layer sqrt(sum((decoded-y_float)^2)/N) / max(sqrt(sum(y_float^2)/N), 1e-8); then max over 12 layers",
        "sample_directories": len(by_sample),
        "all_sample_directories_have_12_layers": complete,
        "incomplete_sample_directories": incomplete,
        "reference": "provided NPZ y_float, checked against independent X @ W + b",
        "sources": sources,
        "available_export_manifests": manifest_sources,
        "sample_provenance": provenance,
        "all_samples_eligible_for_local_validation_screen": provenance_eligible,
        "provenance_note": "Split and source ID are operator declarations. Matching SHA-256 values check local integrity, not actual membership in an official dataset split. Verify source IDs against the original dataset manifest. Legacy exports without provenance are unknown; synthetic/unverified/train/test/mixed inputs cannot pass the local validation screen.",
        "task_diagnostic_note": "Per-task NRMSE is reported separately from the pooled 12-layer metric for local debugging. It is not an official performance pass, especially on ineligible samples.",
        "saturation_note": "Operand counts and MAC events are summed per invocation; repeated W/b in different samples are counted again. Zero saturation is desirable but does not by itself prove 3% accuracy.",
        "candidates": reports,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-root", required=True, type=Path, help="directories of layer_00..11.npz exports")
    parser.add_argument("--candidates", required=True, type=Path, help="named fixed-point candidate JSON")
    parser.add_argument("--report", required=True, type=Path, help="write complete JSON report here")
    args = parser.parse_args()
    try:
        report = evaluate(args.input_root, load_candidates(args.candidates))
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    except (OSError, ValueError, TypeError) as exc:
        parser.exit(1, f"Error: {exc}\n")
    print(f"Wrote {args.report}")
    for row in report["candidates"]:
        value = row["maximum_12_layer_nrmse"]
        score = "incomplete 12-layer coverage" if value is None else f"{value:.3%} local max NRMSE"
        print(f"{row['name']}: {score}")


if __name__ == "__main__":
    main()
