# Reproduce the experiments

Batch launchers and the documented Vivado flows target Windows; the Verilator
commands below target Linux with a C++20 compiler and GNU Make. Run commands from the specified experiment directory. Drivers locate source relative to their own file. Do not mix source revisions or overwrite recorded results/.

## End-to-end BIST

From experiments/q2_e2e_campaign on Windows, double-click RUN_16_BIT.bat, or run Vivado in batch with `-source run_e2e.tcl -tclargs 16`. The driver creates a separate on-disk simulation project. Success requires ALL 4609 END-TO-END BIST SCENARIOS PASSED and e2e_w16_PASS.txt; check LATEST_RUN.txt for output location.
For W32 use the same Tcl driver with `-tclargs 32`; the supplied recorded W32 result is from Verilator, not XSIM.

Linux W16/W32 alternative from that directory (use a fresh copy to preserve recorded output files):

```sh
verilator --binary --timing --assert -CFLAGS '-std=c++20' --top-module tb_q2_bist_e2e_w16 rtl/publication_scalable_memristor_core.sv tb/tb_q2_bist_e2e.sv
./obj_dir/Vtb_q2_bist_e2e_w16
```

Replace both top/executable suffixes with w32 for W32. Check testbench declarations if using another tool version.

## Defect-aware baselines

From experiments/q2_remap_baseline on Windows, run 1_RUN_SIMULATION.bat then 2_RUN_IMPLEMENTATION.bat. Simulation checks both spare counts; implementation evaluates three registered designs at W16. See its README and source manifest for exact protocol, resume handling and Vivado path override.

## Placement sensitivity

From experiments/Q2_Placement_Study on Windows, run RUN_PLACEMENT_STUDY.bat. Expected matrix is 3 designs x 3 placement directives at 100 MHz. Outputs are placed in that packet's results/placement_study_w16. Completion requires IMPLEMENTATION_COMPLETE.txt, nine COMPLETE.txt markers and nine PASS rows with timing_met=1. A flow PASS alone does not establish timing closure.
Recorded originals are under the repository's results/placement_sensitivity.

## Clean-start new-fault sweep

From experiments/late_fault_and_geometric (Linux):

```sh
verilator --binary --timing --assert -CFLAGS '-std=c++20' --top-module tb_late_fault_sweep rtl/publication_scalable_memristor_core.sv rtl/q2_shared_spare_core.sv tb_late_fault_sweep.sv
./obj_dir/Vtb_late_fault_sweep
```

The recorded Verilator build used CFG_CXXFLAGS_PCH_I=-include and CFG_CXXFLAGS_STD=-std=c++20 as local toolchain settings. Three *_late_PASS.txt markers, scenario CSVs and summary CSVs should be generated. Every independently reset case runs clean BIST, writes a background, adds one fault, observes stale maps, retests and rewrites. No lost-data recovery is inferred.

## Paired geometric-threshold study

Copy experiments/late_fault_and_geometric to a fresh working directory before running if you wish to retain its original CSVs, then execute:

```sh
python run_geometric_comparison.py
```

Expected 36 profile/strategy/stored-value rows, 100000 trials per stored value. Seed 20261010. Severe geometric totals: 199942 correct, 13 false accepted, 45 rejected; paired calibration: 200000 correct. Other original sensing/model generators live in experiments/historical_project/q2_review_experiments/python and expose --help. Python dependencies are in the root requirements.txt.

## Original registered baselines and models

Preserve the entire experiments/historical_project layout. Use q2_review_experiments/2_RUN_VIVADO_FUNCTIONAL.bat for TMR/SECDED/preservation functional checks, and 3C_RUN_REGISTERED_QUICK.bat for the registered matrix. Do not substitute older unregistered wrapper results for registered core counts. Consult q2_review_experiments/REGISTERED_V7_VALIDATION.md and its README.

## Board demonstration

Use board/README.md. Hardware compilation/programming needs Vivado and a ZedBoard; no FPGA board is needed for the software and RTL-only simulations.

## Independent plain-TMR comparison

From experiments/plain_tmr_late_fault/ (Linux), use its README commands. The existing plain-TMR module has no BIST or diagnosis map. Success requires ALL 384 PLAIN TMR SINGLE-NEW-FAULT CHECKS PASSED, a 384-row scenario CSV and plain_tmr_late_PASS.txt. The supplied actual trace passes every site/polarity/background case.

## Numeric figures

From repository root run `python scripts/regenerate_figures.py`. It rebuilds numeric plots 3-11 from recorded CSVs under figures/regenerated. Styling may differ from the preserved publication masters; the source data are the same. Architectural diagrams are retained as supplied image/vector masters. Consult docs/figure_number_mapping.json for current main/supplement numbering.

## Explicit three-primary boundary output checks

Windows: run experiments/three_primary_boundary/1_RUN_SIMULATION.bat from a short
local extraction path. This reruns the functional campaigns and adds 32 explicit
proposal/plain-TMR assertions for IDs 0,1,2. It does not run implementation.
Require ALL 32 THREE-PRIMARY PROPOSAL AND PLAIN-TMR WORD CHECKS PASSED and
ALL DEFECT-AWARE BASELINE TESTS PASSED. The detailed trace must contain 32 rows.
Linux commands and the exact scope are in the experiment README. The supplied
added results are actual Verilator records in results/three_primary_boundary.
