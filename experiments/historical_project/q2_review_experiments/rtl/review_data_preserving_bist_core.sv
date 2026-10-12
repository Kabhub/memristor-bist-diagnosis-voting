`timescale 1ns/1ps

// Data-preserving offline BIST variant of the proposed architecture.
//
// Sequence: SAVE -> WRITE_ZERO -> CHECK_ZERO -> WRITE_ONE -> CHECK_ONE ->
// RESTORE -> VERIFY -> REPORT.  One WIDTH-bit buffer is retained for each
// physical replica, so the synthesis result exposes the exact FF and latency
// cost of preserving data. This remains an offline BIST because normal access
// pauses during the eight-cycle test.
module review_data_preserving_bist_core #(
    parameter integer WIDTH = 8,
    parameter logic [13:0] R_ON_OHMS = 14'd100,
    parameter logic [13:0] R_OFF_OHMS = 14'd10000,
    parameter logic [13:0] R_THRESHOLD_OHMS = 14'd5050
) (
    input  logic                   clk,
    input  logic                   reset,
    input  logic                   start,
    input  logic                   operational_write_enable,
    input  logic [WIDTH-1:0]       operational_write_data,
    input  logic [(3*WIDTH)-1:0]   inject_lrs_fault_map,
    input  logic [(3*WIDTH)-1:0]   inject_hrs_fault_map,
    output logic                   busy,
    output logic                   done,
    output logic                   fault_found,
    output logic                   diagnosis_valid,
    output logic                   restore_ok,
    output logic [15:0]            bist_cycle_count,
    output logic [WIDTH-1:0]       corrected_data,
    output logic [(3*WIDTH)-1:0]   lrs_fault_map,
    output logic [(3*WIDTH)-1:0]   hrs_fault_map,
    output logic [(3*WIDTH)-1:0]   replica_health_map,
    output logic [WIDTH-1:0]       uncorrectable_map
);

    localparam integer MAP_WIDTH = 3 * WIDTH;
    localparam logic [3:0] IDLE        = 4'd0;
    localparam logic [3:0] SAVE        = 4'd1;
    localparam logic [3:0] WRITE_ZERO  = 4'd2;
    localparam logic [3:0] CHECK_ZERO  = 4'd3;
    localparam logic [3:0] WRITE_ONE   = 4'd4;
    localparam logic [3:0] CHECK_ONE   = 4'd5;
    localparam logic [3:0] RESTORE     = 4'd6;
    localparam logic [3:0] VERIFY      = 4'd7;
    localparam logic [3:0] REPORT      = 4'd8;

    logic [3:0] state;
    logic cell_write_enable;
    logic [WIDTH-1:0] cell_write_a;
    logic [WIDTH-1:0] cell_write_b;
    logic [WIDTH-1:0] cell_write_c;
    logic [WIDTH-1:0] replica_a;
    logic [WIDTH-1:0] replica_b;
    logic [WIDTH-1:0] replica_c;
    logic [WIDTH-1:0] saved_a;
    logic [WIDTH-1:0] saved_b;
    logic [WIDTH-1:0] saved_c;
    logic [13:0] resistance_a [0:WIDTH-1];
    logic [13:0] resistance_b [0:WIDTH-1];
    logic [13:0] resistance_c [0:WIDTH-1];
    logic [MAP_WIDTH-1:0] replicas_in_lrs;
    logic [MAP_WIDTH-1:0] replicas_in_hrs;

    assign replica_health_map = ~(lrs_fault_map | hrs_fault_map);

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
                .clk(clk), .reset(reset), .write_enable(cell_write_enable),
                .write_data(cell_write_a[bit_index]), .fault_mode(mode_a),
                .read_data(replica_a[bit_index]),
                .resistance_ohms(resistance_a[bit_index])
            );
            publication_memristor_cell #(
                .R_ON_OHMS(R_ON_OHMS), .R_OFF_OHMS(R_OFF_OHMS),
                .R_THRESHOLD_OHMS(R_THRESHOLD_OHMS)
            ) cell_b (
                .clk(clk), .reset(reset), .write_enable(cell_write_enable),
                .write_data(cell_write_b[bit_index]), .fault_mode(mode_b),
                .read_data(replica_b[bit_index]),
                .resistance_ohms(resistance_b[bit_index])
            );
            publication_memristor_cell #(
                .R_ON_OHMS(R_ON_OHMS), .R_OFF_OHMS(R_OFF_OHMS),
                .R_THRESHOLD_OHMS(R_THRESHOLD_OHMS)
            ) cell_c (
                .clk(clk), .reset(reset), .write_enable(cell_write_enable),
                .write_data(cell_write_c[bit_index]), .fault_mode(mode_c),
                .read_data(replica_c[bit_index]),
                .resistance_ohms(resistance_c[bit_index])
            );

            assign replicas_in_lrs[bit_index] =
                resistance_a[bit_index] < R_THRESHOLD_OHMS;
            assign replicas_in_lrs[WIDTH + bit_index] =
                resistance_b[bit_index] < R_THRESHOLD_OHMS;
            assign replicas_in_lrs[(2*WIDTH) + bit_index] =
                resistance_c[bit_index] < R_THRESHOLD_OHMS;
            assign replicas_in_hrs[bit_index] =
                resistance_a[bit_index] >= R_THRESHOLD_OHMS;
            assign replicas_in_hrs[WIDTH + bit_index] =
                resistance_b[bit_index] >= R_THRESHOLD_OHMS;
            assign replicas_in_hrs[(2*WIDTH) + bit_index] =
                resistance_c[bit_index] >= R_THRESHOLD_OHMS;

            always_comb begin
                corrected_data[bit_index] =
                    (replica_a[bit_index] & replica_b[bit_index]) |
                    (replica_a[bit_index] & replica_c[bit_index]) |
                    (replica_b[bit_index] & replica_c[bit_index]);
                uncorrectable_map[bit_index] = 1'b0;
                if (diagnosis_valid) begin
                    case ({replica_health_map[bit_index],
                           replica_health_map[WIDTH + bit_index],
                           replica_health_map[(2*WIDTH) + bit_index]})
                        3'b111: corrected_data[bit_index] =
                            (replica_a[bit_index] & replica_b[bit_index]) |
                            (replica_a[bit_index] & replica_c[bit_index]) |
                            (replica_b[bit_index] & replica_c[bit_index]);
                        3'b110: begin
                            corrected_data[bit_index] = replica_a[bit_index];
                            if (replica_a[bit_index] != replica_b[bit_index])
                                uncorrectable_map[bit_index] = 1'b1;
                        end
                        3'b101: begin
                            corrected_data[bit_index] = replica_a[bit_index];
                            if (replica_a[bit_index] != replica_c[bit_index])
                                uncorrectable_map[bit_index] = 1'b1;
                        end
                        3'b011: begin
                            corrected_data[bit_index] = replica_b[bit_index];
                            if (replica_b[bit_index] != replica_c[bit_index])
                                uncorrectable_map[bit_index] = 1'b1;
                        end
                        3'b100: corrected_data[bit_index] = replica_a[bit_index];
                        3'b010: corrected_data[bit_index] = replica_b[bit_index];
                        3'b001: corrected_data[bit_index] = replica_c[bit_index];
                        default: begin
                            uncorrectable_map[bit_index] = 1'b1;
                        end
                    endcase
                end
            end
        end
    endgenerate

    always_comb begin
        cell_write_enable = 1'b0;
        cell_write_a = operational_write_data;
        cell_write_b = operational_write_data;
        cell_write_c = operational_write_data;
        busy = 1'b0;
        done = 1'b0;
        case (state)
            IDLE: cell_write_enable = operational_write_enable;
            SAVE: busy = 1'b1;
            WRITE_ZERO: begin
                busy = 1'b1;
                cell_write_enable = 1'b1;
                cell_write_a = '0;
                cell_write_b = '0;
                cell_write_c = '0;
            end
            CHECK_ZERO: busy = 1'b1;
            WRITE_ONE: begin
                busy = 1'b1;
                cell_write_enable = 1'b1;
                cell_write_a = '1;
                cell_write_b = '1;
                cell_write_c = '1;
            end
            CHECK_ONE: busy = 1'b1;
            RESTORE: begin
                busy = 1'b1;
                cell_write_enable = 1'b1;
                cell_write_a = saved_a;
                cell_write_b = saved_b;
                cell_write_c = saved_c;
            end
            VERIFY: busy = 1'b1;
            REPORT: done = 1'b1;
            default: begin
                busy = 1'b0;
                done = 1'b0;
            end
        endcase
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            saved_a <= '0;
            saved_b <= '0;
            saved_c <= '0;
            lrs_fault_map <= '0;
            hrs_fault_map <= '0;
            fault_found <= 1'b0;
            diagnosis_valid <= 1'b0;
            restore_ok <= 1'b0;
            bist_cycle_count <= 16'd0;
        end else begin
            case (state)
                IDLE: begin
                    if (start) begin
                        lrs_fault_map <= '0;
                        hrs_fault_map <= '0;
                        fault_found <= 1'b0;
                        diagnosis_valid <= 1'b0;
                        restore_ok <= 1'b0;
                        bist_cycle_count <= 16'd1;
                        state <= SAVE;
                    end
                end
                SAVE: begin
                    saved_a <= replica_a;
                    saved_b <= replica_b;
                    saved_c <= replica_c;
                    bist_cycle_count <= bist_cycle_count + 1'b1;
                    state <= WRITE_ZERO;
                end
                WRITE_ZERO: begin
                    bist_cycle_count <= bist_cycle_count + 1'b1;
                    state <= CHECK_ZERO;
                end
                CHECK_ZERO: begin
                    lrs_fault_map <= replicas_in_lrs;
                    bist_cycle_count <= bist_cycle_count + 1'b1;
                    state <= WRITE_ONE;
                end
                WRITE_ONE: begin
                    bist_cycle_count <= bist_cycle_count + 1'b1;
                    state <= CHECK_ONE;
                end
                CHECK_ONE: begin
                    hrs_fault_map <= replicas_in_hrs;
                    fault_found <= (|lrs_fault_map) | (|replicas_in_hrs);
                    diagnosis_valid <= 1'b1;
                    bist_cycle_count <= bist_cycle_count + 1'b1;
                    state <= RESTORE;
                end
                RESTORE: begin
                    bist_cycle_count <= bist_cycle_count + 1'b1;
                    state <= VERIFY;
                end
                VERIFY: begin
                    restore_ok <=
                        ((((replica_a ^ saved_a) & replica_health_map[WIDTH-1:0]) == '0) &&
                         (((replica_b ^ saved_b) & replica_health_map[(2*WIDTH)-1:WIDTH]) == '0) &&
                         (((replica_c ^ saved_c) & replica_health_map[(3*WIDTH)-1:(2*WIDTH)]) == '0));
                    bist_cycle_count <= bist_cycle_count + 1'b1;
                    state <= REPORT;
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
