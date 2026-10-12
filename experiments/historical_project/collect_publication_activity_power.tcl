# Activity-annotated power comparison for the three 8-bit publication
# architectures. Run from Vivado's Tcl console with no project open:
#
#   cd {C:/Users/Kabir/OneDrive/Desktop/q2 pubes/be_memristor_fpga_q2_publication}
#   source {collect_publication_activity_power.tcl}
#
# The script first generates one RTL SAIF file per architecture using the same
# deterministic workload. It then performs three independent routed
# implementations, imports the matching SAIF file, and writes vectorless and
# activity-annotated power reports for a controlled comparison.  The simulator
# is explicitly restarted after launch so SAIF capture begins at time zero.

set script_dir [file dirname [file normalize [info script]]]
set source_file [file join $script_dir publication_scalable_memristor_core.sv]
set wrapper_file [file join $script_dir publication_architecture_wrapper.sv]
set activity_tb_file [file join $script_dir tb_publication_power_activity.sv]
set report_root [file normalize [file join $script_dir publication_activity_power_reports]]

if {[llength [get_projects -quiet]] > 0} {
    error "Close the open Vivado project, then source this script from the Vivado Tcl shell or start page."
}

foreach required_file [list $source_file $wrapper_file $activity_tb_file] {
    if {![file exists $required_file]} {
        error "Required source file not found: $required_file"
    }
}

file mkdir $report_root

set part_name xc7z020clg484-1
set clock_period_ns 10.000
set architectures {
    {unprotected 0 tb_publication_power_activity_unprotected tb_publication_power_activity_unprotected/activity/dut}
    {standard_tmr 1 tb_publication_power_activity_standard_tmr tb_publication_power_activity_standard_tmr/activity/dut}
    {proposed_bist_guided 2 tb_publication_power_activity_proposed tb_publication_power_activity_proposed/activity/dut}
}

proc extract_activity_power_value {report_text pattern} {
    if {[regexp $pattern $report_text -> value]} {
        return $value
    }
    return "NA"
}

proc validate_activity_saif {saif_path architecture_name} {
    set saif_file [open $saif_path r]
    set saif_text [read $saif_file]
    close $saif_file

    if {![regexp {\(DURATION[[:space:]]+([0-9]+)\)} $saif_text -> duration_ps]} {
        error "Could not read SAIF duration for $architecture_name"
    }

    set start_transitions "NA"
    foreach saif_line [split $saif_text "\n"] {
        if {[regexp {^[[:space:]]*\(start[[:space:]].*\(TC[[:space:]]+([0-9]+)\)\)} \
                $saif_line -> start_transitions]} {
            break
        }
    }

    # A complete run is 7.985 us and contains three start pulses (six
    # transitions). These checks catch Vivado's default pre-run before SAIF
    # logging, which otherwise omits the first 1 us of the workload.
    if {$duration_ps < 7900000} {
        error "Incomplete SAIF for $architecture_name: duration is $duration_ps ps; expected at least 7900000 ps"
    }
    if {$start_transitions ne "6"} {
        error "Incomplete SAIF for $architecture_name: start transition count is $start_transitions; expected 6"
    }

    return [list $duration_ps $start_transitions]
}

puts ""
puts "============================================================"
puts "PUBLICATION ACTIVITY-BASED POWER FLOW"
puts "This intentionally runs 3 simulations and 3 implementations."
puts "Do not close Vivado until the completion message appears."
puts "============================================================"

# Use one isolated XSim project per architecture. Keep these projects under the
# Windows temporary directory instead of the already-deep publication path.
# XSim generates several additional nested directories while compiling its C
# model; keeping the base path short avoids the Windows 260-character limit.
if {[info exists ::env(TEMP)] && [string length $::env(TEMP)] > 0} {
    set simulation_temp_root $::env(TEMP)
} elseif {[info exists ::env(TMP)] && [string length $::env(TMP)] > 0} {
    set simulation_temp_root $::env(TMP)
} else {
    set simulation_temp_root [pwd]
}
set simulation_work_root [file normalize [file join $simulation_temp_root q2_saif]]
file mkdir $simulation_work_root
puts "XSim temporary working directory: $simulation_work_root"

set architecture_index 0
foreach architecture_spec $architectures {
    incr architecture_index
    lassign $architecture_spec architecture_name architecture_id simulation_top saif_scope
    set run_dir [file join $report_root [format "%s_w8" $architecture_name]]
    set saif_path [file join $run_dir [format "%s_activity.saif" $architecture_name]]
    set simulation_project_dir [file join $simulation_work_root $architecture_id]
    set simulation_project_name [format "saif_sim_%d" $architecture_id]
    file mkdir $run_dir

    puts ""
    puts [format "SAIF simulation %d/3: %s" $architecture_index $architecture_name]

    create_project -force $simulation_project_name $simulation_project_dir -part $part_name
    set_property target_language Verilog [current_project]
    add_files -norecurse [list $source_file $wrapper_file]
    add_files -fileset sim_1 -norecurse [list $activity_tb_file]
    set_property top $simulation_top [get_filesets sim_1]
    set_property xsim.elaborate.debug_level typical [get_filesets sim_1]
    update_compile_order -fileset sim_1
    launch_simulation -simset sim_1 -mode behavioral

    # launch_simulation can advance by the fileset's default runtime before it
    # returns. Rewind to time zero before opening the SAIF file.
    restart
    puts "SAIF capture start time: [current_time]"
    open_saif $saif_path
    set saif_objects [get_objects -r [format "/%s/*" $saif_scope]]
    if {[llength $saif_objects] == 0} {
        error "No simulator objects found for recursive SAIF scope $saif_scope"
    }
    log_saif $saif_objects
    run -all
    close_saif
    close_sim

    if {![file exists $saif_path] || [file size $saif_path] == 0} {
        error "SAIF generation failed for $architecture_name"
    }
    lassign [validate_activity_saif $saif_path $architecture_name] \
        saif_duration_ps($architecture_name) saif_start_transitions($architecture_name)
    set saif_logged_objects($architecture_name) [llength $saif_objects]
    close_project
}

set validation_path [file join $report_root saif_capture_validation.csv]
set validation_file [open $validation_path w]
puts $validation_file "architecture,duration_ps,start_transitions,recursively_logged_objects,status"
foreach architecture_spec $architectures {
    lassign $architecture_spec architecture_name architecture_id simulation_top saif_scope
    puts $validation_file "$architecture_name,$saif_duration_ps($architecture_name),$saif_start_transitions($architecture_name),$saif_logged_objects($architecture_name),PASS"
}
close $validation_file

set csv_path [file join $report_root activity_power_summary.csv]
set csv_file [open $csv_path w]
puts $csv_file "architecture,width,operational_cycles,write_cycles,bist_runs,vectorless_total_power_w,vectorless_dynamic_power_w,vectorless_confidence,saif_total_power_w,saif_dynamic_power_w,saif_device_static_power_w,saif_confidence,saif_design_nets_matched"

set architecture_index 0
foreach architecture_spec $architectures {
    incr architecture_index
    lassign $architecture_spec architecture_name architecture_id simulation_top saif_scope
    set run_name [format "%s_w8" $architecture_name]
    set run_dir [file join $report_root $run_name]
    set saif_path [file join $run_dir [format "%s_activity.saif" $architecture_name]]

    puts ""
    puts [format "Routed implementation %d/3: %s" $architecture_index $architecture_name]

    create_project -in_memory -part $part_name
    read_verilog -sv [list $source_file $wrapper_file]

    synth_design \
        -top publication_architecture_wrapper \
        -part $part_name \
        -mode out_of_context \
        -generic [list WIDTH=8 ARCHITECTURE=$architecture_id]

    create_clock -name research_clk -period $clock_period_ns [get_ports clk]
    set non_clock_inputs [get_ports -quiet -filter {DIRECTION == IN && NAME != clk}]
    if {[llength $non_clock_inputs] > 0} {
        set_false_path -from $non_clock_inputs
    }
    if {[llength [all_outputs]] > 0} {
        set_false_path -to [all_outputs]
    }

    opt_design
    place_design
    phys_opt_design
    route_design

    # Capture the default estimate first, then annotate the same routed design
    # with the matching workload activity so placement and routing are held
    # constant between the two power reports.
    set vectorless_power_text [report_power -return_string]
    report_power -file [file join $run_dir vectorless_reference_power.rpt]
    report_power -format xml \
        -file [file join $run_dir vectorless_reference_power.xml]

    read_saif \
        -strip_path $saif_scope \
        -out_file [file join $run_dir saif_unmatched.rpt] \
        $saif_path

    set activity_power_text [report_power -return_string]
    report_power -file [file join $run_dir activity_power.rpt]
    report_power -format xml -file [file join $run_dir activity_power.xml]
    report_utilization -file [file join $run_dir utilization.rpt]
    report_utilization -hierarchical \
        -file [file join $run_dir utilization_hierarchical.rpt]
    report_timing_summary -delay_type min_max -report_unconstrained \
        -file [file join $run_dir timing_summary.rpt]
    report_methodology -file [file join $run_dir methodology.rpt]
    write_checkpoint -force [file join $run_dir routed_activity_power.dcp]

    set vectorless_total [extract_activity_power_value \
        $vectorless_power_text \
        {\|\s*Total On-Chip Power \(W\)\s*\|\s*([0-9.eE+\-]+)}]
    set vectorless_dynamic [extract_activity_power_value \
        $vectorless_power_text \
        {\|\s*Dynamic \(W\)\s*\|\s*([0-9.eE+\-]+)}]
    set vectorless_confidence [extract_activity_power_value \
        $vectorless_power_text \
        {\|\s*Confidence Level\s*\|\s*([A-Za-z]+)}]

    set activity_total [extract_activity_power_value \
        $activity_power_text \
        {\|\s*Total On-Chip Power \(W\)\s*\|\s*([0-9.eE+\-]+)}]
    set activity_dynamic [extract_activity_power_value \
        $activity_power_text \
        {\|\s*Dynamic \(W\)\s*\|\s*([0-9.eE+\-]+)}]
    set activity_static [extract_activity_power_value \
        $activity_power_text \
        {\|\s*Device Static \(W\)\s*\|\s*([0-9.eE+\-]+)}]
    set activity_confidence [extract_activity_power_value \
        $activity_power_text \
        {\|\s*Confidence Level\s*\|\s*([A-Za-z]+)}]
    set activity_nets_matched [string trim [extract_activity_power_value \
        $activity_power_text \
        {\|\s*Design Nets Matched\s*\|\s*([^|]+)\|}]]

    puts $csv_file "$architecture_name,8,768,576,3,$vectorless_total,$vectorless_dynamic,$vectorless_confidence,$activity_total,$activity_dynamic,$activity_static,$activity_confidence,$activity_nets_matched"
    flush $csv_file
    close_project
}

close $csv_file

set metadata_path [file join $report_root activity_power_run_metadata.txt]
set metadata_file [open $metadata_path w]
puts $metadata_file "Vivado version: [version -short]"
puts $metadata_file "Target part: $part_name"
puts $metadata_file "Clock period: $clock_period_ns ns (100 MHz)"
puts $metadata_file "Architectures: unprotected, standard TMR, proposed BIST-guided"
puts $metadata_file "BIST phases: fault-free, one HRS fault, same-bit two-HRS fault"
puts $metadata_file "Operational cycles: 768 total (256 per phase)"
puts $metadata_file "Write-enable cycles: 576 total (75 percent duty)"
puts $metadata_file "Idle/read cycles: 192 total (25 percent duty)"
puts $metadata_file "BIST runs: 3; expected BIST latency: 5 cycles each"
puts $metadata_file "SAIF capture: explicitly restarted to time zero and validated for full duration plus six start transitions"
puts $metadata_file "SAIF hierarchy: recursively logged below one explicit DUT scope per architecture; DUT scope stripped before annotation"
close $metadata_file

puts ""
puts "============================================================"
puts "PUBLICATION ACTIVITY-BASED POWER FLOW COMPLETE"
puts "Results: $report_root"
puts "Upload activity_power_summary.csv and the three activity_power.rpt files."
puts "Also include saif_unmatched.rpt if it contains any unmatched objects."
puts "============================================================"
