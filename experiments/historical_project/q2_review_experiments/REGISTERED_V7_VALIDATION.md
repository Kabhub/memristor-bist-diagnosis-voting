# Registered benchmark v7

Evidence from v6: standard TMR W32 completes implementation, but setup
WNS is +0.598 ns, hold WHS is -0.833 ns, and 192 hold endpoints fail.
The detailed worst paths start at the external reset port and show reset
and clock net segments marked unset. The method report reports zero checks.
Zero methodology checks do not establish timing closure.

AMD UG905 explains that OOC boundary interface nets are not routed without
partition-pin constraints. The new benchmark avoids treating these boundary
estimates as an integrated interface by surrounding each existing wrapper
with physical launch/capture registers and an instantiated BUFG.

The original five functional architecture wrappers and cores are unchanged.
All input and output signals pass through their corresponding bank stage,
including reset, BIST control, fault injection, and diagnosis/status outputs.
Only external port-to-input-bank and output-bank-to-port paths are excluded.
All internal register-to-register paths are timed, and worst reported setup
and hold endpoints are checked for sequential-cell ownership.

This is a new experiment, not a repaired version of the same measurement.
Old v5/v6 rows must not be combined with v7 timing or area comparisons.
Results use a separate vivado_quick_registered_v7 namespace.
Core area is taken from report_utilization -cells [get_cells dut]; complete
benchmark area and bank overhead are reported separately. Power remains
whole-benchmark vectorless power, not isolated-core or measured board power.
The harness adds an input stage and an output stage; original core BIST
latency counts are unchanged and are not the harness end-to-end latency.

Completed local validation:
- pyslang elaboration of five shells at WIDTH 8/16/32: zero RTL errors.
  The local check uses a behavioral BUFG stub, not AMD primitive simulation.
- Structural connection checks: every core input/output uses its bank stage.
- Eleven Tcl command-flow cases: valid run; inf/empty slack rejection;
  residual negative hold; simulated successful hold repair; missing clock
  site; 55-job quick matrix; early placement-failure stop; missing DUT
  hierarchy; malformed resource metrics; outer-port path rejection.
- Control-flow tests use mocked commands and synthetic results in temporary
  directories. They are not FPGA implementation results.

The Vivado W32 check is still required. Timing closure is not guaranteed.
Final integrated board timing is a separate hardware implementation result.

Primary sources:
- https://docs.amd.com/r/2022.2-English/up905-vivado-hierarchical-design/Context-Constraints
- https://docs.amd.com/r/en-US/ug953-vivado-7series-libraries/BUFG
- https://docs.amd.com/r/en-US/ug835-vivado-tcl-commands/report_utilization
- https://docs.amd.com/r/2025.2-English/ug835-vivado-tcl-commands/get_timing_paths
