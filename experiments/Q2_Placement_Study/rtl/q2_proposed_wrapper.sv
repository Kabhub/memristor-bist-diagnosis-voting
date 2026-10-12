`timescale 1ns/1ps
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
