# Fast correction pass for the publication activity-power experiment.
#
# Use this script only when publication_activity_power_reports already contains
# the three routed_activity_power.dcp files produced by the full flow.  It
# regenerates complete, recursively logged SAIF files from time zero and then
# re-runs power analysis on those checkpoints.  It does not synthesize, place,
# or route the designs again.
#
# Run from the Vivado start page or Tcl shell with no project open:
#
#   cd {C:/Users/Kabir/OneDrive/Desktop/q2 pubes/be_memristor_fpga_q2_publication}
#   source {refresh_activity_power_from_checkpoints.tcl}

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

    if {$duration_ps < 7900000} {
        error "Incomplete SAIF for $architecture_name: duration is $duration_ps ps; expected at least 7900000 ps"
    }
    if {$start_transitions ne "6"} {
        error "Incomplete SAIF for $architecture_name: start transition count is $start_transitions; expected 6"
    }

    return [list $duration_ps $start_transitions]
}

foreach architecture_spec $architectures {
    lassign $architecture_spec architecture_name architecture_id simulation_top saif_scope
    set checkpoint_path [file join $report_root \
        [format "%s_w8" $architecture_name] routed_activity_power.dcp]
    if {![file exists $checkpoint_path]} {
        error "Required routed checkpoint not found: $checkpoint_path"
    }
}

puts ""
puts "============================================================"
puts "FAST ACTIVITY-POWER REFRESH FROM ROUTED CHECKPOINTS"
puts "Runs 3 simulations and 3 power reports; no synthesis or routing."
puts "============================================================"

if {[info exists ::env(TEMP)] && [string length $::env(TEMP)] > 0} {
    set simulation_temp_root $::env(TEMP)
} elseif {[info exists ::env(TMP)] && [string length $::env(TMP)] > 0} {
    set simulation_temp_root $::env(TMP)
} else {
    set simulation_temp_root [pwd]
}
set simulation_work_root [file normalize [file join $simulation_temp_root q2_saif_refresh]]
file mkdir $simulation_work_root
puts "XSim temporary working directory: $simulation_work_root"

set architecture_index 0
foreach architecture_spec $architectures {
    incr architecture_index
    lassign $architecture_spec architecture_name architecture_id simulation_top saif_scope
    set run_dir [file join $report_root [format "%s_w8" $architecture_name]]
    set saif_path [file join $run_dir [format "%s_activity.saif" $architecture_name]]
    set simulation_project_dir [file join $simulation_work_root $architecture_id]
    set simulation_project_name [format "saif_refresh_%d" $architecture_id]

    puts ""
    puts [format "Corrected SAIF simulation %d/3: %s" \
        $architecture_index $architecture_name]

    create_project -force $simulation_project_name $simulation_project_dir -part $part_name
    set_property target_language Verilog [current_project]
    add_files -norecurse [list $source_file $wrapper_file]
    add_files -fileset sim_1 -norecurse [list $activity_tb_file]
    set_property top $simulation_top [get_filesets sim_1]
    set_property xsim.elaborate.debug_level typical [get_filesets sim_1]
    update_compile_order -fileset sim_1
    launch_simulation -simset sim_1 -mode behavioral

    # launch_simulation normally advances by the configured simulation runtime.
    # Rewind first so the complete testbench, including the first BIST pulse,
    # is represented in the SAIF file.
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
    set checkpoint_path [file join $run_dir routed_activity_power.dcp]

    puts ""
    puts [format "Checkpoint power refresh %d/3: %s" \
        $architecture_index $architecture_name]

    open_checkpoint $checkpoint_path

    # The supplied checkpoints were saved after the earlier SAIF import. Clear
    # those activity attributes before producing a fresh vectorless reference.
    # Vivado 2026.1 requires an explicit object list for this command.
    set switching_objects [concat \
        [get_ports -quiet *] \
        [get_nets -hierarchical -quiet *]]
    if {[llength $switching_objects] == 0} {
        error "No ports or nets were found for switching-activity reset"
    }
    reset_switching_activity $switching_objects
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
    write_checkpoint -force $checkpoint_path

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
    close_design
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
puts $metadata_file "Write-enable cycles: 576 total (75 percent of operational cycles)"
puts $metadata_file "Idle/read cycles: 192 total (25 percent of operational cycles)"
puts $metadata_file "BIST runs: 3; expected BIST latency: 5 cycles each"
puts $metadata_file "SAIF capture: explicitly restarted to time zero and validated for full duration plus six start transitions"
puts $metadata_file "SAIF hierarchy: recursively logged below one explicit DUT scope per architecture; DUT scope stripped before annotation"
puts $metadata_file "Implementation reuse: power refreshed from the three previously routed checkpoints"
close $metadata_file

set status_path [file join $report_root ACTIVITY_POWER_STATUS.txt]
set status_file [open $status_path w]
puts $status_file "VALID: corrected SAIF capture completed from time zero."
puts $status_file "Use activity_power_summary.csv and saif_capture_validation.csv in this folder."
close $status_file

puts ""
puts "============================================================"
puts "CORRECTED ACTIVITY-POWER REFRESH COMPLETE"
puts "No synthesis, placement, or routing was repeated."
puts "Results: $report_root"
puts "Zip publication_activity_power_reports and upload it."
puts "============================================================"
