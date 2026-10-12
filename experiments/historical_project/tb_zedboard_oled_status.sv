`timescale 1ns/1ps

module tb_zedboard_oled_status;

    logic       clk = 1'b0;
    logic       reset;
    logic       toggle_power;
    logic       detail_mode;
    logic       fault_enable;
    logic [1:0] fault_mode;
    logic [2:0] fault_bit_address;
    logic [1:0] fault_replica;
    logic       busy;
    logic       test_complete;
    logic       fault_found;
    logic       lrs_found;
    logic       hrs_found;
    logic [7:0] corrected_data;
    logic [13:0] detected_resistance_ohms;
    logic       oled_on;
    logic       OLED_DC;
    logic       OLED_RES;
    logic       OLED_SCLK;
    logic       OLED_SDIN;
    logic       OLED_VBAT;
    logic       OLED_VDD;

    integer cycle_count = 0;
    integer bit_count = 0;
    integer command_count = 0;
    integer clear_data_count = 0;
    integer vbat_off_cycle;
    integer vdd_off_cycle;
    logic [7:0] received_byte = 8'h00;
    logic       received_dc = 1'b0;
    logic [7:0] captured_commands [0:63];
    logic [7:0] expected_commands [0:21];

    zedboard_oled_status #(
        // Reduced counters keep behavioral simulation quick. Hardware uses
        // the module defaults: 100 MHz and 100 ms VBAT delays.
        .CLK_HZ(100_000),
        .SPI_HALF_PERIOD_CYCLES(1),
        .VDD_DELAY_MS(1),
        .RESET_DELAY_MS(1),
        .VBAT_DELAY_MS(2),
        .OFF_DELAY_MS(2)
    ) dut (
        .clk(clk),
        .reset(reset),
        .toggle_power(toggle_power),
        .detail_mode(detail_mode),
        .fault_enable(fault_enable),
        .fault_mode(fault_mode),
        .fault_bit_address(fault_bit_address),
        .fault_replica(fault_replica),
        .busy(busy),
        .test_complete(test_complete),
        .fault_found(fault_found),
        .lrs_found(lrs_found),
        .hrs_found(hrs_found),
        .corrected_data(corrected_data),
        .detected_resistance_ohms(detected_resistance_ohms),
        .comparison_mode(1'b0),
        .comparison_ready(1'b0),
        .fault_pair(2'b11),
        .standard_pass(1'b0),
        .proposed_pass(1'b0),
        .standard_data(8'h00),
        .oled_on(oled_on),
        .OLED_DC(OLED_DC),
        .OLED_RES(OLED_RES),
        .OLED_SCLK(OLED_SCLK),
        .OLED_SDIN(OLED_SDIN),
        .OLED_VBAT(OLED_VBAT),
        .OLED_VDD(OLED_VDD)
    );

    always #5 clk = ~clk;

    always @(posedge clk)
        cycle_count = cycle_count + 1;

    // Decode every transmitted SPI byte and retain command bytes (DC=0).
    always @(posedge OLED_SCLK) begin
        if (bit_count == 0)
            received_dc = OLED_DC;

        received_byte = {received_byte[6:0], OLED_SDIN};

        if (bit_count == 7) begin
            if (received_dc && (OLED_VBAT === 1'b1)) begin
                clear_data_count = clear_data_count + 1;
            end else if (!received_dc && (command_count < 64)) begin
                captured_commands[command_count] = received_byte;
                command_count = command_count + 1;
            end
            bit_count = 0;
        end else begin
            bit_count = bit_count + 1;
        end
    end

    task automatic pulse_power_button;
        begin
            @(negedge clk);
            toggle_power = 1'b1;
            @(negedge clk);
            toggle_power = 1'b0;
        end
    endtask

    initial begin
        expected_commands[0]  = 8'hAE;
        expected_commands[1]  = 8'hD5;
        expected_commands[2]  = 8'h80;
        expected_commands[3]  = 8'hA8;
        expected_commands[4]  = 8'h1F;
        expected_commands[5]  = 8'hD3;
        expected_commands[6]  = 8'h00;
        expected_commands[7]  = 8'h40;
        expected_commands[8]  = 8'h8D;
        expected_commands[9]  = 8'h14;
        expected_commands[10] = 8'hA1;
        expected_commands[11] = 8'hC8;
        expected_commands[12] = 8'hDA;
        expected_commands[13] = 8'h02;
        expected_commands[14] = 8'h81;
        expected_commands[15] = 8'h8F;
        expected_commands[16] = 8'hD9;
        expected_commands[17] = 8'hF1;
        expected_commands[18] = 8'hDB;
        expected_commands[19] = 8'h40;
        expected_commands[20] = 8'hA4;
        expected_commands[21] = 8'hA6;

        reset             = 1'b1;
        toggle_power      = 1'b0;
        detail_mode       = 1'b0;
        fault_enable      = 1'b1;
        fault_mode        = 2'b10;
        fault_bit_address = 3'd3;
        fault_replica     = 2'd1;
        busy              = 1'b0;
        test_complete     = 1'b1;
        fault_found       = 1'b1;
        lrs_found         = 1'b0;
        hrs_found         = 1'b1;
        corrected_data    = 8'hFF;
        detected_resistance_ohms = 14'd10000;

        repeat (4) @(posedge clk);
        #1;
        if ((OLED_VDD !== 1'b1) || (OLED_VBAT !== 1'b1)) begin
            $error("FAIL: OLED power rails were not initially off");
            $fatal(1);
        end

        reset = 1'b0;

        wait (OLED_VDD === 1'b0);
        if (OLED_VBAT !== 1'b1) begin
            $error("FAIL: VBAT enabled before VDD");
            $fatal(1);
        end

        wait (OLED_VBAT === 1'b0);
        if (OLED_VDD !== 1'b0) begin
            $error("FAIL: VDD was not held on while VBAT enabled");
            $fatal(1);
        end

        wait (oled_on === 1'b1);
        repeat (3) @(posedge clk);

        if (command_count < 35) begin
            $error("FAIL: only %0d OLED initialization commands captured",
                   command_count);
            $fatal(1);
        end

        for (integer index = 0; index < 22; index = index + 1) begin
            if (captured_commands[index] !== expected_commands[index]) begin
                $error("FAIL: OLED command %0d was %h, expected %h",
                       index, captured_commands[index], expected_commands[index]);
                $fatal(1);
            end
        end

        for (integer clear_page = 0; clear_page < 4;
             clear_page = clear_page + 1) begin
            if ((captured_commands[22 + (clear_page * 3)] !==
                 (8'hB0 | {6'b000000, clear_page[1:0]})) ||
                (captured_commands[23 + (clear_page * 3)] !== 8'h00) ||
                (captured_commands[24 + (clear_page * 3)] !== 8'h10)) begin
                $error("FAIL: clear-screen page commands incorrect for page %0d",
                       clear_page);
                $fatal(1);
            end
        end

        if ((clear_data_count !== 512) ||
            (captured_commands[34] !== 8'hAF)) begin
            $error("FAIL: screen was not cleared before display-on; bytes=%0d AF=%h",
                   clear_data_count, captured_commands[34]);
            $fatal(1);
        end

        // Directly verify the two screen layouts used by the pixel generator.
        if (dut.screen_character(
                1'b0, 2'd1, 5'd9, 1'b1, 2'b10, 3'd3, 2'd1,
                1'b0, 1'b1, 1'b1, 1'b0, 1'b1, 8'hFF,
                14'd10000) !== "1") begin
            $error("FAIL: corrected word was not rendered MSB-first");
            $fatal(1);
        end

        if (dut.screen_character(
                1'b1, 2'd0, 5'd9, 1'b1, 2'b10, 3'd3, 2'd1,
                1'b0, 1'b1, 1'b1, 1'b0, 1'b1, 8'hFF,
                14'd10000) !== "H") begin
            $error("FAIL: HRS detail text was not rendered");
            $fatal(1);
        end

        if (dut.screen_character(
                1'b1, 2'd1, 5'd14, 1'b1, 2'b10, 3'd3, 2'd1,
                1'b0, 1'b1, 1'b1, 1'b0, 1'b1, 8'hFF,
                14'd10000) !== "B") begin
            $error("FAIL: replica B detail text was not rendered");
            $fatal(1);
        end

        if (dut.screen_character(
                1'b1, 2'd2, 5'd6, 1'b1, 2'b10, 3'd3, 2'd1,
                1'b0, 1'b1, 1'b1, 1'b0, 1'b1, 8'hFF,
                14'd10000) !== "1") begin
            $error("FAIL: 10000-ohm HRS value was not rendered");
            $fatal(1);
        end

        if ((dut.screen_character(
                 1'b1, 2'd2, 5'd6, 1'b1, 2'b01, 3'd6, 2'd2,
                 1'b0, 1'b1, 1'b1, 1'b1, 1'b0, 8'hFF,
                 14'd100) !== " ") ||
            (dut.screen_character(
                 1'b1, 2'd2, 5'd8, 1'b1, 2'b01, 3'd6, 2'd2,
                 1'b0, 1'b1, 1'b1, 1'b1, 1'b0, 8'hFF,
                 14'd100) !== "1")) begin
            $error("FAIL: 100-ohm LRS value was not rendered correctly");
            $fatal(1);
        end

        if ((dut.screen_character(
                 1'b1, 2'd3, 5'd6, 1'b1, 2'b10, 3'd3, 2'd1,
                 1'b0, 1'b1, 1'b1, 1'b0, 1'b1, 8'hFF,
                 14'd10000) !== "P") ||
            (dut.screen_character(
                 1'b1, 2'd3, 5'd16, 1'b1, 2'b10, 3'd3, 2'd1,
                 1'b0, 1'b1, 1'b1, 1'b0, 1'b1, 8'hFF,
                 14'd10000) !== "P")) begin
            $error("FAIL: combined BIST/TMR detail line was not rendered");
            $fatal(1);
        end

        // Verify safe power-down: display off, VBAT off, delay, then VDD off.
        pulse_power_button();
        wait (OLED_VBAT === 1'b1);
        vbat_off_cycle = cycle_count;
        if (OLED_VDD !== 1'b0) begin
            $error("FAIL: VDD switched off before the VBAT discharge delay");
            $fatal(1);
        end

        wait (OLED_VDD === 1'b1);
        vdd_off_cycle = cycle_count;
        if ((vdd_off_cycle - vbat_off_cycle) < 199) begin
            $error("FAIL: OLED shutdown delay too short: %0d cycles",
                   vdd_off_cycle - vbat_off_cycle);
            $fatal(1);
        end

        if (oled_on !== 1'b0) begin
            $error("FAIL: OLED still marked on after shutdown");
            $fatal(1);
        end

        // A second BTNR press starts the correct VDD-first power-up again.
        pulse_power_button();
        wait (OLED_VDD === 1'b0);
        if (OLED_VBAT !== 1'b1) begin
            $error("FAIL: second power-up did not begin with VDD only");
            $fatal(1);
        end

        $display("ALL OLED CONTROLLER TESTS PASSED");
        $finish;
    end

    initial begin
        #2_000_000;
        $fatal(1, "TIMEOUT: OLED controller simulation did not finish");
    end

endmodule
