# Three registered OOC implementations, using the tested v7 timing method.
set pack_root [file dirname [file normalize [info script]]]
if {[current_project -quiet] ne ""} {error "An existing project is open. Use RUN_PLACEMENT_STUDY.bat separately."}
# RTL is unchanged from the completed W16 functional campaigns.
# This packet adds implementation configurations only; see VALIDATION.md.
set part_name xc7z020clg484-1
set report_root [file join $pack_root results placement_study_w16]
file mkdir $report_root
set f [open [file join $pack_root SOURCE_SHA256.json] r]; set fingerprints [read $f]; close $f
set saved_fingerprints [file join $report_root SOURCE_SHA256.json]
if {[file exists $saved_fingerprints]} {
    set f [open $saved_fingerprints r]; set previous [read $f]; close $f
    if {$previous ne $fingerprints} {error "Source manifest changed. Rename results/placement_study_w16 before a fresh comparison."}
} else {
    file copy [file join $pack_root SOURCE_SHA256.json] $saved_fingerprints
}
set design_files [list \
    [file join $pack_root rtl publication_scalable_memristor_core.sv] \
    [file join $pack_root rtl q2_shared_spare_core.sv] \
    [file join $pack_root rtl q2_proposed_wrapper.sv] \
    [file join $pack_root rtl q2_registered_benchmarks.sv]]
set f [open [file join $pack_root LATEST_IMPLEMENTATION.txt] w]; puts $f $report_root; close $f
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

proc review_assert_register_path {path} {
    foreach property {STARTPOINT_PIN ENDPOINT_PIN} {
        set pin [get_property $property $path]
        set cells [get_cells -quiet -of_objects [get_pins -quiet [list $pin]]]
        if {[llength $cells] != 1 || ![get_property IS_SEQUENTIAL $cells]} {
            error "Benchmark timing path has a non-register $property: $pin"
        }
    }
}

proc append_review_row {csv_path row} {
    set header "phase,architecture,width,strategy,place_directive,route_directive,constraint_mhz,clock_period_ns,status,luts,ffs,bram,dsp,wns_ns,whs_ns,timing_met,margin_fmax_indicator_mhz,total_power_mw,dynamic_power_mw,power_confidence,bist_cycles,benchmark_total_luts,benchmark_total_ffs,benchmark_overhead_luts,benchmark_overhead_ffs,timing_scope,power_scope,run_directory"
    set rows [list $header]
    if {[file exists $csv_path]} {
        set f [open $csv_path r]; set content [string trim [read $f]]; close $f
        foreach previous [lrange [split $content "\n"] 1 end] {
            set previous [string trim $previous]
            if {[lindex [split $previous ,] end] ne [lindex [split $row ,] end]} {lappend rows $previous}
        }
    }
    lappend rows $row
    set f [open "${csv_path}.tmp" w]; puts $f [join $rows "\n"]; close $f
    file rename -force "${csv_path}.tmp" $csv_path
}

proc run_review_implementation {phase architecture top width strategy place_directive route_directive frequency_mhz bist_cycles report_root part_name design_files} {
    set run_name "${phase}_${architecture}_w${width}_${strategy}_${frequency_mhz}MHz"
    set run_dir [file join $report_root $run_name]
    set complete_marker [file join $run_dir COMPLETE.txt]
    set csv_path [file join $report_root implementation_summary.csv]
    if {[file exists $complete_marker]} {
        foreach required {core_utilization.rpt timing_summary.rpt applied_constraints.xdc experiment_method.txt} {
            if {![file exists [file join $run_dir $required]]} {error "Completed run is missing $required: $run_name"}
        }
        if {![file exists $csv_path]} {error "Completed run has no summary CSV: $run_name"}
        set f [open $csv_path r]; set content [read $f]; close $f
        set matches 0
        foreach row [lrange [split [string trim $content] "\n"] 1 end] {
            set fields [split [string trim $row] ,]
            if {[lindex $fields end] eq $run_name && [lindex $fields 8] eq "PASS"} {incr matches}
        }
        if {$matches != 1} {error "Completed run has no unique PASS summary row: $run_name"}
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
    set total_luts "NA"
    set total_ffs "NA"
    set overhead_luts "NA"
    set overhead_ffs "NA"

    if {[catch {
        create_project -in_memory -part $part_name -force
        set_property target_language Verilog [current_project]
        # Read one Tcl list item at a time. This is required when the parent
        # folder contains a space, for example "q2 pubes" on Windows.
        foreach design_file $design_files {
            read_verilog -sv [list $design_file]
        }
        # Retain DUT hierarchy so core area can be reported separately.
        synth_design -top $top -part $part_name -mode out_of_context -flatten_hierarchy none -generic WIDTH=$width
        create_clock -name review_clk -period $period_ns [get_ports clk]
        # This shell contains a real clock buffer; do not substitute HD.CLK_SRC.
        set clock_source_site BUFGCTRL_X0Y0
        if {[llength [get_sites -quiet $clock_source_site]] != 1} {
            error "Required OOC clock-context site $clock_source_site is unavailable on $part_name"
        }
        set buffer_cell [get_cells -quiet bench_clock_buffer]
        if {[llength $buffer_cell] != 1} {error "Benchmark BUFG instance is missing"}
        set_property LOC $clock_source_site $buffer_cell
        set launch_cells [get_cells -quiet -hierarchical -filter {IS_SEQUENTIAL && NAME =~ *_launch_reg*}]
        set capture_cells [get_cells -quiet -hierarchical -filter {IS_SEQUENTIAL && NAME =~ *_capture_reg*}]
        if {[llength $launch_cells] == 0 || [llength $capture_cells] == 0} {
            error "Benchmark input/output register banks were not preserved"
        }
        set non_clock_inputs [get_ports -quiet -filter {DIRECTION == IN && NAME != clk}]
        set data_outputs [get_ports -quiet -filter {DIRECTION == OUT}]
        # Outer ports only feed/observe benchmark bank registers; no board
        # interface is being modeled here. Exclude ONLY those outer paths.
        # The launch-bank -> DUT -> capture-bank paths remain fully timed.
        if {[llength $non_clock_inputs] > 0} {
            set_false_path -from $non_clock_inputs -to $launch_cells
        }
        if {[llength $data_outputs] > 0} {
            set_false_path -from $capture_cells -to $data_outputs
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

        set dut_cell [get_cells -quiet dut]
        if {[llength $dut_cell] != 1} {error "DUT hierarchy missing; core area cannot be isolated"}
        set utilization_text [report_utilization -cells $dut_cell -return_string]
        set total_utilization_text [report_utilization -return_string]
        set power_text [report_power -return_string]
        report_utilization -file [file join $run_dir utilization.rpt]
        report_utilization -cells $dut_cell -file [file join $run_dir core_utilization.rpt]
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
        set total_luts [extract_review_value $total_utilization_text {\|\s*Slice LUTs\*?\s*\|\s*([0-9]+)}]
        set total_ffs [extract_review_value $total_utilization_text {\|\s*Slice Registers\s*\|\s*([0-9]+)}]
        foreach metric [list $luts $ffs $bram $dsp $total_luts $total_ffs] {
            if {![review_finite_number $metric] || $metric < 0} {error "Missing/invalid resource metric: $metric"}
        }
        set overhead_luts [expr {$total_luts - $luts}]
        set overhead_ffs [expr {$total_ffs - $ffs}]
        if {$overhead_luts < 0 || $overhead_ffs <= 0} {error "Invalid benchmark/core resource split"}
        set max_path [get_timing_paths -delay_type max -max_paths 1 -nworst 1]
        set min_path [get_timing_paths -delay_type min -max_paths 1 -nworst 1]
        if {[llength $max_path] > 0} { set wns [get_property SLACK $max_path] }
        if {[llength $min_path] > 0} { set whs [get_property SLACK $min_path] }
        if {![review_finite_number $wns] || ![review_finite_number $whs]} {
            error "No finite setup/hold slack was obtained. See timing_summary.rpt and applied_constraints.xdc. This run is not valid timing evidence."
        }
        review_assert_register_path $max_path
        review_assert_register_path $min_path
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
        puts $method "Method: registered benchmark synthesized OOC; no package I/O buffers"
        puts $method "Clock: instantiated BUFG located at $clock_source_site; internal clock tree routed"
        puts $method "Physical optimization: ExploreWithHoldFix before route; one post-route hold_fix/reroute if hold slack is negative"
        puts $method "Timing scope: same-clock launch-register/DUT/capture-register paths; external bank ports excluded explicitly"
        puts $method "All DUT paths, including synchronous reset from the launch bank, remain timed"
        puts $method "Core area: DUT hierarchy only; total/overhead benchmark area reported separately"
        puts $method "Harness latency: one input bank stage and one output bank stage; original core/BIST latency unchanged"
        puts $method "Clock period ns: $period_ns"
        puts $method "PASS means implementation and metric extraction completed; timing_met separately checks both setup and hold"
        puts $method "Power: whole-benchmark vectorless estimate including register banks and BUFG; not isolated core or board power"
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

    append_review_row $csv_path "$phase,$architecture,$width,$strategy,$place_directive,$route_directive,$frequency_mhz,$period_ns,$run_status,$luts,$ffs,$bram,$dsp,$wns,$whs,$timing_met,$fmax_indicator,$total_power_mw,$dynamic_power_mw,$confidence,$bist_cycles,$total_luts,$total_ffs,$overhead_luts,$overhead_ffs,registered_internal,whole_benchmark_vectorless,$run_name"
    if {$run_status eq "PASS"} {
        set previous_failure [file join $run_dir FAILED.txt]
        if {[file exists $previous_failure]} {file delete $previous_failure}
        set marker [open $complete_marker w]
        puts $marker "Completed with Vivado [version -short]"
        close $marker
    } else {
        # A broken setup must not consume hours on dozens of later rows.
        error "Campaign stopped at $run_name. Read [file join $run_dir FAILED.txt] and the Vivado log before restarting."
    }
}


set metadata [open [file join $report_root campaign_metadata.txt] w]
puts $metadata "Vivado: [version -short]; part=$part_name; WIDTH=16; clock=100 MHz; place Default/Explore/ExtraNetDelay_high, route Default"
puts $metadata "Three designs only: proposed_destructive (48 cells), remap_two_spares (18 cells), remap_matched_cells (48 cells)"
puts $metadata "Both baselines include actual BIST plus serial allocation: diagnosis=5 cycles, allocation=16, total=21"
puts $metadata "All test controllers are destructive. Normal operation: one rising-edge write and combinational read."
puts $metadata "Core LUT/FF area excludes measurement register banks and BUFG; total and overhead reported separately."
puts $metadata "Internal registered OOC timing only; three documented placement configurations; not independent random seeds or verified maximum frequency."
puts $metadata "Power is a whole-benchmark vectorless estimate, including banks and BUFG, not device/board power."
puts $metadata "PASS means flow/metrics completed. timing_met separately requires nonnegative setup and hold slack."
puts $metadata "Remapper is a research cell-level shared-spare baseline, not a reproduction of a row/column BISR paper."
close $metadata
foreach placement_spec {
    {default Default}
    {explore Explore}
    {extra_net_delay_high ExtraNetDelay_high}
} {
    lassign $placement_spec strategy placement
    foreach spec {
        {proposed_destructive review_proposed_destructive_registered_benchmark 5}
        {remap_two_spares q2_remap_two_registered_benchmark 21}
        {remap_matched_cells q2_remap_matched_registered_benchmark 21}
    } {
        lassign $spec architecture top cycles
        run_review_implementation placement_sensitivity $architecture $top 16 $strategy $placement Default 100 $cycles $report_root $part_name $design_files
    }
}
set marker [open [file join $report_root IMPLEMENTATION_COMPLETE.txt] w]
puts $marker "ALL 9 PLACEMENT STUDY IMPLEMENTATIONS COMPLETED"; close $marker
puts "ALL 9 PLACEMENT STUDY IMPLEMENTATIONS COMPLETED"
puts "RESULTS TO SEND: $report_root"
