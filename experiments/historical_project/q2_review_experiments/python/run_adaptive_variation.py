#!/usr/bin/env python3
"""Calibrated-threshold, guard-band, and repeated-read sensitivity study.

Device-to-device resistance spread and temporal read noise are modelled
separately. Repeated reads reduce temporal noise only; they do not magically
remove a static device offset. The study therefore reports acceptance,
conditional correctness, accepted-correct probability, false classification,
and rejection instead of hiding guard-band rejections inside "accuracy".

This is an assumed-model sensitivity analysis, not measured-device evidence.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np


R_LRS = 100.0
R_HRS = 10_000.0
FIXED_THRESHOLD = 5_050.0
DEFAULT_SEED = 20261010

PROFILES = (
    ("cv_00", 0.00, 0.00),
    ("cv_05", 0.05, 0.05),
    ("cv_10", 0.10, 0.10),
    ("moderate", 0.10, 0.25),
    ("stress", 0.20, 0.40),
    ("severe", 0.30, 0.60),
)

STRATEGIES = (
    ("fixed_r1", "fixed", 1, 0.00),
    ("calibrated_r1", "calibrated", 1, 0.00),
    ("calibrated_guard10_r1", "calibrated", 1, 0.10),
    ("calibrated_r3", "calibrated", 3, 0.00),
    ("calibrated_guard10_r3", "calibrated", 3, 0.10),
    ("calibrated_guard10_r5", "calibrated", 5, 0.10),
)


def lognormal_mean_cv(
    rng: np.random.Generator, mean: float, cv: float, shape: tuple[int, ...]
) -> np.ndarray:
    if cv == 0.0:
        return np.full(shape, mean, dtype=np.float64)
    sigma = math.sqrt(math.log1p(cv * cv))
    mu = math.log(mean) - 0.5 * sigma * sigma
    return rng.lognormal(mu, sigma, shape)


def observed_resistance(
    rng: np.random.Generator,
    is_lrs: np.ndarray,
    cv_lrs: float,
    cv_hrs: float,
    read_noise_cv: float,
    reads: int,
) -> np.ndarray:
    """Return the median of repeated reads from one static device sample."""
    static = np.empty(is_lrs.shape, dtype=np.float64)
    lrs_count = int(np.count_nonzero(is_lrs))
    hrs_count = int(is_lrs.size - lrs_count)
    if lrs_count:
        static[is_lrs] = lognormal_mean_cv(rng, R_LRS, cv_lrs, (lrs_count,))
    if hrs_count:
        static[~is_lrs] = lognormal_mean_cv(rng, R_HRS, cv_hrs, (hrs_count,))
    noise = lognormal_mean_cv(
        rng, 1.0, read_noise_cv, (reads,) + tuple(is_lrs.shape)
    )
    return np.median(noise * static[None, ...], axis=0)


def choose_calibrated_threshold(
    rng: np.random.Generator,
    cv_lrs: float,
    cv_hrs: float,
    read_noise_cv: float,
    reads: int,
    calibration_samples: int,
) -> float:
    lrs = observed_resistance(
        rng,
        np.ones(calibration_samples, dtype=bool),
        cv_lrs,
        cv_hrs,
        read_noise_cv,
        reads,
    )
    hrs = observed_resistance(
        rng,
        np.zeros(calibration_samples, dtype=bool),
        cv_lrs,
        cv_hrs,
        read_noise_cv,
        reads,
    )
    candidates = np.geomspace(
        max(1.0, float(np.percentile(lrs, 90))),
        max(float(np.percentile(lrs, 90)) + 1.0, float(np.percentile(hrs, 10))),
        401,
    )
    error = np.array(
        [np.mean(lrs >= threshold) + np.mean(hrs < threshold) for threshold in candidates]
    )
    minimum = np.min(error)
    tied = candidates[np.isclose(error, minimum, rtol=0.0, atol=1e-12)]
    # When the distributions are separated, many thresholds may have zero
    # calibration error. Pick the log-centre of the zero-error interval rather
    # than claiming a physically universal optimum.
    return float(math.sqrt(float(tied[0]) * float(tied[-1])))


def classify(values: np.ndarray, threshold: float, guard_fraction: float) -> np.ndarray:
    lower = threshold * (1.0 - guard_fraction)
    upper = threshold * (1.0 + guard_fraction)
    result = np.full(values.shape, -1, dtype=np.int8)  # -1 = rejected/unknown
    result[values < lower] = 1  # LRS
    result[values > upper] = 0  # HRS
    return result


def metrics(expected_lrs: np.ndarray, decision: np.ndarray) -> dict[str, float | int]:
    accepted = decision >= 0
    correct = accepted & (decision == expected_lrs.astype(np.int8))
    false = accepted & ~correct
    total = decision.size
    accepted_count = int(np.count_nonzero(accepted))
    correct_count = int(np.count_nonzero(correct))
    return {
        "trials": total,
        "accepted_count": accepted_count,
        "correct_count": correct_count,
        "false_classification_count": int(np.count_nonzero(false)),
        "rejected_count": total - accepted_count,
        "acceptance_rate": accepted_count / total,
        "correct_given_accepted": correct_count / accepted_count if accepted_count else math.nan,
        "accepted_correct_rate": correct_count / total,
        "false_classification_rate": int(np.count_nonzero(false)) / total,
        "rejection_rate": (total - accepted_count) / total,
    }


def proposed_double_fault_trial(
    rng: np.random.Generator,
    trials: int,
    data_value: int,
    cv_lrs: float,
    cv_hrs: float,
    read_noise_cv: float,
    reads: int,
    threshold: float,
    guard_fraction: float,
) -> dict[str, float | int]:
    """Challenge A+B with a same-bit fault opposite to the stored value."""
    if data_value == 0:
        zero_lrs = np.tile(np.array([True, True, False]), (trials, 1))
        one_lrs = np.ones((trials, 3), dtype=bool)
        operation_lrs = zero_lrs
    else:
        zero_lrs = np.zeros((trials, 3), dtype=bool)
        one_lrs = np.tile(np.array([False, False, True]), (trials, 1))
        operation_lrs = one_lrs

    zero_read = observed_resistance(
        rng, zero_lrs, cv_lrs, cv_hrs, read_noise_cv, reads
    )
    one_read = observed_resistance(
        rng, one_lrs, cv_lrs, cv_hrs, read_noise_cv, reads
    )
    operation_read = observed_resistance(
        rng, operation_lrs, cv_lrs, cv_hrs, read_noise_cv, reads
    )
    zero_class = classify(zero_read, threshold, guard_fraction)
    one_class = classify(one_read, threshold, guard_fraction)
    operation_class = classify(operation_read, threshold, guard_fraction)

    # During WRITE_ZERO, an LRS decision means stuck-LRS. During WRITE_ONE,
    # an HRS decision means stuck-HRS. A guard-band rejection is treated as
    # untrusted, preserving safety rather than silently accepting uncertainty.
    unhealthy = (zero_class != 0) | (one_class != 1)
    trusted = ~unhealthy
    operational_valid = operation_class >= 0
    usable = trusted & operational_valid
    usable_count = np.count_nonzero(usable, axis=1)
    ones = np.count_nonzero(usable & (operation_class == 1), axis=1)
    zeros = np.count_nonzero(usable & (operation_class == 0), axis=1)
    accepted = (usable_count > 0) & ((ones == 0) | (zeros == 0))
    output = ones > 0
    correct = accepted & (output == bool(data_value))
    accepted_count = int(np.count_nonzero(accepted))
    correct_count = int(np.count_nonzero(correct))
    false_count = int(np.count_nonzero(accepted & ~correct))
    return {
        "trials": trials,
        "accepted_count": accepted_count,
        "correct_count": correct_count,
        "false_output_count": false_count,
        "uncorrectable_count": trials - accepted_count,
        "acceptance_rate": accepted_count / trials,
        "correct_given_accepted": correct_count / accepted_count if accepted_count else math.nan,
        "accepted_correct_rate": correct_count / trials,
        "false_output_rate": false_count / trials,
        "uncorrectable_rate": (trials - accepted_count) / trials,
    }


def write_csv(path: Path, rows: list[dict[str, object]]) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)


def plot_results(output: Path, rows: list[dict[str, object]], architecture_rows: list[dict[str, object]]) -> None:
    profile_names = [profile[0] for profile in PROFILES]
    selected = {"fixed_r1", "calibrated_r1", "calibrated_guard10_r3", "calibrated_guard10_r5"}
    fig, axes = plt.subplots(1, 3, figsize=(13.2, 4.0), sharex=True)
    for strategy in selected:
        subset = [row for row in rows if row["strategy"] == strategy]
        axes[0].plot(profile_names, [100 * float(row["acceptance_rate"]) for row in subset], marker="o", label=strategy)
        axes[1].plot(profile_names, [100 * float(row["correct_given_accepted"]) for row in subset], marker="o", label=strategy)
        axes[2].plot(profile_names, [100 * float(row["accepted_correct_rate"]) for row in subset], marker="o", label=strategy)
    axes[0].set_ylabel("Rate (%)")
    axes[0].set_title("Acceptance")
    axes[1].set_title("Correct | accepted")
    axes[2].set_title("Accepted-correct")
    for axis in axes:
        axis.grid(True, alpha=0.25)
        axis.tick_params(axis="x", rotation=35)
        axis.set_ylim(0, 101)
    handles, labels = axes[0].get_legend_handles_labels()
    fig.legend(handles, labels, loc="upper center", ncol=2, frameon=False)
    fig.tight_layout(rect=(0, 0, 1, 0.86))
    fig.savefig(output / "threshold_strategy_comparison.pdf", bbox_inches="tight")
    fig.savefig(output / "threshold_strategy_comparison.png", dpi=300, bbox_inches="tight")
    plt.close(fig)

    fig, ax = plt.subplots(figsize=(8.2, 4.5))
    for strategy in selected:
        subset = [
            row
            for row in architecture_rows
            if row["strategy"] == strategy and int(row["stored_data"]) == 1
        ]
        ax.plot(
            profile_names,
            [100 * float(row["accepted_correct_rate"]) for row in subset],
            marker="o",
            label=strategy,
        )
    ax.set_ylabel("Double-fault accepted-correct (%)")
    ax.set_xlabel("Variation profile")
    ax.set_ylim(0, 101)
    ax.grid(True, alpha=0.25)
    ax.legend(frameon=False, ncol=2)
    fig.tight_layout()
    fig.savefig(output / "double_fault_recovery.pdf", bbox_inches="tight")
    fig.savefig(output / "double_fault_recovery.png", dpi=300, bbox_inches="tight")
    plt.close(fig)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=Path("review_results/variation"))
    parser.add_argument("--trials", type=int, default=100_000)
    parser.add_argument("--calibration-samples", type=int, default=20_000)
    parser.add_argument("--read-noise-cv", type=float, default=0.15)
    parser.add_argument("--seed", type=int, default=DEFAULT_SEED)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)

    state_rows: list[dict[str, object]] = []
    architecture_rows: list[dict[str, object]] = []
    threshold_rows: list[dict[str, object]] = []
    for profile_index, (profile, cv_lrs, cv_hrs) in enumerate(PROFILES):
        calibrated: dict[int, float] = {}
        for reads in (1, 3, 5):
            calibrated[reads] = choose_calibrated_threshold(
                np.random.default_rng(args.seed + profile_index * 1000 + reads),
                cv_lrs,
                cv_hrs,
                args.read_noise_cv,
                reads,
                args.calibration_samples,
            )
            threshold_rows.append(
                {
                    "profile": profile,
                    "cv_lrs": cv_lrs,
                    "cv_hrs": cv_hrs,
                    "reads": reads,
                    "calibrated_threshold_ohms": calibrated[reads],
                }
            )

        expected = np.concatenate(
            (np.ones(args.trials, dtype=bool), np.zeros(args.trials, dtype=bool))
        )
        for strategy_index, (name, threshold_kind, reads, guard) in enumerate(STRATEGIES):
            threshold = FIXED_THRESHOLD if threshold_kind == "fixed" else calibrated[reads]
            values = observed_resistance(
                np.random.default_rng(
                    args.seed + 100_000 + profile_index * 1000 + strategy_index
                ),
                expected,
                cv_lrs,
                cv_hrs,
                args.read_noise_cv,
                reads,
            )
            row: dict[str, object] = {
                "profile": profile,
                "cv_lrs": cv_lrs,
                "cv_hrs": cv_hrs,
                "read_noise_cv": args.read_noise_cv,
                "strategy": name,
                "threshold_kind": threshold_kind,
                "threshold_ohms": threshold,
                "guard_fraction": guard,
                "repeated_reads": reads,
            }
            row.update(metrics(expected, classify(values, threshold, guard)))
            state_rows.append(row)

            for data_value in (0, 1):
                arch_row: dict[str, object] = {
                    "profile": profile,
                    "cv_lrs": cv_lrs,
                    "cv_hrs": cv_hrs,
                    "read_noise_cv": args.read_noise_cv,
                    "strategy": name,
                    "threshold_ohms": threshold,
                    "guard_fraction": guard,
                    "repeated_reads": reads,
                    "stored_data": data_value,
                    "fault_case": "same_bit_double_fault_replicas_A_B",
                }
                arch_row.update(
                    proposed_double_fault_trial(
                        np.random.default_rng(
                            args.seed
                            + 200_000
                            + profile_index * 10_000
                            + strategy_index * 100
                            + data_value
                        ),
                        args.trials,
                        data_value,
                        cv_lrs,
                        cv_hrs,
                        args.read_noise_cv,
                        reads,
                        threshold,
                        guard,
                    )
                )
                architecture_rows.append(arch_row)

    write_csv(args.output / "threshold_calibration.csv", threshold_rows)
    write_csv(args.output / "classification_strategy_summary.csv", state_rows)
    write_csv(args.output / "architecture_variation_summary.csv", architecture_rows)
    plot_results(args.output, state_rows, architecture_rows)
    metadata = {
        "model": "lognormal static resistance multiplied by independent lognormal read noise",
        "nominal_lrs_ohms": R_LRS,
        "nominal_hrs_ohms": R_HRS,
        "fixed_threshold_ohms": FIXED_THRESHOLD,
        "read_noise_cv": args.read_noise_cv,
        "trials_per_state_or_data_value": args.trials,
        "calibration_samples_per_state": args.calibration_samples,
        "guard_policy": "values inside threshold +/- guard fraction are rejected and treated as untrusted",
        "repeated_read_policy": "median; mitigates temporal read noise, not static D2D variation",
        "scope": "assumed-model sensitivity only; not measured device characterization",
    }
    (args.output / "variation_metadata.json").write_text(
        json.dumps(metadata, indent=2) + "\n", encoding="utf-8"
    )
    print(f"PASS: adaptive variation study written to {args.output}")


if __name__ == "__main__":
    main()
