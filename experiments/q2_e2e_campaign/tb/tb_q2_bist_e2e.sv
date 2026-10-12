`timescale 1ns/1ps

// Injection controls act only on the cells. Expected maps are oracle values
// for assertions; they are never supplied to the diagnosis or voting logic.
module q2_bist_e2e_campaign #(
    parameter integer WIDTH = 16
);
    localparam integer CELLS = 3 * WIDTH;
    localparam integer EXPECTED_SCENARIOS = 1 + 2 * CELLS * CELLS;
    localparam integer EXPECTED_SINGLE = 2 * CELLS;
    localparam integer EXPECTED_DOUBLE = 2 * CELLS * (CELLS - 1);
    localparam integer EXPECTED_PRIMARY_CHECKS = 2 * EXPECTED_SCENARIOS;

    logic clk = 1'b0;
    logic reset, start, write_enable;
    logic [WIDTH-1:0] write_data;
    logic [CELLS-1:0] inject_lrs, inject_hrs;
    wire busy, done, fault_found, diagnosis_valid;
    wire [15:0] bist_cycle_count;
    wire [WIDTH-1:0] corrected_data, standard_tmr_data, unprotected_data;
    wire [WIDTH-1:0] uncorrectable_map;
    wire [CELLS-1:0] lrs_fault_map, hrs_fault_map, health_map;

    publication_scalable_memristor_core #(.WIDTH(WIDTH), .ARCHITECTURE(2)) dut (
        .clk(clk), .reset(reset), .start(start),
        .operational_write_enable(write_enable), .operational_write_data(write_data),
        .inject_lrs_fault_map(inject_lrs), .inject_hrs_fault_map(inject_hrs),
        .busy(busy), .done(done), .fault_found(fault_found),
        .diagnosis_valid(diagnosis_valid), .bist_cycle_count(bist_cycle_count),
        .corrected_data(corrected_data), .standard_tmr_data(standard_tmr_data),
        .unprotected_data(unprotected_data), .uncorrectable_map(uncorrectable_map),
        .lrs_fault_map(lrs_fault_map), .hrs_fault_map(hrs_fault_map),
        .replica_health_map(health_map)
    );
    always #5 clk = ~clk;

    integer scenario_count = 0;
    integer single_count = 0, double_count = 0;
    integer detected_count = 0, localized_count = 0;
    integer primary_checks = 0, primary_passes = 0;
    integer primary_tmr_passes = 0, primary_tmr_failures = 0;
    integer mixed_checks = 0, mixed_passes = 0, mixed_tmr_failures = 0;
    integer same_bit_scenarios = 0, same_bit_primary_checks = 0;
    integer same_bit_primary_tmr_failures = 0;
    integer csv_file, summary_file, pass_file;
    integer a, b, ta, tb, bit_index;
    logic [CELLS-1:0] expected_lrs, expected_hrs;
    logic [WIDTH-1:0] alternating;
    string output_prefix;

    task automatic fail(input string message);
        begin
            $display("E2E FAILURE: width=%0d scenario=%0d: %s", WIDTH, scenario_count, message);
            if (csv_file != 0) $fflush(csv_file);
            $fatal(1, "%s", message);
        end
    endtask

    task automatic run_bist;
        integer elapsed_cycles;
        begin
            @(negedge clk);
            if (done !== 1'b0 || busy !== 1'b0) fail("Core not idle before BIST");
            start = 1'b1;
            @(posedge clk); #1;
            if (diagnosis_valid !== 1'b0 || busy !== 1'b1)
                fail("New BIST did not invalidate the previous diagnosis");
            @(negedge clk); start = 1'b0;
            elapsed_cycles = 1;
            while (done !== 1'b1 && elapsed_cycles < 12) begin
                @(posedge clk); #1;
                elapsed_cycles = elapsed_cycles + 1;
            end
            if (done !== 1'b1) fail("BIST completion timeout");
            if (elapsed_cycles != 5 || bist_cycle_count !== 16'd5)
                fail("Unexpected BIST latency; expected five cycles including start acceptance");
        end
    endtask

    task automatic verify_diagnosis(input integer fault_order);
        begin
            if (diagnosis_valid !== 1'b1) fail("Diagnosis is not valid at completion");
            if (fault_found !== (fault_order != 0)) fail("Fault detection mismatch");
            if (lrs_fault_map !== expected_lrs || hrs_fault_map !== expected_hrs)
                fail("BIST fault-location or polarity map mismatch");
            if (health_map !== ~(expected_lrs | expected_hrs)) fail("Health map mismatch");
            if (uncorrectable_map !== {WIDTH{1'b0}}) fail("Unexpected rejection after BIST");
        end
    endtask

    task automatic check_word(
        input logic [WIDTH-1:0] value,
        input logic primary,
        input logic same_bit
    );
        begin
            @(negedge clk);
            if (busy !== 1'b0 || done !== 1'b0) fail("Write attempted outside IDLE");
            write_data = value; write_enable = 1'b1;
            @(posedge clk); #1;
            if (corrected_data !== value || uncorrectable_map !== {WIDTH{1'b0}})
                fail($sformatf("Corrected word/rejection mismatch: write=%h output=%h reject=%h",
                    value, corrected_data, uncorrectable_map));
            if (diagnosis_valid !== 1'b1 || lrs_fault_map !== expected_lrs || hrs_fault_map !== expected_hrs)
                fail("Operational write changed diagnosis unexpectedly");
            if (primary) begin
                primary_checks = primary_checks + 1;
                primary_passes = primary_passes + 1;
                if (same_bit) same_bit_primary_checks = same_bit_primary_checks + 1;
                if (standard_tmr_data === value) primary_tmr_passes = primary_tmr_passes + 1;
                else begin
                    primary_tmr_failures = primary_tmr_failures + 1;
                    if (same_bit) same_bit_primary_tmr_failures = same_bit_primary_tmr_failures + 1;
                end
            end else begin
                mixed_checks = mixed_checks + 1;
                mixed_passes = mixed_passes + 1;
                if (standard_tmr_data !== value) mixed_tmr_failures = mixed_tmr_failures + 1;
            end
            @(negedge clk); write_enable = 1'b0;
        end
    endtask

    task automatic scenario(
        input integer fault_order, input integer cell_a, input integer cell_b,
        input integer polarity_a, input integer polarity_b
    );
        logic same_bit;
        begin
            same_bit = (fault_order == 2) && ((cell_a % WIDTH) == (cell_b % WIDTH));
            @(negedge clk);
            inject_lrs = expected_lrs; inject_hrs = expected_hrs;
            run_bist();
            verify_diagnosis(fault_order);
            @(posedge clk); #1;
            if (done !== 1'b0 || busy !== 1'b0) fail("BIST did not return to IDLE");
            check_word('0, 1'b1, same_bit);
            check_word('1, 1'b1, same_bit);
            check_word(alternating, 1'b0, same_bit);
            check_word(~alternating, 1'b0, same_bit);
            $fdisplay(csv_file,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,%h,%h,%h,%h,%h,5,PASS",
                scenario_count, WIDTH, fault_order, cell_a, cell_b, polarity_a, polarity_b,
                expected_lrs, expected_hrs, lrs_fault_map, hrs_fault_map, health_map);
            scenario_count = scenario_count + 1;
            if (fault_order > 0) begin
                detected_count = detected_count + 1;
                localized_count = localized_count + 1;
            end
            if (fault_order == 1) single_count = single_count + 1;
            if (fault_order == 2) double_count = double_count + 1;
            if (same_bit) same_bit_scenarios = same_bit_scenarios + 1;
            if (scenario_count % 250 == 0) begin
                $fflush(csv_file);
                $display("E2E progress: %0d / %0d scenarios", scenario_count, EXPECTED_SCENARIOS);
            end
        end
    endtask

    initial begin
        output_prefix = $sformatf("e2e_w%0d", WIDTH);
        csv_file = $fopen({output_prefix,"_scenarios.csv"}, "w");
        if (csv_file == 0) $fatal(1,"Cannot open per-scenario CSV");
        $fdisplay(csv_file,"scenario_id,width,fault_order,cell_a,cell_b,polarity_a,polarity_b,expected_lrs_map,expected_hrs_map,diagnosed_lrs_map,diagnosed_hrs_map,health_map,bist_cycles,status");
        $display("End-to-end RTL campaign: WIDTH=%0d, CELLS=%0d, scenarios=%0d", WIDTH, CELLS, EXPECTED_SCENARIOS);
        reset=1'b1; start=1'b0; write_enable=1'b0;
        write_data='0; inject_lrs='0; inject_hrs='0; expected_lrs='0; expected_hrs='0;
        for (bit_index=0; bit_index<WIDTH; bit_index=bit_index+1)
            alternating[bit_index] = ((bit_index % 2) == 1);
        repeat (3) @(posedge clk);
        @(negedge clk); reset=1'b0;
        scenario(0, -1, -1, -1, -1);
        for (a=0; a<CELLS; a=a+1) begin
            for (ta=0; ta<2; ta=ta+1) begin
                expected_lrs='0; expected_hrs='0;
                if (ta==0) expected_lrs[a]=1'b1; else expected_hrs[a]=1'b1;
                scenario(1, a, -1, ta, -1);
            end
        end
        for (a=0; a<CELLS-1; a=a+1) begin
            for (b=a+1; b<CELLS; b=b+1) begin
                for (ta=0; ta<2; ta=ta+1) begin
                    for (tb=0; tb<2; tb=tb+1) begin
                        expected_lrs='0; expected_hrs='0;
                        if (ta==0) expected_lrs[a]=1'b1; else expected_hrs[a]=1'b1;
                        if (tb==0) expected_lrs[b]=1'b1; else expected_hrs[b]=1'b1;
                        scenario(2, a, b, ta, tb);
                    end
                end
            end
        end
        if (scenario_count != EXPECTED_SCENARIOS || single_count != EXPECTED_SINGLE ||
            double_count != EXPECTED_DOUBLE || detected_count != EXPECTED_SCENARIOS-1 ||
            localized_count != EXPECTED_SCENARIOS-1 || primary_checks != EXPECTED_PRIMARY_CHECKS ||
            primary_passes != EXPECTED_PRIMARY_CHECKS || mixed_checks != EXPECTED_PRIMARY_CHECKS ||
            mixed_passes != EXPECTED_PRIMARY_CHECKS || primary_tmr_failures != 6*WIDTH ||
            primary_tmr_passes != EXPECTED_PRIMARY_CHECKS-6*WIDTH ||
            same_bit_scenarios != 12*WIDTH || same_bit_primary_checks != 24*WIDTH ||
            same_bit_primary_tmr_failures != 6*WIDTH)
            fail("Final campaign counts do not match exhaustive enumeration");
        $fclose(csv_file); csv_file=0;

        // Additional protocol checks do not change the exhaustive counts.
        // First exercise loss of all three replicas at one bit: maps must be
        // diagnosed and that bit must be rejected for both data backgrounds.
        @(negedge clk);
        expected_lrs='0; expected_hrs='0;
        expected_hrs[0]=1'b1; expected_hrs[WIDTH]=1'b1; expected_hrs[2*WIDTH]=1'b1;
        inject_lrs=expected_lrs; inject_hrs=expected_hrs;
        run_bist();
        if (hrs_fault_map !== expected_hrs || lrs_fault_map !== expected_lrs ||
            diagnosis_valid !== 1'b1 || fault_found !== 1'b1 ||
            uncorrectable_map !== {{(WIDTH-1){1'b0}},1'b1})
            fail("Three-fault boundary was not diagnosed and rejected");
        @(posedge clk); #1;
        @(negedge clk); write_data='0; write_enable=1'b1;
        @(posedge clk); #1;
        if (uncorrectable_map !== {{(WIDTH-1){1'b0}},1'b1}) fail("Triple-fault zero write falsely accepted");
        @(negedge clk); write_data='1;
        @(posedge clk); #1;
        if (uncorrectable_map !== {{(WIDTH-1){1'b0}},1'b1}) fail("Triple-fault one write falsely accepted");
        @(negedge clk); write_enable=1'b0; expected_lrs='0; expected_hrs='0;
        inject_lrs='0; inject_hrs='0;
        run_bist(); verify_diagnosis(0);
        @(posedge clk); #1;
        if (done !== 1'b0) fail("Recovery BIST did not return to IDLE");

        summary_file=$fopen({output_prefix,"_summary.csv"},"w");
        if (summary_file==0) fail("Cannot open summary CSV");
        $fdisplay(summary_file,"width,cells,scenarios,single_scenarios,double_scenarios,detected,exactly_localized,primary_checks,primary_proposed_passes,primary_tmr_passes,primary_tmr_failures,mixed_checks,mixed_proposed_passes,mixed_tmr_failures,same_bit_scenarios,same_bit_primary_checks,same_bit_primary_tmr_failures,bist_cycles,triple_fault_boundary_passed,clear_map_recovery_passed,status");
        $fdisplay(summary_file,"%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,%0d,5,1,1,PASS",
            WIDTH,CELLS,scenario_count,single_count,double_count,detected_count,localized_count,
            primary_checks,primary_passes,primary_tmr_passes,primary_tmr_failures,
            mixed_checks,mixed_passes,mixed_tmr_failures,same_bit_scenarios,same_bit_primary_checks,
            same_bit_primary_tmr_failures);
        $fclose(summary_file);
        pass_file=$fopen({output_prefix,"_PASS.txt"},"w");
        if (pass_file==0) fail("Cannot open final pass marker");
        $fdisplay(pass_file,"ALL %0d END-TO-END BIST SCENARIOS PASSED: WIDTH=%0d; PRIMARY_CHECKS=%0d; MIXED_CHECKS=%0d",scenario_count,WIDTH,primary_checks,mixed_checks);
        $fclose(pass_file);
        $display("ALL %0d END-TO-END BIST SCENARIOS PASSED",scenario_count);
        $display("Primary proposed checks: %0d/%0d; standard TMR failures: %0d",primary_passes,primary_checks,primary_tmr_failures);
        $display("Additional alternating-pattern checks: %0d/%0d",mixed_passes,mixed_checks);
        $display("Triple-fault rejection and fault-map clearing checks passed.");
        $finish;
    end
    initial begin
        #10000000;
        $fatal(1,"Global end-to-end campaign timeout");
    end
endmodule

module tb_q2_bist_e2e_w16;
    q2_bist_e2e_campaign #(.WIDTH(16)) campaign();
endmodule
module tb_q2_bist_e2e_w32;
    q2_bist_e2e_campaign #(.WIDTH(32)) campaign();
endmodule
