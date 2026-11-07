# INT16 FFN1: two held-out validation samples for RTL

This branch adds a small, self-checking handoff package. Its parent is the frozen
software commit `bbff21cfb836fcc2d81bb6d475ddc4f6e48a26d9`; the frozen
configuration and code are not changed.

## Download and reconstruct

The 2,591,933-byte ZIP was split into four binary parts solely to use the
available upload connection. Clone this branch and run from this directory:

```sh
sha256sum -c PARTS_SHA256SUMS.txt
cat sample_pack.zip.part00 sample_pack.zip.part01 sample_pack.zip.part02 sample_pack.zip.part03 > int16_ffn1_two_validation_samples_2026-11-07.zip
printf '%s  %s\n' 'e0fd382ee9fec8dfb5f42aa3205f0623241976a47953df62b446009a9e2c8ea7' 'int16_ffn1_two_validation_samples_2026-11-07.zip' | sha256sum -c -
unzip int16_ffn1_two_validation_samples_2026-11-07.zip -d int16_handoff
cd int16_handoff
sha256sum -c SHA256SUMS.txt
```

The package contains 2 selected WAVs, 12 layers per sample, and for each layer
`x.mem`, `w.mem`, `bias.mem`, `y_expected.mem`. The WAVs are provenance only;
RTL uses the `.mem` images directly. The top `manifest.json` gives source IDs,
shapes, out_shift, and hashes; each `images/manifest.json` gives exact per-layer
format and per-file hashes. No original audio library, TensorFlow environment,
or full layer NPZ archive is included.

- `sample_yes`: ordinary validation command.
- `sample_down_high_error`: highest layer-00 single-sample NRMSE among the
  separate 50-sample pre-contest screen; this sample exercises output saturation.
- Both are in the original Speech Commands V2 `validation_list.txt`, absent
  from `testing_list.txt`, and different from the calibration audio.
- Frozen INT16 config SHA-256:
  `38ccd1d37d2b442c5f1883684007c1eeeae6718ace2faa2e8ed9b98867a1ee1f`.
- Model source commit: `237e4097afd4f6851e0b82f0a8d65c2dfe8eae30`.
- RTL numeric baseline: `d7329f200832697a4946bada5b72bf7db5b4ed7c`.

Read the package's `README.md` for the memory word layout and RTL comparison
procedure. These are software-generated Golden vectors, not measured RTL
outputs, organizer 600-sample accuracy, or continuous full-network inference.

Original data source: Google Speech Commands V2,
`https://storage.googleapis.com/download.tensorflow.org/data/speech_commands_v0.02.tar.gz`.
