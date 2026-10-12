`timescale 1ns/1ps

// Hardware demonstration top for the Q2 diagnosis-guided voter experiment.
// This is intentionally separate from zedboard_memristor_top so the verified
// single-fault board design remains unchanged and can be restored at any time.
//
// Controls:
//   SW0       : enable the double fault
//   SW1       : 0=stuck-at-LRS, 1=stuck-at-HRS
//   SW4:SW2   : logical bit 0..7
//   SW6:SW5   : 00=A+B, 01=A+C, 10=B+C, 11=reserved/no fault
//   SW7       : 0=corrected-output/health view, 1=comparison view
//   BTNU      : reset test logic
//   BTNC      : start BIST and automatic post-diagnosis challenge write
//   BTNR      : safely toggle OLED power
module zedboard_memristor_q2_demo_top (
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
    (* ASYNC_REG = "TRUE" *) logic [1:0] oled_toggle_sync;
    (* ASYNC_REG = "TRUE" *) logic [7:0] switch_meta;
    (* ASYNC_REG = "TRUE" *) logic [7:0] switch_sync;

    logic start_previous;
    logic start_pulse;
    logic oled_toggle_previous;
    logic oled_toggle_pulse;
    logic system_reset;

    logic       configured_fault_enable;
    logic       configured_fault_is_hrs;
    logic [2:0] configured_fault_bit;
    logic [1:0] configured_fault_pair;
    logic [1:0] configured_fault_mode;
    logic [1:0] selected_resistance_replica;
    logic       pair_valid;

    logic [23:0] pair_fault_mask;
    logic [23:0] inject_lrs_fault_map;
    logic [23:0] inject_hrs_fault_map;

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

    logic       test_complete;
    logic       post_write_pending;
    logic       comparison_ready;
    logic       operational_write_enable;
    logic [7:0] challenge_data;
    logic       standard_pass;
    logic       proposed_pass;
    logic       expected_advantage;

    logic       lrs_found;
    logic       hrs_found;
    logic [7:0] fault_bit_map;
    logic [7:0] health_map;
    logic [7:0] status_leds;
    logic       oled_on;

    // Short FPGA-configuration reset for the OLED power sequencer. BTNU resets
    // the experiment without cycling the OLED power rails.
    logic [3:0] oled_por_counter = 4'h0;
    logic       oled_por_reset;

    always_ff @(posedge GCLK) begin
        if (!(&oled_por_counter))
            oled_por_counter <= oled_por_counter + 1'b1;
    end

    assign oled_por_reset = ~(&oled_por_counter);

    always_ff @(posedge GCLK) begin
        reset_sync <= {reset_sync[0], BTNU};
    end

    assign system_reset = reset_sync[1];

    // Synchronize all mechanical board inputs to the 100 MHz PL clock.
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

    // Snapshot the selected experiment when BTNC is pressed. SW7 remains live
    // so the user can change display mode after the result is available.
    always_ff @(posedge GCLK) begin
        if (system_reset) begin
            configured_fault_enable <= 1'b0;
            configured_fault_is_hrs <= 1'b0;
            configured_fault_bit    <= 3'd0;
            configured_fault_pair   <= 2'b11;
        end else if (start_pulse) begin
            configured_fault_enable <= switch_sync[0];
            configured_fault_is_hrs <= switch_sync[1];
            configured_fault_bit    <= switch_sync[4:2];
            configured_fault_pair   <= switch_sync[6:5];
        end
    end

    assign configured_fault_mode = configured_fault_is_hrs ? 2'b10 : 2'b01;
    assign pair_valid = configured_fault_pair != 2'b11;

    // Create two physical-cell faults in the selected logical bit. Map layout:
    // [7:0]=replica A, [15:8]=replica B, [23:16]=replica C.
    always_comb begin
        pair_fault_mask = 24'h000000;

        if (configured_fault_enable && pair_valid) begin
            case (configured_fault_pair)
                2'b00: begin // A+B
                    pair_fault_mask[{2'b00, configured_fault_bit}] = 1'b1;
                    pair_fault_mask[{2'b01, configured_fault_bit}] = 1'b1;
                end
                2'b01: begin // A+C
                    pair_fault_mask[{2'b00, configured_fault_bit}] = 1'b1;
                    pair_fault_mask[{2'b10, configured_fault_bit}] = 1'b1;
                end
                2'b10: begin // B+C
                    pair_fault_mask[{2'b01, configured_fault_bit}] = 1'b1;
                    pair_fault_mask[{2'b10, configured_fault_bit}] = 1'b1;
                end
                default: pair_fault_mask = 24'h000000;
            endcase
        end

        inject_lrs_fault_map = 24'h000000;
        inject_hrs_fault_map = 24'h000000;

        if (configured_fault_is_hrs)
            inject_hrs_fault_map = pair_fault_mask;
        else
            inject_lrs_fault_map = pair_fault_mask;
    end

    // The BIST resistance output reports the first replica in the selected
    // pair; both injected replicas have the same resistance in this demo.
    always_comb begin
        case (configured_fault_pair)
            2'b00, 2'b01: selected_resistance_replica = 2'd0;
            2'b10:       selected_resistance_replica = 2'd1;
            default:     selected_resistance_replica = 2'd3;
        endcase
    end

    // HRS faults are exposed by writing ones; LRS faults are exposed by
    // writing zeros. Ordinary TMR is then outvoted by the two stuck replicas.
    assign challenge_data = configured_fault_is_hrs ? 8'hFF : 8'h00;
    assign operational_write_enable = post_write_pending;

    memristor_bist_8bit bist_system (
        .clk               (GCLK),
        .reset             (system_reset),
        .start             (start_pulse),
        .fault_enable      (configured_fault_enable),
        .fault_bit_address (configured_fault_bit),
        .fault_replica     (selected_resistance_replica),
        .fault_mode        (configured_fault_mode),
        .multi_fault_enable(1'b1),
        .inject_lrs_fault_map(inject_lrs_fault_map),
        .inject_hrs_fault_map(inject_hrs_fault_map),
        .operational_write_enable(operational_write_enable),
        .operational_write_data(challenge_data),
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

    // Once BIST has diagnosed the two bad replicas, perform exactly one
    // functional challenge write while the controller is back in IDLE.
    always_ff @(posedge GCLK) begin
        if (system_reset) begin
            test_complete      <= 1'b0;
            post_write_pending <= 1'b0;
            comparison_ready   <= 1'b0;
        end else if (start_pulse) begin
            test_complete      <= 1'b0;
            post_write_pending <= 1'b0;
            comparison_ready   <= 1'b0;
        end else if (done) begin
            test_complete      <= 1'b1;
            post_write_pending <= 1'b1;
            comparison_ready   <= 1'b0;
        end else if (post_write_pending) begin
            post_write_pending <= 1'b0;
            comparison_ready   <= 1'b1;
        end
    end

    assign standard_pass = comparison_ready &&
                           (standard_tmr_data == challenge_data);
    assign proposed_pass = comparison_ready && diagnosis_valid &&
                           !uncorrectable_fault &&
                           (corrected_data == challenge_data);
    assign expected_advantage = configured_fault_enable && pair_valid &&
                                comparison_ready && !standard_pass &&
                                proposed_pass;

    assign lrs_found = |lrs_fault_map;
    assign hrs_found = |hrs_fault_map;

    assign fault_bit_map = lrs_fault_map[7:0]   |
                           lrs_fault_map[15:8]  |
                           lrs_fault_map[23:16] |
                           hrs_fault_map[7:0]   |
                           hrs_fault_map[15:8]  |
                           hrs_fault_map[23:16];

    assign health_map = test_complete ? ~fault_bit_map : 8'h00;

    // SW7=1 LED meanings:
    // LD0 busy, LD1 BIST complete, LD2 fault found, LD3 comparison ready,
    // LD4 standard TMR pass, LD5 proposed voter pass, LD6 double fault active,
    // LD7 expected research result (standard fails, proposed passes).
    always_comb begin
        status_leds[0] = busy;
        status_leds[1] = test_complete;
        status_leds[2] = fault_found;
        status_leds[3] = comparison_ready;
        status_leds[4] = standard_pass;
        status_leds[5] = proposed_pass;
        status_leds[6] = configured_fault_enable && pair_valid;
        status_leds[7] = expected_advantage;
    end

    always_comb begin
        LD = switch_sync[7] ? status_leds : health_map;
    end

    zedboard_oled_status oled_status (
        .clk               (GCLK),
        .reset             (oled_por_reset),
        .toggle_power      (oled_toggle_pulse),
        .detail_mode       (switch_sync[7]),
        .fault_enable      (configured_fault_enable),
        .fault_mode        (configured_fault_mode),
        .fault_bit_address (configured_fault_bit),
        .fault_replica     (selected_resistance_replica),
        .busy              (busy),
        .test_complete     (test_complete),
        .fault_found       (fault_found),
        .lrs_found         (lrs_found),
        .hrs_found         (hrs_found),
        .corrected_data    (corrected_data),
        .detected_resistance_ohms(detected_resistance_ohms),
        .comparison_mode   (1'b1),
        .comparison_ready  (comparison_ready),
        .fault_pair        (configured_fault_pair),
        .standard_pass     (standard_pass),
        .proposed_pass     (proposed_pass),
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
