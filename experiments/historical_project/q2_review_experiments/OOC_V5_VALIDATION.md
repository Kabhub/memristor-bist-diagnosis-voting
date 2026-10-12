> **Historical local validation note.** This records tool/control-flow checks
> from its original preparation stage. Completed experiment data are in
> the repository-root results/ directory; use docs/EVIDENCE_MAP.md to
> locate the final evidence.

# OOC v5 implementation correction

This patch follows the uploaded three-row `implementation_summary.csv`, the
W8 routed timing report, and the W32 placement failure message.

## Findings

The W8 report lists 58 inputs without input delays and 9 outputs without output
delays. It reports infinite slack and no intra-clock setup/hold paths. The
original campaign constrained only `clk`, making its apparent 100-MHz pass
unusable as timing-closure evidence.

The plain TMR W32 wrapper has 227 inputs and 33 outputs, including both
96-bit fault maps: 260 total package signals. The target XC7Z020-CLG484 has
200 programmable-logic SelectIO pins. Default synthesis inserts I/O buffers,
so the original pin-based implementation cannot place the entire interface.
The provided final placer error is generic; the earlier detailed placer log
would still be needed to identify every reported placement violation.

Unexpected closure of the Vivado application is not explained by these two
reports. The campaign contains no `exit` command. Preserve the application
log or a crash log if that happens again.

## Changes

- Use `synth_design -mode out_of_context` for reusable-core analysis.
- Constrain every non-clock input and every output relative to `review_clk`.
  Maximum interface delays are each 20% of the period; minimum delays are
  0 ns. These are stated comparison assumptions, not measured PCB delays.
- Preserve applied XDC and per-run method notes beside the reports.
- Reject missing or non-finite slack as an invalid evidence run.
- Require both setup and hold to pass for `timing_met=1`.
- Stop the campaign after a tool or metric-extraction failure.
- Keep corrected results under `vivado_quick_ooc_v5` / `vivado_full_ooc_v5`.
- Add a one-design W32 check before the longer campaign.
- Include the reused W32/default/100-MHz resource row in timing statistics.

## Validation performed locally

A Tcl command-flow harness passed six cases: finite timing; infinite timing;
empty timing; negative hold slack; the complete 55-run quick matrix; and a
placement failure that stops after one implementation. These checks also
verify OOC mode, input/output min/max delay commands, project closure, and
completion-marker behavior. The temporary test project path contains spaces.

This is mocked control-flow validation, not execution of Vivado synthesis,
placement, or routing. Those checks remain pending on the user's PC.

## Primary documentation

- AMD UG835, `synth_design` (2026.1):
  https://docs.amd.com/r/en-US/ug835-vivado-tcl-commands/synth_design
- AMD UG903, About Constraining I/O Delay (2026.1):
  https://docs.amd.com/r/en-US/ug903-vivado-using-constraints/About-Constraining-I/O-Delay
- AMD DS190, Table 2, device-package combinations:
  https://docs.amd.com/v/u/en-US/ds190-Zynq-7000-Overview
