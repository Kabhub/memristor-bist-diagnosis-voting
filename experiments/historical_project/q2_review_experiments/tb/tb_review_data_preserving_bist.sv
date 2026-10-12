`timescale 1ns/1ps

module tb_review_data_preserving_bist;
    localparam integer WIDTH = 8;
    logic clk = 1'b0;
    logic reset;
    logic start;
    logic write_enable;
    logic [WIDTH-1:0] write_data;
    logic [(3*WIDTH)-1:0] lrs_inject;
    logic [(3*WIDTH)-1:0] hrs_inject;
    logic busy;
    logic done;
    logic fault_found;
    logic diagnosis_valid;
    logic restore_ok;
    logic [15:0] cycle_count;
    logic [WIDTH-1:0] corrected_data;
    logic [(3*WIDTH)-1:0] lrs_map;
    logic [(3*WIDTH)-1:0] hrs_map;
    logic [(3*WIDTH)-1:0] health_map;
    logic [WIDTH-1:0] uncorrectable_map;

    always #5 clk = ~clk;

    review_data_preserving_bist_core #(.WIDTH(WIDTH)) dut (
        .clk(clk), .reset(reset), .start(start),
        .operational_write_enable(write_enable),
        .operational_write_data(write_data),
        .inject_lrs_fault_map(lrs_inject),
        .inject_hrs_fault_map(hrs_inject),
        .busy(busy), .done(done), .fault_found(fault_found),
        .diagnosis_valid(diagnosis_valid), .restore_ok(restore_ok),
        .bist_cycle_count(cycle_count), .corrected_data(corrected_data),
        .lrs_fault_map(lrs_map), .hrs_fault_map(hrs_map),
        .replica_health_map(health_map),
        .uncorrectable_map(uncorrectable_map)
    );

    task automatic write_word(input logic [WIDTH-1:0] value);
        begin
            write_data = value;
            write_enable = 1'b1;
            @(posedge clk);
            #1;
            write_enable = 1'b0;
            @(posedge clk);
            #1;
        end
    endtask

    task automatic run_bist;
        begin
            start = 1'b1;
            @(posedge clk);
            #1;
            start = 1'b0;
            wait (done === 1'b1);
            #1;
        end
    endtask

    initial begin
        reset = 1'b1;
        start = 1'b0;
        write_enable = 1'b0;
        write_data = '0;
        lrs_inject = '0;
        hrs_inject = '0;
        repeat (2) @(posedge clk);
        reset = 1'b0;
        @(posedge clk);

        write_word(8'hA5);
        run_bist();
        if (!restore_ok || (corrected_data !== 8'hA5) || (cycle_count !== 16'd8))
            $fatal(1, "fault-free save-test-restore failed");
        @(posedge clk);

        write_word(8'hFF);
        hrs_inject[2] = 1'b1;
        hrs_inject[WIDTH+2] = 1'b1;
        run_bist();
        if (!fault_found || !diagnosis_valid || !restore_ok)
            $fatal(1, "double-fault diagnosis/restore status failed");
        if ((corrected_data !== 8'hFF) || (uncorrectable_map !== '0))
            $fatal(1, "double-fault corrected result failed");
        if (!hrs_map[2] || !hrs_map[WIDTH+2])
            $fatal(1, "double HRS localization failed");

        $display("ALL DATA-PRESERVING BIST TESTS PASSED");
        $finish;
    end
endmodule
