`timescale 1ns/1ps

module review_standard_tmr_wrapper #(
    parameter integer WIDTH = 8
) (
    input logic clk, reset, operational_write_enable,
    input logic [WIDTH-1:0] operational_write_data,
    input logic [(3*WIDTH)-1:0] inject_lrs_fault_map,
    input logic [(3*WIDTH)-1:0] inject_hrs_fault_map,
    output logic [WIDTH-1:0] corrected_data,
    output logic disagreement_detected
);
    // Use the dedicated baseline rather than ARCHITECTURE=1 of the original
    // shared core.  The latter retains BIST/status logic and would inflate the
    // area of plain TMR, making the resource comparison unfair.
    review_tmr_baseline #(.WIDTH(WIDTH), .SELF_PURGING(0)) core (
        .clk(clk), .reset(reset), .clear_purge(1'b0), .observe(1'b0),
        .write_enable(operational_write_enable),
        .write_data(operational_write_data),
        .inject_lrs_fault_map(inject_lrs_fault_map),
        .inject_hrs_fault_map(inject_hrs_fault_map),
        .corrected_data(corrected_data), .active_replica_mask(),
        .disagreement_detected(disagreement_detected),
        .purge_event(), .uncorrectable()
    );
endmodule


module review_proposed_destructive_wrapper #(
    parameter integer WIDTH = 8
) (
    input logic clk, reset, start, operational_write_enable,
    input logic [WIDTH-1:0] operational_write_data,
    input logic [(3*WIDTH)-1:0] inject_lrs_fault_map,
    input logic [(3*WIDTH)-1:0] inject_hrs_fault_map,
    output logic busy, done, fault_found, diagnosis_valid,
    output logic [15:0] bist_cycle_count,
    output logic [WIDTH-1:0] corrected_data,
    output logic [(3*WIDTH)-1:0] lrs_fault_map,
    output logic [(3*WIDTH)-1:0] hrs_fault_map,
    output logic [WIDTH-1:0] uncorrectable_map
);
    publication_scalable_memristor_core #(.WIDTH(WIDTH), .ARCHITECTURE(2)) core (
        .clk(clk), .reset(reset), .start(start),
        .operational_write_enable(operational_write_enable),
        .operational_write_data(operational_write_data),
        .inject_lrs_fault_map(inject_lrs_fault_map),
        .inject_hrs_fault_map(inject_hrs_fault_map),
        .busy(busy), .done(done), .fault_found(fault_found),
        .diagnosis_valid(diagnosis_valid), .bist_cycle_count(bist_cycle_count),
        .unprotected_data(), .standard_tmr_data(),
        .corrected_data(corrected_data), .lrs_fault_map(lrs_fault_map),
        .hrs_fault_map(hrs_fault_map), .replica_health_map(),
        .uncorrectable_map(uncorrectable_map)
    );
endmodule


module review_self_purging_wrapper #(
    parameter integer WIDTH = 8
) (
    input logic clk, reset, start, operational_write_enable,
    input logic [WIDTH-1:0] operational_write_data,
    input logic [(3*WIDTH)-1:0] inject_lrs_fault_map,
    input logic [(3*WIDTH)-1:0] inject_hrs_fault_map,
    output logic [WIDTH-1:0] corrected_data,
    output logic [2:0] active_replica_mask,
    output logic disagreement_detected, purge_event, uncorrectable
);
    review_tmr_baseline #(.WIDTH(WIDTH), .SELF_PURGING(1)) core (
        .clk(clk), .reset(reset), .clear_purge(start), .observe(1'b1),
        .write_enable(operational_write_enable),
        .write_data(operational_write_data),
        .inject_lrs_fault_map(inject_lrs_fault_map),
        .inject_hrs_fault_map(inject_hrs_fault_map),
        .corrected_data(corrected_data),
        .active_replica_mask(active_replica_mask),
        .disagreement_detected(disagreement_detected),
        .purge_event(purge_event), .uncorrectable(uncorrectable)
    );
endmodule


module review_secded_wrapper #(
    parameter integer WIDTH = 8,
    parameter integer PARITY_BITS =
        (WIDTH <= 4)  ? 3 :
        (WIDTH <= 11) ? 4 :
        (WIDTH <= 26) ? 5 :
        (WIDTH <= 57) ? 6 : 7,
    parameter integer CODE_WIDTH = WIDTH + PARITY_BITS + 1
) (
    input logic clk, reset, operational_write_enable,
    input logic [WIDTH-1:0] operational_write_data,
    input logic [CODE_WIDTH-1:0] inject_lrs_fault_map,
    input logic [CODE_WIDTH-1:0] inject_hrs_fault_map,
    output logic [WIDTH-1:0] corrected_data,
    output logic error_detected, single_error_corrected,
    output logic double_error_detected, accepted,
    output logic [CODE_WIDTH-1:0] observed_codeword
);
    review_secded_memory #(
        .WIDTH(WIDTH), .PARITY_BITS(PARITY_BITS), .CODE_WIDTH(CODE_WIDTH)
    ) core (
        .clk(clk), .reset(reset), .write_enable(operational_write_enable),
        .write_data(operational_write_data),
        .inject_lrs_fault_map(inject_lrs_fault_map),
        .inject_hrs_fault_map(inject_hrs_fault_map),
        .corrected_data(corrected_data), .error_detected(error_detected),
        .single_error_corrected(single_error_corrected),
        .double_error_detected(double_error_detected), .accepted(accepted),
        .observed_codeword(observed_codeword)
    );
endmodule


module review_proposed_preserving_wrapper #(
    parameter integer WIDTH = 8
) (
    input logic clk, reset, start, operational_write_enable,
    input logic [WIDTH-1:0] operational_write_data,
    input logic [(3*WIDTH)-1:0] inject_lrs_fault_map,
    input logic [(3*WIDTH)-1:0] inject_hrs_fault_map,
    output logic busy, done, fault_found, diagnosis_valid, restore_ok,
    output logic [15:0] bist_cycle_count,
    output logic [WIDTH-1:0] corrected_data,
    output logic [(3*WIDTH)-1:0] lrs_fault_map,
    output logic [(3*WIDTH)-1:0] hrs_fault_map,
    output logic [WIDTH-1:0] uncorrectable_map
);
    review_data_preserving_bist_core #(.WIDTH(WIDTH)) core (
        .clk(clk), .reset(reset), .start(start),
        .operational_write_enable(operational_write_enable),
        .operational_write_data(operational_write_data),
        .inject_lrs_fault_map(inject_lrs_fault_map),
        .inject_hrs_fault_map(inject_hrs_fault_map),
        .busy(busy), .done(done), .fault_found(fault_found),
        .diagnosis_valid(diagnosis_valid), .restore_ok(restore_ok),
        .bist_cycle_count(bist_cycle_count), .corrected_data(corrected_data),
        .lrs_fault_map(lrs_fault_map), .hrs_fault_map(hrs_fault_map),
        .replica_health_map(), .uncorrectable_map(uncorrectable_map)
    );
endmodule
