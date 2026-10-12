# Fair 8-bit implementation comparison for the publication.
# Run from Vivado's Tcl console with:
#   source {C:/path/to/collect_publication_baseline_reports.tcl}
#
# Each architecture is synthesized, placed, and routed independently in an
# in-memory project for xc7z020clg484-1. External configuration/output paths
# are excluded so the reported WNS measures registered core logic. Full
# utilization, timing, and vectorless power reports are preserved alongside a
# compact CSV summary.

set script_dir [file dirname [file normalize [info script]]]
set source_file [file join $script_dir publication_scalable_memristor_core.sv]
set wrapper_file [file join $script_dir publication_architecture_wrapper.sv]
set report_root [file normalize [file join $script_dir publication_baseline_reports]]
file mkdir $report_root

if {[llength [get_projects -quiet]] > 0} {
    error "Close the open Vivado project, then source this script from the Vivado Tcl shell or start page. It uses disposable in-memory projects."
}

set part_name xc7z020clg484-1
set clock_period_ns 10.000

proc extract_report_value {report_text pattern} {
    if {[regexp $pattern $report_text -> value]} {
        return $value
    }
    return "NA"
}

set csv_path [file join $report_root baseline_summary.csv]
set csv_file [open $csv_path w]
puts $csv_file "architecture,width,luts,flip_flops,bram_tiles,dsp_blocks,wns_ns,whs_ns,critical_path_ns,estimated_fmax_mhz,total_power_w,power_confidence"

foreach architecture_spec {
    {unprotected 0}
    {standard_tmr 1}
    {proposed_bist_guided 2}
} {
    lassign $architecture_spec architecture_name architecture_id
    set run_name [format "%s_w8" $architecture_name]
    set run_dir [file join $report_root $run_name]
    file mkdir $run_dir

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

    set utilization_text [report_utilization -return_string]
    set power_text [report_power -return_string]

    report_utilization -hierarchical \
        -file [file join $run_dir utilization.rpt]
    report_timing_summary -delay_type min_max -report_unconstrained \
        -file [file join $run_dir timing_summary.rpt]
    report_power -file [file join $run_dir vectorless_power.rpt]
    report_methodology -file [file join $run_dir methodology.rpt]
    write_checkpoint -force [file join $run_dir routed.dcp]

    set luts [extract_report_value $utilization_text {\|\s*Slice LUTs\*?\s*\|\s*([0-9]+)}]
    set ffs [extract_report_value $utilization_text {\|\s*Slice Registers\s*\|\s*([0-9]+)}]
    set bram [extract_report_value $utilization_text {\|\s*Block RAM Tile\s*\|\s*([0-9.]+)}]
    set dsps [extract_report_value $utilization_text {\|\s*DSPs\s*\|\s*([0-9]+)}]
    # Read slack directly from the routed timing paths. This is more robust
    # across Vivado report-format changes than parsing timing-summary text.
    set wns "NA"
    set whs "NA"
    set max_path [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
    set min_path [get_timing_paths -delay_type min -max_paths 1 -nworst 1]
    if {[llength $max_path] > 0} {
        set wns [get_property SLACK $max_path]
    }
    if {[llength $min_path] > 0} {
        set whs [get_property SLACK $min_path]
    }
    set critical_path "NA"
    set estimated_fmax "NA"
    if {[string is double -strict $wns]} {
        set critical_path [expr {$clock_period_ns - $wns}]
        if {$critical_path > 0.0} {
            set estimated_fmax [expr {1000.0 / $critical_path}]
        }
    }
    set power [extract_report_value $power_text {\|\s*Total On-Chip Power \(W\)\s*\|\s*([0-9.]+)}]
    set confidence [extract_report_value $power_text {\|\s*Confidence Level\s*\|\s*([A-Za-z]+)}]

    puts $csv_file "$architecture_name,8,$luts,$ffs,$bram,$dsps,$wns,$whs,$critical_path,$estimated_fmax,$power,$confidence"
    flush $csv_file
    close_project
}

close $csv_file
puts "Publication baseline comparison complete: $report_root"
puts "Upload baseline_summary.csv and the three report folders for analysis."
