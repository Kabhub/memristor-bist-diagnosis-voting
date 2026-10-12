# Standalone on-disk Vivado simulation project. Source in an empty Vivado
# session, or use RUN_16_BIT.bat. No synthesis or implementation is launched.
set pack_root [file dirname [file normalize [info script]]]
set width 16
if {[info exists argv] && [llength $argv] > 0} {set width [lindex $argv 0]}
if {$width ni {16 32}} {error "Width must be 16 or 32"}
if {[current_project -quiet] ne ""} {
    error "An existing project is open. Use RUN_16_BIT.bat to run separately."
}
set stamp "[clock format [clock seconds] -format %Y%m%d_%H%M%S]_[clock clicks -milliseconds]"
set run_dir [file join $pack_root results "w${width}_$stamp"]
file mkdir $run_dir
set project_dir [file join $run_dir project]
set top "tb_q2_bist_e2e_w${width}"
set prefix "e2e_w${width}"
set expected_scenarios [expr {1 + 2 * (3*$width) * (3*$width)}]
set expected_checks [expr {2 * $expected_scenarios}]
set original_dir [pwd]
cd $run_dir

set config [open [file join $run_dir RUN_CONFIGURATION.txt] w]
puts $config "Vivado: [version -short]"
puts $config "Top: $top"
puts $config "Word width: $width; physical behavioural cells: [expr {3*$width}]"
puts $config "Nominal resistance: LRS=100 ohm; HRS=10000 ohm; threshold=5050 ohm"
puts $config "Faults: stable stuck-LRS/stuck-HRS; orders 0, 1 and 2; BIST runs for every scenario"
puts $config "Expected scenario count: $expected_scenarios"
puts $config "Primary all-zero/all-one checks: $expected_checks"
puts $config "Additional alternating/complement checks: $expected_checks"
puts $config "This is behavioural RTL simulation; no placement/routing or board programming."
close $config

set flow_code [catch {
    create_project e2e $project_dir -part xc7z020clg484-1
    set_property target_language Verilog [current_project]
    set_property simulator_language Mixed [current_project]
    add_files -fileset sources_1 [list [file join $pack_root rtl publication_scalable_memristor_core.sv]]
    add_files -fileset sim_1 [list [file join $pack_root tb tb_q2_bist_e2e.sv]]
    set_property top $top [get_filesets sim_1]
    # Single-thread elaboration and minimal debug reduce compiler/memory load.
    set_property XELAB.MT_LEVEL off [get_filesets sim_1]
    set_property xsim.elaborate.debug_level off [get_filesets sim_1]
    set_property xsim.simulate.runtime 0ns [get_filesets sim_1]
    update_compile_order -fileset sources_1
    update_compile_order -fileset sim_1
    launch_simulation -simset sim_1 -mode behavioral
    run all
    close_sim
    close_project

    set sim_dir [file join $project_dir e2e.sim sim_1 behav xsim]
    foreach suffix {_scenarios.csv _summary.csv _PASS.txt} {
        set source_file [file join $sim_dir "${prefix}${suffix}"]
        if {![file exists $source_file]} {
            # Some simulator integrations keep the caller's working directory.
            set source_file [file join $run_dir "${prefix}${suffix}"]
        }
        if {![file exists $source_file]} {error "Missing simulation output: ${prefix}${suffix}; inspect simulation logs"}
        set destination [file join $run_dir "${prefix}${suffix}"]
        if {[file normalize $source_file] ne [file normalize $destination]} {
            file copy $source_file $destination
        }
    }
    foreach log_name {xvlog.log elaborate.log simulate.log xsim.log} {
        set source_log [file join $sim_dir $log_name]
        if {[file exists $source_log]} {file copy $source_log [file join $run_dir $log_name]}
    }
    set channel [open [file join $run_dir "${prefix}_PASS.txt"] r]
    set pass_text [string trim [read $channel]]
    close $channel
    set expected_text "ALL $expected_scenarios END-TO-END BIST SCENARIOS PASSED: WIDTH=$width; PRIMARY_CHECKS=$expected_checks; MIXED_CHECKS=$expected_checks"
    if {$pass_text ne $expected_text} {error "The testbench PASS marker did not match the expected campaign"}
    set channel [open [file join $run_dir "${prefix}_scenarios.csv"] r]
    set csv_lines [split [string trim [read $channel]] "\n"]
    close $channel
    if {[llength $csv_lines] != $expected_scenarios + 1} {error "Per-scenario CSV row count mismatch"}
    set summary_channel [open [file join $run_dir "${prefix}_summary.csv"] r]
    set summary_text [string trim [read $summary_channel]]
    close $summary_channel
    set summary_lines [split $summary_text "\n"]
    if {[llength $summary_lines] != 2 || [lindex [split [lindex $summary_lines 1] ,] end] ne "PASS"} {
        error "Summary CSV is not a completed PASS result"
    }
    set marker [open [file join $pack_root LATEST_RUN.txt] w]
    puts $marker $run_dir
    close $marker
    puts $pass_text
    puts "RESULTS TO SEND: $run_dir"
} flow_message flow_options]
if {$flow_code != 0} {
    catch {close_sim}
    catch {close_project}
    set failure [open [file join $run_dir RUN_FAILED.txt] w]
    puts $failure $flow_message
    if {[dict exists $flow_options -errorinfo]} {puts $failure [dict get $flow_options -errorinfo]}
    close $failure
    cd $original_dir
    return -options $flow_options $flow_message
}
cd $original_dir
