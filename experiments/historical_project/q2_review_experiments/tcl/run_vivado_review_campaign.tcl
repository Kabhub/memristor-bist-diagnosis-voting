# Resumable post-route area/timing/vectorless-power campaign.
#
# Vivado 7-series place_design does not expose a documented random seed. This
# script therefore uses documented placement/routing directive combinations
# and several clock constraints. Report these as independent implementation
# strategies, not as random seeds.

if {![info exists review_profile]} {
    set review_profile "quick"
}
if {![info exists review_smoke_only]} {
    set review_smoke_only 0
}

if {[llength [get_projects -quiet]] > 0} {
    error "Close the current project before running the reviewer implementation campaign."
}

set script_dir [file dirname [file normalize [info script]]]
set project_root [file normalize [file join $script_dir .. ..]]
set review_root [file normalize [file join $script_dir ..]]
# New namespace: old COMPLETE markers belong to a different, unconstrained
# package-I/O experiment and must not suppress the corrected OOC runs.
set report_root [file join $review_root review_results "vivado_${review_profile}_ooc_v6"]
file mkdir $report_root

set part_name xc7z020clg484-1
set design_files [list \
    [file join $project_root publication_scalable_memristor_core.sv] \
    [file join $review_root rtl review_tmr_baselines.sv] \
    [file join $review_root rtl review_secded_memory.sv] \
    [file join $review_root rtl review_data_preserving_bist_core.sv] \
    [file join $review_root rtl review_synthesis_wrappers.sv]]

set architectures [list \
    [list standard_tmr review_standard_tmr_wrapper 0] \
    [list self_purging_tmr review_self_purging_wrapper 1] \
    [list secded review_secded_wrapper 0] \
    [list proposed_destructive review_proposed_destructive_wrapper 5] \
    [list proposed_preserving review_proposed_preserving_wrapper 8]]

set quick_strategies [list \
    [list default Default Default] \
    [list explore Explore Explore] \
    [list delay ExtraNetDelay_high HigherDelayCost]]
set full_strategies [concat $quick_strategies [list \
    [list spread AltSpreadLogic_high MoreGlobalIterations] \
    [list postopt ExtraPostPlacementOpt AggressiveExplore]]]

if {$review_profile eq "full"} {
    set frequencies_mhz {100 125 150 175 200}
    set strategies $full_strategies
} else {
    set frequencies_mhz {100 150 200}
    set strategies $quick_strategies
}

proc extract_review_value {text pattern} {
    if {[regexp -nocase -- $pattern $text -> value]} {
        return [string trim $value]
    }
    return "NA"
}

proc review_finite_number {value} {
    # Exclude empty strings, NA, inf, -inf and NaN before any slack arithmetic.
    return [regexp {^[+-]?([0-9]+([.][0-9]*)?|[.][0-9]+)([eE][+-]?[0-9]+)?$} $value]
}

proc append_review_row {csv_path row} {
    set exists [file exists $csv_path]
    set handle [open $csv_path a]
    if {!$exists} {
        puts $handle "phase,architecture,width,strategy,place_directive,route_directive,constraint_mhz,clock_period_ns,status,luts,ffs,bram,dsp,wns_ns,whs_ns,timing_met,margin_fmax_indicator_mhz,total_power_mw,dynamic_power_mw,power_confidence,bist_cycles,run_directory"
    }
    puts $handle $row
    close $handle
}

proc run_review_implementation {phase architecture top width strategy place_directive route_directive frequency_mhz bist_cycles report_root part_name design_files} {
    set run_name "${phase}_${architecture}_w${width}_${strategy}_${frequency_mhz}MHz"
    set run_dir [file join $report_root $run_name]
    set complete_marker [file join $run_dir COMPLETE.txt]
    set csv_path [file join $report_root implementation_summary.csv]
    if {[file exists $complete_marker]} {
        puts "SKIP completed: $run_name"
        return
    }
    file mkdir $run_dir
    set period_ns [expr {1000.0 / double($frequency_mhz)}]
    puts "RUN $run_name"

    set run_status "PASS"
    set luts "NA"
    set ffs "NA"
    set bram "NA"
    set dsp "NA"
    set wns "NA"
    set whs "NA"
    set timing_met "NA"
    set fmax_indicator "NA"
    set total_power_mw "NA"
    set dynamic_power_mw "NA"
    set confidence "NA"

    if {[catch {
        create_project -in_memory -part $part_name -force
        set_property target_language Verilog [current_project]
        # Read one Tcl list item at a time. This is required when the parent
        # folder contains a space, for example "q2 pubes" on Windows.
        foreach design_file $design_files {
            read_verilog -sv [list $design_file]
        }
        # These are reusable core interfaces, not a ZedBoard package pinout.
        # OOC synthesis avoids allocating an IOB for each fault-map bit.
        synth_design -top $top -part $part_name -mode out_of_context -generic WIDTH=$width
        create_clock -name review_clk -period $period_ns [get_ports clk]
        # Model the external buffer's origin for OOC clock/hold analysis.
        # Use the same declared context for every architecture and strategy.
        set clock_source_site BUFGCTRL_X0Y0
        if {[llength [get_sites -quiet $clock_source_site]] != 1} {
            error "Required OOC clock-context site $clock_source_site is unavailable on $part_name"
        }
        set_property HD.CLK_SRC $clock_source_site [get_ports clk]
        # Common assumed synchronous module-interface budget for every core.
        # At 100 MHz, max input/output delay is 2 ns each. This is an explicit
        # comparison assumption, not a measured PCB interface requirement.
        set interface_delay_ns [expr {0.20 * $period_ns}]
        set non_clock_inputs [get_ports -quiet -filter {DIRECTION == IN && NAME != clk}]
        set data_outputs [get_ports -quiet -filter {DIRECTION == OUT}]
        if {[llength $non_clock_inputs] > 0} {
            set_input_delay -clock review_clk -max $interface_delay_ns $non_clock_inputs
            set_input_delay -clock review_clk -min 0.0 $non_clock_inputs
        }
        if {[llength $data_outputs] > 0} {
            set_output_delay -clock review_clk -max $interface_delay_ns $data_outputs
            set_output_delay -clock review_clk -min 0.0 $data_outputs
        }
        opt_design
        place_design -directive $place_directive
        phys_opt_design -directive ExploreWithHoldFix
        route_design -directive $route_directive
        # One bounded hold-repair attempt, without relaxing timing constraints.
        set initial_min_path [get_timing_paths -delay_type min -max_paths 1 -nworst 1]
        if {[llength $initial_min_path] > 0} {
            set initial_hold_slack [get_property SLACK $initial_min_path]
            if {[review_finite_number $initial_hold_slack] && $initial_hold_slack < 0.0} {
                phys_opt_design -hold_fix
                route_design -directive $route_directive
            }
        }

        set utilization_text [report_utilization -return_string]
        set power_text [report_power -return_string]
        report_utilization -file [file join $run_dir utilization.rpt]
        report_utilization -hierarchical -file [file join $run_dir utilization_hierarchical.rpt]
        report_methodology -file [file join $run_dir methodology.rpt]
        report_timing_summary -delay_type min_max -report_unconstrained -file [file join $run_dir timing_summary.rpt]
        report_timing -delay_type min -max_paths 20 -file [file join $run_dir hold_paths.rpt]
        report_power -file [file join $run_dir vectorless_power.rpt]
        write_xdc -force [file join $run_dir applied_constraints.xdc]
        write_checkpoint -force [file join $run_dir routed.dcp]

        set luts [extract_review_value $utilization_text {\|\s*Slice LUTs\*?\s*\|\s*([0-9]+)}]
        set ffs [extract_review_value $utilization_text {\|\s*Slice Registers\s*\|\s*([0-9]+)}]
        set bram [extract_review_value $utilization_text {\|\s*Block RAM Tile\s*\|\s*([0-9.]+)}]
        set dsp [extract_review_value $utilization_text {\|\s*DSPs\s*\|\s*([0-9]+)}]
        set max_path [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
        set min_path [get_timing_paths -delay_type min -max_paths 1 -nworst 1]
        if {[llength $max_path] > 0} { set wns [get_property SLACK $max_path] }
        if {[llength $min_path] > 0} { set whs [get_property SLACK $min_path] }
        if {![review_finite_number $wns] || ![review_finite_number $whs]} {
            error "No finite setup/hold slack was obtained. See timing_summary.rpt and applied_constraints.xdc. This run is not valid timing evidence."
        }
        if {[review_finite_number $wns]} {
            set timing_met [expr {($wns >= 0.0) && ($whs >= 0.0) ? 1 : 0}]
            set critical_path [expr {$period_ns - $wns}]
            if {$critical_path > 0.0} {
                set fmax_indicator [expr {1000.0 / $critical_path}]
            }
        }
        set total_power_w [extract_review_value $power_text {\|\s*Total On-Chip Power \(W\)\s*\|\s*([0-9.eE+\-]+)}]
        set dynamic_power_w [extract_review_value $power_text {\|\s*Dynamic \(W\)\s*\|\s*([0-9.eE+\-]+)}]
        if {[string is double -strict $total_power_w]} { set total_power_mw [expr {1000.0 * $total_power_w}] }
        if {[string is double -strict $dynamic_power_w]} { set dynamic_power_mw [expr {1000.0 * $dynamic_power_w}] }
        set confidence [extract_review_value $power_text {\|\s*Confidence Level\s*\|\s*([A-Za-z]+)}]
        set method [open [file join $run_dir experiment_method.txt] w]
        puts $method "Method: out-of-context core synthesis and post-route analysis; no package I/O buffers"
        puts $method "External clock context: HD.CLK_SRC $clock_source_site; assumed common context, not measured board clock topology"
        puts $method "Physical optimization: ExploreWithHoldFix before route; one post-route hold_fix/reroute if hold slack is negative"
        puts $method "Module boundary nets are OOC timing estimates; full-system implementation is required to validate integrated interface timing"
        puts $method "Assumed synchronous interface: input/output max delays each 20% of clock period; min delays 0 ns"
        puts $method "Clock period ns: $period_ns; max interface delay ns: $interface_delay_ns"
        puts $method "PASS means implementation and metric extraction completed; timing_met separately checks both setup and hold"
        puts $method "Power: vectorless model estimate, not board measurement"
        close $method
        close_project
    } error_message error_options]} {
        set run_status "FAILED"
        catch {close_project}
        set failure [open [file join $run_dir FAILED.txt] w]
        puts $failure $error_message
        puts $failure [dict get $error_options -errorinfo]
        close $failure
        puts "FAILED $run_name: $error_message"
    }

    append_review_row $csv_path "$phase,$architecture,$width,$strategy,$place_directive,$route_directive,$frequency_mhz,$period_ns,$run_status,$luts,$ffs,$bram,$dsp,$wns,$whs,$timing_met,$fmax_indicator,$total_power_mw,$dynamic_power_mw,$confidence,$bist_cycles,$run_name"
    if {$run_status eq "PASS"} {
        set marker [open $complete_marker w]
        puts $marker "Completed with Vivado [version -short]"
        close $marker
    } else {
        # A broken setup must not consume hours on dozens of later rows.
        error "Campaign stopped at $run_name. Read [file join $run_dir FAILED.txt] and the Vivado log before restarting."
    }
}

set metadata [open [file join $report_root campaign_metadata.txt] w]
puts $metadata "Vivado version: [version -short]"
puts $metadata "Target part: $part_name"
puts $metadata "Profile: $review_profile"
puts $metadata "Revision: OOC v6; older experiment results/markers are not reused"
puts $metadata "Implementation mode: out_of_context; no board package I/O buffers"
puts $metadata "External clock context: HD.CLK_SRC BUFGCTRL_X0Y0; assumed common surrounding clock-buffer location"
puts $metadata "Hold optimization: ExploreWithHoldFix pre-route; one conditional post-route hold_fix/reroute"
puts $metadata "Boundary timing is an OOC estimate, not full-system interface signoff"
puts $metadata "Interface assumption: synchronous, max input/output delay each 20% of clock period; min delays 0 ns"
puts $metadata "Timing variation method: documented implementation directive combinations; not random seeds"
puts $metadata "Power method: post-route vectorless estimate; do not claim measured board power"
puts $metadata "Highest timing-clean constraint is separate from the margin-derived indicator"
close $metadata

if {$review_smoke_only} {
    # This exercises both fixes: W32 previously exhausted package I/O capacity,
    # and plain TMR previously produced no finite constrained timing paths.
    run_review_implementation resource_scaling standard_tmr review_standard_tmr_wrapper 32 default Default Default 100 0 $report_root $part_name $design_files
    puts "Q2 OOC SMOKE RUN COMPLETE: $report_root"
    puts "Inspect implementation_summary.csv and timing_summary.rpt before launching the 55-run campaign."
    return
}

# Resource scaling: one common 100 MHz/default run at W=8/16/32.
foreach architecture_spec $architectures {
    lassign $architecture_spec architecture top bist_cycles
    foreach width {8 16 32} {
        run_review_implementation resource_scaling $architecture $top $width default Default Default 100 $bist_cycles $report_root $part_name $design_files
    }
}

# Timing robustness: several constraints and documented implementation
# strategies at the realistic comparison width W=32.
foreach architecture_spec $architectures {
    lassign $architecture_spec architecture top bist_cycles
    foreach strategy_spec $strategies {
        lassign $strategy_spec strategy place_directive route_directive
        foreach frequency_mhz $frequencies_mhz {
            if {($strategy eq "default") && ($frequency_mhz == 100)} {
                # Already executed in resource scaling; keep phase labels clean.
                continue
            }
            run_review_implementation timing_sweep $architecture $top 32 $strategy $place_directive $route_directive $frequency_mhz $bist_cycles $report_root $part_name $design_files
        }
    }
}

puts "Q2 REVIEW VIVADO CAMPAIGN COMPLETE: $report_root"

