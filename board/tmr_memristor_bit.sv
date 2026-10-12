`timescale 1ns/1ps

module tmr_memristor_bit (
    input  logic       clk,
    input  logic       reset,
    input  logic       write_enable,
    input  logic       write_data,
    input  logic [1:0] fault_mode_a,
    input  logic [1:0] fault_mode_b,
    input  logic [1:0] fault_mode_c,
    input  logic       diagnosis_valid,
    input  logic       healthy_a,
    input  logic       healthy_b,
    input  logic       healthy_c,
    output logic       read_data,
    output logic       standard_read_data,
    output logic       replica_a,
    output logic       replica_b,
    output logic       replica_c,
    output logic       fault_detected,
    output logic       correctable,
    output logic       uncorrectable,
    output logic [13:0] resistance_a,
    output logic [13:0] resistance_b,
    output logic [13:0] resistance_c
);

    memristor_cell cell_a (
        .clk(clk), .reset(reset), .write_enable(write_enable),
        .write_data(write_data), .fault_mode(fault_mode_a),
        .read_data(replica_a), .resistance_ohms(resistance_a)
    );

    memristor_cell cell_b (
        .clk(clk), .reset(reset), .write_enable(write_enable),
        .write_data(write_data), .fault_mode(fault_mode_b),
        .read_data(replica_b), .resistance_ohms(resistance_b)
    );

    memristor_cell cell_c (
        .clk(clk), .reset(reset), .write_enable(write_enable),
        .write_data(write_data), .fault_mode(fault_mode_c),
        .read_data(replica_c), .resistance_ohms(resistance_c)
    );

    // The standard voter is retained as an experimental baseline.  The
    // diagnosis-guided voter uses the BIST health map after diagnosis.  It can
    // select the remaining healthy replica even when two known-stuck replicas
    // belong to the same logical bit.
    always_comb begin
        standard_read_data = (replica_a & replica_b) |
                             (replica_a & replica_c) |
                             (replica_b & replica_c);

        read_data     = standard_read_data;
        correctable   = 1'b1;
        uncorrectable = 1'b0;

        if (diagnosis_valid) begin
            case ({healthy_a, healthy_b, healthy_c})
                3'b111: read_data = standard_read_data;

                // Exactly two replicas are diagnosed healthy.  A disagreement
                // indicates a fault outside the stored diagnosis and is
                // therefore reported as uncorrectable.
                3'b110: begin
                    read_data = replica_a;
                    if (replica_a != replica_b) begin
                        correctable   = 1'b0;
                        uncorrectable = 1'b1;
                    end
                end
                3'b101: begin
                    read_data = replica_a;
                    if (replica_a != replica_c) begin
                        correctable   = 1'b0;
                        uncorrectable = 1'b1;
                    end
                end
                3'b011: begin
                    read_data = replica_b;
                    if (replica_b != replica_c) begin
                        correctable   = 1'b0;
                        uncorrectable = 1'b1;
                    end
                end

                // With one diagnosed-healthy replica, bypass the two known
                // faulty replicas instead of allowing them to outvote it.
                3'b100: read_data = replica_a;
                3'b010: read_data = replica_b;
                3'b001: read_data = replica_c;

                // No trusted replica remains.  Preserve the baseline value for
                // observability but flag it as unusable.
                default: begin
                    read_data     = standard_read_data;
                    correctable   = 1'b0;
                    uncorrectable = 1'b1;
                end
            endcase
        end

        fault_detected = (replica_a != replica_b) |
                         (replica_a != replica_c) |
                         (replica_b != replica_c) |
                         (diagnosis_valid &&
                          !(healthy_a && healthy_b && healthy_c));
    end

endmodule
