`timescale 1ns/1ps

// Synthesis-only wrapper for a fair implementation comparison.  It exposes
// the function delivered by each architecture while leaving the internal
// comparison taps unconnected, allowing Vivado to remove experiment-only
// observability logic.  The functional comparison testbench instantiates the
// underlying core directly and therefore still checks all three outputs.
module publication_architecture_wrapper #(
    parameter integer WIDTH        = 8,
    parameter integer ARCHITECTURE = 2,
    parameter logic [13:0] R_ON_OHMS        = 14'd100,
    parameter logic [13:0] R_OFF_OHMS       = 14'd10000,
    parameter logic [13:0] R_THRESHOLD_OHMS = 14'd5050
) (
    input  logic                   clk,
    input  logic                   reset,
    input  logic                   start,
    input  logic                   operational_write_enable,
    input  logic [WIDTH-1:0]       operational_write_data,
    input  logic [(3*WIDTH)-1:0]   inject_lrs_fault_map,
    input  logic [(3*WIDTH)-1:0]   inject_hrs_fault_map,
    output logic                   busy,
    output logic                   done,
    output logic                   fault_found,
    output logic                   diagnosis_valid,
    output logic [15:0]            bist_cycle_count,
    output logic [WIDTH-1:0]       corrected_data,
    output logic [(3*WIDTH)-1:0]   lrs_fault_map,
    output logic [(3*WIDTH)-1:0]   hrs_fault_map,
    output logic [(3*WIDTH)-1:0]   replica_health_map,
    output logic [WIDTH-1:0]       uncorrectable_map
);

    publication_scalable_memristor_core #(
        .WIDTH               (WIDTH),
        .ARCHITECTURE        (ARCHITECTURE),
        .R_ON_OHMS           (R_ON_OHMS),
        .R_OFF_OHMS          (R_OFF_OHMS),
        .R_THRESHOLD_OHMS    (R_THRESHOLD_OHMS)
    ) core (
        .clk                     (clk),
        .reset                   (reset),
        .start                   (start),
        .operational_write_enable(operational_write_enable),
        .operational_write_data  (operational_write_data),
        .inject_lrs_fault_map    (inject_lrs_fault_map),
        .inject_hrs_fault_map    (inject_hrs_fault_map),
        .busy                    (busy),
        .done                    (done),
        .fault_found             (fault_found),
        .diagnosis_valid         (diagnosis_valid),
        .bist_cycle_count        (bist_cycle_count),
        .unprotected_data        (),
        .standard_tmr_data       (),
        .corrected_data          (corrected_data),
        .lrs_fault_map           (lrs_fault_map),
        .hrs_fault_map           (hrs_fault_map),
        .replica_health_map      (replica_health_map),
        .uncorrectable_map       (uncorrectable_map)
    );

endmodule
