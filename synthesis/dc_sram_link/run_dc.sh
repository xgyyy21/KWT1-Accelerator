#!/bin/bash
set -u
set -o pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)" || exit 2
for cmd in dc_shell timeout sha256sum; do
  command -v "$cmd" >/dev/null 2>&1 || { printf 'DC_FAIL missing tool: %s\n' "$cmd"; exit 3; }
done
OUT="$(mktemp -d "$ROOT/results_XXXXXXXX")" || exit 4
export KWT1_DC_ROOT="$ROOT" KWT1_DC_OUT="$OUT"
cd "$OUT" || exit 5
printf 'RESULTS=%s\n' "$OUT"
printf 'dc_shell -no_gui -f %s/prepare_sram.tcl\ndc_shell -no_gui -f %s/check.tcl\n' "$ROOT" "$ROOT" > command.txt
printf 'PREP_TIMEOUT_SECONDS=60\nCHECK_TIMEOUT_SECONDS=120\nVIRTUAL_MEMORY_KIB=4194304\n' > limits.txt
ulimit -v 4194304 || { echo 'DC_FAIL could not apply memory limit'; exit 6; }
sha256sum "$ROOT/check.tcl" "$ROOT/prepare_sram.tcl" "$ROOT/run_dc.sh" "$ROOT"/rtl/*.sv > inputs.sha256
timeout --signal=TERM --kill-after=10s 60s dc_shell -no_gui -f "$ROOT/prepare_sram.tcl" 2>&1 | tee prepare.log
prep_codes=("${PIPESTATUS[@]}")
printf '%s\n' "${prep_codes[0]}" > prepare_exit_code.txt
if [[ "${prep_codes[0]}" != 0 || "${prep_codes[1]}" != 0 ]] || ! grep -q '^PREPARE_SRAM_DB_OK ' prepare.log; then
  printf 'STATUS=FAIL\nREASON=sram_db_prepare_failed\n' > summary.txt
  echo "DC_FAIL sram_db_prepare_failed results=$OUT"
  exit 1
fi
timeout --signal=TERM --kill-after=10s 120s dc_shell -no_gui -f "$ROOT/check.tcl" 2>&1 | tee run.log
codes=("${PIPESTATUS[@]}")
printf '%s\n' "${codes[0]}" > dc_exit_code.txt
printf '%s\n' "${codes[1]}" > tee_exit_code.txt
fail() {
  printf 'STATUS=FAIL\nREASON=%s\n' "$1" > summary.txt
  printf 'DC_FAIL %s results=%s\n' "$1" "$OUT"
  exit 1
}
[[ "${codes[0]}" == 0 && "${codes[1]}" == 0 ]] || fail "tool_or_logging_exit_nonzero"
[[ ! -e failure.txt ]] || fail "tcl_failure"
# Scan actual diagnostics, not just success strings or a macro name count.
if grep -Ein '^[[:space:]]*(Error:|Fatal:)|^[[:space:]]*Warning:.*(unresolved|[Uu]nable to resolve|[Cc]annot find.*design|LINK-5|UID-341|LBR-1)' prepare.log run.log > diagnostics_failure.txt; then
  fail "unresolved_reference_or_tool_error"
fi
for f in checks.txt sram_macro_check.ddc sram_macro_check_netlist.v check_design_pre.rpt check_design_post.rpt references_pre.rpt references_post.rpt macro_instances_pre.txt macro_instances_post.txt loaded_libraries.rpt; do
  [[ -s "$f" ]] || fail "missing_or_empty_$f"
done
grep -qx 'STATUS=STRUCTURAL_CHECKS_COMPLETED' checks.txt || fail "checks_not_completed"
grep -qx 'MACRO_COUNT_PRE=24' checks.txt || fail "wrong_pre_count"
grep -qx 'MACRO_COUNT_POST=24' checks.txt || fail "wrong_post_count"
[[ "$(wc -l < macro_instances_pre.txt)" == 24 ]] || fail "wrong_pre_instance_list"
[[ "$(wc -l < macro_instances_post.txt)" == 24 ]] || fail "wrong_post_instance_list"
grep -q '^KWT1_DC_STRUCTURAL_CHECKS_COMPLETED$' run.log || fail "missing_completion_marker"
printf 'STATUS=PASS\nSCOPE=legacy_3_bank_library_link_and_macro_preservation_only\n' > summary.txt
grep -v '^STATUS=' checks.txt >> summary.txt
sha256sum sram_macro_check.ddc sram_macro_check_netlist.v checks.txt run.log > outputs.sha256
echo "DC_LINK_MACRO_PASS results=$OUT"
