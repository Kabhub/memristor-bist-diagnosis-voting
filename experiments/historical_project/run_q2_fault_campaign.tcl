# Run from the Vivado Tcl console after all design and simulation sources have
# been added to the project. The script selects the expanded research campaign,
# runs it to completion, and leaves the transcript in the Vivado project log.

set_property top tb_fault_campaign_q2_1153 [get_filesets sim_1]
update_compile_order -fileset sim_1
launch_simulation -simset sim_1 -mode behavioral
run all

puts "Q2 campaign complete. Confirm that the console reports all 1,153 scenarios passed."
