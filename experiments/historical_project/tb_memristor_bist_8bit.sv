`timescale 1ns/1ps

module tb_memristor_bist_8bit;

    logic        clk = 1'b0;
    logic        reset;
    logic        start;
    logic        fault_enable;
    logic [2:0]  fault_bit_address;
    logic [1:0]  fault_replica;
    logic [1:0]  fault_mode;
    logic        multi_fault_enable;
    logic [23:0] inject_lrs_fault_map;
    logic [23:0] inject_hrs_fault_map;
    logic        operational_write_enable;
    logic [7:0]  operational_write_data;
    logic        busy;
    logic        done;
    logic        fault_found;
    logic        diagnosis_valid;
    logic        uncorrectable_fault;
    logic [23:0] lrs_fault_map;
    logic [23:0] hrs_fault_map;
    logic [23:0] replica_health_map;
    logic [7:0]  corrected_data;
    logic [7:0]  standard_tmr_data;
    logic [7:0]  uncorrectable_map;
    logic [13:0] detected_resistance_ohms;

    localparam logic [1:0] NORMAL       = 2'b00;
    localparam logic [1:0] STUCK_AT_LRS = 2'b01;
    localparam logic [1:0] STUCK_AT_HRS = 2'b10;

    memristor_bist_8bit dut (
        .clk(clk),
        .reset(reset),
        .start(start),
        .fault_enable(fault_enable),
        .fault_bit_address(fault_bit_address),
        .fault_replica(fault_replica),
        .fault_mode(fault_mode),
        .multi_fault_enable(multi_fault_enable),
        .inject_lrs_fault_map(inject_lrs_fault_map),
        .inject_hrs_fault_map(inject_hrs_fault_map),
        .operational_write_enable(operational_write_enable),
        .operational_write_data(operational_write_data),
        .busy(busy),
        .done(done),
        .fault_found(fault_found),
        .diagnosis_valid(diagnosis_valid),
        .uncorrectable_fault(uncorrectable_fault),
        .lrs_fault_map(lrs_fault_map),
        .hrs_fault_map(hrs_fault_map),
        .replica_health_map(replica_health_map),
        .corrected_data(corrected_data),
        .standard_tmr_data(standard_tmr_data),
        .uncorrectable_map(uncorrectable_map),
        .detected_resistance_ohms(detected_resistance_ohms)
    );

    always #5 clk = ~clk;

    task automatic run_bist;
        begin
            wait (done === 1'b0);
            @(negedge clk);
            start = 1'b1;
            @(negedge clk);
            start = 1'b0;
            wait (done === 1'b1);
            #1;
        end
    endtask

    task automatic check_result(
        input logic        expected_fault,
        input logic [23:0] expected_lrs_map,
        input logic [23:0] expected_hrs_map,
        input logic [13:0] expected_resistance,
        input string       test_name
    );
        begin
            if ((fault_found !== expected_fault) ||
                (lrs_fault_map !== expected_lrs_map) ||
                (hrs_fault_map !== expected_hrs_map) ||
                !diagnosis_valid || uncorrectable_fault ||
                (corrected_data !== 8'hFF) ||
                (detected_resistance_ohms !== expected_resistance)) begin
                $error("FAIL: %s | found=%b LRS=%h HRS=%h corrected=%h R=%0d",
                       test_name, fault_found, lrs_fault_map,
                       hrs_fault_map, corrected_data,
                       detected_resistance_ohms);
                $fatal(1);
            end
            $display("PASS: %s | found=%b LRS=%h HRS=%h corrected=%h R=%0d",
                     test_name, fault_found, lrs_fault_map,
                     hrs_fault_map, corrected_data,
                     detected_resistance_ohms);
        end
    endtask

    initial begin
        reset             = 1'b1;
        start             = 1'b0;
        fault_enable      = 1'b0;
        fault_bit_address = 3'd0;
        fault_replica     = 2'd0;
        fault_mode        = NORMAL;
        multi_fault_enable = 1'b0;
        inject_lrs_fault_map = 24'h000000;
        inject_hrs_fault_map = 24'h000000;
        operational_write_enable = 1'b0;
        operational_write_data = 8'h00;

        repeat (2) @(posedge clk);
        #1 reset = 1'b0;

        run_bist();
        check_result(1'b0, 24'h000000, 24'h000000, 14'd0,
                     "No-fault BIST");

        fault_enable      = 1'b1;
        fault_bit_address = 3'd3;
        fault_replica     = 2'd1;
        fault_mode        = STUCK_AT_HRS;
        run_bist();
        check_result(1'b1, 24'h000000, 24'h000800, 14'd10000,
                     "HRS fault at bit 3 replica B");

        fault_bit_address = 3'd6;
        fault_replica     = 2'd2;
        fault_mode        = STUCK_AT_LRS;
        run_bist();
        check_result(1'b1, 24'h400000, 24'h000000, 14'd100,
                     "LRS fault at bit 6 replica C");

        $display("ALL BIST TESTS PASSED");
        $finish;
    end

endmodule
