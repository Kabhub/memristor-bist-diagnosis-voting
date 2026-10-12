# Evidence map for the shortened main paper and supplementary material

| Evidence | Repository files |
|---|---|
| Main Table 3, logical storage/test cost | results/logical_cost_w16.csv; RTL field widths and test protocols in the experiment sources; excludes validity/rejection flags, counters and control state |
| Main Table 4, BIST-in-loop diagnosis | results/end_to_end/w16_xsim; results/end_to_end/w32_verilator; W8 trace/logs in archive/initial_campaigns |
| Main Table 5, perfect-map correction cross-check | results/models/coverage |
| Main Table 6, static remapping | results/defect_aware/w16_xsim |
| Main Table 7, new-fault comparison | experiments/late_fault_and_geometric/*_late_summary.csv; experiments/plain_tmr_late_fault/plain_tmr_late_summary.csv and 384-case trace |
| Main Table 8, core implementation | results/registered_implementation and results/defect_aware/implementation_w16 |
| Main Table 9, paired sensing | experiments/late_fault_and_geometric/geometric_paired_results.csv |
| Supplement S1, benchmark banks | Implementation CSV core/total/overhead fields |
| Supplement S2, standard-TMR W32 constraint | results/registered_implementation/implementation_summary.csv |
| Supplement S3, nine placement configurations | results/placement_sensitivity/implementation_summary.csv and routed reports/checkpoints |
| Supplement S4, estimated power | results/registered_implementation/*/vectorless_power.rpt |
| Supplement S5-S6, VTEAM/exploratory faults | results/models/device_validation |
| Supplement S7, initial wrapper/SAIF | archive/initial_campaigns/publication_activity_power_reports |
| Supplement S8, unpaired guard controls | results/models/variation/architecture_variation_summary.csv, calibrated_guard10_r5 rows |
| Proposed multiword sketch | Original figure_12 asset (main Figure 8); no multiword RTL result |
| ZedBoard deployment | board/ sources; archive/initial_campaigns/zedboard_q2_demo_reports |

Old filenames and raw logs retain original experiment identifiers. docs/figure_number_mapping.json maps original figure assets to the current captions. All reported experiment sources and raw evidence are retained; the working manuscript is distributed separately.
