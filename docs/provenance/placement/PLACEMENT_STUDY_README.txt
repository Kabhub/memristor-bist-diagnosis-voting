Completed placement-strategy study, 11 October 2026

Nine Vivado 2026.1 routed runs: W=16, XC7Z020-CLG484-1, 100 MHz.
Proposed destructive, compact two-spare remapping, matched-cell remapping.
Default, Explore and ExtraNetDelay_high placement; fixed Default routing.
All nine satisfy setup/hold timing. Zero internal unconstrained endpoints,
zero setup/hold/pulse-width failing endpoints, zero methodology checks.

WNS ranges (ns): proposed 4.084-4.121; two-spare 2.809-2.856;
matched-cell 0.565-0.739. LUT/FF: 278/165, 462/157, 1820/313,
respectively, unchanged across strategies. WHS ranges (ns): proposed
0.157; compact 0.091-0.116; matched 0.145.
Vectorless total/dynamic power (mW): 107/4, 108/5, 116/13;
unchanged at the raw reports' 1-mW precision, Medium confidence.

These are three directive choices, not independent random seeds. Internal
registered OOC timing does not establish interface timing or verified Fmax.
Power includes benchmark register banks and BUFG; it is not board power.
Source manifests and raw reports are included in results/placement_sensitivity.
The three Default repetitions are separate execution records but represent
the same configurations. The study evaluates nine directive configurations;
the wider recorded dataset contains 28 execution records and 24 unique
configurations (23 at 100 MHz). Real-device and multiword-array validation
are outside this experiment's scope.
