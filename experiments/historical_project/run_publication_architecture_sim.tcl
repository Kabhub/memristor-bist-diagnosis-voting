# Run from the Vivado Tcl console after adding the publication sources.
# This verifies the common 8-bit BIST sequence for the unprotected,
# conventional-TMR, and proposed diagnosis-guided architectures.

set_property top tb_publication_architecture_comparison [get_filesets sim_1]
update_compile_order -fileset sim_1
launch_simulation -simset sim_1 -mode behavioral
run all

puts "Confirm: ALL PUBLICATION ARCHITECTURE COMPARISON TESTS PASSED"
