"""Export SRAM-sized FFN1 weight tiles and compare two data-access schedules.

This is a software experiment, not a hardware measurement.  Both schedules
compute exactly M*K*N multiply-accumulates.  They use the same dedicated weight
buffer capacity and the same arithmetic and output format.  The comparison
counts logical bytes requested from shared memory, without bus bursts,
contention, cache effects, DMA setup, clock cycles, power, or silicon area.
"""

from __future__ import annotations

import argparse
from hashlib import sha256
import json
from pathlib import Path
from typing import Any

import numpy as np


DEFAULT_TILE_COLUMNS = 16
DEFAULT_WEIGHT_BUFFER_BYTES = 2048  # One 16-bit x 1024-word SRAM macro.
WORD_BITS = 16


def _positive_int(value: Any, label: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
        raise ValueError(f"{label} must be a positive integer")
    return value


def _tensor(manifest: dict[str, Any], name: str, dimensions: int) -> dict[str, Any]:
    tensors = manifest.get("tensors")
    if not isinstance(tensors, dict) or not isinstance(tensors.get(name), dict):
        raise ValueError(f"manifest needs tensors.{name}")
    info = tensors[name]
    shape = info.get("shape")
    if not isinstance(shape, list) or len(shape) != dimensions:
        raise ValueError(f"tensors.{name}.shape must have {dimensions} dimensions")
    for index, extent in enumerate(shape):
        _positive_int(extent, f"tensors.{name}.shape[{index}]")
    bits = _positive_int(info.get("element_bits"), f"tensors.{name}.element_bits")
    if bits % WORD_BITS:
        raise ValueError(f"tensors.{name}.element_bits must be a multiple of 16")
    count = info.get("element_count")
    expected_count = int(np.prod(shape))
    if count != expected_count:
        raise ValueError(f"tensors.{name}.element_count does not match shape")
    word_count = info.get("word_count")
    if word_count != expected_count * (bits // WORD_BITS):
        raise ValueError(f"tensors.{name}.word_count does not match shape and bit width")
    return info


def _sha(data: bytes) -> str:
    return sha256(data).hexdigest()


def estimate_traffic(
    *, rows: int, inner: int, columns: int, tile_columns: int,
    x_element_bytes: int, w_element_bytes: int, bias_element_bytes: int,
    output_element_bytes: int,
) -> dict[str, Any]:
    """Logical shared-memory bytes for a fair row-first vs tile-first model.

    Baseline: for each input row, retain its K X elements in a small row buffer,
    process all output tiles, and reload all W once per row.  Proposed: for
    each output tile, keep its W in the *same* dedicated weight buffer while
    processing every input row, reloading X once per tile.  Each bias is read
    once, and each output is written once in both cases.
    """
    for label, value in (
        ("rows", rows), ("inner", inner), ("columns", columns),
        ("tile_columns", tile_columns), ("x_element_bytes", x_element_bytes),
        ("w_element_bytes", w_element_bytes),
        ("bias_element_bytes", bias_element_bytes),
        ("output_element_bytes", output_element_bytes),
    ):
        _positive_int(value, label)
    tile_count = (columns + tile_columns - 1) // tile_columns
    common_bias = columns * bias_element_bytes
    common_output = rows * columns * output_element_bytes
    row_first_x = rows * inner * x_element_bytes
    row_first_w = rows * inner * columns * w_element_bytes
    tile_first_x = tile_count * rows * inner * x_element_bytes
    tile_first_w = inner * columns * w_element_bytes
    row_first_total = row_first_x + row_first_w + common_bias + common_output
    tile_first_total = tile_first_x + tile_first_w + common_bias + common_output
    return {
        "unit": "logical bytes requested from shared memory, analytical only",
        "multiply_accumulate_count_both": rows * inner * columns,
        "tile_count": tile_count,
        "common_both": {
            "bias_read_once_bytes": common_bias,
            "output_write_once_bytes": common_output,
        },
        "row_first": {
            "loop_order": "row -> output-column tile -> reduction k",
            "x_read_once_bytes": row_first_x,
            "w_reloaded_each_row_bytes": row_first_w,
            "total_bytes": row_first_total,
        },
        "tile_first_weight_stationary": {
            "loop_order": "output-column tile -> row -> reduction k",
            "x_reloaded_each_tile_bytes": tile_first_x,
            "w_read_once_bytes": tile_first_w,
            "total_bytes": tile_first_total,
        },
        "estimated_saved_bytes": row_first_total - tile_first_total,
        "estimated_traffic_ratio_row_first_over_tile_first": row_first_total / tile_first_total,
        "assumptions": [
            "Both schedules use the same dedicated weight-buffer capacity and arithmetic.",
            "A separate K-element row buffer retains X across output tiles in the row-first schedule.",
            "The same separate bias storage is available to both schedules: bias is read once per output channel.",
            "Each result is written once in both schedules.",
            "No cache, bus bursts, arbitration, DMA setup, internal buffer transfers, latency, or PPA is modeled.",
        ],
    }


def export_weight_tiles(
    packed_dir: Path, output_dir: Path, *,
    tile_columns: int = DEFAULT_TILE_COLUMNS,
    weight_buffer_bytes: int = DEFAULT_WEIGHT_BUFFER_BYTES,
) -> dict[str, Any]:
    """Validate one pack, export all W tiles, and write schedule_manifest.json."""
    _positive_int(tile_columns, "tile_columns")
    _positive_int(weight_buffer_bytes, "weight_buffer_bytes")
    if weight_buffer_bytes % (WORD_BITS // 8):
        raise ValueError("weight_buffer_bytes must align to a 16-bit word")

    packed_dir = Path(packed_dir)
    output_dir = Path(output_dir)
    manifest_path = packed_dir / "manifest.json"
    raw_manifest = manifest_path.read_bytes()
    manifest = json.loads(raw_manifest.decode("utf-8"))
    if not isinstance(manifest, dict):
        raise ValueError("manifest.json must contain a JSON object")
    storage = manifest.get("storage")
    if not isinstance(storage, dict) or storage.get("word_bits") != WORD_BITS:
        raise ValueError("this experiment requires the packer's 16-bit word format")
    expected_storage = {
        "word_byte_order": "little-endian",
        "element_word_order": "least-significant 16-bit word first",
        "element_signedness": "two's complement signed",
        "tensor_order": "C row-major, last index fastest",
        "w_index": "w[k,column]",
    }
    for key, value in expected_storage.items():
        if storage.get(key) != value:
            raise ValueError(f"unsupported storage.{key}: expected {value!r}")

    x = _tensor(manifest, "x", 2)
    w = _tensor(manifest, "w", 2)
    bias = _tensor(manifest, "b", 1)
    result = _tensor(manifest, "expected", 2)
    rows, inner = x["shape"]
    w_inner, columns = w["shape"]
    if inner != w_inner or bias["shape"] != [columns] or result["shape"] != [rows, columns]:
        raise ValueError("x, w, b, and expected tensor shapes are inconsistent")

    filename = w.get("binary_file")
    if filename != "w.bin":
        raise ValueError("tensors.w.binary_file must be w.bin")
    w_file = packed_dir / filename
    raw_w = w_file.read_bytes()
    expected_length = inner * columns * (w["element_bits"] // 8)
    if len(raw_w) != expected_length:
        raise ValueError(f"w.bin length {len(raw_w)} != expected {expected_length}")
    original_sha = w.get("binary_sha256")
    if not isinstance(original_sha, str) or _sha(raw_w) != original_sha:
        raise ValueError("w.bin SHA-256 does not match manifest.json")

    actual_max_tile_columns = min(tile_columns, columns)
    max_tile_bytes = inner * actual_max_tile_columns * (w["element_bits"] // 8)
    if max_tile_bytes > weight_buffer_bytes:
        fit = weight_buffer_bytes // (inner * (w["element_bits"] // 8))
        raise ValueError(
            f"one tile needs {max_tile_bytes} bytes but buffer has {weight_buffer_bytes}; "
            f"at most {fit} full output columns fit"
        )

    words_per_element = w["element_bits"] // WORD_BITS
    word_matrix = np.frombuffer(raw_w, dtype="<u2").reshape(inner, columns, words_per_element)
    output_dir.mkdir(parents=True, exist_ok=True)
    tiles: list[dict[str, Any]] = []
    for index, start in enumerate(range(0, columns, tile_columns)):
        stop = min(start + tile_columns, columns)
        tile_words = word_matrix[:, start:stop, :].reshape(-1).copy()
        tile_bytes = tile_words.astype("<u2", copy=False).tobytes()
        stem = f"w_tile_{index:03d}_j{start:03d}_{stop - 1:03d}"
        binary_file = stem + ".bin"
        readmemh_file = stem + ".mem"
        (output_dir / binary_file).write_bytes(tile_bytes)
        (output_dir / readmemh_file).write_text(
            "".join(f"{int(word):04x}\n" for word in tile_words), encoding="ascii"
        )
        tiles.append({
            "tile_index": index,
            "column_start_inclusive": start,
            "column_end_exclusive": stop,
            "columns": stop - start,
            "shape_k_by_columns": [inner, stop - start],
            "element_count": inner * (stop - start),
            "word_count": int(tile_words.size),
            "byte_count": len(tile_bytes),
            "binary_file": binary_file,
            "readmemh_file": readmemh_file,
            "binary_sha256": _sha(tile_bytes),
            "element_order": "for k=0..K-1, for j=start..end-1, W[k,j]",
        })

    traffic = estimate_traffic(
        rows=rows, inner=inner, columns=columns, tile_columns=tile_columns,
        x_element_bytes=x["element_bits"] // 8,
        w_element_bytes=w["element_bits"] // 8,
        bias_element_bytes=bias["element_bits"] // 8,
        output_element_bytes=result["element_bits"] // 8,
    )
    schedule: dict[str, Any] = {
        "schema": "kwt1-weight-stationary-schedule-v1",
        "status": "software-side proposal and analytical traffic estimate; RTL team must validate",
        "source": {
            "packed_manifest_file": str(manifest_path.resolve()),
            "packed_manifest_sha256": _sha(raw_manifest),
            "w_binary_file": str(w_file.resolve()),
            "w_binary_sha256": _sha(raw_w),
            "w_binary_bytes": len(raw_w),
        },
        "shape": {"rows_m": rows, "reduction_k": inner, "output_columns_n": columns},
        "weight_buffer": {
            "capacity_bytes": weight_buffer_bytes,
            "word_bits": WORD_BITS,
            "tile_columns_requested": tile_columns,
            "largest_tile_bytes": max_tile_bytes,
            "example_macro": "16-bit x 1024 words when capacity_bytes=2048",
        },
        "schedule": {
            "outer": "for each output-column tile: load its W once into the dedicated weight buffer",
            "middle": "for each X row: read its K elements once for this tile",
            "inner": "for each tile output column: dot over k=0..K-1, then add bias and write Y[row,column]",
            "numeric_contract": "unchanged from source pack; tiling changes storage/access order only",
        },
        "tiles": tiles,
        "analytical_shared_memory_traffic": traffic,
    }
    (output_dir / "schedule_manifest.json").write_text(
        json.dumps(schedule, ensure_ascii=False, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    return schedule


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--packed-dir", type=Path, required=True,
                        help="directory produced by software/pack_tensors.py")
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--tile-columns", type=int, default=DEFAULT_TILE_COLUMNS)
    parser.add_argument("--weight-buffer-bytes", type=int, default=DEFAULT_WEIGHT_BUFFER_BYTES)
    args = parser.parse_args()
    try:
        schedule = export_weight_tiles(
            args.packed_dir, args.output_dir,
            tile_columns=args.tile_columns,
            weight_buffer_bytes=args.weight_buffer_bytes,
        )
    except (OSError, ValueError, TypeError, json.JSONDecodeError) as exc:
        parser.error(str(exc))
    traffic = schedule["analytical_shared_memory_traffic"]
    print(f"Wrote {args.output_dir / 'schedule_manifest.json'}")
    print(f"Tiles: {len(schedule['tiles'])}; largest weight tile: "
          f"{schedule['weight_buffer']['largest_tile_bytes']} bytes")
    print("Analytical shared-memory bytes: "
          f"row-first={traffic['row_first']['total_bytes']}, "
          f"tile-first={traffic['tile_first_weight_stationary']['total_bytes']}, "
          f"saved={traffic['estimated_saved_bytes']}")
    print("This is an access-count estimate, not measured timing, power, or area.")


if __name__ == "__main__":
    main()
