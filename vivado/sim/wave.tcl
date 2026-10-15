# ============================================================================
# wave.tcl
# Arranges the waveform of tb_takum_mul_wave in the Vivado simulator.
#
# After "Run Behavioral Simulation" has opened, type in the Tcl console:
#
#     source <repository>/vivado/sim/wave.tcl
#
# (create_project.tcl prints the exact line with your path.)
#
# It opens a new waveform window with the signals grouped and shown in a
# useful radix, including the internal (sign, lbar) of the chain, then restarts
# the simulation and runs it to the end, so every signal has its full history.
# ============================================================================

set tb /tb_takum_mul_wave

create_wave_config "takum multiplier N=8"

add_wave_divider "what is being tested"
add_wave $tb/phase
add_wave $tb/what
add_wave -radix unsigned $tb/index

add_wave_divider "operands: takum words and their values"
add_wave -radix bin $tb/a
add_wave -radix bin $tb/b
add_wave $tb/a_value
add_wave $tb/b_value

# lbar is fixed point with 3 fractional bits at N = 8, so the signed decimal
# shown here is 8 times the real lbar: 12 means 1.5, 18 means 2.25.
add_wave_divider "inside the chain: sign and lbar (divide by 8)"
add_wave $tb/dut/a_sign
add_wave -radix dec $tb/dut/a_lbar
add_wave $tb/dut/b_sign
add_wave -radix dec $tb/dut/b_lbar
add_wave $tb/dut/y_sign
add_wave -radix dec $tb/dut/y_lbar
add_wave $tb/dut/y_zero
add_wave $tb/dut/y_nar

add_wave_divider "result"
add_wave -radix bin $tb/y
add_wave -radix bin $tb/y_expected
add_wave $tb/exact_product
add_wave $tb/y_value
add_wave $tb/rel_error

add_wave_divider "checking"
add_wave $tb/match
add_wave -radix unsigned $tb/errors

restart
run all
