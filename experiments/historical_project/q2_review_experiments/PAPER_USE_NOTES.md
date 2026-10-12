# Paper-use notes

## Baseline definitions

- **Standard TMR:** bitwise majority of three replicas.
- **Self-purging TMR:** representative sticky, whole-module minority exclusion.
  It demonstrates why two agreeing faulty replicas can exclude the healthy
  replica. Do not claim that it represents every adaptive TMR design.
- **SECDED:** generic extended-Hamming single-error correction and double-error
  detection. Double-bit errors are rejected rather than silently accepted.
- **Proposed:** resistance-state BIST health map followed by bit-level trusted
  replica selection.

## Metrics to copy exactly

- `correct_rate`: output equals the stored word, whether accepted or rejected.
- `acceptance_rate`: architecture does not report uncorrectable/rejected.
- `accepted_correct_rate`: output is correct and accepted, divided by all
  checks. This is the main variation safety metric.
- `correct_given_accepted`: correct divided only by accepted cases.
- `silent_data_corruption_rate`: wrong output that was still accepted.

## Claims not permitted by these experiments

- Do not describe model outputs as measured device data.
- Do not describe vectorless estimates as board power measurements.
- Do not claim an exact maximum clock from one WNS value.
- Do not claim the proposed scheme tolerates three faults at one bit; all three
  replicas can then be untrusted.
- Do not generalize exact no/single/double coverage beyond the enumerated
  stuck-HRS/LRS model.
- Do not hide guard-band rejection by reporting only conditional accuracy.

## BIST latency and storage

The original destructive sequence has five phases. The data-preserving variant
has eight phases: SAVE, WRITE0, CHECK0, WRITE1, CHECK1, RESTORE, VERIFY, REPORT.
Plain TMR and SECDED have no BIST cycles; the self-purging comparator makes its
sticky module-exclusion decision after one observation clock.
For the simple register implementation it adds `3 x WIDTH` saved-state bits.
The Vivado resource rows quantify the realized FF/LUT cost at 8, 16, and 32
bits. For a real memory array, discuss row-wise buffering rather than implying
that every word must be backed up simultaneously.

