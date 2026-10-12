# Standalone on-disk Vivado simulation project. Source in an empty Vivado
# session, or use 1_RUN_SIMULATION.bat. No synthesis or implementation is launched.
set pack_root [file dirname [file normalize [info script]]]
if {[current_project -quiet] ne ""} {error "An existing project is open. Use 1_RUN_SIMULATION.bat separately."}
set stamp "[clock format [clock seconds] -format %Y%m%d_%H%M%S]_[clock clicks -milliseconds]"
set run_dir [file join $pack_root results "simulation_w16_$stamp"]
file mkdir $run_dir
set project_dir [file join $run_dir project]
set original_dir [pwd]
cd $run_dir
set cfg [open [file join $run_dir RUN_CONFIGURATION.txt] w]
puts $cfg "Vivado: [version -short]; width=16; LRS=100 ohm; HRS=10000 ohm; threshold=5050 ohm"
puts $cfg "18-cell compact and 48-cell matched-spare campaigns: 649 and 4609 scenarios"
puts $cfg "Four words per scenario: all-zero, all-one, alternating, complement. Actual BIST runs every scenario."
puts $cfg "Matched 48-cell campaign instantiates the actual proposed RTL alongside the remapper."
puts $cfg "Nominal stable faults only in exhaustive campaign; selected extra boundary/late-fault checks are separate."
close $cfg
file copy [file join $pack_root SOURCE_SHA256.json] [file join $run_dir SOURCE_SHA256.json]
set flow_code [catch {
    create_project remap $project_dir -part xc7z020clg484-1
    set_property target_language Verilog [current_project]
    set_property simulator_language Mixed [current_project]
    add_files -fileset sources_1 [list [file join $pack_root rtl publication_scalable_memristor_core.sv] [file join $pack_root rtl q2_shared_spare_core.sv]]
    add_files -fileset sim_1 [list [file join $pack_root tb tb_q2_remap.sv]]
    set_property top tb_q2_remap_w16 [get_filesets sim_1]
    set_property XELAB.MT_LEVEL off [get_filesets sim_1]
    set_property xsim.elaborate.debug_level off [get_filesets sim_1]
    set_property xsim.simulate.runtime 0ns [get_filesets sim_1]
    update_compile_order -fileset sources_1
    update_compile_order -fileset sim_1
    launch_simulation -simset sim_1 -mode behavioral
    run all
    close_sim
    close_project
    set sim_dir [file join $project_dir remap.sim sim_1 behav xsim]
    foreach spares {2 32} {
        set prefix "remap_w16_s$spares"
        set cells [expr {16+$spares}]
        set n [expr {1+2*$cells*$cells}]
        set checks [expr {4*$n}]
        foreach suffix {_scenarios.csv _summary.csv _boundary_checks.csv _PASS.txt} {
            set src [file join $sim_dir "${prefix}${suffix}"]
            set dest [file join $run_dir "${prefix}${suffix}"]
            if {![file exists $src]} {set src $dest}
            if {![file exists $src]} {error "Missing simulation output: ${prefix}${suffix}"}
            if {[file normalize $src] ne [file normalize $dest]} {file copy $src $dest}
        }
        set f [open [file join $run_dir "${prefix}_PASS.txt"] r]; set pass [string trim [read $f]]; close $f
        if {$pass ne "ALL $n REMAP SCENARIOS PASSED: WIDTH=16; SPARES=$spares; WORD_CHECKS=$checks"} {error "Incorrect PASS marker: $prefix"}
        set f [open [file join $run_dir "${prefix}_scenarios.csv"] r]; set rows [split [string trim [read $f]] "\n"]; close $f
        if {[llength $rows] != $n+1} {error "Scenario count mismatch: $prefix"}
        foreach row [lrange $rows 1 end] {
            set fields [split [string trim $row] ,]
            if {[llength $fields]!=19 || [lindex $fields 15] ne "21" || [lindex $fields 16] ne "4" || [lindex $fields 17] ne "4" || [lindex $fields end] ne "PASS"} {error "Invalid scenario result: $prefix"}
        }
        set f [open [file join $run_dir "${prefix}_summary.csv"] r]; set rows [split [string trim [read $f]] "\n"]; close $f
        set fields [split [string trim [lindex $rows 1]] ,]
        if {[llength $rows]!=2 || [llength $fields]!=17 || [lindex $fields 3] ne $n || [lindex $fields 7] ne $checks || [lindex $fields 8] ne $checks || [lindex $fields 15] ne "1" || [lindex $fields end] ne "PASS"} {error "Invalid summary: $prefix"}
        set f [open [file join $run_dir "${prefix}_boundary_checks.csv"] r]; set rows [split [string trim [read $f]] "\n"]; close $f
        set expected_boundaries [expr {$spares==32 ? 6 : 5}]
        if {[llength $rows] != $expected_boundaries} {error "Missing boundary checks: $prefix"}
        foreach row [lrange $rows 1 end] {if {[lindex [split [string trim $row] ,] end] ne "PASS"} {error "Failed boundary check: $prefix"}}
        puts $pass
    }
    foreach log_name {xvlog.log elaborate.log simulate.log xsim.log} {
        set src [file join $sim_dir $log_name]
        if {[file exists $src]} {file copy $src [file join $run_dir $log_name]}
    }
    set f [open [file join $run_dir SIMULATION_COMPLETE.txt] w]; puts $f "ALL DEFECT-AWARE BASELINE TESTS PASSED"; close $f
    set f [open [file join $pack_root LATEST_SIMULATION.txt] w]; puts $f $run_dir; close $f
    puts "ALL DEFECT-AWARE BASELINE TESTS PASSED"
    puts "RESULTS TO SEND: $run_dir"
} message options]
if {$flow_code!=0} {
    catch {close_sim}; catch {close_project}
    set f [open [file join $run_dir RUN_FAILED.txt] w]; puts $f $message
    if {[dict exists $options -errorinfo]} {puts $f [dict get $options -errorinfo]}; close $f
    cd $original_dir
    return -options $options $message
}
cd $original_dir
