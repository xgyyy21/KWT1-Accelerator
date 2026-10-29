"""Build 32-bit-per-line files for the existing varied FFN1 testbench.

The primary images in this handoff are 16-bit-word .mem/.bin files. This
adapter does not compute expected results; it only changes text encoding.
"""

from pathlib import Path
import struct


ROOT = Path(__file__).resolve().parent
FILES = {
    "x": "x_fp32.mem",
    "w": "w_fp32.mem",
    "b": "bias_fp32.mem",
    "expected": "expected_fp32.mem",
}


def main():
    for source, target_name in FILES.items():
        data = (ROOT / f"{source}.bin").read_bytes()
        if len(data) % 4:
            raise ValueError(f"{source}.bin is not a sequence of FP32 words")
        bits = [value[0] for value in struct.iter_unpack("<I", data)]
        halfwords = [int(line, 16) for line in (ROOT / f"{source}.mem").read_text("ascii").splitlines()]
        if len(halfwords) != 2 * len(bits):
            raise ValueError(f"{source}.mem has an unexpected word count")
        if any((halfwords[2 * i] | (halfwords[2 * i + 1] << 16)) != value
               for i, value in enumerate(bits)):
            raise ValueError(f"{source}.mem and {source}.bin differ")
        output = "".join(f"{value:08x}\n" for value in bits).encode("ascii")
        target = ROOT / target_name
        if target.exists() and target.read_bytes() != output:
            raise FileExistsError(f"refusing to overwrite differing file: {target}")
        target.write_bytes(output)
        print(f"{target_name}: {len(bits)} FP32 words")


if __name__ == "__main__":
    main()
