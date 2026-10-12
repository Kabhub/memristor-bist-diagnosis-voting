`timescale 1ns/1ps

module tb_review_baselines;
    localparam integer WIDTH = 8;
    localparam integer CODE_WIDTH = 13;
    logic clk = 1'b0;
    logic reset;
    logic clear_purge;
    logic write_enable;
    logic [WIDTH-1:0] write_data;
    logic [(3*WIDTH)-1:0] tmr_lrs;
    logic [(3*WIDTH)-1:0] tmr_hrs;
    logic [WIDTH-1:0] purge_data;
    logic [2:0] active_mask;
    logic disagreement;
    logic purge_event;
    logic purge_uncorrectable;
    logic [CODE_WIDTH-1:0] ecc_lrs;
    logic [CODE_WIDTH-1:0] ecc_hrs;
    logic [WIDTH-1:0] ecc_data;
    logic ecc_error;
    logic ecc_single;
    logic ecc_double;
    logic ecc_accepted;
    logic [CODE_WIDTH-1:0] ecc_code;
    integer first_one;
    integer second_one;

    always #5 clk = ~clk;

    review_tmr_baseline #(.WIDTH(WIDTH), .SELF_PURGING(1)) purge_dut (
        .clk(clk), .reset(reset), .clear_purge(clear_purge), .observe(1'b1),
        .write_enable(write_enable), .write_data(write_data),
        .inject_lrs_fault_map(tmr_lrs), .inject_hrs_fault_map(tmr_hrs),
        .corrected_data(purge_data), .active_replica_mask(active_mask),
        .disagreement_detected(disagreement), .purge_event(purge_event),
        .uncorrectable(purge_uncorrectable)
    );

    review_secded_memory #(.WIDTH(WIDTH)) ecc_dut (
        .clk(clk), .reset(reset), .write_enable(write_enable),
        .write_data(write_data), .inject_lrs_fault_map(ecc_lrs),
        .inject_hrs_fault_map(ecc_hrs), .corrected_data(ecc_data),
        .error_detected(ecc_error), .single_error_corrected(ecc_single),
        .double_error_detected(ecc_double), .accepted(ecc_accepted),
        .observed_codeword(ecc_code)
    );

    task automatic pulse_clear;
        begin
            clear_purge = 1'b1;
            @(posedge clk);
            clear_purge = 1'b0;
            @(posedge clk);
        end
    endtask

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

    initial begin
        reset = 1'b1;
        clear_purge = 1'b0;
        write_enable = 1'b0;
        write_data = '0;
        tmr_lrs = '0;
        tmr_hrs = '0;
        ecc_lrs = '0;
        ecc_hrs = '0;
        repeat (2) @(posedge clk);
        reset = 1'b0;
        @(posedge clk);

        write_word(8'hA5);
        if ((purge_data !== 8'hA5) || (ecc_data !== 8'hA5))
            $fatal(1, "fault-free baseline failed");

        // A+B agree incorrectly at bit 2. Module-level self-purging removes C,
        // the healthy minority, and therefore retains the wrong word.
        pulse_clear();
        tmr_hrs[2] = 1'b1;
        tmr_hrs[WIDTH+2] = 1'b1;
        write_word(8'hFF);
        repeat (2) @(posedge clk);
        #1;
        if ((active_mask !== 3'b011) || (purge_data !== 8'hFB))
            $fatal(1, "self-purging agreeing-double-fault behavior mismatch");

        // Find two currently-one ECC bits and force them to HRS. One must be
        // corrected; two must be detected and rejected.
        tmr_hrs = '0;
        ecc_lrs = '0;
        ecc_hrs = '0;
        write_word(8'hFF);
        first_one = -1;
        second_one = -1;
        for (integer index = 0; index < CODE_WIDTH; index = index + 1) begin
            if (ecc_code[index] && (first_one < 0))
                first_one = index;
            else if (ecc_code[index] && (second_one < 0))
                second_one = index;
        end
        if ((first_one < 0) || (second_one < 0))
            $fatal(1, "could not find ECC test bits");
        ecc_hrs[first_one] = 1'b1;
        #1;
        if (!ecc_single || ecc_double || !ecc_accepted || (ecc_data !== 8'hFF))
            $fatal(1, "SECDED single-bit correction failed");
        ecc_hrs[second_one] = 1'b1;
        #1;
        if (!ecc_double || ecc_accepted)
            $fatal(1, "SECDED double-bit detection failed");

        $display("ALL REVIEW BASELINE TESTS PASSED");
        $finish;
    end
endmodule
