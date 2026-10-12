# Q2 Reviewer Experiment Pack

This folder adds the experiments requested during review without replacing the
original publication evidence.  It addresses the weak-baseline, scale,
device-realism, variation, implementation-robustness, and destructive-BIST
comments.

## What is included

| Evidence | Scope | Main output |
|---|---|---|
| Exact fault coverage | no fault plus every single and distinct double stuck-HRS/LRS fault at 8, 16, and 32 bits | `review_results/coverage/coverage_summary.csv` |
| Stronger baselines | standard TMR, module-level self-purging TMR, SECDED, and proposed bit-level diagnosis | coverage CSVs plus synthesizable RTL |
| Variation mitigation | fixed/calibrated thresholds, 10% guard band, and 1/3/5 repeated reads | `review_results/variation/` |
| Device-model validation | published VTEAM equations and Pt-Hf-Ti parameter set; read-disturb, drift, short-pulse, and intermittent sensitivity | `review_results/device_validation/` |
| Data preservation | 8-cycle save-test-restore-verify BIST beside the original 5-cycle destructive BIST | RTL, testbench, and Vivado implementation rows |
| Implementation robustness | 8/16/32-bit resource scaling and 32-bit multi-constraint/multi-strategy runs | `review_results/vivado_quick/` |

`accepted-correct` always means `correct AND not rejected`, divided by all
trials. `correct | accepted` is reported separately. This prevents guard-band
rejections from being counted as successful corrections.

## Run order on Windows

Extract the ZIP first. Open **Command Prompt** in this folder and run:

```bat
0_INSTALL_PYTHON_DEPS.bat
1_RUN_SOFTWARE_EXPERIMENTS.bat
```

Then open the **Vivado Tcl Shell** or Vivado's Tcl console and follow
`RUN_FROM_VIVADO_TCL.txt`. Run functional simulation before implementation.

The recommended implementation campaign is `3_RUN_VIVADO_QUICK.bat` from a
Vivado-enabled command prompt. It is resumable: completed runs have a
`COMPLETE.txt` marker and are skipped if the command is restarted. The full
campaign is optional and much longer.

After Vivado completes:

```bat
4_SUMMARIZE_VIVADO_QUICK.bat
5_PACKAGE_RESULTS.bat
```

Send back `q2_review_results.zip`. It contains the CSVs, metadata, reports,
checkpoints, and figures needed to update the journal.

## Experiment boundaries

- Python coverage is exact for the stated no/single/double stuck-at model; it
  is not an FPGA implementation result.
- VTEAM is a published-model endpoint validation, not measured characterization
  of a physical memristor attached to the ZedBoard.
- The variation campaign is a seeded assumed-model sensitivity study. Static
  device-to-device spread and temporal read noise are kept separate.
- Vivado power is post-route vectorless estimation, not measured board power.
- Vivado 7-series implementation directives are treated as strategy variation,
  not described as random seeds.
- A timing-clean implemented constraint is reported separately from the
  WNS-derived margin indicator; the latter is not called measured Fmax.

## Primary model reference

S. Kvatinsky, M. Ramadan, E. G. Friedman, and A. Kolodny, “VTEAM: A General
Model for Voltage-Controlled Memristors,” *IEEE Transactions on Circuits and
Systems II: Express Briefs*, 2015, DOI: `10.1109/TCSII.2015.2433536`.

