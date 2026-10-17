"""Check the hardware cache readback CSV against the software FP32 images.

This checks only the local matrix-cache-manager readback boundary. It does not
claim that FP32 arithmetic, DMA, the AI engine, or the E203 path has passed.
The CSV's absolute ``mem_hex_file`` values are provenance from the producer;
the checker opens the matching files under ``--image-dir`` instead.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
from pathlib import Path
from typing import Mapping


Group = tuple[str, str]
REQUIRED_GROUPS: Mapping[Group, str] = {
    ("hand_2x2", "X"): "x",
    ("hand_2x2", "W"): "w",
    ("hand_2x2", "BIAS"): "bias",
    ("rounding_nonfused", "X"): "rounding_x",
    ("rounding_nonfused", "W"): "rounding_w",
    ("rounding_nonfused", "BIAS"): "rounding_bias",
    ("k32_boundary", "X"): "tile_x",
    ("k32_boundary", "W"): "tile_w",
    ("k32_boundary", "BIAS"): "tile_bias",
}

FIELDS = (
    "case", "tensor", "input_bin", "input_sha256", "mem_hex_file",
    "rtl_revision", "rtl_snapshot_sha256", "bank", "row", "column", "k",
    "low_word_address", "high_word_address", "word_low16", "word_high16",
    "reconstructed_fp32_bits", "low_request_cycle", "low_data_valid_cycle",
    "high_request_cycle", "high_data_valid_cycle",
)
_HEX16 = re.compile(r"[0-9a-fA-F]{4}\Z")
_HEX32 = re.compile(r"0x[0-9a-fA-F]{8}\Z")
_SHA256 = re.compile(r"[0-9a-fA-F]{64}\Z")
_BANK = {"X": "A", "W": "B", "BIAS": "RESULT"}


class ReadbackError(ValueError):
    """A readback record or its provenance does not match the image."""


def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _nonnegative_decimal(value: str, label: str, line: int) -> int:
    if not value.isascii() or not value.isdecimal():
        raise ReadbackError(f"line {line}: {label} must be a decimal integer")
    return int(value)


def _read_words(path: Path) -> list[int]:
    try:
        lines = path.read_text(encoding="ascii").splitlines()
    except (OSError, UnicodeError) as exc:
        raise ReadbackError(f"cannot read {path.name}: {exc}") from exc
    if not lines:
        raise ReadbackError(f"{path.name}: empty 16-bit word image")
    words = []
    for number, line in enumerate(lines, start=1):
        if not _HEX16.fullmatch(line):
            raise ReadbackError(f"{path.name} line {number}: expected exactly four hex digits")
        words.append(int(line, 16))
    return words


def _reference_images(image_dir: Path, groups: Mapping[Group, str]) -> dict[Group, dict]:
    manifest_path = image_dir / "manifest.json"
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError) as exc:
        raise ReadbackError(f"cannot read image manifest: {exc}") from exc
    tensors = manifest.get("tensors")
    if not isinstance(tensors, dict):
        raise ReadbackError("image manifest has no tensors object")

    images = {}
    for group, name in groups.items():
        entry = tensors.get(name)
        if not isinstance(entry, dict):
            raise ReadbackError(f"manifest is missing tensor {name}")
        shape = entry.get("shape")
        if (not isinstance(shape, list) or len(shape) != 2
                or any(type(n) is not int or n <= 0 for n in shape)):
            raise ReadbackError(f"tensor {name}: invalid two-dimensional shape")
        count = shape[0] * shape[1]
        if entry.get("word_count") != 2 * count:
            raise ReadbackError(f"tensor {name}: manifest word count disagrees with shape")
        declared_bytes = entry.get("bytes", entry.get("byte_count"))
        if declared_bytes != 4 * count:
            raise ReadbackError(f"tensor {name}: manifest byte count disagrees with shape")
        if entry.get("element_bits", 32) != 32:
            raise ReadbackError(f"tensor {name}: expected 32-bit elements")
        binary_path = image_dir / f"{name}.bin"
        try:
            binary = binary_path.read_bytes()
        except OSError as exc:
            raise ReadbackError(f"cannot read {binary_path.name}: {exc}") from exc
        if len(binary) != 4 * count:
            raise ReadbackError(f"{binary_path.name}: byte count disagrees with shape")
        digest = _sha256(binary)
        if entry.get("sha256_bin", "").lower() != digest:
            raise ReadbackError(f"{binary_path.name}: SHA-256 disagrees with manifest")
        words = _read_words(image_dir / f"{name}.mem")
        if len(words) != 2 * count:
            raise ReadbackError(f"{name}.mem: word count disagrees with shape")
        rebuilt = b"".join(word.to_bytes(2, "little") for word in words)
        if rebuilt != binary:
            raise ReadbackError(f"{name}.mem: low-word-first bytes disagree with {name}.bin")
        manifest_words = entry.get("words_hex")
        if manifest_words is not None and manifest_words != [f"{w:04x}" for w in words]:
            raise ReadbackError(f"{name}.mem: words disagree with manifest")
        images[group] = {"name": name, "shape": shape, "words": words, "sha256": digest}
    return images


def check_readback(
    csv_path: Path,
    image_dir: Path,
    groups: Mapping[Group, str] = REQUIRED_GROUPS,
) -> dict:
    """Validate each record and require complete, unique coverage of every group."""
    csv_path, image_dir = Path(csv_path), Path(image_dir)
    images = _reference_images(image_dir, groups)
    try:
        csv_bytes = csv_path.read_bytes()
        with csv_path.open("r", encoding="utf-8-sig", newline="") as stream:
            reader = csv.DictReader(stream, strict=True)
            if tuple(reader.fieldnames or ()) != FIELDS:
                raise ReadbackError("readback CSV header does not match the 20-field schema")
            rows = list(reader)
    except (OSError, UnicodeError, csv.Error) as exc:
        raise ReadbackError(f"cannot read readback CSV: {exc}") from exc

    expected_count = sum(image["shape"][0] * image["shape"][1] for image in images.values())
    if len(rows) != expected_count:
        raise ReadbackError(f"readback CSV has {len(rows)} rows; expected {expected_count}")
    seen: dict[Group, set[int]] = {group: set() for group in groups}
    sha_mismatches: dict[Group, tuple[str, str]] = {}
    revision = snapshot = None
    previous_cycle = -1
    previous_group: Group | None = None
    previous_low_cycle = -1
    for line, record in enumerate(rows, start=2):
        if None in record or any(value is None or value == "" for value in record.values()):
            raise ReadbackError(f"line {line}: missing or extra CSV fields")
        group = record["case"], record["tensor"]
        if group not in images:
            raise ReadbackError(f"line {line}: unexpected case/tensor {group}")
        image = images[group]
        name = image["name"]
        if record["input_bin"] != f"{name}.bin":
            raise ReadbackError(f"line {line}: input file name disagrees with {group}")
        if record["input_sha256"].lower() != image["sha256"]:
            sha_mismatches[group] = (record["input_sha256"], image["sha256"])
        if Path(record["mem_hex_file"].replace("\\", "/")).name != f"{name}.mem":
            raise ReadbackError(f"line {line}: source mem file name disagrees with {group}")
        if record["bank"] != _BANK[group[1]]:
            raise ReadbackError(f"line {line}: cache bank disagrees with tensor")
        if not record["rtl_revision"].strip():
            raise ReadbackError(f"line {line}: RTL revision is empty")
        if not _SHA256.fullmatch(record["rtl_snapshot_sha256"]):
            raise ReadbackError(f"line {line}: invalid RTL snapshot SHA-256")
        if revision is None:
            revision, snapshot = record["rtl_revision"], record["rtl_snapshot_sha256"].lower()
        elif (record["rtl_revision"], record["rtl_snapshot_sha256"].lower()) != (revision, snapshot):
            raise ReadbackError(f"line {line}: RTL provenance changed within the CSV")

        row = _nonnegative_decimal(record["row"], "row", line)
        column = _nonnegative_decimal(record["column"], "column", line)
        rows_count, columns_count = image["shape"]
        if row >= rows_count or column >= columns_count:
            raise ReadbackError(f"line {line}: matrix coordinate is out of range")
        element = row * columns_count + column
        if element in seen[group]:
            raise ReadbackError(f"line {line}: duplicate {group} element {element}")
        seen[group].add(element)
        k = -1 if group[1] == "BIAS" else column if group[1] == "X" else row
        if record["k"] != str(k):
            raise ReadbackError(f"line {line}: K index disagrees with matrix coordinate")
        low_address = _nonnegative_decimal(record["low_word_address"], "low word address", line)
        high_address = _nonnegative_decimal(record["high_word_address"], "high word address", line)
        if (low_address, high_address) != (2 * element, 2 * element + 1):
            raise ReadbackError(f"line {line}: 16-bit word addresses disagree with row-major layout")
        for field in ("word_low16", "word_high16"):
            if not _HEX16.fullmatch(record[field]):
                raise ReadbackError(f"line {line}: {field} must have four hex digits")
        low, high = int(record["word_low16"], 16), int(record["word_high16"], 16)
        if (low, high) != tuple(image["words"][2 * element:2 * element + 2]):
            raise ReadbackError(f"line {line}: readback words disagree with {name}.mem")
        if not _HEX32.fullmatch(record["reconstructed_fp32_bits"]):
            raise ReadbackError(f"line {line}: reconstructed FP32 bits need eight hex digits")
        if int(record["reconstructed_fp32_bits"], 16) != ((high << 16) | low):
            raise ReadbackError(f"line {line}: reconstructed FP32 bits disagree with readback words")

        low_req = _nonnegative_decimal(record["low_request_cycle"], "low request cycle", line)
        low_valid = _nonnegative_decimal(record["low_data_valid_cycle"], "low valid cycle", line)
        high_req = _nonnegative_decimal(record["high_request_cycle"], "high request cycle", line)
        high_valid = _nonnegative_decimal(record["high_data_valid_cycle"], "high valid cycle", line)
        if low_valid != low_req + 1 or high_valid != high_req + 1:
            raise ReadbackError(f"line {line}: cache read is not valid one cycle after request")
        if high_req != low_req + 2:
            raise ReadbackError(f"line {line}: high-word request cycle is not two after low-word request")
        if low_req <= previous_cycle:
            raise ReadbackError(f"line {line}: readback cycle overlaps previous record")
        if group == previous_group and low_req != previous_low_cycle + 4:
            raise ReadbackError(f"line {line}: cycles are discontinuous inside {group}")
        previous_cycle, previous_group, previous_low_cycle = high_valid, group, low_req

    for group, image in images.items():
        expected = image["shape"][0] * image["shape"][1]
        if len(seen[group]) != expected:
            raise ReadbackError(f"missing readback elements in {group}")
    if sha_mismatches:
        details = "; ".join(
            f"{case}/{tensor}: CSV {claimed}, actual {actual}"
            for (case, tensor), (claimed, actual) in sha_mismatches.items()
        )
        raise ReadbackError(
            f"input SHA-256 disagrees in {len(sha_mismatches)} group(s): {details}"
        )

    return {
        "status": "PASS",
        "scope": "matrix_cache_manager 16-bit word readback only; no arithmetic/DMA/SoC validation",
        "csv_sha256": _sha256(csv_bytes),
        "rtl_revision": revision,
        "rtl_snapshot_sha256": snapshot,
        "records_checked": len(rows),
        "groups": [
            {"case": case, "tensor": tensor, "input": image["name"] + ".bin",
             "input_sha256": image["sha256"], "elements_checked": len(seen[(case, tensor)])}
            for (case, tensor), image in images.items()
        ],
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--csv", required=True, type=Path, help="hardware handoff/word_readback.csv")
    parser.add_argument("--image-dir", required=True, type=Path, help="software FP32 hand image directory")
    parser.add_argument("--report", type=Path, help="optional JSON summary")
    args = parser.parse_args()
    try:
        result = check_readback(args.csv, args.image_dir)
    except ReadbackError as exc:
        parser.error(str(exc))
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result, indent=2))


if __name__ == "__main__":
    main()
