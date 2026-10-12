# End-to-end resistance-aware BIST campaign

## Run this next

1. Extract the ZIP into `C:\Q2`. It creates the folder `C:\Q2\E2E_BIST` (a short local path).
2. Double-click `RUN_16_BIT.bat`.
3. Wait for `ALL 4609 END-TO-END BIST SCENARIOS PASSED`.
4. Open `LATEST_RUN.txt`. It gives the exact completed result directory.
5. Send that directory as a ZIP, or send its summary CSV, scenario CSV, PASS marker, configuration text and simulation logs.

The batch file uses your previously reported Vivado location, `C:\AMDDesignTools\2026.1\Vivado\bin\vivado.bat`, then checks the system path. If your installation is elsewhere, set `Q2_VIVADO_BIN` to its `bin` directory or use the Tcl alternative below. Existing FPGA projects can remain closed. This creates a separate on-disk simulation project and does not synthesize, route or program the board.

### Tcl alternative

Open Vivado with no project open, then run:

```tcl
source {C:/Q2/E2E_BIST/run_e2e.tcl}
```

The braces prevent Tcl from splitting paths containing spaces, but the short local path is recommended for the Windows simulator toolchain. No `cd` command is needed.

## What this experiment establishes

The DUT is the unchanged `publication_scalable_memristor_core`, configured with WIDTH=16 and ARCHITECTURE=2, as used by the destructive publication benchmark. Its nominal state values are 100/10000 ohm, with a 5050-ohm classifier. Injection inputs act on the behavioural cells. The testbench starts the actual BIST controller and compares its resulting fault maps to independent expected values. It never supplies a diagnosis map to the voter.

The exhaustive campaign includes:

- One no-fault scenario.
- 96 single stuck-state faults across 48 cells, testing both polarities.
- 4512 distinct double-fault scenarios: every cell pair and all four polarity combinations.
- Exact location and polarity checks, health-map checks and five-cycle BIST completion for every scenario.
- 9218 primary operational checks using all-zero and all-one words.
- 9218 additional operational checks using alternating bits and their complement.
- Additional three-fault rejection and cleared-map recovery checks, reported separately from the exhaustive order-0/1/2 scenario count.

Scenarios run consecutively without resetting the DUT between them. Starting each new BIST must invalidate the old diagnosis. This tests map refresh as the injected faults change.

The standard-TMR result is observed on the same replica values and recorded separately. Its primary failure count is checked against the analytic expectation of 96 for 16 bits. Such a TMR failure is an expected baseline result; it is not a failure of this campaign.

The campaign enumerates all specified stuck-fault configurations for four backgrounds. It does not enumerate every possible 16-bit word, analogue distribution or operation history. It covers the destructive core, not the save-test-restore variant.

## Results and completion checks

Each execution creates a unique `results/w16_.../` directory. Outputs include:

- `e2e_w16_scenarios.csv`: 4609 rows of actual diagnosed maps and per-scenario PASS status.
- `e2e_w16_summary.csv`: aggregate detection, localization, primary/mixed-pattern counts, TMR failures and protocol-check status.
- `e2e_w16_PASS.txt`: created by the testbench only after all assertions and final count checks pass.
- `RUN_CONFIGURATION.txt`: tool version, width and experiment assumptions.
- Simulator logs when available, plus the complete on-disk simulation project.

The Tcl driver validates the testbench's completion marker, CSV row count and summary status. It does not declare success merely because simulation returned. On failure, inspect `RUN_FAILED.txt` in the latest attempt directory and the Vivado log. A previous successful `LATEST_RUN.txt` can remain after a later failed attempt; use the current console result and newest attempt directory when troubleshooting.

## Optional 32-bit campaign

The same testbench includes a 32-bit top. After the 16-bit result is confirmed, an optional separate batch run is:

```bat
"C:\AMDDesignTools\2026.1\Vivado\bin\vivado.bat" -mode batch -source "C:\Q2\E2E_BIST\run_e2e.tcl" -tclargs 32
```

This enumerates 18433 scenarios over 96 cells, with 36866 primary checks and another 36866 mixed-pattern checks. The optional campaign is RTL simulation, not an additional implementation sweep.

## Local validation

`local_validation/` contains separately labeled Linux Verilator build/run records and checked results produced while preparing this package. They are RTL simulation records, not Vivado, FPGA implementation, measured-device or board results. Your Vivado run goes into `results/`, keeping tool provenance distinct.

`SOURCE_SHA256.json` identifies the packaged RTL, testbench and runners. The resistance core is copied without modifications from the publication project. The package adds test and run files only.

The next technical experiment after this campaign is a defect-aware baseline under a clearly defined comparison protocol. This package addresses larger-width diagnosis in the BIST loop; it does not add that baseline.

## Vivado command references

- AMD UG900 (2026.1), behavioral simulation and launch_simulation: https://docs.amd.com/r/en-US/ug900-vivado-logic-simulation/Using-the-launch_simulation-Command
- AMD UG900 (2026.1), simulation runtime options: https://docs.amd.com/r/en-US/ug900-vivado-logic-simulation/Vivado-Simulator-Simulation-Options
- AMD UG900 (2026.1), elaboration threading: https://docs.amd.com/r/en-US/ug900-vivado-logic-simulation/xelab-xvhdl-and-xvlog-xsim-Command-Options
