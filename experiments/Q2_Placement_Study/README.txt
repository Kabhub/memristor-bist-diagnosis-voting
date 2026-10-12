Q2 PLACEMENT STRATEGY STUDY: 9 RUNS

1. Extract the entire ZIP into C:\Q2\Q2_Placement_Study.
2. Close any Vivado GUI project. Double-click RUN_PLACEMENT_STUDY.bat.
   Default installation: C:\AMDDesignTools\2026.1\Vivado\bin.
   If different, set Q2_VIVADO_BIN to the Vivado bin directory.
3. Wait for ALL 9 PLACEMENT STUDY IMPLEMENTATIONS COMPLETED.
4. Zip and send the whole results\placement_study_w16 folder and vivado.log.
   Keep routed.dcp locally; you can omit checkpoint files from the uploaded ZIP.

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
Failure stops the campaign; send the log and FAILED.txt rather than repeatedly retrying.
PASS means the flow produced metrics; timing_met=1 separately means setup/hold met.
Do not report a failing constraint as a successful operating frequency.

Timing conclusions: report each strategy, the min/max WNS and WHS, core LUT/FF,
and number of timing-clean configurations. Three strategies do not estimate a
random-seed distribution or confidence interval. Whole-benchmark vectorless power
retains Medium confidence and includes measurement banks and BUFG.
No results for these nine new runs were available at packet creation.
