#!/usr/bin/env python3
"""Summarize registered benchmarks: core area, internal timing, benchmark power."""

from __future__ import annotations

import argparse
import csv
import math
from collections import defaultdict
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np


def number(value: str) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return math.nan


def write_csv(path: Path, rows: list[dict[str, object]]) -> None:
    if not rows:
        return
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("summary_csv", type=Path)
    parser.add_argument("--output", type=Path, default=None)
    args = parser.parse_args()
    output = args.output or args.summary_csv.parent
    output.mkdir(parents=True, exist_ok=True)
    rows = [row for row in csv.DictReader(args.summary_csv.open(encoding="utf-8")) if row["status"] == "PASS"]
    if not rows:
        raise SystemExit("No successful Vivado rows are available yet")
    if any(row.get("timing_scope") != "registered_internal" or
           row.get("power_scope") != "whole_benchmark_vectorless" for row in rows):
        raise SystemExit("Expected v7 registered benchmark rows; do not mix earlier OOC experiments")

    resource = [row for row in rows if row["phase"] == "resource_scaling"]
    resource_rows = [
        {
            "architecture": row["architecture"],
            "width": int(row["width"]),
            "luts": int(float(row["luts"])),
            "ffs": int(float(row["ffs"])),
            "area_scope": "DUT hierarchy inside registered benchmark",
            "benchmark_total_luts": row["benchmark_total_luts"],
            "benchmark_total_ffs": row["benchmark_total_ffs"],
            "benchmark_overhead_luts": row["benchmark_overhead_luts"],
            "benchmark_overhead_ffs": row["benchmark_overhead_ffs"],
            "bram": row["bram"],
            "dsp": row["dsp"],
            "wns_ns": row["wns_ns"],
            "whs_ns": row["whs_ns"],
            "timing_met": row["timing_met"],
            "timing_scope": row["timing_scope"],
            "constraint_mhz": row["constraint_mhz"],
            "whole_benchmark_power_mw_vectorless": row["total_power_mw"],
            "power_scope": row["power_scope"],
            "bist_cycles": row["bist_cycles"],
        }
        for row in resource
    ]
    write_csv(output / "resource_scaling_summary.csv", resource_rows)

    groups: dict[tuple[str, int], list[dict[str, str]]] = defaultdict(list)
    # The W32/default/100-MHz run is performed in resource_scaling and reused,
    # rather than rerun in timing_sweep. Include it in strategy statistics so
    # the 100-MHz comparison has the same three strategies as 150/200 MHz.
    timing = [row for row in rows if row["phase"] == "timing_sweep"] + [
        row for row in resource if int(row["width"]) == 32
    ]
    for row in timing:
        groups[(row["architecture"], int(row["constraint_mhz"]))].append(row)
    timing_rows: list[dict[str, object]] = []
    for (architecture, frequency), group in sorted(groups.items()):
        wns = np.array([number(row["wns_ns"]) for row in group], dtype=float)
        whs = np.array([number(row["whs_ns"]) for row in group], dtype=float)
        power = np.array([number(row["total_power_mw"]) for row in group], dtype=float)
        clean = [int(float(row["timing_met"])) for row in group if row["timing_met"] not in ("", "NA")]
        timing_rows.append(
            {
                "architecture": architecture,
                "constraint_mhz": frequency,
                "strategy_runs": len(group),
                "timing_clean_runs": sum(clean),
                "timing_clean_fraction": sum(clean) / len(clean) if clean else math.nan,
                "wns_mean_ns": float(np.nanmean(wns)),
                "wns_std_ns": float(np.nanstd(wns)),
                "wns_min_ns": float(np.nanmin(wns)),
                "wns_max_ns": float(np.nanmax(wns)),
                "whs_min_ns": float(np.nanmin(whs)),
                "timing_scope": "registered internal paths",
                "whole_benchmark_vectorless_power_mean_mw": float(np.nanmean(power)),
                "whole_benchmark_vectorless_power_std_mw": float(np.nanstd(power)),
            }
        )
    write_csv(output / "timing_strategy_summary.csv", timing_rows)

    by_architecture: dict[str, list[dict[str, object]]] = defaultdict(list)
    for row in timing_rows:
        by_architecture[str(row["architecture"])].append(row)
    closure_rows: list[dict[str, object]] = []
    for architecture, group in sorted(by_architecture.items()):
        any_clean = [int(row["constraint_mhz"]) for row in group if int(row["timing_clean_runs"]) > 0]
        all_clean = [
            int(row["constraint_mhz"])
            for row in group
            if int(row["timing_clean_runs"]) == int(row["strategy_runs"])
        ]
        closure_rows.append(
            {
                "architecture": architecture,
                "highest_constraint_with_any_clean_strategy_mhz": max(any_clean) if any_clean else "none",
                "highest_constraint_clean_for_all_strategies_mhz": max(all_clean) if all_clean else "none",
                "note": "Timing-clean registered benchmark constraints; not bare-core Fmax or board I/O closure",
            }
        )
    write_csv(output / "timing_closure_summary.csv", closure_rows)

    architecture_order = sorted({row["architecture"] for row in resource_rows})
    widths = sorted({int(row["width"]) for row in resource_rows})
    fig, axes = plt.subplots(1, 2, figsize=(10.5, 4.2))
    for architecture in architecture_order:
        subset = sorted(
            [row for row in resource_rows if row["architecture"] == architecture],
            key=lambda row: int(row["width"]),
        )
        axes[0].plot([int(row["width"]) for row in subset], [int(row["luts"]) for row in subset], marker="o", label=architecture)
        axes[1].plot([int(row["width"]) for row in subset], [int(row["ffs"]) for row in subset], marker="o", label=architecture)
    axes[0].set(xlabel="Data width (bits)", ylabel="Post-route DUT LUTs (banks excluded)", xticks=widths)
    axes[1].set(xlabel="Data width (bits)", ylabel="Post-route DUT FFs (banks excluded)", xticks=widths)
    for axis in axes:
        axis.grid(True, alpha=0.25)
    handles, labels = axes[0].get_legend_handles_labels()
    fig.legend(handles, labels, loc="upper center", ncol=3, frameon=False)
    fig.tight_layout(rect=(0, 0, 1, 0.85))
    fig.savefig(output / "review_resource_scaling.pdf", bbox_inches="tight")
    fig.savefig(output / "review_resource_scaling.png", dpi=300, bbox_inches="tight")
    plt.close(fig)
    print(f"PASS: Vivado summaries written to {output}")


if __name__ == "__main__":
    main()
