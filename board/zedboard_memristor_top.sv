`timescale 1ns/1ps

module zedboard_memristor_top (
    input  logic       GCLK,
    input  logic       BTNC,
    input  logic       BTNU,
    input  logic       BTNR,
    input  logic [7:0] SW,
    output logic [7:0] LD,
    output logic       OLED_DC,
    output logic       OLED_RES,
    output logic       OLED_SCLK,
    output logic       OLED_SDIN,
    output logic       OLED_VBAT,
    output logic       OLED_VDD
);

    (* ASYNC_REG = "TRUE" *) logic [1:0] reset_sync = 2'b11;
    (* ASYNC_REG = "TRUE" *) logic [1:0] start_sync;
    logic       start_previous;
    logic       start_pulse;
    (* ASYNC_REG = "TRUE" *) logic [1:0] oled_toggle_sync;
    logic       oled_toggle_previous;
    logic       oled_toggle_pulse;
    (* ASYNC_REG = "TRUE" *) logic [7:0] switch_meta;
    (* ASYNC_REG = "TRUE" *) logic [7:0] switch_sync;
    logic       system_reset;

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
    logic        test_complete;
    logic        lrs_found;
    logic        hrs_found;
    logic        tolerance_success;
    logic [1:0]  selected_fault_mode;
    logic [7:0]  fault_bit_map;
    logic [7:0]  health_map;
    logic [7:0]  status_leds;
    logic        oled_on;

    // This short power-on reset is initialized by the FPGA configuration.
    // BTNU resets the BIST only, so using it does not repeatedly power-cycle OLED.
    logic [3:0] oled_por_counter = 4'h0;
    logic       oled_por_reset;

    always_ff @(posedge GCLK) begin
        if (!(&oled_por_counter))
            oled_por_counter <= oled_por_counter + 1'b1;
    end

    assign oled_por_reset = ~(&oled_por_counter);

    // BTNU is asynchronous to GCLK.  Synchronizing it prevents the raw board
    // input from entering the BIST and control state machines directly.
    always_ff @(posedge GCLK) begin
        reset_sync <= {reset_sync[0], BTNU};
    end

    assign system_reset = reset_sync[1];

    // Synchronize the mechanical controls to the 100 MHz FPGA clock.
    always_ff @(posedge GCLK) begin
        if (system_reset) begin
            start_sync           <= 2'b00;
            start_previous       <= 1'b0;
            oled_toggle_sync     <= 2'b00;
            oled_toggle_previous <= 1'b0;
            switch_meta          <= 8'h00;
            switch_sync          <= 8'h00;
        end else begin
            start_sync           <= {start_sync[0], BTNC};
            start_previous       <= start_sync[1];
            oled_toggle_sync     <= {oled_toggle_sync[0], BTNR};
            oled_toggle_previous <= oled_toggle_sync[1];
            switch_meta          <= SW;
            switch_sync          <= switch_meta;
        end
    end

    assign start_pulse       = start_sync[1] & ~start_previous;
    assign oled_toggle_pulse = oled_toggle_sync[1] & ~oled_toggle_previous;

    // SW1: 0 = stuck-at-LRS, 1 = stuck-at-HRS.
    assign selected_fault_mode = switch_sync[1] ? 2'b10 : 2'b01;

    memristor_bist_8bit bist_system (
        .clk               (GCLK),
        .reset             (system_reset),
        .start             (start_pulse),
        .fault_enable      (switch_sync[0]),
        .fault_bit_address (switch_sync[4:2]),
        .fault_replica     (switch_sync[6:5]),
        .fault_mode        (selected_fault_mode),
        .multi_fault_enable(1'b0),
        .inject_lrs_fault_map(24'h000000),
        .inject_hrs_fault_map(24'h000000),
        .operational_write_enable(1'b0),
        .operational_write_data(8'h00),
        .busy              (busy),
        .done              (done),
        .fault_found       (fault_found),
        .diagnosis_valid   (diagnosis_valid),
        .uncorrectable_fault(uncorrectable_fault),
        .lrs_fault_map     (lrs_fault_map),
        .hrs_fault_map     (hrs_fault_map),
        .replica_health_map(replica_health_map),
        .corrected_data    (corrected_data),
        .standard_tmr_data (standard_tmr_data),
        .uncorrectable_map (uncorrectable_map),
        .detected_resistance_ohms(detected_resistance_ohms)
    );

    // Keep the completion result visible after the very fast BIST finishes.
    always_ff @(posedge GCLK) begin
        if (system_reset)
            test_complete <= 1'b0;
        else if (start_pulse)
            test_complete <= 1'b0;
        else if (done)
            test_complete <= 1'b1;
    end

    assign lrs_found = |lrs_fault_map;
    assign hrs_found = |hrs_fault_map;

    // Collapse the three replica maps into one logical 8-bit fault-location map.
    assign fault_bit_map = lrs_fault_map[7:0]   |
                           lrs_fault_map[15:8]  |
                           lrs_fault_map[23:16] |
                           hrs_fault_map[7:0]   |
                           hrs_fault_map[15:8]  |
                           hrs_fault_map[23:16];

    // One LED per logical bit: 1=healthy, 0=fault detected at that bit.
    assign health_map = test_complete ? ~fault_bit_map : 8'h00;

    assign tolerance_success = test_complete && fault_found &&
                               diagnosis_valid && !uncorrectable_fault &&
                               (corrected_data == 8'hFF);

    always_comb begin
        status_leds[0] = busy;
        status_leds[1] = test_complete;
        status_leds[2] = fault_found;
        status_leds[3] = lrs_found;
        status_leds[4] = hrs_found;
        status_leds[5] = tolerance_success;
        status_leds[6] = switch_sync[0];
        status_leds[7] = test_complete & ~fault_found;
    end

    // SW7=0: LEDs are the health map. SW7=1: LEDs are status indicators.
    always_comb begin
        LD = switch_sync[7] ? status_leds : health_map;
    end

    zedboard_oled_status oled_status (
        .clk               (GCLK),
        .reset             (oled_por_reset),
        .toggle_power      (oled_toggle_pulse),
        .detail_mode       (switch_sync[7]),
        .fault_enable      (switch_sync[0]),
        .fault_mode        (selected_fault_mode),
        .fault_bit_address (switch_sync[4:2]),
        .fault_replica     (switch_sync[6:5]),
        .busy              (busy),
        .test_complete     (test_complete),
        .fault_found       (fault_found),
        .lrs_found         (lrs_found),
        .hrs_found         (hrs_found),
        .corrected_data    (corrected_data),
        .detected_resistance_ohms(detected_resistance_ohms),
        .comparison_mode   (1'b0),
        .comparison_ready  (1'b0),
        .fault_pair        (2'b11),
        .standard_pass     (1'b0),
        .proposed_pass     (1'b0),
        .standard_data     (standard_tmr_data),
        .oled_on           (oled_on),
        .OLED_DC           (OLED_DC),
        .OLED_RES          (OLED_RES),
        .OLED_SCLK         (OLED_SCLK),
        .OLED_SDIN         (OLED_SDIN),
        .OLED_VBAT         (OLED_VBAT),
        .OLED_VDD          (OLED_VDD)
    );

endmodule
