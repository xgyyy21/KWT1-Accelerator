# Hardware Import Handoff

## Scope

Imported the reviewed hardware work from the local project into the `hardware`
branch of `KWT1-Accelerator`.

- `rtl/`: 22 SystemVerilog source/file-list files
- `tb/`: 22 SystemVerilog testbenches
- `scripts/`: 2 PowerShell regression/vector scripts
- Total imported files: 46
- Source bytes: 81,848
- Source and destination SHA-256 comparison: 0 mismatches

No software sources were present in the local project. The following were
intentionally excluded: `build/`, `.tools/`, contest guidance materials,
images, generated simulation outputs, models, datasets, credentials, and
process-library files.

## Verification

Run on 2026-10-17 using the portable Icarus Verilog installation from the
original project:

- RTL regression: 22/22 testbenches passed
- SoC elaboration (`ai_engine_soc_adapter`): passed
- FP32 vector set: 20,441 pairs generated and checked by `fp32_math_tb`

The first run exposed a path-only issue: the regression wrapper generated
`build/fp32_vectors.txt` relative to the caller's original working directory,
while `fp32_math_tb` reads it relative to the shared checkout. The vector file
was explicitly generated in the shared checkout before the successful rerun.
No RTL source was changed to work around this issue.

## Reproduction

From the shared checkout, generate the ignored FP32 vector file first:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Generate-Fp32Vectors.ps1 -OutputPath .\build\fp32_vectors.txt
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Run-Regression.ps1 -Iverilog D:\competition\.tools\iverilog\bin\iverilog.exe -Vvp D:\competition\.tools\iverilog\bin\vvp.exe
```

## Not Yet Verified

- Synthesis and gate-level implementation
- Timing, area, and power reports
- FPGA/ASIC SoC integration with the team software
- Quantized model accuracy and end-to-end software execution

## Dependencies and Known Issues

- Windows PowerShell and Icarus Verilog are required for the supplied tests.
- The regression wrapper's relative FP32 vector generation should be made
  checkout-location independent before CI or clean-machine use.
- The imported RTL has not been modified or reformatted during onboarding.
