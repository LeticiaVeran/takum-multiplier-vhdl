# ============================================================================
# build.tcl
# Out-of-context synthesis and implementation of the takum multiplier, to get
# area, timing and power numbers. Run it from this folder:
#
#   vivado -mode batch -source build.tcl -tclargs <N> [chain|mul] [period_ns] [nodsp]
#
#   N          takum width: 8, 16, 32, 64 ...
#   chain|mul  chain (default): decoder + multiplier + encoder, the whole unit
#              mul: the multiplier alone, the counterpart of a posit multiplier
#              core without its codec
#   period_ns  clock period to constrain, default 10.0 (100 MHz)
#   nodsp      optional: forbid DSP blocks, so everything is built from LUTs
#
# Examples:
#   vivado -mode batch -source build.tcl -tclargs 16
#   vivado -mode batch -source build.tcl -tclargs 16 mul
#   vivado -mode batch -source build.tcl -tclargs 32 chain 5.0
#   vivado -mode batch -source build.tcl -tclargs 16 mul 10.0 nodsp
#
# Why out of context (-mode out_of_context): the wrapper has 6N + 22 ports,
# more than the 210 pins of the Nexys A7 from N = 32 on, and with real pins the
# input registers would sit next to scattered I/O pads, so the timing would
# measure wires across the chip instead of the multiplier. Out of context there
# are no pins: the reported path runs from the input registers to the output
# registers, through the logic under study.
#
# Reports land in reports/. The numbers that matter are printed at the end,
# followed by a row ready to paste into results.md.
# ============================================================================

set n       [lindex $argv 0]
set variant [lindex $argv 1]
set period  [lindex $argv 2]
set dsp     [lindex $argv 3]

if {$n == ""}       { set n 16 }
if {$variant == ""} { set variant "chain" }
if {$period == ""}  { set period 10.0 }
if {$variant ne "chain" && $variant ne "mul"} {
  error "variant must be 'chain' or 'mul', got '$variant'"
}

# Nexys A7-100T. For the A7-50T use xc7a50tcsg324-1.
set part "xc7a100tcsg324-1"

set use_chain [expr {$variant eq "chain" ? 1 : 0}]
set run_name  "${variant}_n${n}"
if {$dsp eq "nodsp"} { append run_name "_nodsp" }

# Paths are taken relative to this script, so it works from any folder.
set here [file dirname [file normalize [info script]]]
set root [file normalize [file join $here .. ..]]
set reports [file join $here reports]
file mkdir $reports

# ---- sources: the design (rtl/) and the measurement wrapper (this folder) ----
read_vhdl -vhdl2008 [list \
  [file join $root rtl codec predecoder.vhd] \
  [file join $root rtl codec decoder_logarithmic.vhd] \
  [file join $root rtl codec postencoder.vhd] \
  [file join $root rtl codec encoder_logarithmic.vhd] \
  [file join $root rtl takum_mul_log.vhd] \
  [file join $root rtl takum_mul_top.vhd] \
  [file join $here takum_mul_synth_wrapper.vhd] ]

read_xdc [file join $here nexys_a7.xdc]

# ---- synthesis and implementation -------------------------------------------
set synth_args [list -top takum_mul_synth_wrapper -part $part -mode out_of_context \
                     -generic N=$n -generic USE_CHAIN=$use_chain]
if {$dsp eq "nodsp"} { lappend synth_args -max_dsp 0 }
synth_design {*}$synth_args

# The requested period replaces the 10 ns of the XDC.
create_clock -name sys_clk -period $period [get_ports clk]

opt_design
place_design
phys_opt_design
route_design

# ---- reports ----------------------------------------------------------------
report_utilization                -file [file join $reports ${run_name}_utilization.rpt]
report_utilization -hierarchical  -file [file join $reports ${run_name}_utilization_hier.rpt]
report_timing_summary             -file [file join $reports ${run_name}_timing.rpt]
report_timing -max_paths 10 -nworst 1 -delay_type max \
                                  -file [file join $reports ${run_name}_paths.rpt]
report_power                      -file [file join $reports ${run_name}_power.rpt]

# ---- the numbers that matter --------------------------------------------------
set wns   [get_property SLACK [get_timing_paths -delay_type max]]
set delay [expr {$period - $wns}]
set fmax  [expr {1000.0 / $delay}]

set luts  [llength [get_cells -hierarchical -filter {PRIMITIVE_GROUP == LUT}]]
set ffs   [llength [get_cells -hierarchical -filter {PRIMITIVE_GROUP == FLOP_LATCH}]]
set carry [llength [get_cells -hierarchical -filter {REF_NAME == CARRY4}]]
set dsps  [llength [get_cells -hierarchical -filter {REF_NAME =~ DSP48*}]]

# Slice LUTs as the utilisation report counts them (two small functions can
# share one physical LUT, so this can be lower than the LUT cell count).
set slice_luts "?"
regexp {Slice LUTs\*?\s*\|\s*(\d+)} [report_utilization -return_string] -> slice_luts

set dyn_power "?"
regexp {Dynamic \(W\)\s*\|\s*([0-9.]+)} [report_power -return_string] -> dyn_power

puts "-----------------------------------------------------------------"
puts "run          : $run_name on $part"
puts "period       : $period ns"
puts "WNS          : $wns ns"
puts "path delay   : [format %.3f $delay] ns   (period - WNS)"
puts "Fmax         : [format %.1f $fmax] MHz"
puts "Slice LUTs   : $slice_luts   (LUT cells: $luts)"
puts "CARRY4       : $carry"
puts "DSP blocks   : $dsps"
puts "flip-flops   : $ffs   (mostly the wrapper's own registers)"
puts "dynamic power: $dyn_power W   (vectorless estimate)"
puts "-----------------------------------------------------------------"
puts "row for results.md:"
puts "| $n | $slice_luts | $carry | $dsps | $ffs | [format %.3f $delay] | [format %.1f $fmax] | $dyn_power |"
puts "-----------------------------------------------------------------"
