`timescale 1ns/1ps

module tb_zedboard_memristor_q2_demo_top;

    logic       GCLK = 1'b0;
    logic       BTNC;
    logic       BTNU;
    logic       BTNR;
    logic [7:0] SW;
    logic [7:0] LD;
    logic       OLED_DC;
    logic       OLED_RES;
    logic       OLED_SCLK;
    logic       OLED_SDIN;
    logic       OLED_VBAT;
    logic       OLED_VDD;

    zedboard_memristor_q2_demo_top dut (
        .GCLK(GCLK),
        .BTNC(BTNC),
        .BTNU(BTNU),
        .BTNR(BTNR),
        .SW(SW),
        .LD(LD),
        .OLED_DC(OLED_DC),
        .OLED_RES(OLED_RES),
        .OLED_SCLK(OLED_SCLK),
        .OLED_SDIN(OLED_SDIN),
        .OLED_VBAT(OLED_VBAT),
        .OLED_VDD(OLED_VDD)
    );

    always #5 GCLK = ~GCLK;

    task automatic run_double_fault_case(
        input logic        fault_is_hrs,
        input logic [2:0]  fault_bit,
        input logic [1:0]  fault_pair,
        input logic [23:0] expected_map,
        input logic [7:0]  expected_standard,
        input logic [7:0]  expected_proposed,
        input logic [13:0] expected_resistance,
        input string       test_name
    );
        logic [7:0] expected_health;
        begin
            SW = 8'h00;
            SW[0]   = 1'b1;
            SW[1]   = fault_is_hrs;
            SW[4:2] = fault_bit;
            SW[6:5] = fault_pair;
            SW[7]   = 1'b0;

            // Allow switch synchronization, then create one clean start edge.
            repeat (4) @(posedge GCLK);
            @(negedge GCLK);
            BTNC = 1'b1;
            repeat (4) @(posedge GCLK);
            @(negedge GCLK);
            BTNC = 1'b0;

            wait (dut.comparison_ready === 1'b0);
            wait (dut.comparison_ready === 1'b1);
            #1;

            if (fault_is_hrs) begin
                if ((dut.hrs_fault_map !== expected_map) ||
                    (dut.lrs_fault_map !== 24'h000000)) begin
                    $error("FAIL: %s maps LRS=%h HRS=%h expected HRS=%h",
                           test_name, dut.lrs_fault_map, dut.hrs_fault_map,
                           expected_map);
                    $fatal(1);
                end
            end else begin
                if ((dut.lrs_fault_map !== expected_map) ||
                    (dut.hrs_fault_map !== 24'h000000)) begin
                    $error("FAIL: %s maps LRS=%h HRS=%h expected LRS=%h",
                           test_name, dut.lrs_fault_map, dut.hrs_fault_map,
                           expected_map);
                    $fatal(1);
                end
            end

            if (dut.standard_tmr_data !== expected_standard) begin
                $error("FAIL: %s standard=%h expected=%h",
                       test_name, dut.standard_tmr_data, expected_standard);
                $fatal(1);
            end

            if (dut.corrected_data !== expected_proposed) begin
                $error("FAIL: %s proposed=%h expected=%h",
                       test_name, dut.corrected_data, expected_proposed);
                $fatal(1);
            end

            if ((dut.standard_pass !== 1'b0) ||
                (dut.proposed_pass !== 1'b1) ||
                (dut.expected_advantage !== 1'b1) ||
                (dut.uncorrectable_fault !== 1'b0)) begin
                $error("FAIL: %s comparison std=%b new=%b advantage=%b uncorr=%b",
                       test_name, dut.standard_pass, dut.proposed_pass,
                       dut.expected_advantage, dut.uncorrectable_fault);
                $fatal(1);
            end

            if (dut.detected_resistance_ohms !== expected_resistance) begin
                $error("FAIL: %s resistance=%0d expected=%0d",
                       test_name, dut.detected_resistance_ohms,
                       expected_resistance);
                $fatal(1);
            end

            expected_health = ~(8'h01 << fault_bit);
            if (LD !== expected_health) begin
                $error("FAIL: %s health LEDs=%h expected=%h",
                       test_name, LD, expected_health);
                $fatal(1);
            end

            // Detailed comparison mode: 0xEE means standard failed while the
            // proposed voter passed and all test-completion flags are set.
            SW[7] = 1'b1;
            repeat (3) @(posedge GCLK);
            #1;
            if (LD !== 8'hEE) begin
                $error("FAIL: %s comparison LEDs=%h expected=EE",
                       test_name, LD);
                $fatal(1);
            end

            $display("PASS: %s | STD=%h NEW=%h MAP=%h LED=%h",
                     test_name, dut.standard_tmr_data, dut.corrected_data,
                     expected_map, LD);
        end
    endtask

    initial begin
        BTNC = 1'b0;
        BTNU = 1'b1;
        BTNR = 1'b0;
        SW   = 8'h00;

        repeat (5) @(posedge GCLK);
        #1 BTNU = 1'b0;

        // HRS double faults: challenge word FF. Ordinary TMR incorrectly
        // clears the selected bit; the diagnosis-guided voter retains FF.
        run_double_fault_case(
            1'b1, 3'd2, 2'b00, 24'h000404,
            8'hFB, 8'hFF, 14'd10000, "HRS bit2 pair A+B"
        );
        run_double_fault_case(
            1'b1, 3'd0, 2'b01, 24'h010001,
            8'hFE, 8'hFF, 14'd10000, "HRS bit0 pair A+C"
        );
        run_double_fault_case(
            1'b1, 3'd7, 2'b10, 24'h808000,
            8'h7F, 8'hFF, 14'd10000, "HRS bit7 pair B+C"
        );

        // LRS double faults: challenge word 00. Ordinary TMR incorrectly
        // sets the selected bit; the diagnosis-guided voter retains 00.
        run_double_fault_case(
            1'b0, 3'd3, 2'b00, 24'h000808,
            8'h08, 8'h00, 14'd100, "LRS bit3 pair A+B"
        );
        run_double_fault_case(
            1'b0, 3'd6, 2'b01, 24'h400040,
            8'h40, 8'h00, 14'd100, "LRS bit6 pair A+C"
        );
        run_double_fault_case(
            1'b0, 3'd5, 2'b10, 24'h202000,
            8'h20, 8'h00, 14'd100, "LRS bit5 pair B+C"
        );

        // Directly verify the research OLED strings for the final LRS case.
        if ((dut.oled_status.comparison_screen_character(
                 2'd1, 5'd12, 2'b01, 3'd5, 2'b10,
                 1'b0, 1'b1, 1'b0, 1'b1, 8'h20, 8'h00) !== "B") ||
            (dut.oled_status.comparison_screen_character(
                 2'd1, 5'd14, 2'b01, 3'd5, 2'b10,
                 1'b0, 1'b1, 1'b0, 1'b1, 8'h20, 8'h00) !== "C") ||
            (dut.oled_status.comparison_screen_character(
                 2'd2, 5'd5, 2'b01, 3'd5, 2'b10,
                 1'b0, 1'b1, 1'b0, 1'b1, 8'h20, 8'h00) !== "F") ||
            (dut.oled_status.comparison_screen_character(
                 2'd2, 5'd15, 2'b01, 3'd5, 2'b10,
                 1'b0, 1'b1, 1'b0, 1'b1, 8'h20, 8'h00) !== "P")) begin
            $error("FAIL: Q2 OLED comparison text was not rendered correctly");
            $fatal(1);
        end

        $display("ALL Q2 DOUBLE-FAULT ZEDBOARD DEMO TESTS PASSED");
        $finish;
    end

    initial begin
        #50_000;
        $fatal(1, "TIMEOUT: Q2 ZedBoard demonstration simulation did not finish");
    end

endmodule
