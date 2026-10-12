# One corrected 32-bit core implementation, not the full campaign.
set review_profile "quick"
set review_smoke_only 1
source [file join [file dirname [file normalize [info script]]] run_vivado_review_campaign.tcl]
