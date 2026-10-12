# Explicit three-primary boundary assertions

This simulation checks the W16 proposal under three stable faults at physical
IDs 0,1,2. In its three-replica layout these affect three distinct logical bits
of replica A, leaving two healthy replicas per affected bit. All eight LRS/HRS
polarity assignments and four backgrounds are checked: **32 word checks**.
Actual BIST produces the maps before writes. Output, map, diagnosis-valid and
zero-rejection assertions are explicit; plain TMR is also asserted correct.

This is a selected three-fault placement sweep. It does not prove correction
of arbitrary three faults: faults at IDs 0,16,32 remove all replicas of bit 0
and the proposal must reject that bit, as checked separately in the same run.

The runner also repeats the existing 649-scenario compact-remapper and
4,609-scenario matched-remapper campaigns. Added boundary checks have separate
counts and do not change their original single/double-fault denominators.

## Windows / Vivado 2026.1

Extract the repository into C:\Q2\repo. Open
experiments\three_primary_boundary and double-click 1_RUN_SIMULATION.bat.
No synthesis, implementation or board programming is launched.
Use a short local directory and retain the whole experiment folder.
Read LATEST_SIMULATION.txt for the result directory. Success requires:

- ALL 32 THREE-PRIMARY PROPOSAL AND PLAIN-TMR WORD CHECKS PASSED
- ALL DEFECT-AWARE BASELINE TESTS PASSED
- proposed_three_primary_PASS.txt and a 32-row word-check CSV

## Linux / Verilator

Run from a fresh copy of this folder to preserve recorded data:

```sh
verilator --binary --timing --assert -Wno-fatal -CFLAGS '-std=c++20' --top-module tb_q2_remap_w16 rtl/publication_scalable_memristor_core.sv rtl/q2_shared_spare_core.sv tb/tb_q2_remap.sv
./obj_dir/Vtb_q2_remap_w16
```

Evaluated source hashes are in SOURCE_SHA256.json. Recorded results are kept
separately under repository-root results/three_primary_boundary/.
