`timescale 1ns/1ps

// Conventional word/module-level TMR baseline.  SELF_PURGING=1 implements a
// sticky minority-module exclusion decision without using the proposed BIST
// health map.  It is intentionally module-level: one disagreement can remove
// an entire WIDTH-bit replica, and two agreeing faulty modules can identify the
// healthy module as the minority.  This is the limitation compared by the
// paper; it is not presented as a new self-purging algorithm.
module review_tmr_baseline #(
    parameter integer WIDTH = 8,
    parameter integer SELF_PURGING = 0,
    parameter logic [13:0] R_ON_OHMS = 14'd100,
    parameter logic [13:0] R_OFF_OHMS = 14'd10000,
    parameter logic [13:0] R_THRESHOLD_OHMS = 14'd5050
) (
    input  logic                   clk,
    input  logic                   reset,
    input  logic                   clear_purge,
    input  logic                   observe,
    input  logic                   write_enable,
    input  logic [WIDTH-1:0]       write_data,
    input  logic [(3*WIDTH)-1:0]   inject_lrs_fault_map,
    input  logic [(3*WIDTH)-1:0]   inject_hrs_fault_map,
    output logic [WIDTH-1:0]       corrected_data,
    output logic [2:0]             active_replica_mask,
    output logic                   disagreement_detected,
    output logic                   purge_event,
    output logic                   uncorrectable
);

    logic [WIDTH-1:0] replica_a;
    logic [WIDTH-1:0] replica_b;
    logic [WIDTH-1:0] replica_c;
    logic             ambiguous_latched;

    generate
        for (genvar bit_index = 0; bit_index < WIDTH; bit_index++) begin : gen_cells
            logic [1:0] mode_a;
            logic [1:0] mode_b;
            logic [1:0] mode_c;

            always_comb begin
                mode_a = 2'b00;
                mode_b = 2'b00;
                mode_c = 2'b00;
                if (inject_lrs_fault_map[bit_index])
                    mode_a = 2'b01;
                else if (inject_hrs_fault_map[bit_index])
                    mode_a = 2'b10;
                if (inject_lrs_fault_map[WIDTH + bit_index])
                    mode_b = 2'b01;
                else if (inject_hrs_fault_map[WIDTH + bit_index])
                    mode_b = 2'b10;
                if (inject_lrs_fault_map[(2*WIDTH) + bit_index])
                    mode_c = 2'b01;
                else if (inject_hrs_fault_map[(2*WIDTH) + bit_index])
                    mode_c = 2'b10;
            end

            publication_memristor_cell #(
                .R_ON_OHMS(R_ON_OHMS), .R_OFF_OHMS(R_OFF_OHMS),
                .R_THRESHOLD_OHMS(R_THRESHOLD_OHMS)
            ) cell_a (
                .clk(clk), .reset(reset), .write_enable(write_enable),
                .write_data(write_data[bit_index]), .fault_mode(mode_a),
                .read_data(replica_a[bit_index]), .resistance_ohms()
            );
            publication_memristor_cell #(
                .R_ON_OHMS(R_ON_OHMS), .R_OFF_OHMS(R_OFF_OHMS),
                .R_THRESHOLD_OHMS(R_THRESHOLD_OHMS)
            ) cell_b (
                .clk(clk), .reset(reset), .write_enable(write_enable),
                .write_data(write_data[bit_index]), .fault_mode(mode_b),
                .read_data(replica_b[bit_index]), .resistance_ohms()
            );
            publication_memristor_cell #(
                .R_ON_OHMS(R_ON_OHMS), .R_OFF_OHMS(R_OFF_OHMS),
                .R_THRESHOLD_OHMS(R_THRESHOLD_OHMS)
            ) cell_c (
                .clk(clk), .reset(reset), .write_enable(write_enable),
                .write_data(write_data[bit_index]), .fault_mode(mode_c),
                .read_data(replica_c[bit_index]), .resistance_ohms()
            );
        end
    endgenerate

    always_ff @(posedge clk) begin
        if (reset || clear_purge) begin
            active_replica_mask <= 3'b111;
            ambiguous_latched  <= 1'b0;
            purge_event        <= 1'b0;
        end else begin
            purge_event <= 1'b0;
            if ((SELF_PURGING != 0) && observe) begin
                case (active_replica_mask)
                    3'b111: begin
                        if ((replica_b == replica_c) && (replica_a != replica_b)) begin
                            active_replica_mask <= 3'b110;
                            purge_event <= 1'b1;
                        end else if ((replica_a == replica_c) && (replica_b != replica_a)) begin
                            active_replica_mask <= 3'b101;
                            purge_event <= 1'b1;
                        end else if ((replica_a == replica_b) && (replica_c != replica_a)) begin
                            active_replica_mask <= 3'b011;
                            purge_event <= 1'b1;
                        end else if ((replica_a != replica_b) &&
                                     (replica_a != replica_c) &&
                                     (replica_b != replica_c)) begin
                            ambiguous_latched <= 1'b1;
                        end
                    end
                    3'b110: if (replica_b != replica_c) ambiguous_latched <= 1'b1;
                    3'b101: if (replica_a != replica_c) ambiguous_latched <= 1'b1;
                    3'b011: if (replica_a != replica_b) ambiguous_latched <= 1'b1;
                    default: ambiguous_latched <= 1'b1;
                endcase
            end
        end
    end

    always_comb begin
        disagreement_detected = (replica_a != replica_b) ||
                                (replica_a != replica_c) ||
                                (replica_b != replica_c);
        uncorrectable = 1'b0;
        if (SELF_PURGING == 0) begin
            corrected_data = (replica_a & replica_b) |
                             (replica_a & replica_c) |
                             (replica_b & replica_c);
        end else begin
            case (active_replica_mask)
                3'b111: corrected_data = (replica_a & replica_b) |
                                          (replica_a & replica_c) |
                                          (replica_b & replica_c);
                3'b110: begin
                    corrected_data = replica_b;
                    uncorrectable = replica_b != replica_c;
                end
                3'b101: begin
                    corrected_data = replica_a;
                    uncorrectable = replica_a != replica_c;
                end
                3'b011: begin
                    corrected_data = replica_a;
                    uncorrectable = replica_a != replica_b;
                end
                3'b100: corrected_data = replica_c;
                3'b010: corrected_data = replica_b;
                3'b001: corrected_data = replica_a;
                default: begin
                    corrected_data = (replica_a & replica_b) |
                                     (replica_a & replica_c) |
                                     (replica_b & replica_c);
                    uncorrectable = 1'b1;
                end
            endcase
            uncorrectable = uncorrectable | ambiguous_latched;
        end
    end

endmodule
