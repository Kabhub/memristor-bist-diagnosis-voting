# OOC v6 clock-context and hold patch

The uploaded v5 report has routed state, no unconstrained endpoints,
setup WNS +0.678 ns, hold WHS -0.314 ns, and 288 failing hold endpoints.
The summary records 162 LUTs, 96 FFs, and timing_met=0. The worst hold
path is operational_write_data[0] to a stored_resistance register, with
zero input min delay and 0.973 ns destination-clock insertion delay.
These values do not establish timing closure or measured board Fmax.

The prior script omitted the external clock-buffer location. AMD identifies
HD.CLK_SRC as the OOC context property for an external clock buffer and
uses this property in OOC IP benchmarks to support correct hold closure.
This omission needs correction; the next run will determine how much of
the observed hold violation is resolved by the corrected context.

Changes:
- Declare HD.CLK_SRC BUFGCTRL_X0Y0 after create_clock, validating the site.
- Apply the same declared clock context to all implementations.
- Use ExploreWithHoldFix before routing; conditionally attempt one
  post-route hold_fix followed by rerouting when hold slack is negative.
- Preserve interface timing budgets and setup/hold pass criteria.
- Write detailed hold_paths.rpt and method metadata.
- Use vivado_quick_ooc_v6 / vivado_full_ooc_v6 to avoid old completion markers.

OOC boundary nets are not full-system routed interfaces. Their timing is
an estimate under the declared module-interface and external-clock context.
Final board timing requires implementation of the integrated board design.

Validation is Tcl control-flow testing using mocked Vivado commands, not a
Vivado implementation. Cases cover valid extraction, nonfinite setup slack,
remaining hold violations, successful simulated hold repair, unavailable
clock context site, a 55-job matrix, and early placement-failure stop.
Actual placement, routing, and hold closure still require Vivado on the PC.

Primary AMD documentation:
- https://docs.amd.com/r/2022.1-English/ug905-vivado-hierarchical-design/Context-Constraints
- https://download.amd.com/docnav/documents/ip_attachments/clk-wiz.html
- https://docs.amd.com/r/en-US/ug835-vivado-tcl-commands/phys_opt_design
