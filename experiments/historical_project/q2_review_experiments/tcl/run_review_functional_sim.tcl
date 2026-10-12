# Vivado/xsim functional checks for the new reviewer experiment RTL.
set script_dir [file dirname [file normalize [info script]]]
set project_root [file normalize [file join $script_dir .. ..]]
set review_root [file normalize [file join $script_dir ..]]
set log_root [file join $review_root review_results simulation]
file mkdir $log_root

set design_files [list \
    [file join $project_root publication_scalable_memristor_core.sv] \
    [file join $review_root rtl review_tmr_baselines.sv] \
    [file join $review_root rtl review_secded_memory.sv] \
    [file join $review_root rtl review_data_preserving_bist_core.sv] \
    [file join $review_root rtl review_synthesis_wrappers.sv]]

set tests [list \
    [list tb_review_baselines [file join $review_root tb tb_review_baselines.sv]] \
    [list tb_review_data_preserving_bist [file join $review_root tb tb_review_data_preserving_bist.sv]]]

foreach test_spec $tests {
    lassign $test_spec test_top test_file
    puts "Running $test_top"
    # Vivado does not allow add_files/fileset simulation setup in an in-memory
    # project. Give each test a disposable on-disk project under review_results.
    # This does not modify or add files to the user's main FPGA project.
    set test_project_dir [file join $log_root "${test_top}_project"]
    create_project $test_top $test_project_dir -part xc7z020clg484-1 -force
    set_property target_language Verilog [current_project]
    # Add one Tcl list item at a time. This prevents Vivado's fileset parser
    # from splitting a project path such as "q2 pubes" at the space.
    foreach design_file $design_files {
        add_files -fileset sources_1 [list $design_file]
    }
    add_files -fileset sim_1 [list $test_file]
    set_property top $test_top [get_filesets sim_1]
    update_compile_order -fileset sources_1
    update_compile_order -fileset sim_1
    launch_simulation -simset sim_1 -mode behavioral
    log_wave -recursive *
    run all
    close_sim
    close_project
}

set marker [open [file join $log_root FUNCTIONAL_SIMULATION_COMPLETE.txt] w]
puts $marker "Both reviewer testbenches completed. Confirm the Vivado console contains both ALL ... TESTS PASSED messages."
close $marker
puts "REVIEW FUNCTIONAL SIMULATION COMPLETE"

