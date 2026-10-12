#!/usr/bin/env python3
"""Validate the two-state classifier against the published VTEAM equations.

The default parameters reproduce the Pt-Hf-Ti VTEAM fit reported in Table I
of Kvatinsky et al., IEEE TCAS-II, 2015 (DOI 10.1109/TCSII.2015.2433536).
The purpose is logical-state validation, not a claim that the ZedBoard contains
or directly measures that device.
"""

from __future__ import annotations

import argparse
import csv
import json
from dataclasses import dataclass, asdict
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np


@dataclass(frozen=True)
class VTEAMParameters:
    alpha_off: float = 1.0
    alpha_on: float = 3.0
    v_off: float = 0.5
    v_on: float = -0.53
    r_off: float = 2_500.0
    r_on: float = 100.0
    k_off: float = 4.03e-8
    k_on: float = -80.0
    w_off: float = 10e-9
    w_on: float = 0.0


def state_rate(voltage: float, p: VTEAMParameters) -> float:
    if voltage > p.v_off:
        return p.k_off * (voltage / p.v_off - 1.0) ** p.alpha_off
    if voltage < p.v_on:
        return p.k_on * (voltage / p.v_on - 1.0) ** p.alpha_on
    return 0.0


def resistance(w: np.ndarray | float, p: VTEAMParameters) -> np.ndarray | float:
    normalized = (np.asarray(w) - p.w_on) / (p.w_off - p.w_on)
    result = p.r_on + normalized * (p.r_off - p.r_on)
    if np.ndim(result) == 0:
        return float(result)
    return result


def apply_pulse(
    initial_w: float,
    voltage: float,
    duration: float,
    p: VTEAMParameters,
    points: int = 1001,
) -> tuple[np.ndarray, np.ndarray]:
    time = np.linspace(0.0, duration, points)
    w = initial_w + state_rate(voltage, p) * time
    w = np.clip(w, p.w_on, p.w_off)
    return time, w


def full_switch_duration(initial_w: float, voltage: float, p: VTEAMParameters) -> float:
    rate = state_rate(voltage, p)
    if rate > 0:
        return (p.w_off - initial_w) / rate
    if rate < 0:
        return (initial_w - p.w_on) / abs(rate)
    return float("inf")


def write_csv(path: Path, rows: list[dict[str, object]]) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)


def run_nominal_validation(output: Path, p: VTEAMParameters) -> list[dict[str, object]]:
    threshold = 0.5 * (p.r_on + p.r_off)
    reset_voltage = 1.0
    set_voltage = -1.0
    reset_duration = 1.05 * full_switch_duration(p.w_on, reset_voltage, p)
    set_duration = 1.05 * full_switch_duration(p.w_off, set_voltage, p)

    reset_time, reset_w = apply_pulse(p.w_on, reset_voltage, reset_duration, p)
    set_time, set_w = apply_pulse(p.w_off, set_voltage, set_duration, p)
    reset_r = resistance(reset_w, p)
    set_r = resistance(set_w, p)

    rows = [
        {
            "operation": "RESET_to_HRS",
            "voltage_v": reset_voltage,
            "duration_s": reset_duration,
            "initial_resistance_ohms": float(reset_r[0]),
            "final_resistance_ohms": float(reset_r[-1]),
            "classifier_threshold_ohms": threshold,
            "expected_bit": 0,
            "classified_bit": int(reset_r[-1] < threshold),
            "agreement": int((reset_r[-1] < threshold) == 0),
        },
        {
            "operation": "SET_to_LRS",
            "voltage_v": set_voltage,
            "duration_s": set_duration,
            "initial_resistance_ohms": float(set_r[0]),
            "final_resistance_ohms": float(set_r[-1]),
            "classifier_threshold_ohms": threshold,
            "expected_bit": 1,
            "classified_bit": int(set_r[-1] < threshold),
            "agreement": int((set_r[-1] < threshold) == 1),
        },
    ]
    write_csv(output / "vteam_nominal_validation.csv", rows)

    fig, axes = plt.subplots(1, 2, figsize=(10.0, 4.0))
    axes[0].plot(reset_time, reset_r, label="RESET")
    axes[0].axhline(threshold, color="black", linestyle="--", label="classifier")
    axes[0].set(xlabel="Time (s)", ylabel="Resistance (ohm)", title="VTEAM RESET")
    axes[1].plot(set_time, set_r, label="SET", color="#d55e00")
    axes[1].axhline(threshold, color="black", linestyle="--", label="classifier")
    axes[1].set(xlabel="Time (s)", ylabel="Resistance (ohm)", title="VTEAM SET")
    for axis in axes:
        axis.grid(True, alpha=0.25)
        axis.legend(frameon=False)
    fig.tight_layout()
    fig.savefig(output / "vteam_set_reset.pdf", bbox_inches="tight")
    fig.savefig(output / "vteam_set_reset.png", dpi=300, bbox_inches="tight")
    plt.close(fig)
    return rows


def run_fault_sensitivity(output: Path, p: VTEAMParameters, seed: int) -> list[dict[str, object]]:
    rng = np.random.default_rng(seed)
    threshold = 0.5 * (p.r_on + p.r_off)
    rows: list[dict[str, object]] = []

    # Read disturb: the voltage is inside the VTEAM dead band, so the state
    # derivative is exactly zero in the published model.
    for initial_name, initial_w, expected in (
        ("LRS", p.w_on, 1),
        ("HRS", p.w_off, 0),
    ):
        _, disturbed_w = apply_pulse(initial_w, 0.10, 1.0, p)
        final_r = float(resistance(disturbed_w[-1], p))
        rows.append(
            {
                "fault_model": "read_disturb_below_threshold",
                "initial_state": initial_name,
                "severity": "read_0.10V_for_1s",
                "final_resistance_ohms": final_r,
                "expected_bit": expected,
                "classified_bit": int(final_r < threshold),
                "accepted_correct": int((final_r < threshold) == expected),
            }
        )

    # Gradual drift is an explicit sensitivity overlay, not part of nonvolatile
    # VTEAM. Move the state a fraction toward the opposite boundary.
    for drift_fraction in (0.05, 0.10, 0.25, 0.50, 0.75):
        for initial_name, initial_w, target_w, expected in (
            ("LRS", p.w_on, p.w_off, 1),
            ("HRS", p.w_off, p.w_on, 0),
        ):
            final_w = initial_w + drift_fraction * (target_w - initial_w)
            final_r = float(resistance(final_w, p))
            rows.append(
                {
                    "fault_model": "gradual_state_drift",
                    "initial_state": initial_name,
                    "severity": f"fraction_{drift_fraction:.2f}",
                    "final_resistance_ohms": final_r,
                    "expected_bit": expected,
                    "classified_bit": int(final_r < threshold),
                    "accepted_correct": int((final_r < threshold) == expected),
                }
            )

    # Transition failure: shorten SET/RESET pulses relative to the full-switch
    # time and observe whether the final state crosses the classifier.
    for operation, initial_w, voltage, expected in (
        ("SET", p.w_off, -1.0, 1),
        ("RESET", p.w_on, 1.0, 0),
    ):
        full = full_switch_duration(initial_w, voltage, p)
        for pulse_fraction in (0.10, 0.25, 0.50, 0.75, 1.00):
            _, trajectory = apply_pulse(initial_w, voltage, full * pulse_fraction, p)
            final_r = float(resistance(trajectory[-1], p))
            rows.append(
                {
                    "fault_model": "transition_failure_short_pulse",
                    "initial_state": operation,
                    "severity": f"pulse_fraction_{pulse_fraction:.2f}",
                    "final_resistance_ohms": final_r,
                    "expected_bit": expected,
                    "classified_bit": int(final_r < threshold),
                    "accepted_correct": int((final_r < threshold) == expected),
                }
            )

    # Intermittent fault: report empirical logical availability for transparent
    # probabilities without pretending that one probability is device-universal.
    trials = 100_000
    for probability in (0.001, 0.01, 0.05, 0.10):
        failures = rng.random(trials) < probability
        rows.append(
            {
                "fault_model": "intermittent_state_inversion",
                "initial_state": "balanced_bits",
                "severity": f"event_probability_{probability:.3f}",
                "final_resistance_ohms": "NA",
                "expected_bit": "balanced",
                "classified_bit": "NA",
                "accepted_correct": float(np.mean(~failures)),
            }
        )

    write_csv(output / "additional_fault_sensitivity.csv", rows)
    return rows


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=Path("review_results/device_validation"))
    parser.add_argument("--seed", type=int, default=20261010)
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)
    parameters = VTEAMParameters()
    nominal = run_nominal_validation(args.output, parameters)
    sensitivity = run_fault_sensitivity(args.output, parameters, args.seed)
    metadata = {
        "source": "S. Kvatinsky, M. Ramadan, E. G. Friedman, and A. Kolodny, VTEAM: A General Model for Voltage-Controlled Memristors, IEEE TCAS-II, 2015",
        "doi": "10.1109/TCSII.2015.2433536",
        "parameter_set": "Table I Pt-Hf-Ti memristor fit",
        "parameters": asdict(parameters),
        "i_v_relation": "linear resistance-state interpolation",
        "window": "ideal hard state bounds",
        "classification_threshold": "device-specific midpoint of fitted RON and ROFF",
        "nominal_agreement": sum(int(row["agreement"]) for row in nominal) / len(nominal),
        "scope": "logical endpoint validation and stated fault sensitivity; not new measured-device fitting",
        "additional_fault_rows": len(sensitivity),
    }
    (args.output / "vteam_validation_metadata.json").write_text(
        json.dumps(metadata, indent=2) + "\n", encoding="utf-8"
    )
    print(f"PASS: VTEAM validation written to {args.output}")


if __name__ == "__main__":
    main()
