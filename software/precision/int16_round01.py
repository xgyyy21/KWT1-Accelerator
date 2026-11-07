"""Calibrate and evaluate the provisional INT16 KWT-1 FFN1 numeric contract.

Uses the existing 12-layer NPZ reader and provenance checks. Calibration and
evaluation are separate commands; using the same sample for both is explicitly
reported as exploratory. No TensorFlow model or RTL is changed here.
"""

from __future__ import annotations

import argparse
from collections import defaultdict
import csv
from dataclasses import asdict
from hashlib import sha256
import json
from pathlib import Path

import numpy as np

from software.kwt_reference import LAYER_COUNT, PINNED_COMMIT
from software.precision.int16_numeric import LayerFormat, SYMMETRIC_LIMIT, evaluate_layer
from software.precision.study import OFFICIAL_MODEL, file_hash, load_case, sample_provenance


CLIP_KEYS = ("x", "w", "bias", "mac", "bias_add", "y")
COUNTS_PER_LAYER = {"x": 99 * 64, "w": 64 * 256, "bias": 256,
                    "mac": 99 * 256 * 64, "bias_add": 99 * 256, "y": 99 * 256}


def _samples(root: Path) -> list[dict[str, object]]:
    root = root.resolve()
    files = sorted(root.rglob("layer_??.npz"))
    folders = sorted({p.parent for p in files})
    if not folders:
        raise ValueError(f"no 12-layer exports found under {root}")
    result = []
    for folder in folders:
        manifest_path = folder / "manifest.json"
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        if manifest.get("upstream_commit") != PINNED_COMMIT or manifest.get("model") != OFFICIAL_MODEL:
            raise ValueError(f"{manifest_path}: wrong fixed model identity")
        records = manifest.get("layers")
        if not isinstance(records, list) or len(records) != LAYER_COUNT:
            raise ValueError(f"{manifest_path}: need 12 layer records")
        by_layer = {item.get("layer"): item for item in records if isinstance(item, dict)}
        if set(by_layer) != set(range(LAYER_COUNT)):
            raise ValueError(f"{manifest_path}: missing or duplicate layers")
        arrays = []
        layer_hashes = {}
        for layer in range(LAYER_COUNT):
            path = folder / f"layer_{layer:02d}.npz"
            digest = file_hash(path)
            if by_layer[layer].get("file") != path.name or by_layer[layer].get("sha256") != digest:
                raise ValueError(f"{path}: manifest hash mismatch")
            layer_hashes[layer] = digest
            arrays.append(load_case(path))
        source = manifest.get("input_file")
        if source and Path(source).is_file() and file_hash(Path(source)) != manifest.get("input_sha256"):
            raise ValueError(f"{manifest_path}: audio hash mismatch")
        result.append({"folder": str(folder), "manifest": manifest,
                       "manifest_sha256": file_hash(manifest_path), "layers": arrays,
                       "layer_sha256": layer_hashes,
                       "provenance": sample_provenance(folder, root, layer_hashes)})
    return result


def _frac(values: np.ndarray, percentile: float = 100.0) -> int:
    values = np.abs(np.asarray(values, dtype=np.float64))
    magnitude = float(np.max(values) if percentile == 100.0 else np.percentile(values, percentile))
    for frac in range(30, -1, -1):
        if np.rint(magnitude * float(1 << frac)) <= SYMMETRIC_LIMIT:
            return frac
    return 0


def _format(x_values: np.ndarray, w_values: np.ndarray, b_values: np.ndarray,
            y_values: np.ndarray, percentile: float,
            per_channel_w: bool = False) -> LayerFormat:
    xf = _frac(x_values, percentile)
    yf = _frac(y_values, percentile)
    if per_channel_w:
        wf = [_frac(w_values[:, col], percentile) for col in range(w_values.shape[1])]
    else:
        wf = [_frac(w_values, percentile)]
    # Bias is stored in the product domain and must fit signed INT32.
    b_lo, b_hi = -(1 << 31), (1 << 31) - 1
    bias_by_channel = np.asarray(b_values).reshape(-1, w_values.shape[1]) if per_channel_w else None
    for col in range(len(wf)):
        bias_column = bias_by_channel[:, col] if per_channel_w else b_values
        while (xf + wf[col] > 40 or np.any(np.rint(np.asarray(bias_column) * float(1 << (xf + wf[col]))) < b_lo)
               or np.any(np.rint(np.asarray(bias_column) * float(1 << (xf + wf[col]))) > b_hi)):
            if wf[col] == 0:
                raise ValueError("bias cannot fit INT32 even at w_frac=0")
            wf[col] -= 1
    yf = min(yf, xf + min(wf))
    return LayerFormat(x_frac=xf, w_frac=tuple(wf) if per_channel_w else wf[0], y_frac=yf)


def calibrate(root: Path) -> dict[str, object]:
    samples = _samples(root)
    layers: dict[str, list[dict[str, object]]] = {name: [] for name in
        ("global_max_abs", "layer_max_abs", "layer_percentile_99_9", "channel_w_max_abs")}
    all_x = np.concatenate([sample["layers"][layer]["x"].ravel() for sample in samples for layer in range(12)])
    all_w = np.concatenate([sample["layers"][layer]["w"].ravel() for sample in samples for layer in range(12)])
    all_b = np.concatenate([sample["layers"][layer]["b"].ravel() for sample in samples for layer in range(12)])
    all_y = np.concatenate([sample["layers"][layer]["y_float"].ravel() for sample in samples for layer in range(12)])
    global_fmt = _format(all_x, all_w, all_b, all_y, 100.0)
    for layer in range(LAYER_COUNT):
        x = np.concatenate([sample["layers"][layer]["x"] for sample in samples], axis=0)
        w = np.concatenate([sample["layers"][layer]["w"] for sample in samples], axis=0)
        b = np.concatenate([sample["layers"][layer]["b"] for sample in samples], axis=0)
        y = np.concatenate([sample["layers"][layer]["y_float"] for sample in samples], axis=0)
        layers["global_max_abs"].append(asdict(global_fmt))
        layers["layer_max_abs"].append(asdict(_format(x, w, b, y, 100.0)))
        layers["layer_percentile_99_9"].append(asdict(_format(x, w, b, y, 99.9)))
        layers["channel_w_max_abs"].append(asdict(_format(x, w, b, y, 100.0, per_channel_w=True)))
    return {
        "schema": "kwt1-int16-round01-config-v1",
        "status": "provisional; power-of-two scales calibrated on provided samples",
        "selected_candidate": "layer_max_abs",
        "rounding": "nearest_even",
        "x_w_y_range": [-SYMMETRIC_LIMIT, SYMMETRIC_LIMIT],
        "reserved_int16_value": -32768,
        "zero_point": 0,
        "model_commit": PINNED_COMMIT,
        "model": OFFICIAL_MODEL,
        "calibration_sources": [
            {"manifest_sha256": sample["manifest_sha256"],
             "input_sha256": sample["manifest"].get("input_sha256"),
             "source_id": sample["provenance"].get("source_id"),
             "split": sample["provenance"].get("split"),
             "layer_sha256": sample["layer_sha256"]}
            for sample in samples
        ],
        "candidates": layers,
    }


def _nrmse(error_sq: float, reference_sq: float, n: int) -> float:
    return float(np.sqrt(error_sq / n) / max(np.sqrt(reference_sq / n), 1e-8))


def evaluate(input_root: Path, config: dict[str, object], config_sha256: str) -> tuple[dict[str, object], list[dict[str, object]], list[dict[str, object]]]:
    if config.get("schema") != "kwt1-int16-round01-config-v1" or config.get("rounding") != "nearest_even":
        raise ValueError("not a supported INT16 nearest-even configuration")
    samples = _samples(input_root)
    calibration_hashes = {item["manifest_sha256"] for item in config["calibration_sources"]}
    evaluation_hashes = {sample["manifest_sha256"] for sample in samples}
    overlap = bool(calibration_hashes & evaluation_hashes)
    all_layers = []
    all_tasks = []
    candidates = []
    for name, formats in config["candidates"].items():
        if len(formats) != LAYER_COUNT:
            raise ValueError(f"{name}: expected 12 formats")
        totals = defaultdict(lambda: {"n": 0, "samples": 0, "error_sq": 0.0,
                                      "reference_sq": 0.0, "max_abs_error": 0.0,
                                      "saturation": {key: 0 for key in CLIP_KEYS},
                                      "theoretical_bound": 0, "observed_min": 0,
                                      "observed_max": 0, "minimum_bits": 2})
        for sample in samples:
            for layer in range(LAYER_COUNT):
                data = sample["layers"][layer]
                raw_fmt = formats[layer]
                w_frac = raw_fmt["w_frac"]
                fmt = LayerFormat(x_frac=raw_fmt["x_frac"],
                                  w_frac=tuple(w_frac) if isinstance(w_frac, list) else w_frac,
                                  y_frac=raw_fmt["y_frac"], bias_bits=raw_fmt["bias_bits"],
                                  acc_bits=raw_fmt["acc_bits"])
                got = evaluate_layer(data["x"], data["w"], data["b"], fmt)
                ref = data["y_float"]
                error = got["y_real"] - ref
                error_sq = float(np.square(error).sum())
                reference_sq = float(np.square(ref).sum())
                max_abs = float(np.abs(error).max())
                n = int(ref.size)
                all_tasks.append({"candidate": name, "source_id": sample["provenance"]["source_id"],
                                  "split": sample["provenance"]["split"],
                                  "manifest_sha256": sample["manifest_sha256"],
                                  "layer_npz_sha256": sample["layer_sha256"][layer],
                                  "layer": f"{layer:02d}", "values": n,
                                  "nrmse": _nrmse(error_sq, reference_sq, n),
                                  "rmse": float(np.sqrt(error_sq / n)),
                                  "max_abs_error": max_abs})
                row = totals[layer]
                row["n"] += n
                row["samples"] += 1
                row["error_sq"] += error_sq
                row["reference_sq"] += reference_sq
                row["max_abs_error"] = max(row["max_abs_error"], max_abs)
                for key in CLIP_KEYS:
                    row["saturation"][key] += got["saturation"][key]
                acc = got["accumulator"]
                row["theoretical_bound"] = max(row["theoretical_bound"], acc["theoretical_max"])
                row["minimum_bits"] = max(row["minimum_bits"], acc["minimum_signed_bits_for_this_data"])
                row["observed_min"] = min(row["observed_min"], acc["observed_min"])
                row["observed_max"] = max(row["observed_max"], acc["observed_max"])
        scores = []
        aggregate_clips = {key: 0 for key in CLIP_KEYS}
        for layer in range(LAYER_COUNT):
            row = totals[layer]
            nrmse = _nrmse(row["error_sq"], row["reference_sq"], row["n"])
            scores.append(nrmse)
            record = {"candidate": name, "layer": f"{layer:02d}",
                      "samples": row["samples"], "values": row["n"],
                      "nrmse": nrmse, "rmse": float(np.sqrt(row["error_sq"] / row["n"])),
                      "max_abs_error": row["max_abs_error"],
                      "error_sq_sum": row["error_sq"], "reference_sq_sum": row["reference_sq"],
                      "observed_acc_min": row["observed_min"],
                      "observed_acc_max": row["observed_max"],
                      "theoretical_acc_abs_bound": row["theoretical_bound"],
                      "minimum_signed_acc_bits_for_these_inputs": row["minimum_bits"]}
            for key in CLIP_KEYS:
                value = row["saturation"][key]
                aggregate_clips[key] += value
                record[f"{key}_saturation_count"] = value
                record[f"{key}_saturation_rate"] = value / (row["samples"] * COUNTS_PER_LAYER[key])
            all_layers.append(record)
        worst = max(range(12), key=lambda layer: scores[layer])
        candidates.append({"name": name, "maximum_12_layer_nrmse": scores[worst],
                           "worst_layer": f"{worst:02d}",
                           "all_12_layers_present": True,
                           "saturation_counts": aggregate_clips,
                           "maximum_required_signed_acc_bits_for_these_inputs": max(totals[i]["minimum_bits"] for i in range(12)),
                           "format_by_layer": formats})
    summary = {"schema": "kwt1-int16-round01-result-v1",
               "status": "exploratory if calibration overlaps evaluation or split unverified",
               "model_commit": PINNED_COMMIT, "model": OFFICIAL_MODEL,
               "config_sha256": config_sha256, "selected_candidate": config["selected_candidate"],
               "evaluation_sample_count": len(samples), "layer_count": LAYER_COUNT,
               "calibration_evaluation_overlap": overlap,
               "official_validation_claim": False,
               "source_manifests": [{"sha256": s["manifest_sha256"],
                                    "provenance": s["provenance"],
                                    "input_sha256": s["manifest"].get("input_sha256"),
                                    "checkpoint_sha256": s["manifest"].get("checkpoint_sha256"),
                                    "layer_sha256": s["layer_sha256"]} for s in samples],
               "metric": "sqrt(sum(error^2)/N)/max(sqrt(sum(reference^2)/N),1e-8), pooled within layer; max over 12",
               "integer_rule": "INT16 symmetric ±32767, zero-point 0, nearest-even, each K integer MAC then bias, saturate at configured accumulator width, integer-shift requantization",
               "full_range_accumulator_bound": 64 * (SYMMETRIC_LIMIT ** 2) + (1 << 31),
               "full_range_accumulator_minimum_signed_bits": 38,
               "candidates": candidates}
    return summary, all_layers, all_tasks


def _write_csv(path: Path, rows: list[dict[str, object]]) -> None:
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    cal = sub.add_parser("calibrate")
    cal.add_argument("--calibration-root", type=Path, required=True)
    cal.add_argument("--config", type=Path, required=True)
    ev = sub.add_parser("evaluate")
    ev.add_argument("--input-root", type=Path, required=True)
    ev.add_argument("--config", type=Path, required=True)
    ev.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    if args.command == "calibrate":
        if args.config.exists():
            parser.error(f"preserving existing config: {args.config}")
        result = calibrate(args.calibration_root)
        args.config.parent.mkdir(parents=True, exist_ok=True)
        args.config.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"wrote {args.config}")
    else:
        config = json.loads(args.config.read_text(encoding="utf-8"))
        summary, layers, tasks = evaluate(args.input_root, config, file_hash(args.config))
        args.output_dir.mkdir(parents=True, exist_ok=True)
        targets = (args.output_dir / "int16_summary.json",
                   args.output_dir / "int16_per_layer.csv",
                   args.output_dir / "int16_per_sample.csv")
        if any(path.exists() for path in targets):
            parser.error("preserving existing INT16 result files")
        targets[0].write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        _write_csv(targets[1], layers)
        _write_csv(targets[2], tasks)
        for candidate in summary["candidates"]:
            print(f"{candidate['name']}: {candidate['maximum_12_layer_nrmse']:.6%} worst layer {candidate['worst_layer']}")
        print(f"wrote {args.output_dir}")


if __name__ == "__main__":
    main()
