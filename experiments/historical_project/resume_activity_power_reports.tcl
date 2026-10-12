# Resume only the checkpoint power-report stage after corrected SAIF generation.
# This script does not launch simulation and does not synthesize/place/route.
# It is intended for recovery from a failure at reset_switching_activity in the
# checkpoint refresh script.

set script_dir [file dirname [file normalize [info script]]]
set report_root [file normalize [file join $script_dir publication_activity_power_reports]]
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

# An interrupted refresh can leave the first checkpoint and CSV channel
# open. Close both before resuming.
if {[info exists csv_file]} {
    catch {close $csv_file}
    unset csv_file
}
catch {close_design}

foreach architecture_spec $architectures {
    lassign $architecture_spec architecture_name architecture_id simulation_top saif_scope
    set run_dir [file join $report_root [format "%s_w8" $architecture_name]]
    set saif_path [file join $run_dir [format "%s_activity.saif" $architecture_name]]
    set checkpoint_path [file join $run_dir routed_activity_power.dcp]
    if {![file exists $checkpoint_path]} {
        error "Required routed checkpoint not found: $checkpoint_path"
    }
    if {![file exists $saif_path]} {
        error "Required corrected SAIF not found: $saif_path"
    }
    lassign [validate_activity_saif $saif_path $architecture_name] \
        duration_ps start_transitions
    puts "Validated $architecture_name SAIF: $duration_ps ps, $start_transitions start transitions"
}

puts ""
puts "============================================================"
puts "RESUMING POWER REPORTS FROM CORRECTED SAIF + CHECKPOINTS"
puts "No simulation, synthesis, placement, or routing will run."
puts "============================================================"

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
    puts [format "Checkpoint power report %d/3: %s" \
        $architecture_index $architecture_name]

    open_checkpoint $checkpoint_path

    # Vivado 2026.1 requires reset_switching_activity to receive objects.
    set switching_objects [concat \
        [get_ports -quiet *] \
        [get_nets -hierarchical -quiet *]]
    if {[llength $switching_objects] == 0} {
        error "No ports or nets were found for $architecture_name"
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
puts $metadata_file "SAIF capture: restarted to time zero and validated for full duration plus six start transitions"
puts $metadata_file "SAIF hierarchy: recursively logged below one explicit DUT scope per architecture; DUT scope stripped before annotation"
puts $metadata_file "Implementation reuse: power reports resumed from existing corrected SAIF files and routed checkpoints"
close $metadata_file

set status_path [file join $report_root ACTIVITY_POWER_STATUS.txt]
set status_file [open $status_path w]
puts $status_file "VALID: corrected SAIF capture and checkpoint power reports completed."
puts $status_file "Use activity_power_summary.csv and saif_capture_validation.csv in this folder."
close $status_file

puts ""
puts "============================================================"
puts "CORRECTED ACTIVITY-POWER REPORTS COMPLETE"
puts "No simulation, synthesis, placement, or routing was repeated."
puts "Results: $report_root"
puts "Zip publication_activity_power_reports and upload it."
puts "============================================================"
