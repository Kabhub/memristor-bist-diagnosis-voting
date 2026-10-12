`timescale 1ns/1ps

module tb_zedboard_memristor_top;

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

    zedboard_memristor_top dut (
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

    // ZedBoard programmable-logic clock: 100 MHz.
    always #5 GCLK = ~GCLK;

    task automatic press_start_and_wait;
        begin
            // Allow the switches to pass through their synchronizers.
            repeat (3) @(posedge GCLK);

            @(negedge GCLK);
            BTNC = 1'b1;
            repeat (4) @(posedge GCLK);
            @(negedge GCLK);
            BTNC = 1'b0;

            wait (dut.test_complete === 1'b1);
            #1;
        end
    endtask

    task automatic select_led_mode(input logic detail_mode);
        begin
            SW[7] = detail_mode;
            repeat (3) @(posedge GCLK);
            #1;
        end
    endtask

    task automatic check_leds(
        input logic [7:0] expected_leds,
        input string      test_name
    );
        begin
            if (LD !== expected_leds) begin
                $error("FAIL: %s | LEDs=%b expected=%b",
                       test_name, LD, expected_leds);
                $fatal(1);
            end
            $display("PASS: %s | LEDs=%b", test_name, LD);
        end
    endtask

    initial begin
        BTNC = 1'b0;
        BTNU = 1'b1;
        BTNR = 1'b0;
        SW   = 8'h00;

        repeat (5) @(posedge GCLK);
        #1 BTNU = 1'b0;

        // SW7=0: no fault means all eight logical bits are healthy.
        SW = 8'h00;
        press_start_and_wait();
        check_leds(8'hFF, "No-fault health map");

        // SW7=1: restore the original status indicators.
        select_led_mode(1'b1);
        check_leds(8'h82, "No-fault status view");

        // HRS fault: bit 3, replica B. LD3 must be the only dark LED.
        // SW0=enable, SW1=HRS, SW[4:2]=3, SW[6:5]=replica B.
        SW = 8'h2F;
        press_start_and_wait();
        check_leds(8'hF7, "HRS fault health map at bit 3");

        if (dut.detected_resistance_ohms !== 14'd10000) begin
            $error("FAIL: HRS detected resistance=%0d expected=10000",
                   dut.detected_resistance_ohms);
            $fatal(1);
        end

        select_led_mode(1'b1);
        check_leds(8'h76, "HRS status view");

        // LRS fault: bit 6, replica C. LD6 must be the only dark LED.
        // SW0=enable, SW1=LRS, SW[4:2]=6, SW[6:5]=replica C.
        SW = 8'h59;
        press_start_and_wait();
        check_leds(8'hBF, "LRS fault health map at bit 6");

        if (dut.detected_resistance_ohms !== 14'd100) begin
            $error("FAIL: LRS detected resistance=%0d expected=100",
                   dut.detected_resistance_ohms);
            $fatal(1);
        end

        select_led_mode(1'b1);
        check_leds(8'h6E, "LRS status view");

        if (dut.corrected_data !== 8'hFF) begin
            $error("FAIL: corrected TMR word=%h expected=FF", dut.corrected_data);
            $fatal(1);
        end

        $display("ALL UPDATED ZEDBOARD TOP TESTS PASSED");
        $finish;
    end

    initial begin
        #5000;
        $fatal(1, "TIMEOUT: ZedBoard top-level simulation did not finish");
    end

endmodule
