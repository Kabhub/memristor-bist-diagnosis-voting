# Headline result checks

Checked against the recorded files and accompanying manuscript on 12 October 2026.

| Quantity | Recorded value | Evidence |
|---|---:|---|
| W8 nominal stuck-fault scenarios | 1,153 | archive/initial_campaigns/q2_fault_campaign_results.csv and the 1,153-case run log |
| W16 BIST-in-loop scenarios | 4,609 | results/end_to_end/w16_xsim/e2e_w16_summary.csv; matching scenario trace |
| W32 BIST-in-loop scenarios | 18,433 | results/end_to_end/w32_verilator/e2e_w32_summary.csv; matching scenario trace |
| W16 proposed destructive core LUTs / FFs | 278 / 165 | results/registered_implementation/implementation_summary.csv |
| Proposal, clean-start single-new-fault sweep | 384/384 accepted-correct | experiments/late_fault_and_geometric/proposed_late_summary.csv |
| Plain TMR, same clean-start sweep | 384/384 accepted-correct | experiments/plain_tmr_late_fault/plain_tmr_late_summary.csv and 384-case trace |

All quantities match the accompanying paper. The current manuscript's clean-start
new-fault comparison is **Table 7**, with a plain-TMR row; its numbering changed
from Table 6 during restructuring. Plain TMR has no BIST/health-map input.
The result demonstrates replication masking a single new fault after a clean
start. It does not establish a unique diagnosis-guided benefit or tolerance of
two diagnosed faults followed by a third fault.

FPGA LUT/FF values are isolated behavioural-emulation core counts within the
registered benchmark, not physical memristor-array area. Machine-readable checks
are in RESULT_CHECKS.json.
