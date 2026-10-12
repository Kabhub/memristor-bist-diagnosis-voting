#!/usr/bin/env python3
"""Reproducible resistance-variation sensitivity campaign.

This is an assumed-model Monte Carlo study for the behavioural FPGA model; it
is not a substitute for measurements from a fabricated memristor.  Positive
LRS and HRS values are sampled from lognormal distributions whose arithmetic
means remain equal to the RTL nominal values.  The coefficient of variation
(CV) is swept explicitly so every assumption is visible in the output.

Generated evidence:
  * state_classification_sweep.csv
  * threshold_sweep.csv
  * architecture_robustness.csv
  * architecture_robustness_summary.csv
  * variation_read_error.{png,pdf}
  * threshold_sensitivity.{png,pdf}
  * fault_order_tolerance.{png,pdf}
  * variation_campaign_metadata.txt
"""

from __future__ import annotations

import argparse
import csv
import itertools
import math
from pathlib import Path
import platform

import matplotlib
import matplotlib.pyplot as plt
import numpy as np


R_ON_OHMS = 100.0
R_OFF_OHMS = 10_000.0
R_THRESHOLD_OHMS = 5_050.0
DEFAULT_SEED = 20_261_002

# These are deliberately labelled sensitivity profiles.  They are not fitted
# to one physical technology.  The asymmetric profiles reflect the common
# observation that HRS is more variable than LRS.
PROFILES = (
    ("deterministic", 0.00, 0.00),
    ("low_variation", 0.02, 0.15),
    ("moderate_variation", 0.10, 0.25),
    ("stress_variation", 0.20, 0.40),
)

SYMMETRIC_CV_SWEEP = (0.00, 0.05, 0.10, 0.20, 0.30, 0.40, 0.50)


def lognormal_samples(
    rng: np.random.Generator,
    arithmetic_mean: float,
    coefficient_of_variation: float,
    size: int | tuple[int, ...],
) -> np.ndarray:
    """Sample a positive lognormal distribution with a requested mean/CV."""
    if coefficient_of_variation == 0.0:
        return np.full(size, arithmetic_mean, dtype=np.float64)
    sigma = math.sqrt(math.log1p(coefficient_of_variation**2))
    mu = math.log(arithmetic_mean) - 0.5 * sigma**2
    return rng.lognormal(mean=mu, sigma=sigma, size=size)


def lognormal_parameters(
    arithmetic_mean: float, coefficient_of_variation: float
) -> tuple[float, float]:
    """Return the log-space mu and sigma for a positive mean/CV pair."""
    sigma = math.sqrt(math.log1p(coefficient_of_variation**2))
    mu = math.log(arithmetic_mean) - 0.5 * sigma**2
    return mu, sigma


def normal_cdf(value: float) -> float:
    return 0.5 * (1.0 + math.erf(value / math.sqrt(2.0)))


def lognormal_tail_probabilities(
    threshold: float,
    cv_lrs: float,
    cv_hrs: float,
) -> tuple[float, float]:
    """Return exact LRS->HRS and HRS->LRS rates for the assumed model."""
    mu_lrs, sigma_lrs = lognormal_parameters(R_ON_OHMS, cv_lrs)
    mu_hrs, sigma_hrs = lognormal_parameters(R_OFF_OHMS, cv_hrs)
    lrs_as_hrs = 1.0 - normal_cdf((math.log(threshold) - mu_lrs) / sigma_lrs)
    hrs_as_lrs = normal_cdf((math.log(threshold) - mu_hrs) / sigma_hrs)
    return lrs_as_hrs, hrs_as_lrs


def model_optimal_threshold(
    cv_lrs: float,
    cv_hrs: float,
    lower_bound: float,
    upper_bound: float,
) -> float:
    """Find the equal-prior Bayes threshold from lognormal PDF crossings."""
    mu_lrs, sigma_lrs = lognormal_parameters(R_ON_OHMS, cv_lrs)
    mu_hrs, sigma_hrs = lognormal_parameters(R_OFF_OHMS, cv_hrs)
    lrs_variance = sigma_lrs**2
    hrs_variance = sigma_hrs**2

    # Equate the two lognormal probability density functions after the common
    # -log(R) term cancels.  The remaining expression is quadratic in log(R).
    a = 1.0 / hrs_variance - 1.0 / lrs_variance
    b = -2.0 * mu_hrs / hrs_variance + 2.0 * mu_lrs / lrs_variance
    c = (
        mu_hrs**2 / hrs_variance
        - mu_lrs**2 / lrs_variance
        + 2.0 * math.log(sigma_hrs / sigma_lrs)
    )
    roots = np.roots((a, b, c))
    candidates = [lower_bound, upper_bound]
    for root in roots:
        if abs(root.imag) < 1e-10:
            threshold = math.exp(float(root.real))
            if lower_bound <= threshold <= upper_bound:
                candidates.append(threshold)

    def balanced_error(threshold: float) -> float:
        errors = lognormal_tail_probabilities(threshold, cv_lrs, cv_hrs)
        return 0.5 * sum(errors)

    return min(candidates, key=balanced_error)


def state_samples(
    rng: np.random.Generator,
    states_are_lrs: np.ndarray,
    cv_lrs: float,
    cv_hrs: float,
) -> np.ndarray:
    """Sample one resistance for each Boolean LRS/HRS state entry."""
    result = np.empty(states_are_lrs.shape, dtype=np.float64)
    lrs_mask = states_are_lrs
    hrs_mask = ~states_are_lrs
    if np.any(lrs_mask):
        result[lrs_mask] = lognormal_samples(
            rng, R_ON_OHMS, cv_lrs, int(np.count_nonzero(lrs_mask))
        )
    if np.any(hrs_mask):
        result[hrs_mask] = lognormal_samples(
            rng, R_OFF_OHMS, cv_hrs, int(np.count_nonzero(hrs_mask))
        )
    return result


def wilson_interval(successes: int, trials: int) -> tuple[float, float]:
    """Return a 95% Wilson score interval for a binomial proportion."""
    if trials == 0:
        return (math.nan, math.nan)
    z = 1.959963984540054
    p = successes / trials
    denominator = 1.0 + z**2 / trials
    centre = (p + z**2 / (2.0 * trials)) / denominator
    half_width = (
        z
        * math.sqrt((p * (1.0 - p) + z**2 / (4.0 * trials)) / trials)
        / denominator
    )
    return (max(0.0, centre - half_width), min(1.0, centre + half_width))


def write_csv(path: Path, fieldnames: list[str], rows: list[dict[str, object]]) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def run_state_classification_sweep(
    output_dir: Path, trials: int, seed: int
) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    for index, cv in enumerate(SYMMETRIC_CV_SWEEP):
        rng = np.random.default_rng(seed + 1000 + index)
        lrs = lognormal_samples(rng, R_ON_OHMS, cv, trials)
        hrs = lognormal_samples(rng, R_OFF_OHMS, cv, trials)
        lrs_errors = int(np.count_nonzero(lrs >= R_THRESHOLD_OHMS))
        hrs_errors = int(np.count_nonzero(hrs < R_THRESHOLD_OHMS))
        total_errors = lrs_errors + hrs_errors
        low, high = wilson_interval(total_errors, 2 * trials)
        rows.append(
            {
                "cv_lrs": f"{cv:.4f}",
                "cv_hrs": f"{cv:.4f}",
                "threshold_ohms": f"{R_THRESHOLD_OHMS:.1f}",
                "samples_per_state": trials,
                "lrs_as_hrs_errors": lrs_errors,
                "lrs_as_hrs_rate": f"{lrs_errors / trials:.10f}",
                "hrs_as_lrs_errors": hrs_errors,
                "hrs_as_lrs_rate": f"{hrs_errors / trials:.10f}",
                "balanced_read_error_rate": f"{total_errors / (2 * trials):.10f}",
                "balanced_error_ci95_low": f"{low:.10f}",
                "balanced_error_ci95_high": f"{high:.10f}",
            }
        )

    write_csv(
        output_dir / "state_classification_sweep.csv",
        list(rows[0].keys()),
        rows,
    )
    return rows


def run_threshold_sweep(
    output_dir: Path, trials: int, seed: int
) -> tuple[list[dict[str, object]], float]:
    cv_lrs = 0.20
    cv_hrs = 0.40
    rng = np.random.default_rng(seed + 2000)
    lrs = lognormal_samples(rng, R_ON_OHMS, cv_lrs, trials)
    hrs = lognormal_samples(rng, R_OFF_OHMS, cv_hrs, trials)
    best_threshold = model_optimal_threshold(cv_lrs, cv_hrs, 150.0, 9000.0)
    thresholds = np.unique(
        np.concatenate(
            (
                np.geomspace(150.0, 9000.0, 121),
                np.array([R_THRESHOLD_OHMS, best_threshold]),
            )
        )
    )

    rows: list[dict[str, object]] = []
    for threshold in thresholds:
        lrs_errors = int(np.count_nonzero(lrs >= threshold))
        hrs_errors = int(np.count_nonzero(hrs < threshold))
        balanced_error = (lrs_errors + hrs_errors) / (2.0 * trials)
        model_lrs_error, model_hrs_error = lognormal_tail_probabilities(
            float(threshold), cv_lrs, cv_hrs
        )
        rows.append(
            {
                "cv_lrs": f"{cv_lrs:.4f}",
                "cv_hrs": f"{cv_hrs:.4f}",
                "threshold_ohms": f"{threshold:.6f}",
                "samples_per_state": trials,
                "lrs_as_hrs_rate": f"{lrs_errors / trials:.10f}",
                "hrs_as_lrs_rate": f"{hrs_errors / trials:.10f}",
                "balanced_read_error_rate": f"{balanced_error:.10f}",
                "model_lrs_as_hrs_rate": f"{model_lrs_error:.16e}",
                "model_hrs_as_lrs_rate": f"{model_hrs_error:.16e}",
                "model_balanced_read_error_rate": f"{0.5 * (model_lrs_error + model_hrs_error):.16e}",
                "is_rtl_threshold": int(math.isclose(threshold, R_THRESHOLD_OHMS)),
                "is_model_optimal_threshold": int(
                    math.isclose(threshold, best_threshold)
                ),
            }
        )

    write_csv(output_dir / "threshold_sweep.csv", list(rows[0].keys()), rows)
    return rows, best_threshold


def simulate_replicated_case(
    rng: np.random.Generator,
    trials: int,
    data_value: int,
    faulty_replicas: tuple[int, ...],
    cv_lrs: float,
    cv_hrs: float,
) -> dict[str, int]:
    """Simulate standard TMR and the RTL-equivalent diagnosis-guided voter."""
    fault_type = np.zeros(3, dtype=np.int8)
    # Exercise the direction that challenges the stored data: stuck-LRS for a
    # requested zero, and stuck-HRS for a requested one.
    if data_value == 0:
        fault_type[list(faulty_replicas)] = 1  # stuck-at-LRS
    else:
        fault_type[list(faulty_replicas)] = 2  # stuck-at-HRS

    fault_matrix = np.broadcast_to(fault_type, (trials, 3))

    # BIST zero write: healthy/HRS-fault cells should read HRS; LRS faults stay LRS.
    zero_states_lrs = fault_matrix == 1
    zero_resistance = state_samples(rng, zero_states_lrs, cv_lrs, cv_hrs)
    detected_lrs = zero_resistance < R_THRESHOLD_OHMS

    # BIST one write: healthy/LRS-fault cells should read LRS; HRS faults stay HRS.
    one_states_lrs = fault_matrix != 2
    one_resistance = state_samples(rng, one_states_lrs, cv_lrs, cv_hrs)
    detected_hrs = one_resistance >= R_THRESHOLD_OHMS
    health = ~(detected_lrs | detected_hrs)

    expected_lrs = fault_matrix == 1
    expected_hrs = fault_matrix == 2
    exact_diagnosis = np.all(
        (detected_lrs == expected_lrs) & (detected_hrs == expected_hrs), axis=1
    )
    healthy_physical = fault_matrix == 0
    false_positive = np.any((detected_lrs | detected_hrs) & healthy_physical, axis=1)
    missed_fault = np.any(
        ((expected_lrs & ~detected_lrs) | (expected_hrs & ~detected_hrs)), axis=1
    )

    operational_states_lrs = np.where(
        fault_matrix == 1,
        True,
        np.where(fault_matrix == 2, False, bool(data_value)),
    )
    operational_resistance = state_samples(
        rng, operational_states_lrs, cv_lrs, cv_hrs
    )
    read_bits = operational_resistance < R_THRESHOLD_OHMS

    standard_output = np.count_nonzero(read_bits, axis=1) >= 2
    standard_correct = standard_output == bool(data_value)

    health_count = np.count_nonzero(health, axis=1)
    proposed_output = standard_output.copy()
    uncorrectable = health_count == 0

    one_healthy = health_count == 1
    if np.any(one_healthy):
        proposed_output[one_healthy] = (
            np.count_nonzero(read_bits[one_healthy] & health[one_healthy], axis=1) == 1
        )

    two_healthy = health_count == 2
    if np.any(two_healthy):
        healthy_ones = np.count_nonzero(
            read_bits[two_healthy] & health[two_healthy], axis=1
        )
        disagree = healthy_ones == 1
        uncorrectable[two_healthy] = disagree
        proposed_output[two_healthy] = healthy_ones >= 1

    proposed_correct = (proposed_output == bool(data_value)) & ~uncorrectable

    return {
        "trials": trials,
        "standard_correct": int(np.count_nonzero(standard_correct)),
        "proposed_correct": int(np.count_nonzero(proposed_correct)),
        "uncorrectable": int(np.count_nonzero(uncorrectable)),
        "exact_diagnosis": int(np.count_nonzero(exact_diagnosis)),
        "false_positive": int(np.count_nonzero(false_positive)),
        "missed_fault": int(np.count_nonzero(missed_fault)),
    }


def simulate_unprotected_case(
    rng: np.random.Generator,
    trials: int,
    data_value: int,
    fault_count: int,
    cv_lrs: float,
    cv_hrs: float,
) -> dict[str, int]:
    if fault_count not in (0, 1):
        raise ValueError("An unprotected bit contains only one cell")
    if fault_count == 0:
        states_lrs = np.full(trials, bool(data_value), dtype=bool)
    else:
        states_lrs = np.full(trials, not bool(data_value), dtype=bool)
    resistance = state_samples(rng, states_lrs, cv_lrs, cv_hrs)
    read_data = resistance < R_THRESHOLD_OHMS
    correct = read_data == bool(data_value)
    return {"trials": trials, "correct": int(np.count_nonzero(correct))}


def run_architecture_campaign(
    output_dir: Path, trials: int, seed: int
) -> list[dict[str, object]]:
    rows: list[dict[str, object]] = []
    profile_seed_stride = 100_000
    data_seed_stride = 10_000
    fault_seed_stride = 1_000

    for profile_index, (profile, cv_lrs, cv_hrs) in enumerate(PROFILES):
        for data_value in (0, 1):
            # The unprotected baseline has one physical cell per bit and is
            # therefore evaluated only at fault orders zero and one.
            for fault_count in (0, 1):
                rng = np.random.default_rng(
                    seed
                    + 3000
                    + profile_index * profile_seed_stride
                    + data_value * data_seed_stride
                    + fault_count * fault_seed_stride
                )
                result = simulate_unprotected_case(
                    rng, trials, data_value, fault_count, cv_lrs, cv_hrs
                )
                low, high = wilson_interval(result["correct"], result["trials"])
                rows.append(
                    {
                        "profile": profile,
                        "cv_lrs": f"{cv_lrs:.4f}",
                        "cv_hrs": f"{cv_hrs:.4f}",
                        "architecture": "unprotected",
                        "stored_data": data_value,
                        "faults_in_logical_bit": fault_count,
                        "fault_type": "none"
                        if fault_count == 0
                        else ("stuck_lrs" if data_value == 0 else "stuck_hrs"),
                        "trials": result["trials"],
                        "correct_count": result["correct"],
                        "correction_rate": f"{result['correct'] / result['trials']:.10f}",
                        "correction_ci95_low": f"{low:.10f}",
                        "correction_ci95_high": f"{high:.10f}",
                        "uncorrectable_count": 0,
                        "uncorrectable_rate": "0.0000000000",
                        "exact_diagnosis_count": "NA",
                        "exact_diagnosis_rate": "NA",
                        "false_positive_count": "NA",
                        "false_positive_rate": "NA",
                        "missed_fault_count": "NA",
                        "missed_fault_rate": "NA",
                    }
                )

            for fault_count in range(4):
                totals = {
                    "trials": 0,
                    "standard_correct": 0,
                    "proposed_correct": 0,
                    "uncorrectable": 0,
                    "exact_diagnosis": 0,
                    "false_positive": 0,
                    "missed_fault": 0,
                }
                for combination_index, faulty_replicas in enumerate(
                    itertools.combinations(range(3), fault_count)
                ):
                    rng = np.random.default_rng(
                        seed
                        + 4000
                        + profile_index * profile_seed_stride
                        + data_value * data_seed_stride
                        + fault_count * fault_seed_stride
                        + combination_index
                    )
                    result = simulate_replicated_case(
                        rng,
                        trials,
                        data_value,
                        faulty_replicas,
                        cv_lrs,
                        cv_hrs,
                    )
                    for key in totals:
                        totals[key] += result[key]

                fault_name = "none" if fault_count == 0 else (
                    "stuck_lrs" if data_value == 0 else "stuck_hrs"
                )
                for architecture, correct_key in (
                    ("standard_tmr", "standard_correct"),
                    ("proposed_bist_guided", "proposed_correct"),
                ):
                    correct = totals[correct_key]
                    total = totals["trials"]
                    low, high = wilson_interval(correct, total)
                    rows.append(
                        {
                            "profile": profile,
                            "cv_lrs": f"{cv_lrs:.4f}",
                            "cv_hrs": f"{cv_hrs:.4f}",
                            "architecture": architecture,
                            "stored_data": data_value,
                            "faults_in_logical_bit": fault_count,
                            "fault_type": fault_name,
                            "trials": total,
                            "correct_count": correct,
                            "correction_rate": f"{correct / total:.10f}",
                            "correction_ci95_low": f"{low:.10f}",
                            "correction_ci95_high": f"{high:.10f}",
                            "uncorrectable_count": totals["uncorrectable"]
                            if architecture == "proposed_bist_guided"
                            else 0,
                            "uncorrectable_rate": f"{totals['uncorrectable'] / total:.10f}"
                            if architecture == "proposed_bist_guided"
                            else "0.0000000000",
                            "exact_diagnosis_count": totals["exact_diagnosis"],
                            "exact_diagnosis_rate": f"{totals['exact_diagnosis'] / total:.10f}",
                            "false_positive_count": totals["false_positive"],
                            "false_positive_rate": f"{totals['false_positive'] / total:.10f}",
                            "missed_fault_count": totals["missed_fault"],
                            "missed_fault_rate": f"{totals['missed_fault'] / total:.10f}",
                        }
                    )

    write_csv(output_dir / "architecture_robustness.csv", list(rows[0].keys()), rows)
    return rows


def write_architecture_summary(
    rows: list[dict[str, object]], output_dir: Path
) -> None:
    """Aggregate the two stored-data polarities into paper-ready rows."""
    summary: list[dict[str, object]] = []
    for profile, cv_lrs, cv_hrs in PROFILES:
        for architecture in (
            "unprotected",
            "standard_tmr",
            "proposed_bist_guided",
        ):
            maximum_faults = 1 if architecture == "unprotected" else 3
            for fault_count in range(maximum_faults + 1):
                selected = [
                    row
                    for row in rows
                    if row["profile"] == profile
                    and row["architecture"] == architecture
                    and int(row["faults_in_logical_bit"]) == fault_count
                ]
                total = sum(int(row["trials"]) for row in selected)
                correct = sum(int(row["correct_count"]) for row in selected)
                low, high = wilson_interval(correct, total)

                if architecture == "unprotected":
                    uncorrectable_count: int | str = 0
                    exact_count: int | str = "NA"
                    false_count: int | str = "NA"
                    missed_count: int | str = "NA"
                    exact_rate = false_rate = missed_rate = "NA"
                else:
                    uncorrectable_count = sum(
                        int(row["uncorrectable_count"]) for row in selected
                    )
                    exact_count = sum(
                        int(row["exact_diagnosis_count"]) for row in selected
                    )
                    false_count = sum(
                        int(row["false_positive_count"]) for row in selected
                    )
                    missed_count = sum(
                        int(row["missed_fault_count"]) for row in selected
                    )
                    exact_rate = f"{exact_count / total:.10f}"
                    false_rate = f"{false_count / total:.10f}"
                    missed_rate = f"{missed_count / total:.10f}"

                summary.append(
                    {
                        "profile": profile,
                        "cv_lrs": f"{cv_lrs:.4f}",
                        "cv_hrs": f"{cv_hrs:.4f}",
                        "architecture": architecture,
                        "faults_in_logical_bit": fault_count,
                        "trials": total,
                        "correct_count": correct,
                        "correction_rate": f"{correct / total:.10f}",
                        "correction_ci95_low": f"{low:.10f}",
                        "correction_ci95_high": f"{high:.10f}",
                        "uncorrectable_count": uncorrectable_count,
                        "uncorrectable_rate": f"{uncorrectable_count / total:.10f}",
                        "exact_diagnosis_count": exact_count,
                        "exact_diagnosis_rate": exact_rate,
                        "false_positive_count": false_count,
                        "false_positive_rate": false_rate,
                        "missed_fault_count": missed_count,
                        "missed_fault_rate": missed_rate,
                    }
                )

    write_csv(
        output_dir / "architecture_robustness_summary.csv",
        list(summary[0].keys()),
        summary,
    )


def configure_plot_style() -> None:
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
            "grid.alpha": 0.25,
        }
    )


def save_figure(fig: plt.Figure, output_dir: Path, stem: str) -> None:
    fig.tight_layout()
    fig.savefig(output_dir / f"{stem}.png", bbox_inches="tight")
    fig.savefig(output_dir / f"{stem}.pdf", bbox_inches="tight")
    plt.close(fig)


def plot_state_sweep(rows: list[dict[str, object]], output_dir: Path) -> None:
    cvs = np.array([float(row["cv_lrs"]) for row in rows]) * 100.0
    lrs_error = np.array([float(row["lrs_as_hrs_rate"]) for row in rows]) * 100.0
    hrs_error = np.array([float(row["hrs_as_lrs_rate"]) for row in rows]) * 100.0
    balanced = (
        np.array([float(row["balanced_read_error_rate"]) for row in rows]) * 100.0
    )
    floor = 1e-5

    fig, ax = plt.subplots(figsize=(5.4, 3.2))
    ax.semilogy(cvs, np.maximum(lrs_error, floor), "o-", label="LRS read as HRS")
    ax.semilogy(cvs, np.maximum(hrs_error, floor), "s-", label="HRS read as LRS")
    ax.semilogy(cvs, np.maximum(balanced, floor), "^-", label="Balanced read error")
    ax.set_xlabel("Coefficient of variation for both states (%)")
    ax.set_ylabel("Error rate (%)")
    ax.set_title("Fixed 5,050-Ω Threshold Under Resistance Variation")
    ax.set_ylim(bottom=floor)
    ax.legend()
    save_figure(fig, output_dir, "variation_read_error")


def plot_threshold_sweep(
    rows: list[dict[str, object]], output_dir: Path, best_threshold: float
) -> None:
    thresholds = np.array([float(row["threshold_ohms"]) for row in rows])
    errors = np.array(
        [float(row["model_balanced_read_error_rate"]) for row in rows]
    ) * 100.0
    fig, ax = plt.subplots(figsize=(5.4, 3.2))
    ax.semilogy(thresholds, np.maximum(errors, 1e-5), color="#1f77b4")
    ax.axvline(
        R_THRESHOLD_OHMS,
        color="#d62728",
        linestyle="--",
        label="RTL threshold (5,050 Ω)",
    )
    ax.axvline(
        best_threshold,
        color="#2ca02c",
        linestyle=":",
        label=f"Model-optimal threshold ({best_threshold:.0f} Ω)",
    )
    ax.set_xlabel("Resistance decision threshold (Ω)")
    ax.set_ylabel("Balanced read error (%)")
    ax.set_title("Threshold Sensitivity at CV(LRS)=20%, CV(HRS)=40%")
    ax.legend()
    save_figure(fig, output_dir, "threshold_sensitivity")


def plot_fault_order(rows: list[dict[str, object]], output_dir: Path) -> None:
    fig, axes = plt.subplots(1, len(PROFILES), figsize=(10.8, 2.9), sharey=True)
    colors = {"standard_tmr": "#d95f02", "proposed_bist_guided": "#1b9e77"}
    labels = {"standard_tmr": "Standard TMR", "proposed_bist_guided": "Proposed"}

    for axis, (profile, cv_lrs, cv_hrs) in zip(axes, PROFILES):
        for architecture in ("standard_tmr", "proposed_bist_guided"):
            rates = []
            for fault_count in range(4):
                selected = [
                    float(row["correction_rate"])
                    for row in rows
                    if row["profile"] == profile
                    and row["architecture"] == architecture
                    and int(row["faults_in_logical_bit"]) == fault_count
                ]
                rates.append(100.0 * float(np.mean(selected)))
            axis.plot(
                range(4),
                rates,
                "o-",
                color=colors[architecture],
                label=labels[architecture],
            )
        axis.set_title(f"{profile.replace('_', ' ').title()}\nCV={cv_lrs:.0%}/{cv_hrs:.0%}")
        axis.set_xlabel("Faulty replicas in one bit")
        axis.set_xticks(range(4))
        axis.set_ylim(-2, 102)
    axes[0].set_ylabel("Correct and accepted output (%)")
    axes[-1].legend(loc="lower left")
    save_figure(fig, output_dir, "fault_order_tolerance")


def write_metadata(
    output_dir: Path,
    trials: int,
    seed: int,
    best_threshold: float,
) -> None:
    lines = [
        "Resistance-variation sensitivity campaign",
        f"Python: {platform.python_version()}",
        f"NumPy: {np.__version__}",
        f"Matplotlib: {matplotlib.__version__}",
        f"Seed: {seed}",
        f"Monte Carlo trials per state/replica-combination: {trials}",
        f"Nominal R_ON: {R_ON_OHMS:.1f} ohms",
        f"Nominal R_OFF: {R_OFF_OHMS:.1f} ohms",
        f"RTL threshold: {R_THRESHOLD_OHMS:.1f} ohms",
        "Distribution: lognormal, parameterized to retain the nominal arithmetic mean",
        "Profiles (CV_LRS, CV_HRS):",
    ]
    lines.extend(f"  {name}: {cv_lrs:.4f}, {cv_hrs:.4f}" for name, cv_lrs, cv_hrs in PROFILES)
    lines.extend(
        [
            "Threshold-search profile: CV_LRS=0.20, CV_HRS=0.40",
            f"Equal-prior model-optimal threshold in that profile: {best_threshold:.6f} ohms",
            "Claim boundary: assumed-model sensitivity analysis only; no physical device was measured.",
        ]
    )
    (output_dir / "variation_campaign_metadata.txt").write_text(
        "\n".join(lines) + "\n", encoding="utf-8"
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=Path(__file__).resolve().parent / "publication_variation_results",
    )
    parser.add_argument(
        "--trials",
        type=int,
        default=200_000,
        help="Monte Carlo trials per state or replica combination (default: 200000)",
    )
    parser.add_argument("--seed", type=int, default=DEFAULT_SEED)
    args = parser.parse_args()
    if args.trials < 10_000:
        parser.error("Use at least 10,000 trials for stable reported estimates")

    args.output_dir.mkdir(parents=True, exist_ok=True)
    configure_plot_style()
    state_rows = run_state_classification_sweep(args.output_dir, args.trials, args.seed)
    threshold_rows, best_threshold = run_threshold_sweep(
        args.output_dir, args.trials, args.seed
    )
    architecture_rows = run_architecture_campaign(
        args.output_dir, args.trials, args.seed
    )
    write_architecture_summary(architecture_rows, args.output_dir)
    plot_state_sweep(state_rows, args.output_dir)
    plot_threshold_sweep(threshold_rows, args.output_dir, best_threshold)
    plot_fault_order(architecture_rows, args.output_dir)
    write_metadata(args.output_dir, args.trials, args.seed, best_threshold)

    print(f"Variation campaign complete: {args.output_dir}")
    print(f"Model-optimal stress-profile threshold: {best_threshold:.1f} ohms")
    print("Claim boundary: sensitivity analysis, not physical-device validation")


if __name__ == "__main__":
    main()
