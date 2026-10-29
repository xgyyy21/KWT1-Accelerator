# KWT-1 Real Layer 00 FFN1 RTL Result

Date: 2026-10-23 (Asia/Shanghai). Hardware-side functional simulation; not software-owner independent acceptance.

## Result

- Task: `X[99,64] x W[64,256] + bias[256] -> Y[99,256]`, one real model encoder layer 00 FFN1.
- Simulator exit: `0`; compile exit: `0`; checker exit: `0`.
- Outputs: **25,344/25,344** matched software expected bits; first difference: `None`.
- Writeback: **50,688** halfwords verified for address, coordinates, low/high order, data, uniqueness and final-memory agreement.
- Tiling: **208** tiles; **2** K-block descriptors per tile; **3** final valid rows.
- Input reads: `642,048` halfwords. Last accepted write cycle `2587777`; DONE cycle `2587779`.
- Wall runtime: `8668.125` seconds; simulated wait cycles: `2,587,777`.

## Data And Source Identity

- Software ZIP SHA-256: `5504f7b2e77be9350cc6da40d4a122d892084486d5b57cd0553ffb9550ff8147`.
- The X/W/bias loaded into the RTL memory model were recombined and matched to the supplied binary tensors. Expected binary SHA-256: `24c84d16792bd5ab10bedfce5ebfd84a6305495477672d3144044e1ce33a51c5`.
- RTL/TB source-manifest SHA-256: `81a87f9e2488b8cca687006235d0abb83dbce6720786b719cceeca43b54e63e4`. The project root is not a Git worktree, so sources are identified by file hashes rather than a commit id.
- Compiled VVP SHA-256: `85c98034e10213941f948fd965e0762b34de79bf17a470e1d530040adbdfc3d0`. Actual vvp log SHA-256: `f560ff80cc8ad669e601565256c016a96424afa603be687adf85849c09cc35ba`.
- Frozen local FP32 reference SHA-256: `45daa2c620dcd512ffa2380141cf762477ea25846fc0328027827cfa3842fefb`; all `25,344` expected values recomputed with zero differences.

## Scope And Remaining Confirmation

This establishes hardware-side functional behavior for one FFN1 layer on a protocol-neutral RTL top. The software teammate must independently review this run and its hashes. It does not establish full 12-layer inference, FFN2, verified validation-set accuracy, E203/NICE integration, CPU cache visibility, physical SRAM, 150 MHz timing, area, power, or formal PPA.

The Icarus compile log contains simulation `$fatal` synthesis warnings. Compile and simulation succeeded; synthesis/PPA was not run.

## Replay

See `README.md` for input format and replay instructions. Run the archived `Check-RealFfn1Layer00.py` to verify actual outputs against `inputs/expected.bin`; do not rely on the CSV `match` field.

Evidence checksums are in `SHA256SUMS.txt`; ZIP archive SHA-256 is reported in the accompanying handoff note.
