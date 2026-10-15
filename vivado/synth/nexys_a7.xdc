# ============================================================================
# nexys_a7.xdc
# Timing constraints for measuring the takum multiplier on a Nexys A7
# (Artix-7 xc7a100tcsg324-1).
#
# Only the clock matters. The measurement is out of context: the data ports are
# not connected to pins, because what is measured is the logic between the
# input and output registers of takum_mul_synth_wrapper, not a board demo. For
# the same reason no pin is assigned to the clock either.
#
# Keep the period at 10 ns (100 MHz, the board oscillator) for every design
# that is compared: the maximum frequency is read from the slack as
# Fmax = 1000 / (10 - WNS). build.tcl reads this file before synthesis, so a
# different value here would change its runs too. See vivado/README.md.
# ============================================================================

create_clock -name sys_clk -period 10.000 -waveform {0 5.000} [get_ports clk]

# Out of context there is no clock buffer, so tell Vivado where the clock would
# come from in a real design (a global buffer). Without this, it routes the
# clock as an ordinary net and the timing it reports is not realistic.
set_property HD.CLK_SRC BUFGCTRL_X0Y0 [get_ports clk]

# Inputs and outputs are not timed against anything outside the design.
set_false_path -from [get_ports -filter {DIRECTION == IN && NAME != clk}]
set_false_path -to   [get_ports -filter {DIRECTION == OUT}]

# Configuration bank voltage of the Nexys A7 (3.3 V). It does not affect the
# measurements; it only silences the CFGBVS-1 warning of the DRC report.
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
