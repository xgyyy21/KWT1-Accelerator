# First DC session only. Library-writing mode must precede library reads.
set OUT [file normalize $env(KWT1_DC_OUT)]
set SRAM_LIB /storage1/2026contest/server3/s3_30usr/Desktop/admin_public_dir/SRAM_Lib_2025/RAMSP128X16/lib/RAMSP128X16_tt_1p10v_1p10v_25c.lib
if {[info exists env(KWT1_SRAM_LIB)]} { set SRAM_LIB $env(KWT1_SRAM_LIB) }
set LIB_NAME RAMSP128X16_tt_1p10v_1p10v_25c
set DB [file join $OUT ${LIB_NAME}.db]
if {[catch {
  enable_write_lib_mode
  if {![file readable $SRAM_LIB]} { error "SRAM Liberty is not readable" }
  read_lib $SRAM_LIB
  if {[sizeof_collection [get_lib_cells -quiet ${LIB_NAME}/RAMSP128X16]] != 1} {
    error "SRAM library cell is absent"
  }
  write_lib -format db -output $DB $LIB_NAME
  if {![file isfile $DB] || ![file readable $DB] || [file size $DB] == 0} {
    error "Private SRAM DB was not created"
  }
  puts "PREPARE_SRAM_DB_OK BYTES=[file size $DB]"
} reason]} {
  puts stderr "KWT1_PREPARE_FAIL REASON=$reason"
  exit 1
}
exit 0
