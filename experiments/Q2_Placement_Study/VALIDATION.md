> **Historical local validation note.** This records tool/control-flow checks
> from its original preparation stage. Completed experiment data are in
> the repository-root results/ directory; use docs/EVIDENCE_MAP.md to
> locate the final evidence.

# Validation boundary

RTL files are byte-for-byte copies of the W16 packet already tested in XSIM and
Verilator. Current changes touch only the implementation matrix and runner text.
The previous three-design registered implementation method, hierarchy boundary,
BUFG context, hold-repair procedure and report parsing are retained.

Local Tcl command-stub tests exercise the nine-call matrix, path handling with
spaces, failure stop, missing clocks/DUT/metrics, non-register timing endpoints,
non-finite slack, hold repair, source-manifest consistency and completed-run resume.
These tests validate script control flow only. Vivado is unavailable in this
workspace. Actual placement/routing and device reports require the user's PC.

Default/Explore/ExtraNetDelay_high are documented in AMD UG835 version 2026.1.
They are strategy configurations, not randomly selected placement seeds.
