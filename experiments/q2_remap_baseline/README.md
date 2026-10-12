# Defect-aware comparison for the memristor paper

## Run on your Windows PC

1. Extract this ZIP into `C:\Q2`. You should see
   `C:\Q2\DEFECT_BASELINE\1_RUN_SIMULATION.bat`.
2. Double-click **1_RUN_SIMULATION.bat**. This creates a separate Vivado
   simulation project; your board project does not need to be open.
3. Continue only after **ALL DEFECT-AWARE BASELINE TESTS PASSED**.
4. Double-click **2_RUN_IMPLEMENTATION.bat**. This performs **three**
   16-bit, 100 MHz registered comparisons. It stops on a flow/metric error.
5. Zip the entire `DEFECT_BASELINE\results` folder and send it back. Also
   send `vivado.log` if a run failed. No board programming is required.

The launchers look for
`C:\AMDDesignTools\2026.1\Vivado\bin\vivado.bat`, then `vivado.bat` on PATH.
For another installation, set `Q2_VIVADO_BIN` to its `bin` directory.
Use a short path such as `C:\Q2` to avoid Windows generated-C path issues.
The Tcl drivers preserve spaces in source filenames. Simulation uses a saved
project, single-thread elaboration and debug disabled, as in the successful
16-bit end-to-end package.

If needed, use a separate, empty Vivado Tcl session:

```tcl
source {C:/Q2/DEFECT_BASELINE/run_simulation.tcl}
# Only after the functional simulation has passed:
source {C:/Q2/DEFECT_BASELINE/run_implementation.tcl}
```

`LATEST_SIMULATION.txt` and `LATEST_IMPLEMENTATION.txt` identify the result
folders. Simulation always uses a fresh timestamped folder. Implementation
resumes completed runs in `results/implementation_w16`; failed rows are
replaced on a successful retry. Completed rows are skipped only when their
reports and unique PASS row exist. Restarting after a Vivado crash can repeat
the incomplete design, but completed designs remain available. Run one
implementation launcher at a time. To deliberately start fresh, rename the
old `implementation_w16` folder first. Source-manifest changes require a new
functional simulation and a fresh implementation folder.

## What is being compared

All designs store one 16-bit logical word. Every physical cell is the exact
previously validated `publication_memristor_cell`: nominal LRS=100 ohm,
HRS=10,000 ohm and classification threshold=5,050 ohm. The original proposed
core is unchanged. Both controllers test resistance after writing zero and
one. Test results, rather than an oracle fault map, drive voting/allocation.

| Design | Physical cells | Redundancy | Diagnosis cycles | Allocation cycles | Total test cycles |
|---|---:|---|---:|---:|---:|
| Proposed destructive BIST + voter | 48 | Three replicas per logical bit | 5 | 0 | 5 |
| Compact shared-spare remapper | 18 | 16 primaries + 2 shared spares | 5 | 16 | 21 |
| Matched-cell shared-spare remapper | 48 | 16 primaries + 32 shared spares | 5 | 16 | 21 |

Cell IDs `0..15` are primaries in the remapper; subsequent IDs are spares.
In the proposal, IDs `0..15`, `16..31`, `32..47` are replicas A, B, C. A healthy
primary keeps its address. Faulty primaries, in ascending logical-bit order,
receive the lowest-index healthy unused spare. A registered mapping redirects
normal writes and reads; unused spares receive no operational writes. Allocation
scans one logical bit per cycle, including healthy bits. **The 16-cycle scan is
an implementation choice, not a lower bound for all remapping schemes.**
Mapping registers, the spare-priority encoder, write routing and read routing
are all synthesized and charged to baseline area.

All three tests are destructive; test data overwrite stored data. All require
an external save/restore mechanism to protect live user data. After a completed
test and normal write, each core offers one rising-edge write and a
combinational read. The measurement shell adds one input stage and one output
stage; its stages are separate from the core test-cycle counts.

## Exhaustive functional campaigns

Stable stuck-LRS/stuck-HRS faults are injected into **all physical cells,
including spares**. For `C` cells, the campaign includes one no-fault scenario,
`2C` single-fault scenarios and `4 * C(C-1)/2` double-fault scenarios:
`N = 1 + 2C^2`. Faulty sites are distinct; all four double-fault polarity
combinations are covered. BIST runs anew for every scenario, without resetting
between scenarios. Four word backgrounds follow each diagnosis: zero, one,
alternating bits and their complement. This is exhaustive fault-site/polarity
enumeration for those backgrounds, not an exhaustive sweep of all 65,536 words.

| Campaign | Cells | Scenarios | Injected scenarios | Word checks |
|---|---:|---:|---:|---:|
| Two-spare baseline | 18 | 649 | 648 | 2,596 |
| Matched-cell baseline | 48 | 4,609 | 4,608 | 18,436 |

The matched-cell campaign instantiates the actual proposed BIST/voter alongside
the remapper. Both receive the same physical-ID injection maps and writes.
Their data layouts differ, which is stated above. Conventional TMR output is
also checked, using the same proposed cells. The compact campaign has a
different cell count and denominator; do not present its raw scenario count
as a like-for-like coverage denominator against 48-cell TMR.

The testbench verifies exact LRS/HRS localization and health maps, every
logical-to-physical address, healthy/injective allocation, rejection flags,
test latency, stable mapping during operation and data retention with writes
disabled. Oracle maps are assertions only; they never drive the voter or allocator.
Both remappers can recover any two stable faulty cells when at least 16 cells
remain healthy. The proposed scheme's corresponding guarantee assumes at most
two faulty cells overall, so at least one healthy replica remains at each bit.

Extra boundary checks are listed separately in `*_boundary_checks.csv`:

- Three faulty primaries exhaust the compact pool, which flags bit 2 instead
  of accepting a wrong word; the larger pool repairs them.
- Faults at IDs 0, 16 and 32 eliminate all three proposed replicas of bit 0.
  The proposal rejects that bit; the shared pool still repairs its logical word.
- A new stuck-HRS fault at primary ID 0 **after a clean diagnosis** corrupts
  the remapper's single active copy without a fresh rejection flag. The paired
  proposal still has three initially healthy replicas and masks that single
  new fault. This is a selected late-fault test, not exhaustive temporal coverage.
- Retesting repairs the new fault. Clearing faults and rerunning BIST restores
  clean diagnosis and identity mappings.

## Resource and timing evidence

Only three implementations are run: the proposal and the two remappers at
WIDTH=16, 100 MHz, Default placement/routing. The procedure reuses the successful
registered v7 OOC benchmark: physical BUFG at BUFGCTRL_X0Y0, preserved launch
and capture registers, timed internal register paths and explicit exceptions
only for external measurement-bank ports. It avoids package-I/O placement.
Core LUT/FF/BRAM/DSP counts exclude the register banks and clock buffer; total
benchmark counts and overhead are reported separately. The proposal wrapper
and registered shell match the earlier v7 implementation source.

`implementation_summary.csv` retains the established report columns.
`bist_cycles` means total ready-for-operation test latency here: 5 or 21.
The table above separates diagnosis from allocation. PASS means the flow and
metric extraction completed; `timing_met` separately requires nonnegative
setup **and** hold slack. One bounded hold-repair/reroute attempt is allowed.
The margin-derived frequency is an indicator, not verified Fmax. This is one
configuration per design, so it does not replace a timing-robustness study.
Power is a whole-benchmark vectorless estimate including register banks and
BUFG, not measured board power or isolated-core power.

No FPGA LUT counts, timing or power values are predicted in this package.
Those measurements must come from your Vivado reports. Retain any result
showing a baseline advantage; the experiment tests a tradeoff rather than
assuming the proposed design will win every metric.

## Provenance and relation to literature

The baseline implements the established BIST/diagnosis/redundancy-analysis/
remapping idea at individual-cell granularity for this single-word behavioural
model. It is our explicit research baseline, **not** a reproduction of a
published SRAM row/column allocation architecture. It does not establish
multiword-array scalability or physical memristor-device validation.

Conceptual related work: J. F. Li, J. C. Yeh, R. F. Huang, C. W. Wu, P. Y. Tsai,
A. Hsu and E. Chow, “A Built-in Self-Repair Scheme for Semiconductor Memories
with 2-D Redundancy,” Proceedings of the International Test Conference, 2003,
pp. 393–402. The authors' institutional record describes testing main and spare
memory and using redundancy analysis for normal remapping:
https://scholars.ncu.edu.tw/en/publications/a-built-in-self-repair-scheme-for-semiconductor-memories-with-2-d/
That paper's reported SRAM overhead is not reused as a result of this baseline.

`local_validation` contains actual **Linux Verilator 5.49** executions of these
RTL campaigns, their per-scenario maps and aggregate results. Both campaigns
passed locally, as did the paired proposal checks and separate boundary tests.
All three registered shells passed Verilator lint using a logical BUFG model.
Driver completion/error/resume handling was tested using Tcl command stubs;
those are control-flow checks, not Vivado execution or FPGA synthesis evidence.
Vivado is unavailable in the build environment. Your Windows Vivado run is
still required. `SOURCE_SHA256.json` records the shipped source hashes.
