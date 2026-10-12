`timescale 1ns/1ps
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

module q2_remap_two_registered_benchmark #(
    parameter integer WIDTH = 16,
    parameter integer SPARES = 2
) (
    input logic clk,
    input logic  reset,
    input logic  operational_write_enable,
    input logic [WIDTH-1:0] operational_write_data,
    input logic [(WIDTH+SPARES)-1:0] inject_lrs_fault_map,
    input logic [(WIDTH+SPARES)-1:0] inject_hrs_fault_map,
    input logic  start,
    output logic  busy,
    output logic  done,
    output logic  fault_found,
    output logic  diagnosis_valid,
    output logic [15:0] bist_cycle_count,
    output logic [WIDTH-1:0] corrected_data,
    output logic [(WIDTH+SPARES)-1:0] lrs_fault_map,
    output logic [(WIDTH+SPARES)-1:0] hrs_fault_map,
    output logic [WIDTH-1:0] uncorrectable_map
);
    wire bench_clk;
    BUFG bench_clock_buffer (.I(clk), .O(bench_clk));
    (* DONT_TOUCH = "TRUE" *) logic  reset_launch;
    (* DONT_TOUCH = "TRUE" *) logic  operational_write_enable_launch;
    (* DONT_TOUCH = "TRUE" *) logic [WIDTH-1:0] operational_write_data_launch;
    (* DONT_TOUCH = "TRUE" *) logic [(WIDTH+SPARES)-1:0] inject_lrs_fault_map_launch;
    (* DONT_TOUCH = "TRUE" *) logic [(WIDTH+SPARES)-1:0] inject_hrs_fault_map_launch;
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
    wire [(WIDTH+SPARES)-1:0] lrs_fault_map_core;
    (* DONT_TOUCH = "TRUE" *) logic [(WIDTH+SPARES)-1:0] lrs_fault_map_capture;
    assign lrs_fault_map = lrs_fault_map_capture;
    wire [(WIDTH+SPARES)-1:0] hrs_fault_map_core;
    (* DONT_TOUCH = "TRUE" *) logic [(WIDTH+SPARES)-1:0] hrs_fault_map_capture;
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
    (* KEEP_HIERARCHY = "TRUE" *) q2_shared_spare_core #(.WIDTH(WIDTH), .SPARES(SPARES)) dut (
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
        .cell_health_map(), .logical_to_physical_map(),
        .uncorrectable_map(uncorrectable_map_core)
    );
endmodule

module q2_remap_matched_registered_benchmark #(
    parameter integer WIDTH = 16,
    parameter integer SPARES = 2*WIDTH
) (
    input logic clk,
    input logic  reset,
    input logic  operational_write_enable,
    input logic [WIDTH-1:0] operational_write_data,
    input logic [(WIDTH+SPARES)-1:0] inject_lrs_fault_map,
    input logic [(WIDTH+SPARES)-1:0] inject_hrs_fault_map,
    input logic  start,
    output logic  busy,
    output logic  done,
    output logic  fault_found,
    output logic  diagnosis_valid,
    output logic [15:0] bist_cycle_count,
    output logic [WIDTH-1:0] corrected_data,
    output logic [(WIDTH+SPARES)-1:0] lrs_fault_map,
    output logic [(WIDTH+SPARES)-1:0] hrs_fault_map,
    output logic [WIDTH-1:0] uncorrectable_map
);
    wire bench_clk;
    BUFG bench_clock_buffer (.I(clk), .O(bench_clk));
    (* DONT_TOUCH = "TRUE" *) logic  reset_launch;
    (* DONT_TOUCH = "TRUE" *) logic  operational_write_enable_launch;
    (* DONT_TOUCH = "TRUE" *) logic [WIDTH-1:0] operational_write_data_launch;
    (* DONT_TOUCH = "TRUE" *) logic [(WIDTH+SPARES)-1:0] inject_lrs_fault_map_launch;
    (* DONT_TOUCH = "TRUE" *) logic [(WIDTH+SPARES)-1:0] inject_hrs_fault_map_launch;
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
    wire [(WIDTH+SPARES)-1:0] lrs_fault_map_core;
    (* DONT_TOUCH = "TRUE" *) logic [(WIDTH+SPARES)-1:0] lrs_fault_map_capture;
    assign lrs_fault_map = lrs_fault_map_capture;
    wire [(WIDTH+SPARES)-1:0] hrs_fault_map_core;
    (* DONT_TOUCH = "TRUE" *) logic [(WIDTH+SPARES)-1:0] hrs_fault_map_capture;
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
    (* KEEP_HIERARCHY = "TRUE" *) q2_shared_spare_core #(.WIDTH(WIDTH), .SPARES(SPARES)) dut (
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
        .cell_health_map(), .logical_to_physical_map(),
        .uncorrectable_map(uncorrectable_map_core)
    );
endmodule
