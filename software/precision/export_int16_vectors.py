"""Export the selected candidate's 12 FFN1 layers as 16-bit SRAM word images.

All addresses here are file-local word indices. No E203 physical address or
accelerator register mapping is inferred. Bias is signed INT32, low word first.
"""

from __future__ import annotations

import argparse
from hashlib import sha256
import json
from pathlib import Path

import numpy as np

from software.precision.int16_numeric import LayerFormat, evaluate_layer
from software.precision.int16_round01 import _samples
from software.precision.study import file_hash


def words_for_array(values: np.ndarray, bits: int) -> list[int]:
    flat = np.asarray(values, dtype=np.int64).ravel(order="C")
    if bits == 16:
        if np.any((flat < -(1 << 15)) | (flat > (1 << 15) - 1)):
            raise ValueError("value outside signed INT16")
        return [int(v) & 0xffff for v in flat]
    if bits == 32:
        if np.any((flat < -(1 << 31)) | (flat > (1 << 31) - 1)):
            raise ValueError("value outside signed INT32")
        words = []
        for value in flat:
            pattern = int(value) & 0xffffffff
            words.extend((pattern & 0xffff, pattern >> 16))
        return words
    raise ValueError("supported element widths: 16, 32")


def _write_words(path: Path, words: list[int]) -> dict[str, object]:
    payload = "".join(f"{word:04x}\n" for word in words).encode("ascii")
    path.write_bytes(payload)
    readback = [int(line, 16) for line in path.read_text(encoding="ascii").splitlines()]
    if readback != words:
        raise RuntimeError(f"word-image round-trip failed: {path}")
    return {"file": path.name, "sha256": sha256(payload).hexdigest(),
            "word_count": len(words), "byte_count": 2 * len(words)}


def export(input_root: Path, config_path: Path, output_dir: Path) -> dict[str, object]:
    samples = _samples(input_root)
    if len(samples) != 1:
        raise ValueError("this compact hardware handoff requires one explicitly identified sample")
    config = json.loads(config_path.read_text(encoding="utf-8"))
    if config.get("schema") != "kwt1-int16-round01-config-v1":
        raise ValueError("wrong INT16 config schema")
    name = config["selected_candidate"]
    formats = config["candidates"][name]
    if output_dir.exists() and any(output_dir.iterdir()):
        raise ValueError(f"preserving existing vector directory: {output_dir}")
    output_dir.mkdir(parents=True, exist_ok=True)
    sample = samples[0]
    layers = []
    for layer, data in enumerate(sample["layers"]):
        raw = formats[layer]
        w_frac = raw["w_frac"]
        fmt = LayerFormat(raw["x_frac"], tuple(w_frac) if isinstance(w_frac, list) else w_frac,
                          raw["y_frac"], raw["bias_bits"], raw["acc_bits"])
        result = evaluate_layer(data["x"], data["w"], data["b"], fmt)
        folder = output_dir / f"layer_{layer:02d}"
        folder.mkdir()
        files = {
            "x": _write_words(folder / "x.mem", words_for_array(result["x_q"], 16)),
            "w": _write_words(folder / "w.mem", words_for_array(result["w_q"], 16)),
            "bias": _write_words(folder / "bias.mem", words_for_array(result["bias_q"], 32)),
            "y_expected": _write_words(folder / "y_expected.mem", words_for_array(result["y_q"], 16)),
        }
        layers.append({"layer": layer, "source_npz_sha256": sample["layer_sha256"][layer],
                       "format": raw, "files": files, "saturation": result["saturation"]})
    manifest = {
        "schema": "kwt1-int16-ffn1-word-images-v1",
        "status": "software-generated INT16 Golden; RTL acceptance documented separately",
        "config_sha256": file_hash(config_path),
        "source_manifest_sha256": sample["manifest_sha256"],
        "source_id": sample["provenance"]["source_id"],
        "split": sample["provenance"]["split"],
        "candidate": name,
        "word_format": "one unsigned 4-hex-digit 16-bit word per line; two's-complement patterns",
        "x_layout": "X[99,64], row-major; one signed INT16 per word",
        "w_layout": "W[64,256], K-major then column; one signed INT16 per word",
        "bias_layout": "bias[256], signed INT32; low 16-bit word then high word",
        "y_layout": "Y[99,256], row-major; one signed INT16 per word",
        "addresses": "zero-based word indices within each file; physical addresses await hardware agreement",
        "layers": layers,
    }
    (output_dir / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    return manifest


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input-root", type=Path, required=True)
    parser.add_argument("--config", type=Path, required=True)
    parser.add_argument("--output-dir", type=Path, required=True)
    args = parser.parse_args()
    manifest = export(args.input_root, args.config, args.output_dir)
    print(f"wrote {len(manifest['layers'])} layers to {args.output_dir}")


if __name__ == "__main__":
    main()
