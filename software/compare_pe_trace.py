"""Compare a measured PE event trace with the SOFTWARE CANDIDATE golden CSV.

This is a draft handoff schema, not a claim that RTL currently emits it. The
testbench must supply logical output coordinates and a GLOBAL k before using
this checker. Rows are matched by event identity, not by CSV row or clock.
"""

from __future__ import annotations

import argparse
import csv
from hashlib import sha256
import json
from pathlib import Path
import re

from software.examples.fp32_trace_csv import HEADER


_HEX32 = re.compile(r"0x[0-9a-fA-F]{8}\Z")
_SHA256 = re.compile(r"[0-9a-fA-F]{64}\Z")
_WORD_FIELDS = {
    "mac": ("x_bits", "w_bits", "acc_before_bits", "product_bits", "acc_after_bits"),
    "bias": ("acc_before_bits", "acc_after_bits", "bias_bits", "result_bits"),
}
_ABSENT_FIELDS = {
    "mac": ("bias_bits", "result_bits"),
    "bias": ("k", "x_bits", "w_bits", "product_bits"),
}


class TraceContractError(ValueError):
    """Trace is not comparable under the current candidate CSV contract."""


def _uint(value: str, field: str, line: int, *, limit: int = 0xFFFFFFFF) -> int:
    if not value.isascii() or not value.isdecimal():
        raise TraceContractError(f"line {line}: {field} must be unsigned decimal")
    number = int(value)
    if number > limit:
        raise TraceContractError(f"line {line}: {field} exceeds {limit}")
    return number


def _load(path: Path, source: str, case_id: str | None) -> tuple[dict, str, int]:
    raw = path.read_bytes()
    try:
        with path.open("r", encoding="utf-8-sig", newline="") as stream:
            reader = csv.DictReader(stream, strict=True)
            if tuple(reader.fieldnames or ()) != HEADER:
                raise TraceContractError(f"{path}: expected the 19-column draft header")
            records = list(reader)
    except (UnicodeError, csv.Error) as exc:
        raise TraceContractError(f"cannot parse {path}: {exc}") from exc

    events = {}
    rtl_commits = set()
    for line, row in enumerate(records, start=2):
        if None in row or any(value is None for value in row.values()):
            raise TraceContractError(f"line {line}: extra or missing CSV columns")
        if row["source_kind"] != source:
            raise TraceContractError(f"line {line}: expected source_kind={source}")
        if not row["case_id"]:
            raise TraceContractError(f"line {line}: empty case_id")
        if case_id is not None and row["case_id"] != case_id:
            continue  # Either CSV may contain other cases from the same run.
        event = row["event"]
        if event not in _WORD_FIELDS:
            raise TraceContractError(f"line {line}: event must be mac or bias")
        if row["valid"] != "1":
            raise TraceContractError(f"line {line}: event rows must have valid=1")
        r = _uint(row["row"], "row", line)
        c = _uint(row["column"], "column", line)
        _uint(row["tile_id"], "tile_id", line)
        k = _uint(row["k"], "global k", line) if event == "mac" else None
        for field in _WORD_FIELDS[event]:
            if not _HEX32.fullmatch(row[field]):
                raise TraceContractError(f"line {line}: {field} needs 0x plus eight hex digits")
        for field in _ABSENT_FIELDS[event]:
            if row[field] != "":
                raise TraceContractError(f"line {line}: {field} must be empty for {event}")
        for field in ("input_manifest_sha256", "reference_trace_sha256"):
            if not _SHA256.fullmatch(row[field]):
                raise TraceContractError(f"line {line}: invalid {field}")
        if source == "rtl_measured":
            _uint(row["cycle"], "cycle", line)
            if not row["rtl_commit"]:
                raise TraceContractError(f"line {line}: missing rtl_commit")
            rtl_commits.add(row["rtl_commit"])
        elif row["cycle"] or row["rtl_commit"]:
            raise TraceContractError(f"line {line}: software demo cannot claim RTL timing or commit")
        key = (row["case_id"], r, c, event, k)
        if key in events:
            raise TraceContractError(f"line {line}: duplicate event {key}")
        events[key] = row
    if len(rtl_commits) > 1:
        raise TraceContractError(f"{path}: multiple RTL commits in one compared trace")
    if not events and source == "software_candidate":
        raise TraceContractError(f"{path}: no comparable events")
    return events, sha256(raw).hexdigest(), len(records)


def _order(key: tuple) -> tuple:
    case, row, column, event, k = key
    return case, row, column, (0 if event == "mac" else 1), (-1 if k is None else k)


def _identity(key: tuple) -> dict:
    case, row, column, event, k = key
    return {"case_id": case, "row": row, "column": column,
            "event": event, "global_k": k}


def compare(expected_csv: Path, actual_csv: Path, *, case_id: str | None = None,
            compare_tile_id: bool = False) -> dict:
    """Return the first logical event mismatch under the draft 19-column schema.

    Clock timing is intentionally not checked: the RTL event-to-cycle contract
    and pipeline-valid mapping remain open. Actual rows may be PE-interleaved.
    """
    expected, expected_sha, _ = _load(Path(expected_csv), "software_candidate", case_id)
    actual, actual_sha, actual_rows = _load(Path(actual_csv), "rtl_measured", case_id)
    first = None
    for key in sorted(expected.keys() | actual.keys(), key=_order):
        exp, got = expected.get(key), actual.get(key)
        if exp is None or got is None:
            first = {**_identity(key), "field": "event", "expected": "<absent>" if exp is None else "<present>",
                     "actual": "<absent>" if got is None else "<present>",
                     "tile_id": int((got or exp)["tile_id"]),
                     "cycle": None if got is None else int(got["cycle"])}
            break
        for field in ("input_manifest_sha256", "reference_trace_sha256"):
            if exp[field].lower() != got[field].lower():
                raise TraceContractError(f"{_identity(key)}: provenance {field} differs")
        fields = (("tile_id",) if compare_tile_id else ()) + _WORD_FIELDS[key[3]]
        for field in fields:
            if exp[field].lower() != got[field].lower():
                first = {**_identity(key), "field": field,
                         "expected": exp[field].lower(), "actual": got[field].lower(),
                         "tile_id": int(got["tile_id"]),
                         "cycle": int(got["cycle"]), "rtl_commit": got["rtl_commit"]}
                break
        if first is not None:
            break
    return {
        "status": "BIT-EXACT-CANDIDATE" if first is None else "MISMATCH",
        "scope": "draft PE event-value comparison only; timing and RTL provenance require separate checks",
        "case_id_filter": case_id,
        "matched_event_identities": len(expected.keys() & actual.keys()),
        "expected_events": len(expected),
        "actual_events": len(actual),
        "actual_csv_rows": actual_rows,
        "expected_csv_sha256": expected_sha,
        "actual_csv_sha256": actual_sha,
        "first_mismatch": first,
    }


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--expected", required=True, type=Path)
    parser.add_argument("--actual", required=True, type=Path)
    parser.add_argument("--case-id", help="compare one case in a multi-case golden CSV")
    parser.add_argument("--compare-tile-id", action="store_true",
                        help="only after hardware and software agree on tile numbering")
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    try:
        result = compare(args.expected, args.actual, case_id=args.case_id,
                         compare_tile_id=args.compare_tile_id)
    except (OSError, TraceContractError) as exc:
        parser.error(str(exc))
    payload = json.dumps(result, indent=2, ensure_ascii=False) + "\n"
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(payload, encoding="utf-8")
    print(payload)
    if result["status"] != "BIT-EXACT-CANDIDATE":
        raise SystemExit(1)


if __name__ == "__main__":
    main()
