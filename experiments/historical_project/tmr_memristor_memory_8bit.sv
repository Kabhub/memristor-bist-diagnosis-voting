`timescale 1ns/1ps

module tmr_memristor_memory_8bit (
    input  logic       clk,
    input  logic       reset,
    input  logic       write_enable,
    input  logic [7:0] write_data,
    input  logic       fault_enable,
    input  logic [2:0] fault_bit_address,
    input  logic [1:0] fault_replica,
    input  logic [1:0] fault_mode,
    input  logic       multi_fault_enable,
    input  logic [23:0] inject_lrs_fault_map,
    input  logic [23:0] inject_hrs_fault_map,
    input  logic       diagnosis_valid,
    input  logic [23:0] replica_health_map,
    output logic [7:0] read_data,
    output logic [7:0] standard_read_data,
    output logic [7:0] fault_detected,
    output logic [7:0] correctable_map,
    output logic [7:0] uncorrectable_map,
    output logic [7:0] replica_a,
    output logic [7:0] replica_b,
    output logic [7:0] replica_c,
    output logic [111:0] resistance_a,
    output logic [111:0] resistance_b,
    output logic [111:0] resistance_c
);

    localparam logic [1:0] NORMAL = 2'b00;

    generate
        for (genvar bit_index = 0; bit_index < 8; bit_index++) begin : gen_tmr_bits
            localparam logic [2:0] BIT_ADDRESS = bit_index;

            logic [1:0] fault_mode_a;
            logic [1:0] fault_mode_b;
            logic [1:0] fault_mode_c;

            always_comb begin
                fault_mode_a = NORMAL;
                fault_mode_b = NORMAL;
                fault_mode_c = NORMAL;

                if (multi_fault_enable) begin
                    // LRS takes precedence if a malformed test requests both
                    // modes for one physical cell.  The Q2 campaign prevents
                    // overlapping injection masks.
                    if (inject_lrs_fault_map[bit_index])
                        fault_mode_a = 2'b01;
                    else if (inject_hrs_fault_map[bit_index])
                        fault_mode_a = 2'b10;

                    if (inject_lrs_fault_map[8 + bit_index])
                        fault_mode_b = 2'b01;
                    else if (inject_hrs_fault_map[8 + bit_index])
                        fault_mode_b = 2'b10;

                    if (inject_lrs_fault_map[16 + bit_index])
                        fault_mode_c = 2'b01;
                    else if (inject_hrs_fault_map[16 + bit_index])
                        fault_mode_c = 2'b10;
                end else if (fault_enable &&
                             (fault_bit_address == BIT_ADDRESS)) begin
                    case (fault_replica)
                        2'd0: fault_mode_a = fault_mode;
                        2'd1: fault_mode_b = fault_mode;
                        2'd2: fault_mode_c = fault_mode;
                        default: begin
                            fault_mode_a = NORMAL;
                            fault_mode_b = NORMAL;
                            fault_mode_c = NORMAL;
                        end
                    endcase
                end
            end

            tmr_memristor_bit tmr_bit (
                .clk            (clk),
                .reset          (reset),
                .write_enable   (write_enable),
                .write_data     (write_data[bit_index]),
                .fault_mode_a   (fault_mode_a),
                .fault_mode_b   (fault_mode_b),
                .fault_mode_c   (fault_mode_c),
                .diagnosis_valid(diagnosis_valid),
                .healthy_a      (replica_health_map[bit_index]),
                .healthy_b      (replica_health_map[8 + bit_index]),
                .healthy_c      (replica_health_map[16 + bit_index]),
                .read_data      (read_data[bit_index]),
                .standard_read_data(standard_read_data[bit_index]),
                .replica_a      (replica_a[bit_index]),
                .replica_b      (replica_b[bit_index]),
                .replica_c      (replica_c[bit_index]),
                .fault_detected (fault_detected[bit_index]),
                .correctable    (correctable_map[bit_index]),
                .uncorrectable  (uncorrectable_map[bit_index]),
                .resistance_a   (resistance_a[(bit_index * 14) +: 14]),
                .resistance_b   (resistance_b[(bit_index * 14) +: 14]),
                .resistance_c   (resistance_c[(bit_index * 14) +: 14])
            );
        end
    endgenerate

endmodule
