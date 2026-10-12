`timescale 1ns/1ps

module tb_publication_architecture_comparison;

    localparam integer WIDTH = 8;

    logic clk = 1'b0;
    logic reset;
    logic start;
    logic operational_write_enable;
    logic [WIDTH-1:0] operational_write_data;
    logic [(3*WIDTH)-1:0] inject_lrs_fault_map;
    logic [(3*WIDTH)-1:0] inject_hrs_fault_map;

    logic done_u, done_s, done_p;
    logic fault_u, fault_s, fault_p;
    logic valid_u, valid_s, valid_p;
    logic [15:0] cycles_u, cycles_s, cycles_p;
    logic [WIDTH-1:0] data_u, data_s, data_p;
    logic [WIDTH-1:0] standard_p;
    logic [(3*WIDTH)-1:0] lrs_u, lrs_s, lrs_p;
    logic [(3*WIDTH)-1:0] hrs_u, hrs_s, hrs_p;
    logic [WIDTH-1:0] uncorr_p;

    always #5 clk = ~clk;

    publication_scalable_memristor_core #(
        .WIDTH(WIDTH), .ARCHITECTURE(0)
    ) unprotected (
        .clk(clk), .reset(reset), .start(start),
        .operational_write_enable(operational_write_enable),
        .operational_write_data(operational_write_data),
        .inject_lrs_fault_map(inject_lrs_fault_map),
        .inject_hrs_fault_map(inject_hrs_fault_map),
        .busy(), .done(done_u), .fault_found(fault_u),
        .diagnosis_valid(valid_u), .bist_cycle_count(cycles_u),
        .unprotected_data(), .standard_tmr_data(),
        .corrected_data(data_u), .lrs_fault_map(lrs_u),
        .hrs_fault_map(hrs_u), .replica_health_map(),
        .uncorrectable_map()
    );

    publication_scalable_memristor_core #(
        .WIDTH(WIDTH), .ARCHITECTURE(1)
    ) standard_tmr (
        .clk(clk), .reset(reset), .start(start),
        .operational_write_enable(operational_write_enable),
        .operational_write_data(operational_write_data),
        .inject_lrs_fault_map(inject_lrs_fault_map),
        .inject_hrs_fault_map(inject_hrs_fault_map),
        .busy(), .done(done_s), .fault_found(fault_s),
        .diagnosis_valid(valid_s), .bist_cycle_count(cycles_s),
        .unprotected_data(), .standard_tmr_data(),
        .corrected_data(data_s), .lrs_fault_map(lrs_s),
        .hrs_fault_map(hrs_s), .replica_health_map(),
        .uncorrectable_map()
    );

    publication_scalable_memristor_core #(
        .WIDTH(WIDTH), .ARCHITECTURE(2)
    ) proposed (
        .clk(clk), .reset(reset), .start(start),
        .operational_write_enable(operational_write_enable),
        .operational_write_data(operational_write_data),
        .inject_lrs_fault_map(inject_lrs_fault_map),
        .inject_hrs_fault_map(inject_hrs_fault_map),
        .busy(), .done(done_p), .fault_found(fault_p),
        .diagnosis_valid(valid_p), .bist_cycle_count(cycles_p),
        .unprotected_data(), .standard_tmr_data(standard_p),
        .corrected_data(data_p), .lrs_fault_map(lrs_p),
        .hrs_fault_map(hrs_p), .replica_health_map(),
        .uncorrectable_map(uncorr_p)
    );

    task automatic run_case(
        input logic [23:0] lrs_mask,
        input logic [23:0] hrs_mask,
        input logic [7:0]  challenge,
        input logic [23:0] expected_lrs_unprotected,
        input logic [23:0] expected_hrs_unprotected,
        input logic [23:0] expected_lrs_replicated,
        input logic [23:0] expected_hrs_replicated,
        input logic [7:0]  expected_unprotected,
        input logic [7:0]  expected_standard,
        input logic [7:0]  expected_proposed,
        input logic [7:0]  expected_uncorrectable,
        input string       name
    );
        begin
            inject_lrs_fault_map = lrs_mask;
            inject_hrs_fault_map = hrs_mask;
            operational_write_enable = 1'b0;

            @(negedge clk);
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;

            wait (done_u && done_s && done_p);
            #1;

            if ((cycles_u !== 16'd5) ||
                (cycles_s !== 16'd5) ||
                (cycles_p !== 16'd5)) begin
                $error("FAIL %s: BIST cycles U=%0d S=%0d P=%0d",
                       name, cycles_u, cycles_s, cycles_p);
                $fatal(1);
            end

            if ((lrs_u !== expected_lrs_unprotected) ||
                (hrs_u !== expected_hrs_unprotected) ||
                (lrs_s !== expected_lrs_replicated) ||
                (hrs_s !== expected_hrs_replicated) ||
                (lrs_p !== expected_lrs_replicated) ||
                (hrs_p !== expected_hrs_replicated)) begin
                $error("FAIL %s: fault maps do not match", name);
                $fatal(1);
            end

            // REPORT lasts one cycle. Write the functional challenge after
            // every controller has returned to IDLE.
            @(posedge clk);
            @(negedge clk);
            operational_write_data   = challenge;
            operational_write_enable = 1'b1;
            @(posedge clk);
            #1;
            operational_write_enable = 1'b0;

            if ((data_u !== expected_unprotected) ||
                (data_s !== expected_standard) ||
                (standard_p !== expected_standard) ||
                (data_p !== expected_proposed) ||
                (uncorr_p !== expected_uncorrectable)) begin
                $error("FAIL %s: U=%h S=%h Pbase=%h P=%h UNC=%h",
                       name, data_u, data_s, standard_p, data_p, uncorr_p);
                $fatal(1);
            end

            $display("PASS %-28s U=%h STD=%h PROP=%h UNC=%h cycles=%0d",
                     name, data_u, data_s, data_p, uncorr_p, cycles_p);
        end
    endtask

    initial begin
        reset = 1'b1;
        start = 1'b0;
        operational_write_enable = 1'b0;
        operational_write_data = 8'h00;
        inject_lrs_fault_map = 24'h000000;
        inject_hrs_fault_map = 24'h000000;

        repeat (4) @(posedge clk);
        reset = 1'b0;

        run_case(
            24'h000000, 24'h000000, 8'hA5,
            24'h000000, 24'h000000,
            24'h000000, 24'h000000,
            8'hA5, 8'hA5, 8'hA5, 8'h00,
            "fault-free baseline"
        );

        run_case(
            24'h000000, 24'h000404, 8'hFF,
            24'h000000, 24'h000004,
            24'h000000, 24'h000404,
            8'hFB, 8'hFB, 8'hFF, 8'h00,
            "HRS bit2 replicas A+B"
        );

        run_case(
            24'h000808, 24'h000000, 8'h00,
            24'h000008, 24'h000000,
            24'h000808, 24'h000000,
            8'h08, 8'h08, 8'h00, 8'h00,
            "LRS bit3 replicas A+B"
        );

        run_case(
            24'h000000, 24'h000002, 8'hFF,
            24'h000000, 24'h000002,
            24'h000000, 24'h000002,
            8'hFD, 8'hFF, 8'hFF, 8'h00,
            "HRS bit1 replica A"
        );

        run_case(
            24'h000000, 24'h010101, 8'hFF,
            24'h000000, 24'h000001,
            24'h000000, 24'h010101,
            8'hFE, 8'hFE, 8'hFE, 8'h01,
            "HRS bit0 replicas A+B+C"
        );

        $display("ALL PUBLICATION ARCHITECTURE COMPARISON TESTS PASSED");
        $finish;
    end

    initial begin
        #100_000;
        $fatal(1, "TIMEOUT: publication architecture comparison");
    end

endmodule
