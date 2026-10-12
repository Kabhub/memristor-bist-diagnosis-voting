`timescale 1ns/1ps

// Parameterized research core used only for publication experiments.  The
// verified ZedBoard top remains unchanged.  Three constant architectures are
// synthesized from this same source so the comparison uses an identical BIST
// sequence and resistance classifier:
//   0 = one unprotected replica per logical bit
//   1 = conventional three-replica majority TMR
//   2 = proposed resistance-aware BIST-guided voter
module publication_scalable_memristor_core #(
    parameter integer WIDTH        = 8,
    parameter integer ARCHITECTURE = 2,
    parameter logic [13:0] R_ON_OHMS       = 14'd100,
    parameter logic [13:0] R_OFF_OHMS      = 14'd10000,
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
    output logic [15:0]            bist_cycle_count,
    output logic [WIDTH-1:0]       unprotected_data,
    output logic [WIDTH-1:0]       standard_tmr_data,
    output logic [WIDTH-1:0]       corrected_data,
    output logic [(3*WIDTH)-1:0]   lrs_fault_map,
    output logic [(3*WIDTH)-1:0]   hrs_fault_map,
    output logic [(3*WIDTH)-1:0]   replica_health_map,
    output logic [WIDTH-1:0]       uncorrectable_map
);

    localparam integer MAP_WIDTH = 3 * WIDTH;

    localparam logic [2:0] IDLE       = 3'd0;
    localparam logic [2:0] WRITE_ZERO = 3'd1;
    localparam logic [2:0] CHECK_ZERO = 3'd2;
    localparam logic [2:0] WRITE_ONE  = 3'd3;
    localparam logic [2:0] CHECK_ONE  = 3'd4;
    localparam logic [2:0] REPORT     = 3'd5;

    logic [2:0] state;
    logic       memory_write_enable;
    logic [WIDTH-1:0] memory_write_data;

    logic [WIDTH-1:0] replica_a;
    logic [WIDTH-1:0] replica_b;
    logic [WIDTH-1:0] replica_c;
    logic [13:0] resistance_a [0:WIDTH-1];
    logic [13:0] resistance_b [0:WIDTH-1];
    logic [13:0] resistance_c [0:WIDTH-1];

    logic [MAP_WIDTH-1:0] replicas_in_lrs;
    logic [MAP_WIDTH-1:0] replicas_in_hrs;

    assign replica_health_map = ~(lrs_fault_map | hrs_fault_map);

    generate
        for (genvar bit_index = 0; bit_index < WIDTH; bit_index++) begin : gen_cells
            logic [1:0] fault_mode_a;
            logic [1:0] fault_mode_b;
            logic [1:0] fault_mode_c;

            always_comb begin
                fault_mode_a = 2'b00;
                fault_mode_b = 2'b00;
                fault_mode_c = 2'b00;

                if (inject_lrs_fault_map[bit_index])
                    fault_mode_a = 2'b01;
                else if (inject_hrs_fault_map[bit_index])
                    fault_mode_a = 2'b10;

                if (inject_lrs_fault_map[WIDTH + bit_index])
                    fault_mode_b = 2'b01;
                else if (inject_hrs_fault_map[WIDTH + bit_index])
                    fault_mode_b = 2'b10;

                if (inject_lrs_fault_map[(2*WIDTH) + bit_index])
                    fault_mode_c = 2'b01;
                else if (inject_hrs_fault_map[(2*WIDTH) + bit_index])
                    fault_mode_c = 2'b10;
            end

            publication_memristor_cell #(
                .R_ON_OHMS       (R_ON_OHMS),
                .R_OFF_OHMS      (R_OFF_OHMS),
                .R_THRESHOLD_OHMS(R_THRESHOLD_OHMS)
            ) cell_a (
                .clk             (clk),
                .reset           (reset),
                .write_enable    (memory_write_enable),
                .write_data      (memory_write_data[bit_index]),
                .fault_mode      (fault_mode_a),
                .read_data       (replica_a[bit_index]),
                .resistance_ohms (resistance_a[bit_index])
            );

            if (ARCHITECTURE == 0) begin : gen_unprotected
                // There is physically only one modelled cell in this branch.
                // B/C are aliases for observability and are excluded from BIST.
                assign replica_b[bit_index]    = replica_a[bit_index];
                assign replica_c[bit_index]    = replica_a[bit_index];
                assign resistance_b[bit_index] = resistance_a[bit_index];
                assign resistance_c[bit_index] = resistance_a[bit_index];
            end else begin : gen_replicated
                publication_memristor_cell #(
                    .R_ON_OHMS       (R_ON_OHMS),
                    .R_OFF_OHMS      (R_OFF_OHMS),
                    .R_THRESHOLD_OHMS(R_THRESHOLD_OHMS)
                ) cell_b (
                    .clk             (clk),
                    .reset           (reset),
                    .write_enable    (memory_write_enable),
                    .write_data      (memory_write_data[bit_index]),
                    .fault_mode      (fault_mode_b),
                    .read_data       (replica_b[bit_index]),
                    .resistance_ohms (resistance_b[bit_index])
                );

                publication_memristor_cell #(
                    .R_ON_OHMS       (R_ON_OHMS),
                    .R_OFF_OHMS      (R_OFF_OHMS),
                    .R_THRESHOLD_OHMS(R_THRESHOLD_OHMS)
                ) cell_c (
                    .clk             (clk),
                    .reset           (reset),
                    .write_enable    (memory_write_enable),
                    .write_data      (memory_write_data[bit_index]),
                    .fault_mode      (fault_mode_c),
                    .read_data       (replica_c[bit_index]),
                    .resistance_ohms (resistance_c[bit_index])
                );
            end

            // The same resistance threshold is used by all three research
            // architectures. Nonexistent B/C cells in architecture 0 are
            // explicitly excluded instead of being counted as replicas.
            assign replicas_in_lrs[bit_index] =
                resistance_a[bit_index] < R_THRESHOLD_OHMS;
            assign replicas_in_hrs[bit_index] =
                resistance_a[bit_index] >= R_THRESHOLD_OHMS;

            if (ARCHITECTURE == 0) begin : gen_single_classifier
                assign replicas_in_lrs[WIDTH + bit_index] = 1'b0;
                assign replicas_in_lrs[(2*WIDTH) + bit_index] = 1'b0;
                assign replicas_in_hrs[WIDTH + bit_index] = 1'b0;
                assign replicas_in_hrs[(2*WIDTH) + bit_index] = 1'b0;
            end else begin : gen_three_classifiers
                assign replicas_in_lrs[WIDTH + bit_index] =
                    resistance_b[bit_index] < R_THRESHOLD_OHMS;
                assign replicas_in_lrs[(2*WIDTH) + bit_index] =
                    resistance_c[bit_index] < R_THRESHOLD_OHMS;
                assign replicas_in_hrs[WIDTH + bit_index] =
                    resistance_b[bit_index] >= R_THRESHOLD_OHMS;
                assign replicas_in_hrs[(2*WIDTH) + bit_index] =
                    resistance_c[bit_index] >= R_THRESHOLD_OHMS;
            end

            always_comb begin
                unprotected_data[bit_index] = replica_a[bit_index];
                standard_tmr_data[bit_index] =
                    (replica_a[bit_index] & replica_b[bit_index]) |
                    (replica_a[bit_index] & replica_c[bit_index]) |
                    (replica_b[bit_index] & replica_c[bit_index]);

                if (ARCHITECTURE == 0)
                    corrected_data[bit_index] = replica_a[bit_index];
                else
                    corrected_data[bit_index] = standard_tmr_data[bit_index];

                uncorrectable_map[bit_index] = 1'b0;

                if ((ARCHITECTURE == 2) && diagnosis_valid) begin
                    case ({replica_health_map[bit_index],
                           replica_health_map[WIDTH + bit_index],
                           replica_health_map[(2*WIDTH) + bit_index]})
                        3'b111: corrected_data[bit_index] =
                            standard_tmr_data[bit_index];

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
                            corrected_data[bit_index] =
                                standard_tmr_data[bit_index];
                            uncorrectable_map[bit_index] = 1'b1;
                        end
                    endcase
                end
            end
        end
    endgenerate

    always_comb begin
        memory_write_enable = 1'b0;
        memory_write_data   = operational_write_data;
        busy                = 1'b0;
        done                = 1'b0;

        case (state)
            IDLE: memory_write_enable = operational_write_enable;

            WRITE_ZERO: begin
                busy                = 1'b1;
                memory_write_enable = 1'b1;
                memory_write_data   = '0;
            end

            CHECK_ZERO: busy = 1'b1;

            WRITE_ONE: begin
                busy                = 1'b1;
                memory_write_enable = 1'b1;
                memory_write_data   = '1;
            end

            CHECK_ONE: busy = 1'b1;
            REPORT:    done = 1'b1;
            default: begin
                busy = 1'b0;
                done = 1'b0;
            end
        endcase
    end

    always_ff @(posedge clk) begin
        if (reset) begin
            state            <= IDLE;
            lrs_fault_map    <= '0;
            hrs_fault_map    <= '0;
            fault_found      <= 1'b0;
            diagnosis_valid  <= 1'b0;
            bist_cycle_count <= 16'd0;
        end else begin
            case (state)
                IDLE: begin
                    if (start) begin
                        lrs_fault_map    <= '0;
                        hrs_fault_map    <= '0;
                        fault_found      <= 1'b0;
                        diagnosis_valid  <= 1'b0;
                        bist_cycle_count <= 16'd1;
                        state            <= WRITE_ZERO;
                    end
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


// Synthesizable two-state resistance cell with parameterized nominal states.
// Keeping the parameters explicit lets the later sensitivity campaign reuse
// exactly the same classification semantics as the scalable architecture.
module publication_memristor_cell #(
    parameter logic [13:0] R_ON_OHMS        = 14'd100,
    parameter logic [13:0] R_OFF_OHMS       = 14'd10000,
    parameter logic [13:0] R_THRESHOLD_OHMS = 14'd5050
) (
    input  logic        clk,
    input  logic        reset,
    input  logic        write_enable,
    input  logic        write_data,
    input  logic [1:0]  fault_mode,
    output logic        read_data,
    output logic [13:0] resistance_ohms
);

    logic [13:0] stored_resistance;
    logic [13:0] effective_resistance;

    always_ff @(posedge clk) begin
        if (reset)
            stored_resistance <= R_OFF_OHMS;
        else if (write_enable) begin
            case (fault_mode)
                2'b01:   stored_resistance <= R_ON_OHMS;
                2'b10:   stored_resistance <= R_OFF_OHMS;
                default: stored_resistance <=
                    write_data ? R_ON_OHMS : R_OFF_OHMS;
            endcase
        end
    end

    always_comb begin
        case (fault_mode)
            2'b01:   effective_resistance = R_ON_OHMS;
            2'b10:   effective_resistance = R_OFF_OHMS;
            default: effective_resistance = stored_resistance;
        endcase
    end

    assign resistance_ohms = effective_resistance;
    assign read_data = effective_resistance < R_THRESHOLD_OHMS;

endmodule
