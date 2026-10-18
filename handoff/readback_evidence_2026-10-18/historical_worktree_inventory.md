# Hardware Worktree Inventory

Generated 2026-10-17 for the local word-readback work. No reset, checkout, clean, commit, or push was performed.

- Repository: `D:\KWT1-Accelerator-shared`
- Branch: `hardware`
- Base commit: `6e0bd881b6acde166ea86636307ac5c69207a57d`
- State: dirty worktree; all pre-existing modifications and untracked files were preserved.
- Simulator: `D:\competition\.tools\iverilog\bin\iverilog.exe`, Icarus Verilog 14.0 (devel).

## Existing Worktree Changes

Modified tracked files:

- `rtl/ai_engine_tile_loop.sv`
- `rtl/files.f`
- `rtl/pe_array_8x16.sv`
- `rtl/systolic_array_8x16.sv`
- `rtl/systolic_tile_engine.sv`
- `tb/ai_engine_tile_loop_tb.sv`
- `tb/pe_array_8x16_tb.sv`
- `tb/systolic_array_8x16_tb.sv`
- `tb/systolic_array_reference_tb.sv`

Untracked files:

- `rtl/ai_engine_cache_soc_adapter.sv`
- `rtl/ai_engine_tiled_executor.sv`
- `rtl/fp32_pe_mac.sv`
- `tb/ai_engine_cache_soc_adapter_tb.sv`
- `tb/ai_engine_tiled_executor_tb.sv`
- `tb/word_readback_tb.sv`

## Source Fingerprints

The aggregate RTL/TB snapshot ID recorded in the readback CSV is
`7c42767dfe3a7be8b39a93d3dbb2e6322c3b3bf0b4fe48c99a2bb6b8fe2bd4fd`.
It is SHA-256 over sorted `rtl/` and `tb/` `.sv`, `.v`, and `.f` entries, each
formatted as `<file SHA-256><two spaces><repo-relative path>`, joined by LF.

Key source and test fingerprints at generation time:

| File | SHA-256 |
| --- | --- |
| `rtl/ai_engine_cache_soc_adapter.sv` | `846a7854d051f94b6847d3c0fc6c993187e624aa0f6d9e073d686714b2f3750c` |
| `rtl/ai_engine_tile_loop.sv` | `50a17fb0a4406151f741a2076a2047194dcc39c2da247464012d8b498eb48a9c` |
| `rtl/ai_engine_tiled_executor.sv` | `a8974bffcdf34335d2dc063d15d6f7a00b8dd83176332413a7b168e0e3505573` |
| `rtl/files.f` | `8eb4001dedac2adfada2342d63143ba53687339f6f051419ba93b126d818d9a8` |
| `rtl/fp32_pe_mac.sv` | `a2c50a912107aaf4f04f8f1cee35915973df6211ff450b114bd2d84fd01ea5ee` |
| `rtl/matrix_cache_manager.sv` | `ad1db76b9df18621d31ae8aae11c9bc5ee30e7dd1baa2caaf7dd3cd4680f8838` |
| `rtl/pe_array_8x16.sv` | `b52e0384c890b8e6b8111ed7a9d8581af91cf7cbb737c0074568ab99db6c08cb` |
| `rtl/systolic_array_8x16.sv` | `0fd4a08515887af4ef32d5cd61701cdb5dc587dcfd644ac06b3bfbf372460a85` |
| `rtl/systolic_tile_engine.sv` | `07802069dfb7bc71e2f97f190bcfda4f087478276d1e7554d015cf5bc9a76135` |
| `tb/ai_engine_cache_soc_adapter_tb.sv` | `be925dbe3f1d36b60b370b219358d6a64fa9a014f010e2b37f9233274ff51c99` |
| `tb/ai_engine_tile_loop_tb.sv` | `29c5e66450b6d84b0153c379c08509e2c5d23d4744df3720b8c5d290dcca79ca` |
| `tb/ai_engine_tiled_executor_tb.sv` | `138af8800fb5945545f8c756edc17caaec6627963d95ccde3807aa730e3f56ca` |
| `tb/pe_array_8x16_tb.sv` | `50891d56e27d17cddb375684d7b24ca25b386163abfaa4b9e42f7b098af11764` |
| `tb/systolic_array_8x16_tb.sv` | `46b05bfd8457425ef519b8dea4809fc45e3d0f447c06f4a196419b1075830708` |
| `tb/systolic_array_reference_tb.sv` | `2d95adea91e4873dcef9bbe2a4f9ffdcbba31c4d5c85da9d8778caf75339691c` |
| `tb/word_readback_tb.sv` | `d2e4dd150409a897e1140cd1f6ddc935972861c217e13ff3e0f1714e612bd382` |

## Readback Result

- Testbench: `tb/word_readback_tb.sv`
- Top: `word_readback_tb`
- Compile: `iverilog -g2012 -s word_readback_tb -o word_readback_tb.vvp rtl/matrix_cache_manager.sv tb/word_readback_tb.sv`
- Run: `vvp word_readback_tb.vvp` with output path, sample directory, base revision, snapshot fingerprint, and input `.bin` SHA-256 values supplied as plusargs.
- Result: PASS for all 144 tensor-element rows. CSV has 20 columns; both 16-bit reads for every element returned one cycle after request; each pair matched the source `.mem` words and reconstructed the expected 32-bit word.
- The nine sample `.mem` files were also independently checked against their corresponding `.bin` byte sequences; all matched.
- CSV: [word_readback.csv](/D:/competition/handoff/word_readback.csv)
- CSV SHA-256: `d7ba2ee7ae5678552899008b292398df861a6da28d06fa13bfa28dd53e732a1b`

This is a targeted cache-manager readback test only. It is not a full RTL regression and does not verify FP32 PE computation.
