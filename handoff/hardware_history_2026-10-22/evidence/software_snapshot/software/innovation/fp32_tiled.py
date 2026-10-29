"""Capacity and arithmetic check for a *candidate* FP32 tiled FFN1 schedule.

This is a software model, not an RTL implementation or a measured performance
result. It assumes three independently usable byte capacities and counts only
logical payload bytes transferred between shared memory and local buffers.
"""

from __future__ import annotations

import argparse
import json
from typing import Dict, List, Sequence

from software.fp32_reference import add_bits, multiply_bits


def _positive(name: str, value: int) -> int:
    if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
        raise ValueError(f"{name} must be a positive integer")
    return value


def _groups(total: int, tile: int) -> int:
    return (total + tile - 1) // tile


def plan_fp32_tiles(
    rows: int, depth: int, columns: int,
    row_tile: int = 8, depth_tile: int = 32, column_tile: int = 16,
    x_capacity: int = 2048, w_capacity: int = 2048, partial_capacity: int = 2048,
) -> Dict[str, object]:
    """Check three independent capacities and estimate isolated weight reuse.

    The baseline rereads all W for every input row. The candidate rereads W
    once per row tile. Both read each X once, each b once per output element,
    and write each Y once. No cache lines, DMA setup, SRAM traffic, or timing
    are modeled. A real implementation must confirm the buffer roles/ports.
    """
    for name, value in (("rows", rows), ("depth", depth), ("columns", columns),
                        ("row_tile", row_tile), ("depth_tile", depth_tile),
                        ("column_tile", column_tile), ("x_capacity", x_capacity),
                        ("w_capacity", w_capacity), ("partial_capacity", partial_capacity)):
        _positive(name, value)

    # Tail tiles use only their actual number of rows, columns, or K values.
    x_peak = min(rows, row_tile) * depth * 4
    w_peak = min(depth, depth_tile) * min(columns, column_tile) * 4
    partial_peak = min(rows, row_tile) * min(columns, column_tile) * 4
    demands = {"x": x_peak, "w": w_peak, "partial": partial_peak}
    capacities = {"x": x_capacity, "w": w_capacity, "partial": partial_capacity}
    for name, demand in demands.items():
        if demand > capacities[name]:
            raise ValueError(f"{name} tile needs {demand} bytes, capacity is {capacities[name]}")

    row_groups = _groups(rows, row_tile)
    column_groups = _groups(columns, column_tile)
    depth_groups = _groups(depth, depth_tile)
    common = {"x_read": rows * depth * 4,
              "bias_read": rows * columns * 4,
              "y_write": rows * columns * 4}
    baseline = dict(common, w_read=rows * depth * columns * 4)
    candidate = dict(common, w_read=row_groups * depth * columns * 4)
    return {
        "status": "DRAFT FP32 capacity/traffic model; not RTL or measured bus traffic",
        "shape": {"rows": rows, "depth": depth, "columns": columns},
        "tile": {"rows": row_tile, "depth": depth_tile, "columns": column_tile},
        "groups": {"rows": row_groups, "depth": depth_groups, "columns": column_groups},
        "peak_buffer_bytes": demands,
        "buffer_capacity_bytes": capacities,
        "multiplications": rows * depth * columns,
        "baseline_logical_bytes": dict(baseline, total=sum(baseline.values())),
        "candidate_logical_bytes": dict(candidate, total=sum(candidate.values())),
        "isolated_w_read_saving_bytes": baseline["w_read"] - candidate["w_read"],
        "assumptions": [
            "three independently usable buffers, with the stated capacities and sufficient ports",
            "each row tile loads all its X once; each K-by-column W tile is reloaded per row tile",
            "partial sums persist across K tiles; bias is added once after all K",
            "both variants read bias once per output element; no bias-reuse claim",
            "counts only logical shared-memory payload bytes, not cycles, bandwidth, cache behavior, or PPA",
        ],
    }


def run_tiled_bits(
    x: Sequence[Sequence[int]], w: Sequence[Sequence[int]], bias: Sequence[int],
    row_tile: int = 8, depth_tile: int = 32, column_tile: int = 16,
) -> List[List[int]]:
    """Demonstrate that tile traversal preserves increasing-k FP32 answers.

    Every product and addition is rounded separately by fp32_reference.py.
    This function is deliberately for small software checks; it does not
    pretend to model SRAM timing or a hardware instruction stream.
    """
    if not x or not w or not bias:
        raise ValueError("X, W and bias must be nonempty")
    rows, depth, columns = len(x), len(w), len(bias)
    if any(len(row) != depth for row in x) or any(len(row) != columns for row in w):
        raise ValueError("inconsistent X/W/b dimensions")
    plan_fp32_tiles(rows, depth, columns, row_tile, depth_tile, column_tile)

    result = [[0] * columns for _ in range(rows)]
    for row_start in range(0, rows, row_tile):
        row_stop = min(row_start + row_tile, rows)
        for column_start in range(0, columns, column_tile):
            column_stop = min(column_start + column_tile, columns)
            partial = [[0] * (column_stop - column_start)
                       for _ in range(row_stop - row_start)]
            for depth_start in range(0, depth, depth_tile):
                for k in range(depth_start, min(depth_start + depth_tile, depth)):
                    for row in range(row_start, row_stop):
                        for column in range(column_start, column_stop):
                            local_row = row - row_start
                            local_column = column - column_start
                            product = multiply_bits(x[row][k], w[k][column])
                            partial[local_row][local_column] = add_bits(
                                partial[local_row][local_column], product)
            for row in range(row_start, row_stop):
                for column in range(column_start, column_stop):
                    result[row][column] = add_bits(
                        partial[row - row_start][column - column_start], bias[column])
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--rows", type=int, default=99)
    parser.add_argument("--depth", type=int, default=64)
    parser.add_argument("--columns", type=int, default=256)
    parser.add_argument("--row-tile", type=int, default=8)
    parser.add_argument("--depth-tile", type=int, default=32)
    parser.add_argument("--column-tile", type=int, default=16)
    args = parser.parse_args()
    report = plan_fp32_tiles(args.rows, args.depth, args.columns,
                             args.row_tile, args.depth_tile, args.column_tile)
    print(json.dumps(report, ensure_ascii=False, indent=2, sort_keys=True))


if __name__ == "__main__":
    main()
