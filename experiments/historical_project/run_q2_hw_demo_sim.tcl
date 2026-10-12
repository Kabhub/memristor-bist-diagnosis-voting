# Run this script from the Vivado Tcl console after adding all design and
# simulation sources. It selects the double-fault ZedBoard testbench and runs
# all six representative hardware-demo cases.

set_property top tb_zedboard_memristor_q2_demo_top [get_filesets sim_1]
update_compile_order -fileset sim_1
launch_simulation -simset sim_1 -mode behavioral
run all

puts "Q2 hardware-demo simulation complete. Confirm that all 6 cases passed."
