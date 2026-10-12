# Added reviewer experiments

## Actual execution

The CSVs and PASS markers are actual Verilator 5.49 RTL and Python/NumPy outputs.
No Vivado implementation results were created in this workspace.

The new-fault sweep uses unchanged W16 proposal and remapping RTL. Each independent
case starts from reset, runs actual clean BIST, writes one of 0x0000, 0xffff,
0xaaaa or 0x5555, and injects one SA-LRS or SA-HRS at every cell. The first read
occurs with stale zero diagnosis maps and no retest. Proposal: 384/384 correct;
compact remap: 80/144 correct plus 64 SDC; matched remap: 320/384 plus 64 SDC.
All runs localize the added fault on actual BIST and become correct after rewriting.
Retest plus rewrite restores service; it does not recover already lost data.
This clean-start sweep does not exhaust previously diagnosed-fault histories.

Reproduce RTL (Linux, Verilator with C++20 support):

    verilator --binary --timing --assert -CFLAGS '-std=c++20' --top-module tb_late_fault_sweep rtl/publication_scalable_memristor_core.sv rtl/q2_shared_spare_core.sv tb_late_fault_sweep.sv
    ./obj_dir/Vtb_late_fault_sweep

Verilator local prebuilt make configuration required CFG_CXXFLAGS_PCH_I=-include
and CFG_CXXFLAGS_STD=-std=c++20. This was a local toolchain build setting, not
an RTL change. A standard installed Verilator should already configure its compiler.
The simulator creates per-scheme CSV, summaries and PASS markers in the working directory.

Reproduce paired sensing (Python 3 with NumPy and Matplotlib):

    python run_geometric_comparison.py

The original sensing model is copied unchanged as run_adaptive_variation.py.
100,000 trials per stored value, six profiles, read-noise CV=0.15, one read,
no guard. Arithmetic 5,050 ohm, geometric 1,000 ohm, and held-out calibrated
thresholds reuse identical evaluation random streams. Arithmetic counts exactly
reproduce the prior fixed_r1 data. Severe geometric outcomes: 199,942 correct,
13 false accepted, 45 rejected in 200,000. Paired calibrated: 200,000 correct.
Original guard/five-read results remain unpaired controls in the manuscript.
The software all-agree sensing policy differs from the RTL majority policy.

VALIDATION_RECORD.json and audit.log describe independent count/oracle checks and
Tcl command-stub validation. Stub reports are not supplied as measured evidence.
