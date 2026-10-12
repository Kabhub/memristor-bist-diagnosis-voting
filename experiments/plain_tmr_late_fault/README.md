# Independent plain-TMR clean-start single-new-fault sweep

Actual execution: Verilator 5.49, 384/384 accepted-correct outputs, zero silent wrong words, zero rejection. The unchanged review_tmr_baseline has SELF_PURGING=0 and no BIST or health-map input. Each case resets, writes one of 0000/ffff/aaaa/5555, injects one stuck-LRS or stuck-HRS into one of 48 cells, and observes the first read. No retest or recovery step is needed in this clean-start experiment.

Reproduce from this directory:

    verilator --binary --timing --assert -CFLAGS '-std=c++20' --top-module tb_plain_tmr_late_sweep publication_scalable_memristor_core.sv review_tmr_baselines.sv tb_plain_tmr_late_sweep.sv
    ./obj_dir/Vtb_plain_tmr_late_sweep

The publication source provides the shared behavioural cell definition. The plain-TMR top uses the existing baseline implementation, rather than receiving diagnosis from the proposal. Recorded local build settings used CFG_CXXFLAGS_PCH_I=-include and CFG_CXXFLAGS_STD=-std=c++20; these are compiler configuration settings, not RTL changes.

CSV, summary and PASS marker are generated in the working directory. The all-sites/both-polarities/four-background trace has been independently checked for 384 unique cases, matching written/observed words and no rejection. This is a replication-versus-remapping comparison after a clean start, not evidence that diagnosis-guided voting uniquely masks a new fault.

The repository contains reference_metadata.json from the publishers' Crossref deposits. Publisher landing-page verification was attempted; ACM endpoints returned 403 and IEEE endpoints required a robot/JavaScript check. A publisher page snippet for ECP was available; DOI/page/author metadata were checked independently from the deposits and author/institutional sources. Blocked landing pages remain a manual verification item. Reference 14's original publisher title uses Computing-In Memories; the manuscript normalizes it to computing in memories per the requested typography correction.
