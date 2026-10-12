> **Historical local validation note.** This records tool/control-flow checks
> from its original preparation stage. Completed experiment data are in
> the repository-root results/ directory; use docs/EVIDENCE_MAP.md to
> locate the final evidence.

# Package validation record

Validation date: 2026-10-10

Windows path fix: source files are passed to Vivado one Tcl list item at a
time, so a parent directory such as `q2 pubes` is preserved as one path.
Functional simulations use disposable on-disk projects because Vivado does not
permit fileset-based `add_files` operations in an in-memory project.

| Check | Result |
|---|---|
| `run_fault_coverage.py` at 8/16/32 bits | PASS |
| `run_adaptive_variation.py` at 100,000 trials per state/data value | PASS |
| `run_vteam_validation.py` | PASS |
| Python bytecode compilation for all four scripts | PASS |
| Vivado-summary parser with the explicitly synthetic example CSV | PASS |
| SystemVerilog parse and elaboration (core, four new RTL files, two testbenches) | PASS: 0 errors; 11 intentional empty-output warnings |
| Tcl structural completeness for all campaign scripts | PASS |
| Existing compiled publication architecture regression | PASS |
| New Vivado xsim functional tests | PENDING on user PC: Vivado is not installed in this build environment |
| New post-route Vivado area/timing/power campaign | PENDING on user PC |

The reference software results shipped in `review_results` were regenerated
with the default seeds and sample counts. The unfilled Vivado results are
intentionally not fabricated; run the numbered Windows/Vivado steps and return
`q2_review_results.zip`.

## Reference-run invariants

- Proposed bit-level diagnosis: 100% accepted-correct and zero silent data
  corruption over the exact no/single/double stuck-HRS/LRS campaign at 8, 16,
  and 32 bits.
- Standard TMR: exactly `6 x WIDTH` wrong word checks across the aggregate
  campaign, corresponding to same-bit double faults that agree against the
  stored value.
- SECDED: zero silently accepted double-bit corruption; activated double-code-
  bit errors are detected and rejected rather than called corrected.
- VTEAM nominal SET and RESET endpoint classification: 100% agreement for the
  stated published parameter set and pulse assumptions.

Aggregate rates across architectures should not be compared without noting
their different physical codeword sizes. Use `coverage_by_fault_order.csv` for
like-for-like no-, single-, and double-fault statements, and always report the
physical-cell count beside the total scenario count.
