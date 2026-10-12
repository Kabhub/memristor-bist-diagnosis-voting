`timescale 1ns/1ps

module tb_tmr_memristor_bit;

    logic       clk = 1'b0;
    logic       reset;
    logic       write_enable;
    logic       write_data;
    logic [1:0] fault_mode_a;
    logic [1:0] fault_mode_b;
    logic [1:0] fault_mode_c;
    logic       diagnosis_valid;
    logic       healthy_a;
    logic       healthy_b;
    logic       healthy_c;
    logic       read_data;
    logic       standard_read_data;
    logic       replica_a;
    logic       replica_b;
    logic       replica_c;
    logic       fault_detected;
    logic       correctable;
    logic       uncorrectable;
    logic [13:0] resistance_a;
    logic [13:0] resistance_b;
    logic [13:0] resistance_c;

    localparam logic [1:0] NORMAL       = 2'b00;
    localparam logic [1:0] STUCK_AT_LRS = 2'b01;
    localparam logic [1:0] STUCK_AT_HRS = 2'b10;

    tmr_memristor_bit dut (
        .clk(clk),
        .reset(reset),
        .write_enable(write_enable),
        .write_data(write_data),
        .fault_mode_a(fault_mode_a),
        .fault_mode_b(fault_mode_b),
        .fault_mode_c(fault_mode_c),
        .diagnosis_valid(diagnosis_valid),
        .healthy_a(healthy_a),
        .healthy_b(healthy_b),
        .healthy_c(healthy_c),
        .read_data(read_data),
        .standard_read_data(standard_read_data),
        .replica_a(replica_a),
        .replica_b(replica_b),
        .replica_c(replica_c),
        .fault_detected(fault_detected),
        .correctable(correctable),
        .uncorrectable(uncorrectable),
        .resistance_a(resistance_a),
        .resistance_b(resistance_b),
        .resistance_c(resistance_c)
    );

    always #5 clk = ~clk;

    task automatic write_bit(input logic value);
        begin
            write_data   = value;
            write_enable = 1'b1;
            @(posedge clk);
            #1 write_enable = 1'b0;
        end
    endtask

    task automatic check_tmr(
        input logic expected_data,
        input logic expected_fault,
        input logic [13:0] expected_resistance_a,
        input logic [13:0] expected_resistance_b,
        input logic [13:0] expected_resistance_c,
        input string test_name
    );
        begin
            #1;
            if ((read_data !== expected_data) ||
                (fault_detected !== expected_fault) ||
                (resistance_a !== expected_resistance_a) ||
                (resistance_b !== expected_resistance_b) ||
                (resistance_c !== expected_resistance_c)) begin
                $error("FAIL: %s | replicas=%b%b%b voted=%b fault=%b R=%0d/%0d/%0d",
                       test_name, replica_a, replica_b, replica_c,
                       read_data, fault_detected,
                       resistance_a, resistance_b, resistance_c);
                $fatal(1);
            end
            $display("PASS: %s | replicas=%b%b%b voted=%b fault=%b R=%0d/%0d/%0d",
                     test_name, replica_a, replica_b, replica_c,
                     read_data, fault_detected,
                     resistance_a, resistance_b, resistance_c);
        end
    endtask

    initial begin
        reset        = 1'b1;
        write_enable = 1'b0;
        write_data   = 1'b0;
        fault_mode_a = NORMAL;
        fault_mode_b = NORMAL;
        fault_mode_c = NORMAL;
        diagnosis_valid = 1'b0;
        healthy_a = 1'b1;
        healthy_b = 1'b1;
        healthy_c = 1'b1;

        repeat (2) @(posedge clk);
        #1 reset = 1'b0;

        write_bit(1'b1);
        check_tmr(1'b1, 1'b0, 14'd100, 14'd100, 14'd100,
                  "Normal write 1");

        fault_mode_a = STUCK_AT_HRS;
        write_bit(1'b1);
        check_tmr(1'b1, 1'b1, 14'd10000, 14'd100, 14'd100,
                  "One HRS fault is tolerated");

        fault_mode_a = NORMAL;
        fault_mode_b = NORMAL;
        fault_mode_c = NORMAL;
        write_bit(1'b0);
        check_tmr(1'b0, 1'b0, 14'd10000, 14'd10000, 14'd10000,
                  "Normal write 0");

        fault_mode_b = STUCK_AT_LRS;
        write_bit(1'b0);
        check_tmr(1'b0, 1'b1, 14'd10000, 14'd100, 14'd10000,
                  "One LRS fault is tolerated");

        // Two HRS faults defeat ordinary TMR for a stored one.  Diagnosis
        // bypasses the known-faulty replicas and selects healthy replica C.
        fault_mode_a = STUCK_AT_HRS;
        fault_mode_b = STUCK_AT_HRS;
        fault_mode_c = NORMAL;
        diagnosis_valid = 1'b1;
        healthy_a = 1'b0;
        healthy_b = 1'b0;
        healthy_c = 1'b1;
        write_bit(1'b1);
        #1;
        if ((standard_read_data !== 1'b0) ||
            (read_data !== 1'b1) || !correctable || uncorrectable) begin
            $error("DIAGNOSIS-GUIDED HRS CORRECTION FAIL");
            $fatal(1);
        end

        // Two LRS faults likewise defeat ordinary TMR for a stored zero.
        fault_mode_a = STUCK_AT_LRS;
        fault_mode_b = STUCK_AT_LRS;
        fault_mode_c = NORMAL;
        write_bit(1'b0);
        #1;
        if ((standard_read_data !== 1'b1) ||
            (read_data !== 1'b0) || !correctable || uncorrectable) begin
            $error("DIAGNOSIS-GUIDED LRS CORRECTION FAIL");
            $fatal(1);
        end

        // The architecture reports an explicit failure when no trusted
        // replica remains.
        healthy_c = 1'b0;
        #1;
        if (!uncorrectable || correctable) begin
            $error("UNCORRECTABLE REPORTING FAIL");
            $fatal(1);
        end

        $display("ALL STANDARD AND DIAGNOSIS-GUIDED TMR TESTS PASSED");
        $finish;
    end

endmodule
