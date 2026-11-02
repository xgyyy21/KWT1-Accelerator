# DC structural macro-link test. Run through run_dc.sh in a private directory.
set ROOT [file normalize $env(KWT1_DC_ROOT)]
set OUT [file normalize $env(KWT1_DC_OUT)]
set STAGE startup

proc require_file {path} {
  if {![file readable $path] || ![file isfile $path] || [file size $path] == 0} {
    error "Required nonempty file is not readable: $path"
  }
}

proc require_true {value description} {
  if {![string is boolean -strict $value]} {
    error "$description returned a non-Boolean result: <$value>"
  }
  if {!$value} { error "$description returned failure" }
}

proc validate_design {tag} {
  global OUT
  set ok 0
  redirect -file [file join $OUT check_design_${tag}.rpt] {
    set ok [check_design]
  }
  require_true $ok "check_design ($tag)"
  redirect -file [file join $OUT references_${tag}.rpt] { report_reference }
}

proc validate_macros {tag} {
  global OUT
  set cells [get_cells -quiet -hierarchical -filter {ref_name == RAMSP128X16}]
  set leaves [get_cells -quiet -hierarchical -filter {ref_name == RAMSP128X16 && is_hierarchical == false}]
  set count [sizeof_collection $cells]
  set leaf_count [sizeof_collection $leaves]
  puts "MACRO_COUNT_${tag}=$count"
  puts "MACRO_LEAF_COUNT_${tag}=$leaf_count"
  if {$count != 24 || $leaf_count != 24} {
    error "Expected exactly 24 RAMSP128X16 leaf cells ($tag); got $count instances / $leaf_count leaves"
  }
  set fp [open [file join $OUT macro_instances_${tag}.txt] w]
  foreach_in_collection cell $cells {
    puts $fp "[get_object_name $cell] [get_attribute $cell ref_name]"
  }
  close $fp
  return $cells
}

proc run_checks {} {
  global ROOT OUT STAGE env
  set TOP sram_macro_check_top
  set STD_DB /storage1/2026contest/server3/s3_30usr/kwt1_smic40_lib/S40/smic/SCC40NLL_VHSC40_RVT_V0.1/SCC40NLL_VHSC40_RVT_V0p1/liberty/1.1v/scc40nll_vhsc40_rvt_tt_v1p1_25c_basic.db
  set SRAM_LIB /storage1/2026contest/server3/s3_30usr/Desktop/admin_public_dir/SRAM_Lib_2025/RAMSP128X16/lib/RAMSP128X16_tt_1p10v_1p10v_25c.lib
  if {[info exists env(KWT1_STD_DB)]} { set STD_DB $env(KWT1_STD_DB) }
  if {[info exists env(KWT1_SRAM_LIB)]} { set SRAM_LIB $env(KWT1_SRAM_LIB) }
  set SRAM_LOGICAL_LIB RAMSP128X16_tt_1p10v_1p10v_25c
  set SRAM_DB [file join $OUT ${SRAM_LOGICAL_LIB}.db]
  set sources [list [file join $ROOT rtl sram_1024x16_adapter.sv] \
                    [file join $ROOT rtl sram_fp32_cache_adapter.sv] \
                    [file join $ROOT rtl sram_macro_check_top.sv]]

  set STAGE inputs
  foreach f [concat [list $STD_DB $SRAM_LIB] $sources] { require_file $f }
  define_design_lib WORK -path [file join $OUT WORK]
  set_app_var search_path [concat [list [file join $ROOT rtl] [file dirname $STD_DB] $OUT] [get_app_var search_path]]

  set STAGE load_standard_db
  read_db $STD_DB
  set STD_LOGICAL_LIB [file rootname [file tail $STD_DB]]
  if {[info exists env(KWT1_STD_LIB_NAME)]} { set STD_LOGICAL_LIB $env(KWT1_STD_LIB_NAME) }
  if {[sizeof_collection [get_libs -quiet $STD_LOGICAL_LIB]] != 1} {
    error "Expected standard-cell logical library was not loaded: $STD_LOGICAL_LIB"
  }
  set STAGE load_private_sram_db
  require_file $SRAM_DB
  read_db $SRAM_DB
  if {[sizeof_collection [get_libs -quiet $SRAM_LOGICAL_LIB]] != 1} {
    error "Expected the documented SRAM logical library name: $SRAM_LOGICAL_LIB"
  }

  # Only standard cells are synthesis targets. SRAM is a linked macro.
  set_app_var target_library [list $STD_DB]
  set_app_var link_library [list * $STD_DB $SRAM_DB]
  redirect -file [file join $OUT loaded_libraries.rpt] { list_libs }
  set lib_cell [get_lib_cells -quiet ${SRAM_LOGICAL_LIB}/RAMSP128X16]
  if {[sizeof_collection $lib_cell] != 1} {
    error "Expected exactly one RAMSP128X16 cell in the loaded SRAM library"
  }
  puts "SRAM_LIB_CELL=[get_object_name $lib_cell]"

  set STAGE analyze
  require_true [analyze -format sverilog $sources] analyze
  set STAGE elaborate
  elaborate $TOP
  current_design $TOP
  set STAGE link_before_compile
  require_true [link] link_before_compile
  validate_design pre
  set macros_pre [validate_macros pre]
  set_dont_touch $macros_pre true

  # Small legacy 3-bank harness only: no PE array, clock target or STA.
  set STAGE structural_compile
  require_true [compile] compile
  set STAGE link_after_compile
  require_true [link] link_after_compile
  validate_design post
  validate_macros post

  set STAGE write_outputs
  write -format ddc -hierarchy -output [file join $OUT sram_macro_check.ddc]
  write -format verilog -hierarchy -output [file join $OUT sram_macro_check_netlist.v]
  foreach f [list sram_macro_check.ddc sram_macro_check_netlist.v \
                  check_design_pre.rpt check_design_post.rpt references_pre.rpt references_post.rpt] {
    require_file [file join $OUT $f]
  }
  set fp [open [file join $OUT checks.txt] w]
  puts $fp "STATUS=STRUCTURAL_CHECKS_COMPLETED"
  puts $fp "SCOPE=legacy_3_bank_library_link_and_macro_preservation"
  puts $fp "STD_DB=$STD_DB"
  puts $fp "SRAM_LIB=$SRAM_LIB"
  puts $fp "PRIVATE_SRAM_DB=$SRAM_DB"
  puts $fp "SRAM_CELL=[get_object_name $lib_cell]"
  puts $fp "MACRO_COUNT_PRE=24"
  puts $fp "MACRO_COUNT_POST=24"
  close $fp
  set STAGE completed
  puts "KWT1_DC_STRUCTURAL_CHECKS_COMPLETED"
}

if {[catch {run_checks} reason details]} {
  set fp [open [file join $OUT failure.txt] w]
  puts $fp "STATUS=FAIL"
  puts $fp "STAGE=$STAGE"
  puts $fp "REASON=$reason"
  if {[dict exists $details -errorinfo]} { puts $fp [dict get $details -errorinfo] }
  close $fp
  puts stderr "KWT1_DC_FAIL STAGE=$STAGE REASON=$reason"
  exit 1
}
exit 0
