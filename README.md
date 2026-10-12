# Resistance-aware BIST and diagnosis-guided voting

Reproducibility repository for **FPGA-Based Resistance-Aware BIST and Diagnosis-Guided Voting for Double-Fault-Tolerant Behavioural Memristor Memory**.
Authors: Joel Purohit, Kabir Sahani, Sameek Bane and Jalpaben Pandya.
The manuscript is in preparation; no publication DOI or public repository URL is assigned in this package.

## What is evaluated

A two-state behavioural memristor model, resistance-state BIST, separate stuck-LRS/stuck-HRS diagnosis maps, bit-level health-guided voting and validity/rejection signaling. The comparison includes standard TMR, representative word-agreement self-purging TMR, SECDED, offline data preservation and two BIST-guided shared-spare remappers.

Actual RTL campaigns use BIST-generated maps. Software perfect-map enumeration is a separate voter/coding cross-check. FPGA resource results measure behavioural emulation and digital protection on XC7Z020, not physical memristor cell area.

## Layout

- `experiments/q2_e2e_campaign/`: actual BIST-in-loop campaign, parameterized testbench and Windows XSIM runner.
- `experiments/q2_remap_baseline/`: two-spare/matched-cell remapping, simulation and implementation runners.
- `experiments/Q2_Placement_Study/`: the nine-run W16 placement runner and checked source manifest.
- `experiments/plain_tmr_late_fault/`: independent no-BIST TMR comparison, actual 384-case trace and pass log.
- `experiments/late_fault_and_geometric/`: exhaustive clean-start late-fault RTL sweep and paired threshold Python study.
- `experiments/historical_project/`: original source layout required by the registered-baseline and model drivers. Its q2_review_experiments subtree contains the current registered benchmark drivers; older wrapper drivers are retained for historical reproduction only.
- `board/`: ZedBoard single/double-fault tops, OLED controller, testbenches and XDC constraints.
- `results/`: recorded end-to-end, defect-aware, registered, software and completed placement outputs.
- `figures/`: publication figures and available vector masters.
- `scripts/`: portable integrity verification and numeric figure regeneration from recorded CSVs.
- `docs/`: reproduction instructions, evidence map, scope and publication tasks.
- `archive/initial_campaigns/`: initial wrapper, SAIF, noise-free characterization and original run logs.

## Setup and execution

See [docs/REPRODUCE.md](docs/REPRODUCE.md) for commands and expected completion checks.
Tested recorded tools: Vivado/XSIM 2026.1, part xc7z020clg484-1; Linux Verilator 5.49 for local RTL campaigns. Python models require NumPy and Matplotlib (`requirements.txt`). C++20/compiler support is needed for the recorded Verilator setup.
On Windows use a short local extraction path, for example `C:\Q2\memristor-bist-diagnosis-voting`, and avoid OneDrive for XSIM build directories. Original batch launchers check the known Vivado installation and then PATH; the per-experiment README documents overrides.

```sh
python scripts/verify_package.py
python -m pip install -r requirements.txt
```

Recorded results are kept separate from freshly generated output directories. Preserve the recorded CSVs and compare your new summaries against the evidence map.

## Recorded evidence

- End-to-end nominal fault scenarios: W8 1,153 (Verilator), W16 4,609 (XSIM), W32 18,433 (Verilator). Wider campaigns exercise all-zero/all-one and alternating/complement backgrounds.
- Shared-spare static scenarios at W16: 649 for 18 cells and 4,609 for 48 cells, with four backgrounds.
- Clean-diagnosis single-new-fault sweep: proposal 384/384 correct; compact remapper 80/144 correct and 64 silent wrong words; matched remapper 320/384 and 64 silent wrong words. This demonstrates residual replication versus remapping without a fresh test. The independent plain-TMR baseline in experiments/plain_tmr_late_fault/ also passes 384/384 actual RTL checks without BIST. This confirms replication masking, rather than a unique diagnosis-guided benefit, for the clean-start sweep.
- Nine completed placement runs: W16, three designs, Default/Explore/ExtraNetDelay_high placement, Default routing, 100 MHz. All meet setup and hold timing. These are directive choices, not independent random seeds.
- Software sensing pairs arithmetic, geometric and calibrated one-read thresholds; guard/five-read controls retain independent streams. VTEAM is an endpoint/model check, not measured-device validation.

The shortened manuscript has 17 pages and its supplement has 7 pages. Figures keep their original asset filenames; docs/figure_number_mapping.json maps these to the current captions.

See [docs/EVIDENCE_MAP.md](docs/EVIDENCE_MAP.md) for the current manuscript table-to-file map. Historical driver READMEs and raw logs describe their original execution context. Statements there about an experiment awaiting execution are historical; the recorded completion status above and in results/ is current.

## Scope

The fault model injects stable stuck-state faults into behavioural storage cells. Correct controller/voter/metadata operation is assumed. Three-fault boundaries, a clean-start new-fault sweep and software sensitivity do not establish arbitrary transient, read-disturb, wear or correlated-failure tolerance. The shared-controller multiword architecture remains a proposed sketch.

## Equipment and contributions

Jalpaben Pandya provided the FPGA board and supervision. No external funding was received (author-confirmed statement for the current revision). Joel Purohit: formal analysis; Kabir Sahani: design/methodology, coding and testing; Sameek Bane: writing and documentation; Jalpaben Pandya: supervision and equipment resources. Additional CRediT roles require factual author confirmation.

## Citation and reuse

`CITATION.cff` identifies the software authors/title without inventing a journal, DOI or repository URL. Before publishing, select the reuse licence with the authors/mentor; this package does not invent a licence grant. See docs/PUBLICATION_TASKS.md. No third-party paper PDFs or Vivado installation/licence files are included. The manuscript and board photographs are delivered/managed separately.
