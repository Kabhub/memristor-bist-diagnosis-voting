`timescale 1ns/1ps

module tb_tmr_memristor_memory_8bit;

    logic       clk = 1'b0;
    logic       reset;
    logic       write_enable;
    logic [7:0] write_data;
    logic       fault_enable;
    logic [2:0] fault_bit_address;
    logic [1:0] fault_replica;
    logic [1:0] fault_mode;
    logic       multi_fault_enable;
    logic [23:0] inject_lrs_fault_map;
    logic [23:0] inject_hrs_fault_map;
    logic       diagnosis_valid;
    logic [23:0] replica_health_map;
    logic [7:0] read_data;
    logic [7:0] standard_read_data;
    logic [7:0] fault_detected;
    logic [7:0] correctable_map;
    logic [7:0] uncorrectable_map;
    logic [7:0] replica_a;
    logic [7:0] replica_b;
    logic [7:0] replica_c;
    logic [111:0] resistance_a;
    logic [111:0] resistance_b;
    logic [111:0] resistance_c;

    localparam logic [1:0] NORMAL       = 2'b00;
    localparam logic [1:0] STUCK_AT_LRS = 2'b01;
    localparam logic [1:0] STUCK_AT_HRS = 2'b10;

    tmr_memristor_memory_8bit dut (
        .clk(clk),
        .reset(reset),
        .write_enable(write_enable),
        .write_data(write_data),
        .fault_enable(fault_enable),
        .fault_bit_address(fault_bit_address),
        .fault_replica(fault_replica),
        .fault_mode(fault_mode),
        .multi_fault_enable(multi_fault_enable),
        .inject_lrs_fault_map(inject_lrs_fault_map),
        .inject_hrs_fault_map(inject_hrs_fault_map),
        .diagnosis_valid(diagnosis_valid),
        .replica_health_map(replica_health_map),
        .read_data(read_data),
        .standard_read_data(standard_read_data),
        .fault_detected(fault_detected),
        .correctable_map(correctable_map),
        .uncorrectable_map(uncorrectable_map),
        .replica_a(replica_a),
        .replica_b(replica_b),
        .replica_c(replica_c),
        .resistance_a(resistance_a),
        .resistance_b(resistance_b),
        .resistance_c(resistance_c)
    );

    always #5 clk = ~clk;

    task automatic write_word(input logic [7:0] value);
        begin
            write_data   = value;
            write_enable = 1'b1;
            @(posedge clk);
            #1 write_enable = 1'b0;
        end
    endtask

    task automatic check_memory(
        input logic [7:0] expected_data,
        input logic [7:0] expected_faults,
        input string test_name
    );
        begin
            #1;
            if ((read_data !== expected_data) ||
                (fault_detected !== expected_faults)) begin
                $error("FAIL: %s | data=%h faults=%b", test_name,
                       read_data, fault_detected);
                $fatal(1);
            end
            $display("PASS: %s | data=%h faults=%b", test_name,
                     read_data, fault_detected);
        end
    endtask

    initial begin
        reset             = 1'b1;
        write_enable      = 1'b0;
        write_data        = 8'h00;
        fault_enable      = 1'b0;
        fault_bit_address = 3'd0;
        fault_replica     = 2'd0;
        fault_mode        = NORMAL;
        multi_fault_enable = 1'b0;
        inject_lrs_fault_map = 24'h000000;
        inject_hrs_fault_map = 24'h000000;
        diagnosis_valid = 1'b0;
        replica_health_map = 24'hFFFFFF;

        repeat (2) @(posedge clk);
        #1 reset = 1'b0;

        write_word(8'hA5);
        check_memory(8'hA5, 8'h00, "Normal 8-bit write");

        fault_enable      = 1'b1;
        fault_bit_address = 3'd0;
        fault_replica     = 2'd0;
        fault_mode        = STUCK_AT_HRS;
        write_word(8'hFF);
        check_memory(8'hFF, 8'b0000_0001,
                     "HRS fault at bit 0 replica A is tolerated");
        if ((resistance_a[0 +: 14] !== 14'd10000) ||
            (resistance_b[0 +: 14] !== 14'd100) ||
            (resistance_c[0 +: 14] !== 14'd100)) begin
            $error("FAIL: HRS replica resistance values are incorrect");
            $fatal(1);
        end

        fault_bit_address = 3'd7;
        fault_replica     = 2'd2;
        fault_mode        = STUCK_AT_LRS;
        write_word(8'h00);
        check_memory(8'h00, 8'b1000_0000,
                     "LRS fault at bit 7 replica C is tolerated");
        if ((resistance_a[(7 * 14) +: 14] !== 14'd10000) ||
            (resistance_b[(7 * 14) +: 14] !== 14'd10000) ||
            (resistance_c[(7 * 14) +: 14] !== 14'd100)) begin
            $error("FAIL: LRS replica resistance values are incorrect");
            $fatal(1);
        end

        fault_enable = 1'b0;
        fault_mode   = NORMAL;
        write_word(8'h3C);
        check_memory(8'h3C, 8'h00, "Normal operation restored");

        $display("ALL 8-BIT TMR MEMORY TESTS PASSED");
        $finish;
    end

endmodule
