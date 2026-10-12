#!/usr/bin/env python3
"""Exact stuck-at coverage campaign for the reviewer baselines.

The TMR-family campaign enumerates every no-fault, single-fault, and distinct
double-fault combination over 3*WIDTH physical cells.  Each injected cell can
be stuck at HRS/0 or LRS/1, and both all-zero and all-one stored words are
checked.  SECDED is evaluated over its actual encoded storage width using the
same stuck-at enumeration.

This script is deliberately independent of Vivado.  It produces the exact
functional coverage evidence; Vivado is used separately for RTL area, timing,
and power estimates.
"""

from __future__ import annotations

import argparse
import csv
import itertools
import json
from dataclasses import dataclass, asdict
from pathlib import Path
from typing import Iterable


WIDTHS = (8, 16, 32)


@dataclass
class Counters:
    architecture: str
    width: int
    physical_cells: int
    scenario_count: int = 0
    word_checks: int = 0
    activated_error_checks: int = 0
    correct_checks: int = 0
    accepted_checks: int = 0
    accepted_correct_checks: int = 0
    detected_checks: int = 0
    uncorrectable_checks: int = 0
    silent_data_corruption_checks: int = 0

    def row(self) -> dict[str, object]:
        data = asdict(self)
        checks = max(1, self.word_checks)
        activated = max(1, self.activated_error_checks)
        data.update(
            {
                "correct_rate": f"{self.correct_checks / checks:.10f}",
                "acceptance_rate": f"{self.accepted_checks / checks:.10f}",
                "accepted_correct_rate": f"{self.accepted_correct_checks / checks:.10f}",
                "detection_rate_among_activated": f"{self.detected_checks / activated:.10f}",
                "uncorrectable_rate": f"{self.uncorrectable_checks / checks:.10f}",
                "silent_data_corruption_rate": f"{self.silent_data_corruption_checks / checks:.10f}",
            }
        )
        return data


def fault_scenarios(cell_count: int) -> Iterable[tuple[tuple[int, int], ...]]:
    """Yield no fault, all singles, and all distinct doubles.

    The second tuple item is the forced logical value: 0=stuck-HRS and
    1=stuck-LRS.
    """
    yield ()
    for cell in range(cell_count):
        for stuck_value in (0, 1):
            yield ((cell, stuck_value),)
    for first, second in itertools.combinations(range(cell_count), 2):
        for first_value in (0, 1):
            for second_value in (0, 1):
                yield ((first, first_value), (second, second_value))


def majority3(a: int, b: int, c: int) -> int:
    return (a & b) | (a & c) | (b & c)


def force_word_bit(word: int, bit: int, value: int) -> int:
    if value:
        return word | (1 << bit)
    return word & ~(1 << bit)


def apply_tmr_faults(width: int, data: int, faults: tuple[tuple[int, int], ...]) -> list[int]:
    replicas = [data, data, data]
    for cell, stuck_value in faults:
        replica = cell // width
        bit = cell % width
        replicas[replica] = force_word_bit(replicas[replica], bit, stuck_value)
    return replicas


def standard_tmr(width: int, replicas: list[int]) -> tuple[int, bool, bool]:
    mask = (1 << width) - 1
    output = majority3(*replicas) & mask
    detected = not (replicas[0] == replicas[1] == replicas[2])
    return output, detected, False


def self_purging_tmr(width: int, replicas: list[int]) -> tuple[int, bool, bool]:
    """Representative conventional module-level self-purging decision.

    A whole replica is purged only when it is the unique word-level minority.
    If all three words differ, the architecture detects ambiguity but cannot
    identify a trustworthy module.  Two agreeing faulty modules can therefore
    purge the healthy minority, which is the known limitation this baseline
    is intended to expose.
    """
    a, b, c = replicas
    mask = (1 << width) - 1
    detected = not (a == b == c)
    uncorrectable = False
    if b == c and a != b:
        output = b
    elif a == c and b != a:
        output = a
    elif a == b and c != a:
        output = a
    elif a == b == c:
        output = a
    else:
        output = majority3(a, b, c)
        uncorrectable = True
    return output & mask, detected, uncorrectable


def proposed_bit_level(
    width: int,
    replicas: list[int],
    faults: tuple[tuple[int, int], ...],
) -> tuple[int, bool, bool]:
    bad = [[False] * width for _ in range(3)]
    for cell, _ in faults:
        bad[cell // width][cell % width] = True

    output = 0
    uncorrectable = False
    for bit in range(width):
        trusted = [
            (replicas[replica] >> bit) & 1
            for replica in range(3)
            if not bad[replica][bit]
        ]
        if not trusted:
            uncorrectable = True
            value = (majority3(*replicas) >> bit) & 1
        elif any(value != trusted[0] for value in trusted[1:]):
            uncorrectable = True
            value = trusted[0]
        else:
            value = trusted[0]
        output |= value << bit
    return output, bool(faults), uncorrectable


def update_counter(
    counter: Counters,
    expected: int,
    output: int,
    detected: bool,
    uncorrectable: bool,
    activated_errors: int,
) -> None:
    correct = output == expected
    accepted = not uncorrectable
    counter.word_checks += 1
    counter.activated_error_checks += int(activated_errors > 0)
    counter.correct_checks += int(correct)
    counter.accepted_checks += int(accepted)
    counter.accepted_correct_checks += int(correct and accepted)
    counter.detected_checks += int(detected and activated_errors > 0)
    counter.uncorrectable_checks += int(uncorrectable)
    counter.silent_data_corruption_checks += int((not correct) and accepted)


def run_tmr_width(width: int) -> list[Counters]:
    cell_count = 3 * width
    scenario_count = 1 + 2 * cell_count + 4 * (cell_count * (cell_count - 1) // 2)
    counters = {
        "standard_tmr": Counters("standard_tmr", width, cell_count, scenario_count),
        "self_purging_tmr": Counters("self_purging_tmr", width, cell_count, scenario_count),
        "proposed_bit_level_bist": Counters(
            "proposed_bit_level_bist", width, cell_count, scenario_count
        ),
    }
    mask = (1 << width) - 1
    for faults in fault_scenarios(cell_count):
        for expected in (0, mask):
            replicas = apply_tmr_faults(width, expected, faults)
            activated = sum(
                ((expected >> (cell % width)) & 1) != stuck
                for cell, stuck in faults
            )
            for name, model in (
                ("standard_tmr", standard_tmr),
                ("self_purging_tmr", self_purging_tmr),
            ):
                output, detected, uncorrectable = model(width, replicas)
                update_counter(
                    counters[name], expected, output, detected, uncorrectable, activated
                )
            output, detected, uncorrectable = proposed_bit_level(width, replicas, faults)
            update_counter(
                counters["proposed_bit_level_bist"],
                expected,
                output,
                detected,
                uncorrectable,
                activated,
            )

    expected_standard_failures = 6 * width
    observed_standard_failures = (
        counters["standard_tmr"].word_checks
        - counters["standard_tmr"].correct_checks
    )
    assert observed_standard_failures == expected_standard_failures, (
        width,
        observed_standard_failures,
        expected_standard_failures,
    )
    assert counters["proposed_bit_level_bist"].accepted_correct_checks == counters[
        "proposed_bit_level_bist"
    ].word_checks
    return list(counters.values())


def parity_bits_for_width(width: int) -> int:
    parity = 0
    while (1 << parity) < width + parity + 1:
        parity += 1
    return parity


def secded_encode(data: int, width: int) -> tuple[int, int]:
    parity_bits = parity_bits_for_width(width)
    hamming_width = width + parity_bits
    code = 0
    data_index = 0
    for position in range(1, hamming_width + 1):
        if position & (position - 1):
            code |= ((data >> data_index) & 1) << (position - 1)
            data_index += 1
    for parity_index in range(parity_bits):
        parity_position = 1 << parity_index
        parity = 0
        for position in range(1, hamming_width + 1):
            if position & parity_position:
                parity ^= (code >> (position - 1)) & 1
        code |= parity << (parity_position - 1)
    overall = code.bit_count() & 1
    code |= overall << hamming_width
    return code, hamming_width + 1


def secded_decode(code: int, width: int) -> tuple[int, bool, bool, bool]:
    parity_bits = parity_bits_for_width(width)
    hamming_width = width + parity_bits
    syndrome = 0
    for parity_index in range(parity_bits):
        parity_position = 1 << parity_index
        parity = 0
        for position in range(1, hamming_width + 1):
            if position & parity_position:
                parity ^= (code >> (position - 1)) & 1
        if parity:
            syndrome |= parity_position
    overall_mismatch = code.bit_count() & 1
    corrected = code
    single_corrected = False
    double_detected = False
    if syndrome and overall_mismatch:
        corrected ^= 1 << (syndrome - 1)
        single_corrected = True
    elif not syndrome and overall_mismatch:
        corrected ^= 1 << hamming_width
        single_corrected = True
    elif syndrome and not overall_mismatch:
        double_detected = True

    data = 0
    data_index = 0
    for position in range(1, hamming_width + 1):
        if position & (position - 1):
            data |= ((corrected >> (position - 1)) & 1) << data_index
            data_index += 1
    detected = single_corrected or double_detected
    return data, detected, double_detected, single_corrected


def run_secded_width(width: int) -> Counters:
    _, code_width = secded_encode(0, width)
    scenario_count = 1 + 2 * code_width + 4 * (code_width * (code_width - 1) // 2)
    counter = Counters("secded", width, code_width, scenario_count)
    mask = (1 << width) - 1
    for faults in fault_scenarios(code_width):
        for expected in (0, mask):
            encoded, _ = secded_encode(expected, width)
            corrupted = encoded
            for cell, stuck in faults:
                corrupted = force_word_bit(corrupted, cell, stuck)
            activated = (corrupted ^ encoded).bit_count()
            decoded, detected, double_detected, _ = secded_decode(corrupted, width)
            update_counter(
                counter,
                expected,
                decoded,
                detected,
                double_detected,
                activated,
            )
    assert counter.silent_data_corruption_checks == 0
    return counter


def run_by_fault_order(width: int) -> list[dict[str, object]]:
    """Return architecture metrics separated into orders 0, 1, and 2."""
    tmr_cells = 3 * width
    grouped: dict[tuple[str, int], Counters] = {}
    for architecture in ("standard_tmr", "self_purging_tmr", "proposed_bit_level_bist"):
        for order in (0, 1, 2):
            grouped[(architecture, order)] = Counters(
                architecture, width, tmr_cells
            )
    mask = (1 << width) - 1
    for faults in fault_scenarios(tmr_cells):
        order = len(faults)
        for architecture in ("standard_tmr", "self_purging_tmr", "proposed_bit_level_bist"):
            grouped[(architecture, order)].scenario_count += 1
        for expected in (0, mask):
            replicas = apply_tmr_faults(width, expected, faults)
            activated = sum(
                ((expected >> (cell % width)) & 1) != stuck
                for cell, stuck in faults
            )
            for architecture, model in (
                ("standard_tmr", standard_tmr),
                ("self_purging_tmr", self_purging_tmr),
            ):
                output, detected, uncorrectable = model(width, replicas)
                update_counter(
                    grouped[(architecture, order)],
                    expected,
                    output,
                    detected,
                    uncorrectable,
                    activated,
                )
            output, detected, uncorrectable = proposed_bit_level(width, replicas, faults)
            update_counter(
                grouped[("proposed_bit_level_bist", order)],
                expected,
                output,
                detected,
                uncorrectable,
                activated,
            )

    _, code_width = secded_encode(0, width)
    for order in (0, 1, 2):
        grouped[("secded", order)] = Counters("secded", width, code_width)
    for faults in fault_scenarios(code_width):
        order = len(faults)
        grouped[("secded", order)].scenario_count += 1
        for expected in (0, mask):
            encoded, _ = secded_encode(expected, width)
            corrupted = encoded
            for cell, stuck in faults:
                corrupted = force_word_bit(corrupted, cell, stuck)
            activated = (corrupted ^ encoded).bit_count()
            decoded, detected, double_detected, _ = secded_decode(corrupted, width)
            update_counter(
                grouped[("secded", order)],
                expected,
                decoded,
                detected,
                double_detected,
                activated,
            )

    rows: list[dict[str, object]] = []
    for (architecture, order), counter in grouped.items():
        row = counter.row()
        row["fault_order"] = order
        rows.append(row)
    return rows


def write_csv(path: Path, rows: list[dict[str, object]]) -> None:
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)


def write_summary(path: Path, counters: list[Counters]) -> None:
    lines = [
        "# Exact fault-coverage summary",
        "",
        "Accepted-correct is defined as `output == expected AND uncorrectable == 0`.",
        "Every TMR result exhaustively covers all order-0/1/2 stuck-HRS/LRS cases",
        "over 3W cells and checks both all-zero and all-one words.",
        "",
        "| Architecture | W | Cells | Scenarios | Checks | Correct | Accepted-correct | Uncorrectable | SDC |",
        "|---|---:|---:|---:|---:|---:|---:|---:|---:|",
    ]
    for counter in counters:
        lines.append(
            f"| {counter.architecture} | {counter.width} | {counter.physical_cells} | "
            f"{counter.scenario_count} | {counter.word_checks} | "
            f"{counter.correct_checks / counter.word_checks:.6%} | "
            f"{counter.accepted_correct_checks / counter.word_checks:.6%} | "
            f"{counter.uncorrectable_checks / counter.word_checks:.6%} | "
            f"{counter.silent_data_corruption_checks} |"
        )
    lines.extend(
        [
            "",
            "SECDED uses its encoded cell count rather than 3W cells. Double-bit errors are",
            "detected and rejected, not corrected. This distinction is preserved by reporting",
            "both raw correctness and accepted-correct operation.",
            "",
        ]
    )
    path.write_text("\n".join(lines), encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=Path("review_results/coverage"))
    parser.add_argument("--widths", nargs="+", type=int, default=list(WIDTHS))
    args = parser.parse_args()
    args.output.mkdir(parents=True, exist_ok=True)

    counters: list[Counters] = []
    order_rows: list[dict[str, object]] = []
    for width in args.widths:
        counters.extend(run_tmr_width(width))
        counters.append(run_secded_width(width))
        order_rows.extend(run_by_fault_order(width))

    rows = [counter.row() for counter in counters]
    write_csv(args.output / "coverage_summary.csv", rows)
    # Put fault_order next to the architecture in the exported table.
    order_rows = [
        {"architecture": row.pop("architecture"), "fault_order": row.pop("fault_order"), **row}
        for row in order_rows
    ]
    write_csv(args.output / "coverage_by_fault_order.csv", order_rows)
    write_summary(args.output / "coverage_summary.md", counters)
    metadata = {
        "widths": args.widths,
        "fault_model": "deterministic stuck-HRS/0 and stuck-LRS/1",
        "tmr_enumeration": "exact order 0, 1, and 2 over 3*WIDTH cells",
        "data_patterns": ["all_zero", "all_one"],
        "accepted_correct_definition": "output equals expected and uncorrectable is false",
        "secded_policy": "correct single-bit errors; detect/reject double-bit errors",
    }
    (args.output / "coverage_metadata.json").write_text(
        json.dumps(metadata, indent=2) + "\n", encoding="utf-8"
    )
    print(f"PASS: exact coverage campaign written to {args.output}")


if __name__ == "__main__":
    main()
