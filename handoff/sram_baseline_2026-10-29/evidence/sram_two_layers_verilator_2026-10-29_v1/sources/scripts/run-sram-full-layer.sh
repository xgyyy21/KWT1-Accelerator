#!/usr/bin/env bash
set -euo pipefail
source_root=$(cygpath -u "$1")
build_dir=$(cygpath -u "$2")
mode="$3"
if [[ -z "$mode" ]]; then mode="full"; fi
cd "$source_root"
{
    date -u '+started_utc=%Y-%m-%dT%H:%M:%SZ'
    verilator --version
    g++ --version
    make --version
} > "$build_dir/tool_versions.txt" 2>&1
pacman -Q > "$build_dir/msys2_packages.txt"
if [[ "$mode" == "two" ]]; then
    shape_arg="-GTWO_LAYERS=1"
elif [[ "$mode" == "second" ]]; then
    shape_arg="-GSECOND_LAYER=1"
else
    shape_arg="-GFULL_LAYER=1"
fi
command=(verilator --binary --timing --assert -sv
    --top-module fp32_sram_accelerator_top_tb "$shape_arg"
    --Mdir "$build_dir/obj_dir" --output-groups 0 -j 2 -Wno-fatal
    -CFLAGS -O2 -f rtl/files.f
    tb/support/ramsp128x16_functional_model.sv tb/fp32_sram_accelerator_top_tb.sv)
printf '%q ' "${command[@]}" > "$build_dir/compile_command.txt"
printf '\n' >> "$build_dir/compile_command.txt"
set +e
"${command[@]}" > "$build_dir/compile.log" 2>&1
compile_rc=$?
set -e
printf '%s\n' "$compile_rc" > "$build_dir/compile_exit_code.txt"
if ((compile_rc!=0)); then tail -n 50 "$build_dir/compile.log"; exit "$compile_rc"; fi
binary="$build_dir/obj_dir/Vfp32_sram_accelerator_top_tb.exe"
[[ -f "$binary" ]] || binary="$build_dir/obj_dir/Vfp32_sram_accelerator_top_tb"
cd "$build_dir"
run_args=("+OUT_DIR=$(cygpath -m "$build_dir")")
printf '%q ' "$binary" "${run_args[@]}" > simulation_command.txt
printf '\n' >> simulation_command.txt
set +e
"$binary" "${run_args[@]}" > simulation.log 2>&1
simulation_rc=$?
set -e
printf '%s\n' "$simulation_rc" > simulation_exit_code.txt
tail -n 5 simulation.log
exit "$simulation_rc"
