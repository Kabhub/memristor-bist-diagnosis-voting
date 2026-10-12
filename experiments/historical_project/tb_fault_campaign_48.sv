`timescale 1ns/1ps

module tb_fault_campaign_48;

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

    localparam logic [1:0] STUCK_AT_LRS = 2'b01;
    localparam logic [1:0] STUCK_AT_HRS = 2'b10;

    integer fault_type_index;
    integer replica_index;
    integer bit_index;
    integer total_faults;
    integer detected_faults;
    integer tolerated_faults;
    integer map_position;
    logic [23:0] expected_map;

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

    initial begin
        reset             = 1'b1;
        start             = 1'b0;
        fault_enable      = 1'b1;
        fault_bit_address = 3'd0;
        fault_replica     = 2'd0;
        fault_mode        = STUCK_AT_LRS;
        multi_fault_enable = 1'b0;
        inject_lrs_fault_map = 24'h000000;
        inject_hrs_fault_map = 24'h000000;
        operational_write_enable = 1'b0;
        operational_write_data = 8'h00;
        total_faults      = 0;
        detected_faults   = 0;
        tolerated_faults  = 0;

        repeat (3) @(posedge clk);
        #1 reset = 1'b0;

        for (fault_type_index = 0;
             fault_type_index < 2;
             fault_type_index = fault_type_index + 1) begin

            for (replica_index = 0;
                 replica_index < 3;
                 replica_index = replica_index + 1) begin

                for (bit_index = 0;
                     bit_index < 8;
                     bit_index = bit_index + 1) begin

                    fault_mode = (fault_type_index == 0) ?
                                 STUCK_AT_LRS : STUCK_AT_HRS;
                    fault_replica     = replica_index[1:0];
                    fault_bit_address = bit_index[2:0];

                    map_position = (replica_index * 8) + bit_index;
                    expected_map = 24'h000001 << map_position;

                    run_bist();
                    total_faults = total_faults + 1;

                    if (fault_found)
                        detected_faults = detected_faults + 1;

                    if (corrected_data == 8'hFF)
                        tolerated_faults = tolerated_faults + 1;

                    if (fault_type_index == 0) begin
                        if ((lrs_fault_map !== expected_map) ||
                            (hrs_fault_map !== 24'h000000)) begin
                            $error("LRS MAP FAIL: replica=%0d bit=%0d LRS=%h HRS=%h expected=%h",
                                   replica_index, bit_index, lrs_fault_map,
                                   hrs_fault_map, expected_map);
                            $fatal(1);
                        end
                    end else begin
                        if ((hrs_fault_map !== expected_map) ||
                            (lrs_fault_map !== 24'h000000)) begin
                            $error("HRS MAP FAIL: replica=%0d bit=%0d LRS=%h HRS=%h expected=%h",
                                   replica_index, bit_index, lrs_fault_map,
                                   hrs_fault_map, expected_map);
                            $fatal(1);
                        end
                    end

                    if (!fault_found || !diagnosis_valid ||
                        uncorrectable_fault ||
                        (corrected_data !== 8'hFF)) begin
                        $error("COVERAGE FAIL: type=%s replica=%0d bit=%0d found=%b corrected=%h",
                               (fault_type_index == 0) ? "LRS" : "HRS",
                               replica_index, bit_index,
                               fault_found, corrected_data);
                        $fatal(1);
                    end

                    if (((fault_type_index == 0) &&
                         (detected_resistance_ohms !== 14'd100)) ||
                        ((fault_type_index == 1) &&
                         (detected_resistance_ohms !== 14'd10000))) begin
                        $error("RESISTANCE FAIL: type=%s replica=%0d bit=%0d R=%0d",
                               (fault_type_index == 0) ? "LRS" : "HRS",
                               replica_index, bit_index,
                               detected_resistance_ohms);
                        $fatal(1);
                    end

                    $display("PASS %0d: type=%s replica=%0d bit=%0d",
                             total_faults,
                             (fault_type_index == 0) ? "LRS" : "HRS",
                             replica_index, bit_index);
                end
            end
        end

        $display("----------------------------------------");
        $display("FAULT CAMPAIGN COMPLETE");
        $display("Total injected faults : %0d", total_faults);
        $display("Detected faults       : %0d", detected_faults);
        $display("Tolerated faults      : %0d", tolerated_faults);
        $display("Detection coverage    : 100%%");
        $display("Tolerance success     : 100%%");
        $display("ALL 48 SINGLE STUCK-AT FAULT TESTS PASSED");
        $finish;
    end

    initial begin
        #20000;
        $fatal(1, "TIMEOUT: fault campaign did not finish");
    end

endmodule
