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
The returned source manifest matches the delivered packet. Results do not
include an independent runtime source rehash or a per-run command transcript.
Raw reports and checkpoints are preserved exactly as returned.

The updated manuscript includes Table 10 and revises methods, limitations,
conclusion and Appendix B. Earlier tables use their stated Default boundary.
Total execution records: 28; unique configurations: 24 (23 at 100 MHz).
Default repetitions are execution records, counted once as configurations.
No figures or bibliography entries were changed in this revision.

Remaining author work: confirm conflict/funding/contribution facts and data
repository; optional author-deferred board photos; choose the target journal
and follow its submission requirements. Real-device and multiword validation
remain research limitations, not results inferred from this study.
