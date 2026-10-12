#!/usr/bin/env python3
"""Convert Vivado comparison CSV files into paper-ready tables and figures."""

from __future__ import annotations

import argparse
import csv
from pathlib import Path

import matplotlib.pyplot as plt
import numpy as np


ARCHITECTURE_ORDER = (
    "unprotected",
    "standard_tmr",
    "proposed_bist_guided",
)
ARCHITECTURE_LABELS = {
    "unprotected": "Unprotected\n+BIST",
    "standard_tmr": "Standard TMR\n+BIST",
    "proposed_bist_guided": "Proposed\nBIST-guided",
}
ARCHITECTURE_COLORS = {
    "unprotected": "#7570b3",
    "standard_tmr": "#d95f02",
    "proposed_bist_guided": "#1b9e77",
}


def read_rows(path: Path) -> list[dict[str, str]]:
    with path.open(newline="", encoding="utf-8") as handle:
        return list(csv.DictReader(handle))


def number(row: dict[str, str], key: str) -> float:
    value = row[key].strip()
    if value in ("", "NA"):
        return float("nan")
    return float(value)


def configure_style() -> None:
    plt.rcParams.update(
        {
            "font.family": "DejaVu Sans",
            "font.size": 9,
            "axes.labelsize": 9,
            "axes.titlesize": 10,
            "legend.fontsize": 8,
            "figure.dpi": 120,
            "savefig.dpi": 300,
            "axes.grid": True,
            "grid.alpha": 0.2,
            "axes.axisbelow": True,
        }
    )


def save_figure(fig: plt.Figure, output_dir: Path, stem: str) -> None:
    fig.tight_layout()
    fig.savefig(output_dir / f"{stem}.png", bbox_inches="tight")
    fig.savefig(output_dir / f"{stem}.pdf", bbox_inches="tight")
    plt.close(fig)


def ordered_baseline(rows: list[dict[str, str]]) -> list[dict[str, str]]:
    by_name = {row["architecture"]: row for row in rows}
    missing = set(ARCHITECTURE_ORDER) - set(by_name)
    if missing:
        raise ValueError(f"Baseline CSV is missing architectures: {sorted(missing)}")
    return [by_name[name] for name in ARCHITECTURE_ORDER]


def plot_baseline_resources(
    rows: list[dict[str, str]], output_dir: Path
) -> None:
    rows = ordered_baseline(rows)
    labels = [ARCHITECTURE_LABELS[row["architecture"]] for row in rows]
    colors = [ARCHITECTURE_COLORS[row["architecture"]] for row in rows]
    metrics = (("luts", "LUTs"), ("flip_flops", "Flip-flops"))
    fig, axes = plt.subplots(1, 2, figsize=(7.1, 3.0))
    for axis, (key, title) in zip(axes, metrics):
        values = [number(row, key) for row in rows]
        bars = axis.bar(labels, values, color=colors, width=0.65)
        axis.set_title(title)
        axis.set_ylabel("Post-route resource count")
        axis.bar_label(bars, fmt="%.0f", padding=2, fontsize=8)
        axis.grid(axis="x", visible=False)
        axis.set_ylim(0, max(values) * 1.18 if max(values) else 1)
    save_figure(fig, output_dir, "baseline_resource_comparison")


def plot_baseline_timing_power(
    rows: list[dict[str, str]], output_dir: Path
) -> None:
    rows = ordered_baseline(rows)
    labels = [ARCHITECTURE_LABELS[row["architecture"]] for row in rows]
    colors = [ARCHITECTURE_COLORS[row["architecture"]] for row in rows]
    fmax = [number(row, "estimated_fmax_mhz") for row in rows]
    power = [number(row, "total_power_w") for row in rows]
    confidence = ", ".join(sorted({row["power_confidence"] for row in rows}))

    fig, axes = plt.subplots(1, 2, figsize=(7.4, 3.2))
    bars = axes[0].bar(labels, fmax, color=colors, width=0.65)
    axes[0].set_title("Timing-Derived Fmax", pad=10)
    axes[0].set_ylabel("Frequency (MHz)")
    axes[0].bar_label(bars, fmt="%.1f", padding=2, fontsize=8)
    axes[0].grid(axis="x", visible=False)
    axes[0].set_ylim(0, max(fmax) * 1.16)

    bars = axes[1].bar(labels, power, color=colors, width=0.65)
    axes[1].set_title(f"Vectorless Total Power ({confidence} Confidence)", pad=10)
    axes[1].set_ylabel("Total on-chip power (W)")
    axes[1].bar_label(bars, fmt="%.3f", padding=2, fontsize=8)
    axes[1].grid(axis="x", visible=False)
    axes[1].set_ylim(0, max(power) * 1.16)
    save_figure(fig, output_dir, "baseline_timing_power")


def write_normalized_baseline(
    rows: list[dict[str, str]], output_dir: Path
) -> None:
    rows = ordered_baseline(rows)
    unprotected = rows[0]
    standard = rows[1]
    fields = [
        "architecture",
        "luts",
        "flip_flops",
        "estimated_fmax_mhz",
        "total_power_w",
        "lut_overhead_vs_unprotected_pct",
        "ff_overhead_vs_unprotected_pct",
        "lut_overhead_vs_standard_tmr_pct",
        "ff_overhead_vs_standard_tmr_pct",
    ]
    output_rows = []
    for row in rows:
        values = {key: number(row, key) for key in fields[1:5]}

        def overhead(key: str, reference: dict[str, str]) -> float:
            base = number(reference, key)
            return 100.0 * (number(row, key) / base - 1.0)

        output_rows.append(
            {
                "architecture": row["architecture"],
                **{key: f"{value:.6f}" for key, value in values.items()},
                "lut_overhead_vs_unprotected_pct": f"{overhead('luts', unprotected):.4f}",
                "ff_overhead_vs_unprotected_pct": f"{overhead('flip_flops', unprotected):.4f}",
                "lut_overhead_vs_standard_tmr_pct": f"{overhead('luts', standard):.4f}",
                "ff_overhead_vs_standard_tmr_pct": f"{overhead('flip_flops', standard):.4f}",
            }
        )
    with (output_dir / "baseline_normalized_comparison.csv").open(
        "w", newline="", encoding="utf-8"
    ) as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(output_rows)


def plot_scaling(rows: list[dict[str, str]], output_dir: Path) -> None:
    fig, axes = plt.subplots(1, 3, figsize=(10.4, 3.1))
    metrics = (
        ("luts", "LUTs", "Post-route LUT count"),
        ("flip_flops", "Flip-flops", "Post-route flip-flop count"),
        ("estimated_fmax_mhz", "Estimated Fmax", "Frequency (MHz)"),
    )
    for architecture in ARCHITECTURE_ORDER:
        selected = sorted(
            (row for row in rows if row["architecture"] == architecture),
            key=lambda row: int(row["width"]),
        )
        if not selected:
            raise ValueError(f"Scaling CSV has no rows for {architecture}")
        widths = [int(row["width"]) for row in selected]
        for axis, (key, title, ylabel) in zip(axes, metrics):
            values = [number(row, key) for row in selected]
            axis.plot(
                widths,
                values,
                "o-",
                color=ARCHITECTURE_COLORS[architecture],
                label=ARCHITECTURE_LABELS[architecture].replace("\n", " "),
            )
            axis.set_title(title)
            axis.set_xlabel("Logical memory width (bits)")
            axis.set_ylabel(ylabel)
            axis.set_xticks(widths)
    axes[-1].legend()
    save_figure(fig, output_dir, "width_scaling_trends")


def write_scaling_fits(rows: list[dict[str, str]], output_dir: Path) -> None:
    fields = (
        "architecture",
        "metric",
        "slope_per_bit",
        "intercept",
        "r_squared",
    )
    output_rows = []
    for architecture in ARCHITECTURE_ORDER:
        selected = sorted(
            (row for row in rows if row["architecture"] == architecture),
            key=lambda row: int(row["width"]),
        )
        x = np.array([int(row["width"]) for row in selected], dtype=float)
        for metric in ("luts", "flip_flops"):
            y = np.array([number(row, metric) for row in selected], dtype=float)
            slope, intercept = np.polyfit(x, y, 1)
            predicted = slope * x + intercept
            residual = float(np.sum((y - predicted) ** 2))
            total = float(np.sum((y - np.mean(y)) ** 2))
            r_squared = 1.0 if total == 0.0 else 1.0 - residual / total
            output_rows.append(
                {
                    "architecture": architecture,
                    "metric": metric,
                    "slope_per_bit": f"{slope:.6f}",
                    "intercept": f"{intercept:.6f}",
                    "r_squared": f"{r_squared:.8f}",
                }
            )
    with (output_dir / "scaling_linear_fits.csv").open(
        "w", newline="", encoding="utf-8"
    ) as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(output_rows)


def main() -> None:
    base = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--baseline",
        type=Path,
        default=base / "publication_baseline_reports" / "baseline_summary.csv",
    )
    parser.add_argument(
        "--scaling",
        type=Path,
        default=base / "publication_scaling_reports" / "scaling_summary.csv",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=base / "publication_vivado_figures",
    )
    args = parser.parse_args()
    missing = [path for path in (args.baseline, args.scaling) if not path.is_file()]
    if missing:
        parser.error(
            "Run the Vivado baseline and scaling scripts first. Missing: "
            + ", ".join(str(path) for path in missing)
        )

    args.output_dir.mkdir(parents=True, exist_ok=True)
    configure_style()
    baseline_rows = read_rows(args.baseline)
    scaling_rows = read_rows(args.scaling)
    plot_baseline_resources(baseline_rows, args.output_dir)
    plot_baseline_timing_power(baseline_rows, args.output_dir)
    write_normalized_baseline(baseline_rows, args.output_dir)
    plot_scaling(scaling_rows, args.output_dir)
    write_scaling_fits(scaling_rows, args.output_dir)
    print(f"Publication tables and figures written to: {args.output_dir}")


if __name__ == "__main__":
    main()
