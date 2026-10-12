`timescale 1ns/1ps

module memristor_bist_8bit (
    input  logic        clk,
    input  logic        reset,
    input  logic        start,
    input  logic        fault_enable,
    input  logic [2:0]  fault_bit_address,
    input  logic [1:0]  fault_replica,
    input  logic [1:0]  fault_mode,
    input  logic        multi_fault_enable,
    input  logic [23:0] inject_lrs_fault_map,
    input  logic [23:0] inject_hrs_fault_map,
    input  logic        operational_write_enable,
    input  logic [7:0]  operational_write_data,
    output logic        busy,
    output logic        done,
    output logic        fault_found,
    output logic        diagnosis_valid,
    output logic        uncorrectable_fault,
    output logic [23:0] lrs_fault_map,
    output logic [23:0] hrs_fault_map,
    output logic [23:0] replica_health_map,
    output logic [7:0]  corrected_data,
    output logic [7:0]  standard_tmr_data,
    output logic [7:0]  uncorrectable_map,
    output logic [13:0] detected_resistance_ohms
);

    localparam logic [2:0] IDLE        = 3'd0;
    localparam logic [2:0] WRITE_ZERO  = 3'd1;
    localparam logic [2:0] CHECK_ZERO  = 3'd2;
    localparam logic [2:0] WRITE_ONE   = 3'd3;
    localparam logic [2:0] CHECK_ONE   = 3'd4;
    localparam logic [2:0] REPORT      = 3'd5;
    localparam logic [13:0] R_THRESHOLD = 14'd5050;

    logic [2:0] state;
    logic       memory_write_enable;
    logic [7:0] memory_write_data;
    logic [7:0] replica_a;
    logic [7:0] replica_b;
    logic [7:0] replica_c;
    logic [7:0] tmr_fault_detected;
    logic [7:0] correctable_map;
    logic [111:0] resistance_a;
    logic [111:0] resistance_b;
    logic [111:0] resistance_c;
    logic [23:0]  replicas_in_lrs;
    logic [23:0]  replicas_in_hrs;
    logic [13:0]  selected_resistance;

    assign replica_health_map = ~(lrs_fault_map | hrs_fault_map);
    assign uncorrectable_fault = diagnosis_valid &&
                                 (|uncorrectable_map);

    function automatic logic [13:0] resistance_at_bit(
        input logic [111:0] resistance_bus,
        input logic [2:0]   bit_address
    );
        begin
            case (bit_address)
                3'd0: resistance_at_bit = resistance_bus[13:0];
                3'd1: resistance_at_bit = resistance_bus[27:14];
                3'd2: resistance_at_bit = resistance_bus[41:28];
                3'd3: resistance_at_bit = resistance_bus[55:42];
                3'd4: resistance_at_bit = resistance_bus[69:56];
                3'd5: resistance_at_bit = resistance_bus[83:70];
                3'd6: resistance_at_bit = resistance_bus[97:84];
                default: resistance_at_bit = resistance_bus[111:98];
            endcase
        end
    endfunction

    // Convert each modelled replica resistance into its physical memory state.
    // These vectors, rather than the binary read outputs, drive BIST detection.
    generate
        for (genvar resistance_index = 0;
             resistance_index < 8;
             resistance_index++) begin : gen_resistance_classifier
            assign replicas_in_lrs[resistance_index] =
                resistance_a[(resistance_index * 14) +: 14] < R_THRESHOLD;
            assign replicas_in_lrs[8 + resistance_index] =
                resistance_b[(resistance_index * 14) +: 14] < R_THRESHOLD;
            assign replicas_in_lrs[16 + resistance_index] =
                resistance_c[(resistance_index * 14) +: 14] < R_THRESHOLD;

            assign replicas_in_hrs[resistance_index] =
                resistance_a[(resistance_index * 14) +: 14] >= R_THRESHOLD;
            assign replicas_in_hrs[8 + resistance_index] =
                resistance_b[(resistance_index * 14) +: 14] >= R_THRESHOLD;
            assign replicas_in_hrs[16 + resistance_index] =
                resistance_c[(resistance_index * 14) +: 14] >= R_THRESHOLD;
        end
    endgenerate

    // Multiplexer used to capture the resistance of the configured test cell.
    always_comb begin
        case (fault_replica)
            2'd0: selected_resistance =
                resistance_at_bit(resistance_a, fault_bit_address);
            2'd1: selected_resistance =
                resistance_at_bit(resistance_b, fault_bit_address);
            2'd2: selected_resistance =
                resistance_at_bit(resistance_c, fault_bit_address);
            default: selected_resistance = 14'd0;
        endcase
    end

    tmr_memristor_memory_8bit memory (
        .clk               (clk),
        .reset             (reset),
        .write_enable      (memory_write_enable),
        .write_data        (memory_write_data),
        .fault_enable      (fault_enable),
        .fault_bit_address (fault_bit_address),
        .fault_replica     (fault_replica),
        .fault_mode        (fault_mode),
        .multi_fault_enable(multi_fault_enable),
        .inject_lrs_fault_map(inject_lrs_fault_map),
        .inject_hrs_fault_map(inject_hrs_fault_map),
        .diagnosis_valid   (diagnosis_valid),
        .replica_health_map(replica_health_map),
        .read_data         (corrected_data),
        .standard_read_data(standard_tmr_data),
        .fault_detected    (tmr_fault_detected),
        .correctable_map   (correctable_map),
        .uncorrectable_map (uncorrectable_map),
        .replica_a         (replica_a),
        .replica_b         (replica_b),
        .replica_c         (replica_c),
        .resistance_a      (resistance_a),
        .resistance_b      (resistance_b),
        .resistance_c      (resistance_c)
    );

    always_comb begin
        memory_write_enable = 1'b0;
        memory_write_data   = operational_write_data;
        busy                = 1'b0;
        done                = 1'b0;

        case (state)
            IDLE: begin
                // Outside BIST, these ports permit post-diagnosis functional
                // writes.  The ZedBoard top ties them low, preserving the
                // existing controls.
                memory_write_enable = operational_write_enable;
            end

            WRITE_ZERO: begin
                busy                = 1'b1;
                memory_write_enable = 1'b1;
                memory_write_data   = 8'h00;
            end

            CHECK_ZERO: busy = 1'b1;

            WRITE_ONE: begin
                busy                = 1'b1;
                memory_write_enable = 1'b1;
                memory_write_data   = 8'hFF;
            end

            CHECK_ONE: busy = 1'b1;

            REPORT: done = 1'b1;

            default: begin
                busy = 1'b0;
                done = 1'b0;
            end
        endcase
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            state         <= IDLE;
            lrs_fault_map <= 24'h000000;
            hrs_fault_map <= 24'h000000;
            fault_found   <= 1'b0;
            diagnosis_valid <= 1'b0;
            detected_resistance_ohms <= 14'd0;
        end else begin
            case (state)
                IDLE: begin
                    if (start) begin
                        lrs_fault_map <= 24'h000000;
                        hrs_fault_map <= 24'h000000;
                        fault_found   <= 1'b0;
                        diagnosis_valid <= 1'b0;
                        detected_resistance_ohms <= 14'd0;
                        state         <= WRITE_ZERO;
                    end
                end

                WRITE_ZERO: state <= CHECK_ZERO;

                CHECK_ZERO: begin
                    // Low resistance after writing HRS/0 means stuck-at-LRS.
                    lrs_fault_map <= replicas_in_lrs;
                    if (|replicas_in_lrs)
                        detected_resistance_ohms <= selected_resistance;
                    state         <= WRITE_ONE;
                end

                WRITE_ONE: state <= CHECK_ONE;

                CHECK_ONE: begin
                    // High resistance after writing LRS/1 means stuck-at-HRS.
                    hrs_fault_map <= replicas_in_hrs;
                    fault_found   <= (|lrs_fault_map) | (|replicas_in_hrs);
                    diagnosis_valid <= 1'b1;
                    if (|replicas_in_hrs)
                        detected_resistance_ohms <= selected_resistance;
                    state         <= REPORT;
                end

                REPORT: begin
                    if (!start)
                        state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
