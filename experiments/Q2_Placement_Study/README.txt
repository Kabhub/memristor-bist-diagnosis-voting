PLACEMENT STRATEGY STUDY: 9 COMPLETED RUNS

Recorded final data: ../../results/placement_sensitivity/.
All nine runs passed the flow and met setup/hold timing.
The commands below reproduce the study on Windows.

1. Extract the repository into C:\Q2\repo
   and open experiments\Q2_Placement_Study.
2. Close any Vivado GUI project. Double-click RUN_PLACEMENT_STUDY.bat.
   Default installation: C:\AMDDesignTools\2026.1\Vivado\bin.
   If different, set Q2_VIVADO_BIN to the Vivado bin directory.
3. Wait for ALL 9 PLACEMENT STUDY IMPLEMENTATIONS COMPLETED.
4. Retain results\placement_study_w16 and vivado.log, including routed.dcp.
   Compare the generated summary with the recorded final data.

Three W=16 designs: proposed destructive BIST, compact two-spare remapping,
matched-cell remapping. Three placement directives: Default, Explore,
ExtraNetDelay_high. Routing remains Default. All clocks remain 100 MHz;
registered internal timing and isolated DUT utilization match the existing study.

This is placement-strategy sensitivity, NOT independent random placement seeds.
Vivado UG835 2026.1 place_design has no documented -seed switch.
https://docs.amd.com/r/en-US/ug835-vivado-tcl-commands/place_design
The RTL sources are identical to the already completed functional campaign.
You do not need to repeat those simulations for this packet.

Completed runs are skipped on restart after reports and summary rows are checked.
To stop between runs, press Ctrl+C after a COMPLETE.txt appears. Relaunch to resume.
An interrupted unfinished run is restarted, not counted as completed.
Do not edit RTL, constraints or the source manifest between runs.
Failure stops the campaign; inspect the log and FAILED.txt before retrying.
PASS means the flow produced metrics; timing_met=1 separately means setup/hold met.
Do not report a failing constraint as a successful operating frequency.

Timing conclusions: report each strategy, the min/max WNS and WHS, core LUT/FF,
and number of timing-clean configurations. Three strategies do not estimate a
random-seed distribution or confidence interval. Whole-benchmark vectorless power
retains Medium confidence and includes measurement banks and BUFG.
The recorded nine-run results are available in ../../results/placement_sensitivity/.
