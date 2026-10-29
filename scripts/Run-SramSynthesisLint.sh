#!/usr/bin/env bash
# Frontend check only. No technology mapping, STA, or memory-macro timing.
set -euo pipefail
source_root=$(cygpath -u "$1")
out=$(cygpath -u "$2")
[[ ! -e "$out" ]] || { echo "Refusing to overwrite $out"; exit 2; }
mkdir -p "$out"
cd "$source_root"
verilator --version > "$out/tool_version.txt"
command=(verilator --lint-only --timing --assert -sv -DSYNTHESIS
  --top-module fp32_accelerator_top -GUSE_SRAM_MACROS=1
  -GSTRICT_COMPETITION_SHAPES=1 -f rtl/files.f)
printf '%q ' "${command[@]}" > "$out/command.txt"
printf '\n' >> "$out/command.txt"
set +e
"${command[@]}" > "$out/lint.log" 2>&1
result=$?
set -e
printf '%s\n' "$result" > "$out/exit_code.txt"
printf 'Lint exit=%s (warnings are fatal; inspect lint.log)\n' "$result"
# Preserve a nonzero lint result as data; the wrapper completed its logging.
