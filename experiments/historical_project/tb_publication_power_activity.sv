`timescale 1ns/1ps

// Deterministic activity workload for the publication power comparison.
// The Tcl flow elaborates this testbench three times with ARCHITECTURE set to
// 0, 1, and 2.  Every elaboration receives the same 100 MHz clock, reset,
// fault sequence, BIST schedule, data sequence, and write-enable pattern.
module tb_publication_power_activity #(
    parameter integer WIDTH        = 8,
    parameter integer ARCHITECTURE = 2
);

    localparam integer MAP_WIDTH = 3 * WIDTH;
    localparam integer OPERATIONAL_CYCLES_PER_PHASE = 256;

    logic                 clk = 1'b0;
    logic                 reset;
    logic                 start;
    logic                 operational_write_enable;
    logic [WIDTH-1:0]     operational_write_data;
    logic [MAP_WIDTH-1:0] inject_lrs_fault_map;
    logic [MAP_WIDTH-1:0] inject_hrs_fault_map;

    logic                 busy;
    logic                 done;
    logic                 fault_found;
    logic                 diagnosis_valid;
    logic [15:0]          bist_cycle_count;
    logic [WIDTH-1:0]     corrected_data;
    logic [MAP_WIDTH-1:0] lrs_fault_map;
    logic [MAP_WIDTH-1:0] hrs_fault_map;
    logic [MAP_WIDTH-1:0] replica_health_map;
    logic [WIDTH-1:0]     uncorrectable_map;

    always #5 clk = ~clk;

    publication_architecture_wrapper #(
        .WIDTH       (WIDTH),
        .ARCHITECTURE(ARCHITECTURE)
    ) dut (
        .clk                     (clk),
        .reset                   (reset),
        .start                   (start),
        .operational_write_enable(operational_write_enable),
        .operational_write_data  (operational_write_data),
        .inject_lrs_fault_map    (inject_lrs_fault_map),
        .inject_hrs_fault_map    (inject_hrs_fault_map),
        .busy                    (busy),
        .done                    (done),
        .fault_found             (fault_found),
        .diagnosis_valid         (diagnosis_valid),
        .bist_cycle_count        (bist_cycle_count),
        .corrected_data          (corrected_data),
        .lrs_fault_map           (lrs_fault_map),
        .hrs_fault_map           (hrs_fault_map),
        .replica_health_map      (replica_health_map),
        .uncorrectable_map       (uncorrectable_map)
    );

    function automatic logic [MAP_WIDTH-1:0] visible_fault_map(
        input logic [MAP_WIDTH-1:0] full_map
    );
        begin
            if (ARCHITECTURE == 0) begin
                visible_fault_map = '0;
                visible_fault_map[WIDTH-1:0] = full_map[WIDTH-1:0];
            end else begin
                visible_fault_map = full_map;
            end
        end
    endfunction

    task automatic run_bist_phase(
        input logic [MAP_WIDTH-1:0] lrs_mask,
        input logic [MAP_WIDTH-1:0] hrs_mask
    );
        logic [MAP_WIDTH-1:0] expected_lrs;
        logic [MAP_WIDTH-1:0] expected_hrs;
        begin
            expected_lrs = visible_fault_map(lrs_mask);
            expected_hrs = visible_fault_map(hrs_mask);

            @(negedge clk);
            inject_lrs_fault_map = lrs_mask;
            inject_hrs_fault_map = hrs_mask;
            operational_write_enable = 1'b0;
            start = 1'b1;

            @(negedge clk);
            start = 1'b0;

            wait (done === 1'b1);
            #1;

            if (bist_cycle_count !== 16'd5)
                $fatal(1, "BIST cycle mismatch: expected 5, observed %0d",
                       bist_cycle_count);

            if ((lrs_fault_map !== expected_lrs) ||
                (hrs_fault_map !== expected_hrs))
                $fatal(1, "BIST diagnosis map mismatch");

            if (fault_found !== (|(expected_lrs | expected_hrs)))
                $fatal(1, "BIST fault_found mismatch");

            if (diagnosis_valid !== 1'b1)
                $fatal(1, "BIST diagnosis_valid was not asserted");

            // REPORT lasts for one cycle.  Wait until the controller has
            // returned to IDLE before beginning operational traffic.
            @(posedge clk);
        end
    endtask

    task automatic run_operational_phase(input logic [7:0] seed);
        logic [7:0] lfsr;
        integer cycle_index;
        begin
            lfsr = seed;

            for (cycle_index = 0;
                 cycle_index < OPERATIONAL_CYCLES_PER_PHASE;
                 cycle_index = cycle_index + 1) begin
                @(negedge clk);

                // x^8 + x^6 + x^5 + x^4 + 1.  Three fixed nonzero seeds are
                // used by the three workload phases.  Data changes on every
                // cycle; writes are enabled on three of every four cycles.
                lfsr = {lfsr[6:0],
                        lfsr[7] ^ lfsr[5] ^ lfsr[4] ^ lfsr[3]};
                operational_write_data = lfsr;
                operational_write_enable = ((cycle_index % 4) != 3);

                @(posedge clk);
                #1;
                if (^corrected_data === 1'bx)
                    $fatal(1, "Unknown corrected output during activity run");

                operational_write_enable = 1'b0;
            end
        end
    endtask

    initial begin
        logic [MAP_WIDTH-1:0] single_hrs_a;
        logic [MAP_WIDTH-1:0] double_hrs_ab;

        if (WIDTH != 8)
            $fatal(1, "The publication power workload is defined for WIDTH=8");

        single_hrs_a = '0;
        double_hrs_ab = '0;
        single_hrs_a[2] = 1'b1;
        double_hrs_ab[2] = 1'b1;
        double_hrs_ab[WIDTH + 2] = 1'b1;

        reset = 1'b1;
        start = 1'b0;
        operational_write_enable = 1'b0;
        operational_write_data = '0;
        inject_lrs_fault_map = '0;
        inject_hrs_fault_map = '0;

        repeat (4) @(posedge clk);
        @(negedge clk);
        reset = 1'b0;

        // Phase 1: fault-free diagnosis and operation.
        run_bist_phase('0, '0);
        run_operational_phase(8'hA5);

        // Phase 2: one HRS fault in replica A, logical bit 2.
        run_bist_phase('0, single_hrs_a);
        run_operational_phase(8'h3C);

        // Phase 3: same-bit HRS faults in replicas A and B.  This is the
        // critical case in which conventional majority voting and the
        // diagnosis-guided voter differ.
        run_bist_phase('0, double_hrs_ab);
        run_operational_phase(8'hD7);

        @(negedge clk);
        operational_write_enable = 1'b0;
        operational_write_data = '0;
        repeat (8) @(posedge clk);

        $display("ACTIVITY WORKLOAD PASSED: architecture=%0d, operational_cycles=768, writes=576, bist_runs=3",
                 ARCHITECTURE);
        $finish;
    end

    initial begin
        #100_000;
        $fatal(1, "TIMEOUT: publication power activity workload");
    end

endmodule

// Explicit simulation tops avoid relying on cached or tool-specific generic
// overrides when the automated flow creates the three SAIF files.
module tb_publication_power_activity_unprotected;
    tb_publication_power_activity #(
        .WIDTH(8), .ARCHITECTURE(0)
    ) activity ();
endmodule

module tb_publication_power_activity_standard_tmr;
    tb_publication_power_activity #(
        .WIDTH(8), .ARCHITECTURE(1)
    ) activity ();
endmodule

module tb_publication_power_activity_proposed;
    tb_publication_power_activity #(
        .WIDTH(8), .ARCHITECTURE(2)
    ) activity ();
endmodule
