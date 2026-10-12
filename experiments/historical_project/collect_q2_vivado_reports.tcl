# Run this script from the Vivado Tcl console after opening the Q2 project.
# The design top must be zedboard_memristor_top and the target part must be
# xc7z020clg484-1.

set report_dir [file normalize "./q2_vivado_reports"]
file mkdir $report_dir

set_property top zedboard_memristor_top [get_filesets sources_1]

reset_run synth_1
launch_runs synth_1 -jobs 4
wait_on_run synth_1
open_run synth_1

report_utilization \
    -file [file join $report_dir post_synthesis_utilization.rpt]
report_timing_summary -report_unconstrained \
    -file [file join $report_dir post_synthesis_timing_summary.rpt]

reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
open_run impl_1

report_utilization -hierarchical \
    -file [file join $report_dir post_implementation_utilization.rpt]
report_timing_summary -delay_type min_max -report_unconstrained \
    -file [file join $report_dir post_implementation_timing_summary.rpt]
report_clock_utilization \
    -file [file join $report_dir clock_utilization.rpt]
report_methodology \
    -file [file join $report_dir methodology.rpt]
report_power \
    -file [file join $report_dir vectorless_power.rpt]

puts "Q2 Vivado reports written to: $report_dir"
