#!/usr/bin/env bash
set -euo pipefail

source_root=$(cygpath -u "$1")
top=$2
build_dir=$(cygpath -u "$3")
jobs=$4
mkdir -p "$build_dir"
cd "$source_root"

{
    printf 'source_root=%s\ntop=%s\n' "$source_root" "$top"
    date -u '+started_utc=%Y-%m-%dT%H:%M:%SZ'
    command -v verilator g++ make python3
    verilator --version
    g++ --version
    make --version
    python3 --version
} > "$build_dir/tool_versions.txt" 2>&1
pacman -Q > "$build_dir/msys2_packages.txt"

sources=()
if [[ "$top" == verilator_environment_smoke_tb ]]; then
    sources+=("tb/$top.sv")
else
    [[ -f rtl/files.f ]] || { echo 'Missing rtl/files.f'; exit 2; }
    [[ -f "tb/$top.sv" ]] || { echo "Missing tb/$top.sv"; exit 2; }
    sources+=(-f rtl/files.f "tb/$top.sv")
fi

{
    sha256sum "tb/$top.sv"
    if [[ "$top" != verilator_environment_smoke_tb ]]; then
        sha256sum rtl/files.f
        while IFS= read -r file || [[ -n "$file" ]]; do
            file=${file%$'\r'}
            [[ -z "$file" || "$file" == \#* || "$file" == //* ]] && continue
            sha256sum "$file"
        done < rtl/files.f
    fi
} > "$build_dir/source_sha256.txt"

# Retain all warnings in the log. They do not by themselves mean the test failed.
# Do not define SYNTHESIS: simulation-only safety checks must remain active.
# GCC 16/UCRT64 has a reported libstdc++ move-constructor link issue at -Os.
# Append -O2 to the C++ flags; do not patch RTL or disable its checks.
command=(verilator --binary --timing --assert -sv --top-module "$top"
         --Mdir "$build_dir/obj_dir" --output-groups 0 -j "$jobs" -Wno-fatal
         -CFLAGS -O2 "${sources[@]}")
printf '%q ' "${command[@]}" > "$build_dir/compile_command.txt"
printf '\n' >> "$build_dir/compile_command.txt"
set +e
"${command[@]}" > "$build_dir/compile.log" 2>&1
compile_rc=$?
set -e
printf '%s\n' "$compile_rc" > "$build_dir/compile_exit_code.txt"
if (( compile_rc != 0 )); then
    tail -n 70 "$build_dir/compile.log"
    exit "$compile_rc"
fi

binary="$build_dir/obj_dir/V$top.exe"
[[ -f "$binary" ]] || binary="$build_dir/obj_dir/V$top"
# Keep any TB-generated output files out of the source tree. Tests which read
# relative fixtures require those fixtures to be prepared in the run directory.
cd "$build_dir"
set +e
"$binary" > "$build_dir/simulate.log" 2>&1
simulate_rc=$?
set -e
printf '%s\n' "$simulate_rc" > "$build_dir/simulate_exit_code.txt"
cat "$build_dir/simulate.log"
exit "$simulate_rc"
