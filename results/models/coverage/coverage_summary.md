# Exact fault-coverage summary

Accepted-correct is defined as `output == expected AND uncorrectable == 0`.
Every TMR result exhaustively covers all order-0/1/2 stuck-HRS/LRS cases
over 3W cells and checks both all-zero and all-one words.

| Architecture | W | Cells | Scenarios | Checks | Correct | Accepted-correct | Uncorrectable | SDC |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| standard_tmr | 8 | 24 | 1153 | 2306 | 97.918474% | 97.918474% | 0.000000% | 48 |
| self_purging_tmr | 8 | 24 | 1153 | 2306 | 97.918474% | 83.347788% | 14.570685% | 48 |
| proposed_bit_level_bist | 8 | 24 | 1153 | 2306 | 100.000000% | 100.000000% | 0.000000% | 0 |
| secded | 8 | 13 | 339 | 678 | 79.941003% | 76.991150% | 23.008850% | 0 |
| standard_tmr | 16 | 48 | 4609 | 9218 | 98.958559% | 98.958559% | 0.000000% | 96 |
| self_purging_tmr | 16 | 48 | 4609 | 9218 | 98.958559% | 83.336949% | 15.621610% | 96 |
| proposed_bit_level_bist | 16 | 48 | 4609 | 9218 | 100.000000% | 100.000000% | 0.000000% | 0 |
| secded | 16 | 22 | 969 | 1938 | 77.708978% | 76.160991% | 23.839009% | 0 |
| standard_tmr | 32 | 96 | 18433 | 36866 | 99.479195% | 99.479195% | 0.000000% | 192 |
| self_purging_tmr | 32 | 96 | 18433 | 36866 | 99.479195% | 83.334238% | 16.144957% | 192 |
| proposed_bit_level_bist | 32 | 96 | 18433 | 36866 | 100.000000% | 100.000000% | 0.000000% | 0 |
| secded | 32 | 39 | 3043 | 6086 | 76.339139% | 75.649031% | 24.350969% | 0 |

SECDED uses its encoded cell count rather than 3W cells. Double-bit errors are
detected and rejected, not corrected. This distinction is preserved by reporting
both raw correctness and accepted-correct operation.
