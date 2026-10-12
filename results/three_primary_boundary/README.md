# Verified three-primary boundary result

Actual Linux Verilator execution on 12 October 2026: **32/32 proposal checks and
32/32 plain-TMR checks passed**, with exact BIST maps, valid diagnosis and no
rejection. Faults are at physical cells 0,1,2 (replica A, three distinct logical
bits); eight LRS/HRS assignments and four word backgrounds were checked.

The same simulation reran the 649 and 4,609 static remapping scenarios with
their original denominators; all passed. Source hashes, the detailed 32-row
boundary trace, all scenario/summary CSVs and actual build/run logs are included.

The proposal boundary assertions are in the new experiment's testbench. Earlier
boundary CSVs remain unchanged; the older accepted_correct text for this case
did not itself constitute an explicit proposal-output assertion. Use this new
trace to support the verified result. This selected configuration is repairable
because each affected bit has two healthy replicas. It does not extend the
arbitrary-two-fault guarantee to all triple-fault placements. The all-three-
replicas-of-one-bit rejection check also passed in the same run.

Build: about 20 seconds; simulation: about 0.9 seconds in this environment.
These durations are not estimates of Vivado/XSIM performance. Windows
reproduction uses experiments/three_primary_boundary/1_RUN_SIMULATION.bat.
No added synthesis, implementation or board measurement was performed.
