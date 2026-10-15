# ============================================================================
# create_project.tcl
# Creates a Vivado project with everything needed to simulate and synthesise
# the takum multiplier, already configured:
#
#   - the six design files from rtl/ and the synthesis wrapper, as VHDL 2008
#   - the timing constraints
#   - the N = 8 waveform testbench as the simulation top, running to the end
#   - synthesis of the full chain at N = 16, out of context
#
# Use it from Vivado's start screen: Tools > Run Tcl Script... and pick this
# file. Or from a terminal: vivado -mode gui -source create_project.tcl
#
# The project is created in vivado/project/ (ignored by git). The source files
# are referenced where they are, not copied, so editing rtl/ edits the project.
# Running the script again deletes that project and starts from scratch.
# ============================================================================

set here     [file dirname [file normalize [info script]]]
set root     [file normalize [file join $here ..]]
set proj_dir [file join $here project]

create_project takum_mul $proj_dir -part xc7a100tcsg324-1 -force

# ---- design sources: used by synthesis and by simulation -------------------
add_files -fileset sources_1 -norecurse [list \
  [file join $root rtl codec predecoder.vhd] \
  [file join $root rtl codec decoder_logarithmic.vhd] \
  [file join $root rtl codec postencoder.vhd] \
  [file join $root rtl codec encoder_logarithmic.vhd] \
  [file join $root rtl takum_mul_log.vhd] \
  [file join $root rtl takum_mul_top.vhd] \
  [file join $here synth takum_mul_synth_wrapper.vhd] ]

# ---- constraints ------------------------------------------------------------
add_files -fileset constrs_1 -norecurse [file join $here synth nexys_a7.xdc]

# ---- simulation-only source -------------------------------------------------
add_files -fileset sim_1 -norecurse [file join $here sim tb_takum_mul_wave.vhd]

# Every VHDL file in the project is VHDL-2008.
set_property file_type {VHDL 2008} [get_files *.vhd]

# ---- synthesis: full chain at N = 16, out of context ------------------------
# Change N and USE_CHAIN (1 = chain, 0 = multiplier alone) in
# Settings > General > Generics/Parameters.
set_property top takum_mul_synth_wrapper [get_filesets sources_1]
set_property generic {N=16 USE_CHAIN=1} [get_filesets sources_1]
set_property -name {STEPS.SYNTH_DESIGN.ARGS.MORE OPTIONS} \
             -value {-mode out_of_context} -objects [get_runs synth_1]

# ---- simulation: the waveform testbench, run to the end ---------------------
set_property top tb_takum_mul_wave [get_filesets sim_1]
set_property top_lib xil_defaultlib [get_filesets sim_1]
set_property -name {xsim.simulate.runtime} -value {all} -objects [get_filesets sim_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts ""
puts "Project ready: $proj_dir"
puts "To see the waveform: Run Behavioral Simulation, then type in this console:"
puts "    source [file join $here sim wave.tcl]"
puts ""
