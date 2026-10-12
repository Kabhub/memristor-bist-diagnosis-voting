`timescale 1ns/1ps
// Timing-only benchmark shells. The original core wrappers are unchanged.
// Input/output banks add one stage each; their external port paths are outside
// the benchmark timing scope. All bank-to-core-to-bank paths remain timed.
// DONT_TOUCH preserves bank registers; KEEP_HIERARCHY supports core area reports.

module review_standard_tmr_registered_benchmark #(
    parameter integer WIDTH = 8
) (
    input logic clk,
    input logic  reset,
    input logic  operational_write_enable,
    input logic [WIDTH-1:0] operational_write_data,
    input logic [(3*WIDTH)-1:0] inject_lrs_fault_map,
    input logic [(3*WIDTH)-1:0] inject_hrs_fault_map,
    output logic [WIDTH-1:0] corrected_data,
    output logic  disagreement_detected
);
    wire bench_clk;
    BUFG bench_clock_buffer (.I(clk), .O(bench_clk));
    (* DONT_TOUCH = "TRUE" *) logic  reset_launch;
    (* DONT_TOUCH = "TRUE" *) logic  operational_write_enable_launch;
    (* DONT_TOUCH = "TRUE" *) logic [WIDTH-1:0] operational_write_data_launch;
    (* DONT_TOUCH = "TRUE" *) logic [(3*WIDTH)-1:0] inject_lrs_fault_map_launch;
    (* DONT_TOUCH = "TRUE" *) logic [(3*WIDTH)-1:0] inject_hrs_fault_map_launch;
    wire [WIDTH-1:0] corrected_data_core;
    (* DONT_TOUCH = "TRUE" *) logic [WIDTH-1:0] corrected_data_capture;
    assign corrected_data = corrected_data_capture;
    wire  disagreement_detected_core;
    (* DONT_TOUCH = "TRUE" *) logic  disagreement_detected_capture;
    assign disagreement_detected = disagreement_detected_capture;
    always_ff @(posedge bench_clk) begin
        reset_launch <= reset;
        operational_write_enable_launch <= operational_write_enable;
        operational_write_data_launch <= operational_write_data;
        inject_lrs_fault_map_launch <= inject_lrs_fault_map;
        inject_hrs_fault_map_launch <= inject_hrs_fault_map;
        corrected_data_capture <= corrected_data_core;
        disagreement_detected_capture <= disagreement_detected_core;
    end
    (* KEEP_HIERARCHY = "TRUE" *) review_standard_tmr_wrapper #(.WIDTH(WIDTH)) dut (
        .clk(bench_clk),
        .reset(reset_launch),
        .operational_write_enable(operational_write_enable_launch),
        .operational_write_data(operational_write_data_launch),
        .inject_lrs_fault_map(inject_lrs_fault_map_launch),
        .inject_hrs_fault_map(inject_hrs_fault_map_launch),
        .corrected_data(corrected_data_core),
        .disagreement_detected(disagreement_detected_core)
    );
endmodule

module review_self_purging_registered_benchmark #(
    parameter integer WIDTH = 8
) (
    input logic clk,
    input logic  reset,
    input logic  operational_write_enable,
    input logic [WIDTH-1:0] operational_write_data,
    input logic [(3*WIDTH)-1:0] inject_lrs_fault_map,
    input logic [(3*WIDTH)-1:0] inject_hrs_fault_map,
    input logic  start,
    output logic [WIDTH-1:0] corrected_data,
    output logic [2:0] active_replica_mask,
    output logic  disagreement_detected,
    output logic  purge_event,
    output logic  uncorrectable
);
    wire bench_clk;
    BUFG bench_clock_buffer (.I(clk), .O(bench_clk));
    (* DONT_TOUCH = "TRUE" *) logic  reset_launch;
    (* DONT_TOUCH = "TRUE" *) logic  operational_write_enable_launch;
    (* DONT_TOUCH = "TRUE" *) logic [WIDTH-1:0] operational_write_data_launch;
    (* DONT_TOUCH = "TRUE" *) logic [(3*WIDTH)-1:0] inject_lrs_fault_map_launch;
    (* DONT_TOUCH = "TRUE" *) logic [(3*WIDTH)-1:0] inject_hrs_fault_map_launch;
    (* DONT_TOUCH = "TRUE" *) logic  start_launch;
    wire [WIDTH-1:0] corrected_data_core;
    (* DONT_TOUCH = "TRUE" *) logic [WIDTH-1:0] corrected_data_capture;
    assign corrected_data = corrected_data_capture;
    wire [2:0] active_replica_mask_core;
    (* DONT_TOUCH = "TRUE" *) logic [2:0] active_replica_mask_capture;
    assign active_replica_mask = active_replica_mask_capture;
    wire  disagreement_detected_core;
    (* DONT_TOUCH = "TRUE" *) logic  disagreement_detected_capture;
    assign disagreement_detected = disagreement_detected_capture;
    wire  purge_event_core;
    (* DONT_TOUCH = "TRUE" *) logic  purge_event_capture;
    assign purge_event = purge_event_capture;
    wire  uncorrectable_core;
    (* DONT_TOUCH = "TRUE" *) logic  uncorrectable_capture;
    assign uncorrectable = uncorrectable_capture;
    always_ff @(posedge bench_clk) begin
        reset_launch <= reset;
        operational_write_enable_launch <= operational_write_enable;
        operational_write_data_launch <= operational_write_data;
        inject_lrs_fault_map_launch <= inject_lrs_fault_map;
        inject_hrs_fault_map_launch <= inject_hrs_fault_map;
        start_launch <= start;
        corrected_data_capture <= corrected_data_core;
        active_replica_mask_capture <= active_replica_mask_core;
        disagreement_detected_capture <= disagreement_detected_core;
        purge_event_capture <= purge_event_core;
        uncorrectable_capture <= uncorrectable_core;
    end
    (* KEEP_HIERARCHY = "TRUE" *) review_self_purging_wrapper #(.WIDTH(WIDTH)) dut (
        .clk(bench_clk),
        .reset(reset_launch),
        .operational_write_enable(operational_write_enable_launch),
        .operational_write_data(operational_write_data_launch),
        .inject_lrs_fault_map(inject_lrs_fault_map_launch),
        .inject_hrs_fault_map(inject_hrs_fault_map_launch),
        .start(start_launch),
        .corrected_data(corrected_data_core),
        .active_replica_mask(active_replica_mask_core),
        .disagreement_detected(disagreement_detected_core),
        .purge_event(purge_event_core),
        .uncorrectable(uncorrectable_core)
    );
endmodule

module review_secded_registered_benchmark #(
    parameter integer WIDTH = 8,
    parameter integer PARITY_BITS = (WIDTH <= 4) ? 3 : (WIDTH <= 11) ? 4 : (WIDTH <= 26) ? 5 : (WIDTH <= 57) ? 6 : 7,
    parameter integer CODE_WIDTH = WIDTH + PARITY_BITS + 1
) (
    input logic clk,
    input logic  reset,
    input logic  operational_write_enable,
    input logic [WIDTH-1:0] operational_write_data,
    input logic [CODE_WIDTH-1:0] inject_lrs_fault_map,
    input logic [CODE_WIDTH-1:0] inject_hrs_fault_map,
    output logic [WIDTH-1:0] corrected_data,
    output logic  error_detected,
    output logic  single_error_corrected,
    output logic  double_error_detected,
    output logic  accepted,
    output logic [CODE_WIDTH-1:0] observed_codeword
);
    wire bench_clk;
    BUFG bench_clock_buffer (.I(clk), .O(bench_clk));
    (* DONT_TOUCH = "TRUE" *) logic  reset_launch;
    (* DONT_TOUCH = "TRUE" *) logic  operational_write_enable_launch;
    (* DONT_TOUCH = "TRUE" *) logic [WIDTH-1:0] operational_write_data_launch;
    (* DONT_TOUCH = "TRUE" *) logic [CODE_WIDTH-1:0] inject_lrs_fault_map_launch;
    (* DONT_TOUCH = "TRUE" *) logic [CODE_WIDTH-1:0] inject_hrs_fault_map_launch;
    wire [WIDTH-1:0] corrected_data_core;
    (* DONT_TOUCH = "TRUE" *) logic [WIDTH-1:0] corrected_data_capture;
    assign corrected_data = corrected_data_capture;
    wire  error_detected_core;
    (* DONT_TOUCH = "TRUE" *) logic  error_detected_capture;
    assign error_detected = error_detected_capture;
    wire  single_error_corrected_core;
    (* DONT_TOUCH = "TRUE" *) logic  single_error_corrected_capture;
    assign single_error_corrected = single_error_corrected_capture;
    wire  double_error_detected_core;
    (* DONT_TOUCH = "TRUE" *) logic  double_error_detected_capture;
    assign double_error_detected = double_error_detected_capture;
    wire  accepted_core;
    (* DONT_TOUCH = "TRUE" *) logic  accepted_capture;
    assign accepted = accepted_capture;
    wire [CODE_WIDTH-1:0] observed_codeword_core;
    (* DONT_TOUCH = "TRUE" *) logic [CODE_WIDTH-1:0] observed_codeword_capture;
    assign observed_codeword = observed_codeword_capture;
    always_ff @(posedge bench_clk) begin
        reset_launch <= reset;
        operational_write_enable_launch <= operational_write_enable;
        operational_write_data_launch <= operational_write_data;
        inject_lrs_fault_map_launch <= inject_lrs_fault_map;
        inject_hrs_fault_map_launch <= inject_hrs_fault_map;
        corrected_data_capture <= corrected_data_core;
        error_detected_capture <= error_detected_core;
        single_error_corrected_capture <= single_error_corrected_core;
        double_error_detected_capture <= double_error_detected_core;
        accepted_capture <= accepted_core;
        observed_codeword_capture <= observed_codeword_core;
    end
    (* KEEP_HIERARCHY = "TRUE" *) review_secded_wrapper #(.WIDTH(WIDTH)) dut (
        .clk(bench_clk),
        .reset(reset_launch),
        .operational_write_enable(operational_write_enable_launch),
        .operational_write_data(operational_write_data_launch),
        .inject_lrs_fault_map(inject_lrs_fault_map_launch),
        .inject_hrs_fault_map(inject_hrs_fault_map_launch),
        .corrected_data(corrected_data_core),
        .error_detected(error_detected_core),
        .single_error_corrected(single_error_corrected_core),
        .double_error_detected(double_error_detected_core),
        .accepted(accepted_core),
        .observed_codeword(observed_codeword_core)
    );
endmodule

module review_proposed_destructive_registered_benchmark #(
    parameter integer WIDTH = 8
) (
    input logic clk,
    input logic  reset,
    input logic  operational_write_enable,
    input logic [WIDTH-1:0] operational_write_data,
    input logic [(3*WIDTH)-1:0] inject_lrs_fault_map,
    input logic [(3*WIDTH)-1:0] inject_hrs_fault_map,
    input logic  start,
    output logic  busy,
    output logic  done,
    output logic  fault_found,
    output logic  diagnosis_valid,
    output logic [15:0] bist_cycle_count,
    output logic [WIDTH-1:0] corrected_data,
    output logic [(3*WIDTH)-1:0] lrs_fault_map,
    output logic [(3*WIDTH)-1:0] hrs_fault_map,
    output logic [WIDTH-1:0] uncorrectable_map
);
    wire bench_clk;
    BUFG bench_clock_buffer (.I(clk), .O(bench_clk));
    (* DONT_TOUCH = "TRUE" *) logic  reset_launch;
    (* DONT_TOUCH = "TRUE" *) logic  operational_write_enable_launch;
    (* DONT_TOUCH = "TRUE" *) logic [WIDTH-1:0] operational_write_data_launch;
    (* DONT_TOUCH = "TRUE" *) logic [(3*WIDTH)-1:0] inject_lrs_fault_map_launch;
    (* DONT_TOUCH = "TRUE" *) logic [(3*WIDTH)-1:0] inject_hrs_fault_map_launch;
    (* DONT_TOUCH = "TRUE" *) logic  start_launch;
    wire  busy_core;
    (* DONT_TOUCH = "TRUE" *) logic  busy_capture;
    assign busy = busy_capture;
    wire  done_core;
    (* DONT_TOUCH = "TRUE" *) logic  done_capture;
    assign done = done_capture;
    wire  fault_found_core;
    (* DONT_TOUCH = "TRUE" *) logic  fault_found_capture;
    assign fault_found = fault_found_capture;
    wire  diagnosis_valid_core;
    (* DONT_TOUCH = "TRUE" *) logic  diagnosis_valid_capture;
    assign diagnosis_valid = diagnosis_valid_capture;
    wire [15:0] bist_cycle_count_core;
    (* DONT_TOUCH = "TRUE" *) logic [15:0] bist_cycle_count_capture;
    assign bist_cycle_count = bist_cycle_count_capture;
    wire [WIDTH-1:0] corrected_data_core;
    (* DONT_TOUCH = "TRUE" *) logic [WIDTH-1:0] corrected_data_capture;
    assign corrected_data = corrected_data_capture;
    wire [(3*WIDTH)-1:0] lrs_fault_map_core;
    (* DONT_TOUCH = "TRUE" *) logic [(3*WIDTH)-1:0] lrs_fault_map_capture;
    assign lrs_fault_map = lrs_fault_map_capture;
    wire [(3*WIDTH)-1:0] hrs_fault_map_core;
    (* DONT_TOUCH = "TRUE" *) logic [(3*WIDTH)-1:0] hrs_fault_map_capture;
    assign hrs_fault_map = hrs_fault_map_capture;
    wire [WIDTH-1:0] uncorrectable_map_core;
    (* DONT_TOUCH = "TRUE" *) logic [WIDTH-1:0] uncorrectable_map_capture;
    assign uncorrectable_map = uncorrectable_map_capture;
    always_ff @(posedge bench_clk) begin
        reset_launch <= reset;
        operational_write_enable_launch <= operational_write_enable;
        operational_write_data_launch <= operational_write_data;
        inject_lrs_fault_map_launch <= inject_lrs_fault_map;
        inject_hrs_fault_map_launch <= inject_hrs_fault_map;
        start_launch <= start;
        busy_capture <= busy_core;
        done_capture <= done_core;
        fault_found_capture <= fault_found_core;
        diagnosis_valid_capture <= diagnosis_valid_core;
        bist_cycle_count_capture <= bist_cycle_count_core;
        corrected_data_capture <= corrected_data_core;
        lrs_fault_map_capture <= lrs_fault_map_core;
        hrs_fault_map_capture <= hrs_fault_map_core;
        uncorrectable_map_capture <= uncorrectable_map_core;
    end
    (* KEEP_HIERARCHY = "TRUE" *) review_proposed_destructive_wrapper #(.WIDTH(WIDTH)) dut (
        .clk(bench_clk),
        .reset(reset_launch),
        .operational_write_enable(operational_write_enable_launch),
        .operational_write_data(operational_write_data_launch),
        .inject_lrs_fault_map(inject_lrs_fault_map_launch),
        .inject_hrs_fault_map(inject_hrs_fault_map_launch),
        .start(start_launch),
        .busy(busy_core),
        .done(done_core),
        .fault_found(fault_found_core),
        .diagnosis_valid(diagnosis_valid_core),
        .bist_cycle_count(bist_cycle_count_core),
        .corrected_data(corrected_data_core),
        .lrs_fault_map(lrs_fault_map_core),
        .hrs_fault_map(hrs_fault_map_core),
        .uncorrectable_map(uncorrectable_map_core)
    );
endmodule

module review_proposed_preserving_registered_benchmark #(
    parameter integer WIDTH = 8
) (
    input logic clk,
    input logic  reset,
    input logic  operational_write_enable,
    input logic [WIDTH-1:0] operational_write_data,
    input logic [(3*WIDTH)-1:0] inject_lrs_fault_map,
    input logic [(3*WIDTH)-1:0] inject_hrs_fault_map,
    input logic  start,
    output logic  busy,
    output logic  done,
    output logic  fault_found,
    output logic  diagnosis_valid,
    output logic  restore_ok,
    output logic [15:0] bist_cycle_count,
    output logic [WIDTH-1:0] corrected_data,
    output logic [(3*WIDTH)-1:0] lrs_fault_map,
    output logic [(3*WIDTH)-1:0] hrs_fault_map,
    output logic [WIDTH-1:0] uncorrectable_map
);
    wire bench_clk;
    BUFG bench_clock_buffer (.I(clk), .O(bench_clk));
    (* DONT_TOUCH = "TRUE" *) logic  reset_launch;
    (* DONT_TOUCH = "TRUE" *) logic  operational_write_enable_launch;
    (* DONT_TOUCH = "TRUE" *) logic [WIDTH-1:0] operational_write_data_launch;
    (* DONT_TOUCH = "TRUE" *) logic [(3*WIDTH)-1:0] inject_lrs_fault_map_launch;
    (* DONT_TOUCH = "TRUE" *) logic [(3*WIDTH)-1:0] inject_hrs_fault_map_launch;
    (* DONT_TOUCH = "TRUE" *) logic  start_launch;
    wire  busy_core;
    (* DONT_TOUCH = "TRUE" *) logic  busy_capture;
    assign busy = busy_capture;
    wire  done_core;
    (* DONT_TOUCH = "TRUE" *) logic  done_capture;
    assign done = done_capture;
    wire  fault_found_core;
    (* DONT_TOUCH = "TRUE" *) logic  fault_found_capture;
    assign fault_found = fault_found_capture;
    wire  diagnosis_valid_core;
    (* DONT_TOUCH = "TRUE" *) logic  diagnosis_valid_capture;
    assign diagnosis_valid = diagnosis_valid_capture;
    wire  restore_ok_core;
    (* DONT_TOUCH = "TRUE" *) logic  restore_ok_capture;
    assign restore_ok = restore_ok_capture;
    wire [15:0] bist_cycle_count_core;
    (* DONT_TOUCH = "TRUE" *) logic [15:0] bist_cycle_count_capture;
    assign bist_cycle_count = bist_cycle_count_capture;
    wire [WIDTH-1:0] corrected_data_core;
    (* DONT_TOUCH = "TRUE" *) logic [WIDTH-1:0] corrected_data_capture;
    assign corrected_data = corrected_data_capture;
    wire [(3*WIDTH)-1:0] lrs_fault_map_core;
    (* DONT_TOUCH = "TRUE" *) logic [(3*WIDTH)-1:0] lrs_fault_map_capture;
    assign lrs_fault_map = lrs_fault_map_capture;
    wire [(3*WIDTH)-1:0] hrs_fault_map_core;
    (* DONT_TOUCH = "TRUE" *) logic [(3*WIDTH)-1:0] hrs_fault_map_capture;
    assign hrs_fault_map = hrs_fault_map_capture;
    wire [WIDTH-1:0] uncorrectable_map_core;
    (* DONT_TOUCH = "TRUE" *) logic [WIDTH-1:0] uncorrectable_map_capture;
    assign uncorrectable_map = uncorrectable_map_capture;
    always_ff @(posedge bench_clk) begin
        reset_launch <= reset;
        operational_write_enable_launch <= operational_write_enable;
        operational_write_data_launch <= operational_write_data;
        inject_lrs_fault_map_launch <= inject_lrs_fault_map;
        inject_hrs_fault_map_launch <= inject_hrs_fault_map;
        start_launch <= start;
        busy_capture <= busy_core;
        done_capture <= done_core;
        fault_found_capture <= fault_found_core;
        diagnosis_valid_capture <= diagnosis_valid_core;
        restore_ok_capture <= restore_ok_core;
        bist_cycle_count_capture <= bist_cycle_count_core;
        corrected_data_capture <= corrected_data_core;
        lrs_fault_map_capture <= lrs_fault_map_core;
        hrs_fault_map_capture <= hrs_fault_map_core;
        uncorrectable_map_capture <= uncorrectable_map_core;
    end
    (* KEEP_HIERARCHY = "TRUE" *) review_proposed_preserving_wrapper #(.WIDTH(WIDTH)) dut (
        .clk(bench_clk),
        .reset(reset_launch),
        .operational_write_enable(operational_write_enable_launch),
        .operational_write_data(operational_write_data_launch),
        .inject_lrs_fault_map(inject_lrs_fault_map_launch),
        .inject_hrs_fault_map(inject_hrs_fault_map_launch),
        .start(start_launch),
        .busy(busy_core),
        .done(done_core),
        .fault_found(fault_found_core),
        .diagnosis_valid(diagnosis_valid_core),
        .restore_ok(restore_ok_core),
        .bist_cycle_count(bist_cycle_count_core),
        .corrected_data(corrected_data_core),
        .lrs_fault_map(lrs_fault_map_core),
        .hrs_fault_map(hrs_fault_map_core),
        .uncorrectable_map(uncorrectable_map_core)
    );
endmodule
