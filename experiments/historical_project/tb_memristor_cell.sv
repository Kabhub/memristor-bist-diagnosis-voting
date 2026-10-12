`timescale 1ns/1ps

module tb_memristor_cell;

    logic        clk = 1'b0;
    logic        reset;
    logic        write_enable;
    logic        write_data;
    logic [1:0]  fault_mode;
    logic        read_data;
    logic [13:0] resistance_ohms;

    localparam logic [1:0] NORMAL        = 2'b00;
    localparam logic [1:0] STUCK_AT_LRS  = 2'b01;
    localparam logic [1:0] STUCK_AT_HRS  = 2'b10;

    memristor_cell dut (
        .clk             (clk),
        .reset           (reset),
        .write_enable    (write_enable),
        .write_data      (write_data),
        .fault_mode      (fault_mode),
        .read_data       (read_data),
        .resistance_ohms (resistance_ohms)
    );

    always #5 clk = ~clk;

    task automatic write_cell(input logic value);
        begin
            write_data   = value;
            write_enable = 1'b1;
            @(posedge clk);
            #1;
            write_enable = 1'b0;
        end
    endtask

    task automatic check_cell(
        input logic expected_data,
        input logic [13:0] expected_resistance,
        input string test_name
    );
        begin
            #1;
            if ((read_data !== expected_data) ||
                (resistance_ohms !== expected_resistance)) begin
                $error("FAIL: %s | data=%b resistance=%0d", test_name,
                       read_data, resistance_ohms);
                $fatal(1);
            end
            $display("PASS: %s", test_name);
        end
    endtask

    initial begin
        reset        = 1'b1;
        write_enable = 1'b0;
        write_data   = 1'b0;
        fault_mode   = NORMAL;

        repeat (2) @(posedge clk);
        #1 reset = 1'b0;
        check_cell(1'b0, 14'd10000, "Reset gives HRS / bit 0");

        write_cell(1'b1);
        check_cell(1'b1, 14'd100, "Normal write of bit 1");

        repeat (3) @(posedge clk);
        check_cell(1'b1, 14'd100,
                   "LRS resistance is retained while write is disabled");

        write_cell(1'b0);
        check_cell(1'b0, 14'd10000, "Normal write of bit 0");

        fault_mode = STUCK_AT_LRS;
        write_cell(1'b0);
        check_cell(1'b1, 14'd100, "Stuck-at-LRS ignores write 0");

        fault_mode = STUCK_AT_HRS;
        write_cell(1'b1);
        check_cell(1'b0, 14'd10000, "Stuck-at-HRS ignores write 1");

        fault_mode = NORMAL;
        write_cell(1'b1);
        check_cell(1'b1, 14'd100, "Normal operation restored");

        $display("ALL MEMRISTOR CELL TESTS PASSED");
        $finish;
    end

endmodule
