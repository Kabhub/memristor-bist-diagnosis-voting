`timescale 1ns/1ps

// Q2 verification campaign
//   1 no-fault baseline
//  48 single stuck-resistance faults
// 1104 double faults = C(24,2) cell pairs x 4 type combinations
// ---------------------------------------------------------------------------
// The campaign checks resistance-based detection, exact localization, the
// diagnosis health map, and functional writes of both 00 and FF after BIST.
// It records ordinary TMR separately so the contribution of diagnosis-guided
// voting can be reported quantitatively.
module tb_fault_campaign_q2_1153;

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

    integer scenario_count;
    integer injected_scenarios;
    integer detected_scenarios;
    integer localized_scenarios;
    integer proposed_word_checks;
    integer proposed_word_passes;
    integer standard_word_passes;
    integer standard_word_failures;
    integer same_bit_double_scenarios;
    integer same_bit_word_checks;
    integer same_bit_standard_failures;
    integer no_fault_false_positives;
    integer cell_1;
    integer cell_2;
    integer type_1;
    integer type_2;
    integer single_cell;
    integer single_type;
    logic [23:0] expected_lrs_map;
    logic [23:0] expected_hrs_map;

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

    task automatic return_to_idle;
        begin
            @(posedge clk);
            #1;
            if (done !== 1'b0) begin
                $error("BIST failed to return to IDLE");
                $fatal(1);
            end
        end
    endtask

    task automatic check_localization(
        input logic        expect_fault,
        input logic [23:0] expected_lrs,
        input logic [23:0] expected_hrs,
        input string       scenario_name
    );
        begin
            if (!diagnosis_valid ||
                (fault_found !== expect_fault) ||
                (lrs_fault_map !== expected_lrs) ||
                (hrs_fault_map !== expected_hrs) ||
                (replica_health_map !== ~(expected_lrs | expected_hrs)) ||
                uncorrectable_fault ||
                (uncorrectable_map !== 8'h00)) begin
                $error("LOCALIZATION FAIL: %s | found=%b valid=%b LRS=%h HRS=%h health=%h uncorr=%h",
                       scenario_name, fault_found, diagnosis_valid,
                       lrs_fault_map, hrs_fault_map,
                       replica_health_map, uncorrectable_map);
                $fatal(1);
            end

            if (expect_fault) begin
                detected_scenarios  = detected_scenarios + 1;
                localized_scenarios = localized_scenarios + 1;
            end else if (fault_found) begin
                no_fault_false_positives = no_fault_false_positives + 1;
            end
        end
    endtask

    task automatic check_operational_word(
        input logic [7:0] value,
        input logic       same_bit_double,
        input string      scenario_name
    );
        begin
            operational_write_data   = value;
            operational_write_enable = 1'b1;
            @(posedge clk);
            #1;
            operational_write_enable = 1'b0;
            #1;

            proposed_word_checks = proposed_word_checks + 1;
            if (same_bit_double)
                same_bit_word_checks = same_bit_word_checks + 1;

            if ((corrected_data !== value) ||
                uncorrectable_fault ||
                (uncorrectable_map !== 8'h00)) begin
                $error("FAULT-AWARE CORRECTION FAIL: %s | write=%h proposed=%h standard=%h uncorr=%h",
                       scenario_name, value, corrected_data,
                       standard_tmr_data, uncorrectable_map);
                $fatal(1);
            end
            proposed_word_passes = proposed_word_passes + 1;

            if (standard_tmr_data === value) begin
                standard_word_passes = standard_word_passes + 1;
            end else begin
                standard_word_failures = standard_word_failures + 1;
                if (same_bit_double)
                    same_bit_standard_failures =
                        same_bit_standard_failures + 1;
            end
        end
    endtask

    task automatic verify_current_scenario(
        input logic        expect_fault,
        input logic [23:0] expected_lrs,
        input logic [23:0] expected_hrs,
        input logic        same_bit_double,
        input string       scenario_name
    );
        begin
            run_bist();
            check_localization(expect_fault, expected_lrs,
                               expected_hrs, scenario_name);
            return_to_idle();
            check_operational_word(8'h00, same_bit_double,
                                   scenario_name);
            check_operational_word(8'hFF, same_bit_double,
                                   scenario_name);
        end
    endtask

    initial begin
        reset                    = 1'b1;
        start                    = 1'b0;
        fault_enable             = 1'b0;
        fault_bit_address        = 3'd0;
        fault_replica            = 2'd0;
        fault_mode               = NORMAL;
        multi_fault_enable       = 1'b1;
        inject_lrs_fault_map     = 24'h000000;
        inject_hrs_fault_map     = 24'h000000;
        operational_write_enable = 1'b0;
        operational_write_data  = 8'h00;

        scenario_count                  = 0;
        injected_scenarios              = 0;
        detected_scenarios              = 0;
        localized_scenarios             = 0;
        proposed_word_checks            = 0;
        proposed_word_passes            = 0;
        standard_word_passes            = 0;
        standard_word_failures          = 0;
        same_bit_double_scenarios       = 0;
        same_bit_word_checks            = 0;
        same_bit_standard_failures      = 0;
        no_fault_false_positives        = 0;

        repeat (3) @(posedge clk);
        #1 reset = 1'b0;

        // Scenario 0: fault-free baseline.
        verify_current_scenario(1'b0, 24'h000000, 24'h000000,
                                1'b0, "No-fault baseline");
        scenario_count = scenario_count + 1;

        // All 48 single-cell faults.
        for (single_cell = 0; single_cell < 24;
             single_cell = single_cell + 1) begin
            for (single_type = 0; single_type < 2;
                 single_type = single_type + 1) begin
                expected_lrs_map = 24'h000000;
                expected_hrs_map = 24'h000000;
                if (single_type == 0)
                    expected_lrs_map[single_cell] = 1'b1;
                else
                    expected_hrs_map[single_cell] = 1'b1;

                inject_lrs_fault_map = expected_lrs_map;
                inject_hrs_fault_map = expected_hrs_map;
                verify_current_scenario(1'b1, expected_lrs_map,
                                        expected_hrs_map, 1'b0,
                                        "Single fault");
                scenario_count     = scenario_count + 1;
                injected_scenarios = injected_scenarios + 1;
            end
        end

        // All 1,104 distinct two-cell / two-type combinations.
        for (cell_1 = 0; cell_1 < 23; cell_1 = cell_1 + 1) begin
            for (cell_2 = cell_1 + 1; cell_2 < 24;
                 cell_2 = cell_2 + 1) begin
                for (type_1 = 0; type_1 < 2; type_1 = type_1 + 1) begin
                    for (type_2 = 0; type_2 < 2;
                         type_2 = type_2 + 1) begin
                        expected_lrs_map = 24'h000000;
                        expected_hrs_map = 24'h000000;

                        if (type_1 == 0)
                            expected_lrs_map[cell_1] = 1'b1;
                        else
                            expected_hrs_map[cell_1] = 1'b1;

                        if (type_2 == 0)
                            expected_lrs_map[cell_2] = 1'b1;
                        else
                            expected_hrs_map[cell_2] = 1'b1;

                        inject_lrs_fault_map = expected_lrs_map;
                        inject_hrs_fault_map = expected_hrs_map;

                        if ((cell_1 % 8) == (cell_2 % 8))
                            same_bit_double_scenarios =
                                same_bit_double_scenarios + 1;

                        verify_current_scenario(
                            1'b1, expected_lrs_map, expected_hrs_map,
                            ((cell_1 % 8) == (cell_2 % 8)),
                            "Double fault");

                        scenario_count     = scenario_count + 1;
                        injected_scenarios = injected_scenarios + 1;

                        if ((scenario_count % 100) == 0)
                            $display("Progress: %0d / 1153 scenarios",
                                     scenario_count);
                    end
                end
            end
        end

        if ((scenario_count                 != 1153) ||
            (injected_scenarios             != 1152) ||
            (detected_scenarios             != 1152) ||
            (localized_scenarios            != 1152) ||
            (proposed_word_checks           != 2306) ||
            (proposed_word_passes           != 2306) ||
            (same_bit_double_scenarios      != 96)   ||
            (same_bit_word_checks           != 192)  ||
            (standard_word_failures         != 48)   ||
            (same_bit_standard_failures     != 48)   ||
            (no_fault_false_positives       != 0)) begin
            $error("FINAL COUNT MISMATCH");
            $fatal(1);
        end

        $display("====================================================");
        $display("Q2 FAULT CAMPAIGN COMPLETE");
        $display("Total scenarios                         : %0d",
                 scenario_count);
        $display("Injected single/double-fault scenarios : %0d",
                 injected_scenarios);
        $display("Detected scenarios                      : %0d",
                 detected_scenarios);
        $display("Exactly localized scenarios             : %0d",
                 localized_scenarios);
        $display("False positives in no-fault baseline    : %0d",
                 no_fault_false_positives);
        $display("Proposed voter word checks passed       : %0d/%0d",
                 proposed_word_passes, proposed_word_checks);
        $display("Standard TMR word checks passed         : %0d/%0d",
                 standard_word_passes, proposed_word_checks);
        $display("Standard TMR failures                   : %0d",
                 standard_word_failures);
        $display("Critical same-bit double scenarios      : %0d",
                 same_bit_double_scenarios);
        $display("Critical standard-TMR failures          : %0d/%0d",
                 same_bit_standard_failures, same_bit_word_checks);
        $display("Detection coverage                      : 100%%");
        $display("Localization accuracy                   : 100%%");
        $display("Diagnosis-guided correction success     : 100%%");
        $display("ALL 1,153 Q2 CAMPAIGN SCENARIOS PASSED");
        $finish;
    end

    initial begin
        #2000000;
        $fatal(1, "TIMEOUT: Q2 fault campaign did not finish");
    end

endmodule
