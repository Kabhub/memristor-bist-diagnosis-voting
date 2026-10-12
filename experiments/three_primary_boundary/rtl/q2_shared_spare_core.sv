`timescale 1ns/1ps
// Research single-word BISR baseline, not a reproduction of a published
// row/column allocator. Cell IDs 0..WIDTH-1 are primaries; the rest are shared
// spares. The same two-state cells and resistance classifier as the proposal
// are used. Injection maps drive cells ONLY; allocation uses BIST results.
module q2_shared_spare_core #(
    parameter integer WIDTH = 16,
    parameter integer SPARES = 2,
    parameter integer ADDR_BITS = $clog2(WIDTH+SPARES),
    parameter logic [13:0] R_ON_OHMS = 14'd100,
    parameter logic [13:0] R_OFF_OHMS = 14'd10000,
    parameter logic [13:0] R_THRESHOLD_OHMS = 14'd5050
) (
    input logic clk, reset, start,
    input logic operational_write_enable,
    input logic [WIDTH-1:0] operational_write_data,
    input logic [WIDTH+SPARES-1:0] inject_lrs_fault_map, inject_hrs_fault_map,
    output logic busy, done, fault_found, diagnosis_valid,
    output logic [15:0] bist_cycle_count,
    output logic [WIDTH-1:0] corrected_data, uncorrectable_map,
    output logic [WIDTH+SPARES-1:0] lrs_fault_map, hrs_fault_map, cell_health_map,
    output wire [WIDTH*ADDR_BITS-1:0] logical_to_physical_map
);
    localparam integer CELLS = WIDTH+SPARES;
    localparam integer INDEX_BITS = (WIDTH > 1) ? $clog2(WIDTH) : 1;
    localparam logic [2:0] IDLE=0, WRITE_ZERO=1, CHECK_ZERO=2,
        WRITE_ONE=3, CHECK_ONE=4, ALLOCATE=5, REPORT=6;
    logic [2:0] state;
    logic [INDEX_BITS-1:0] logical_index;
    logic [ADDR_BITS-1:0] address_map [0:WIDTH-1];
    logic [SPARES-1:0] spare_used;
    logic [CELLS-1:0] read_bits, in_lrs, in_hrs;
    logic [CELLS-1:0] cell_write_enable, cell_write_data;
    logic [13:0] resistance [0:CELLS-1];
    integer selected_spare;

    assign cell_health_map = ~(lrs_fault_map | hrs_fault_map);
    // Lowest-index healthy unused spare. This is a combinational priority
    // encoder; the allocation controller processes one logical bit per cycle.
    always_comb begin
        selected_spare = -1;
        for (integer s=0; s<SPARES; s=s+1)
            if (selected_spare == -1 && !spare_used[s] && cell_health_map[WIDTH+s])
                selected_spare = s;
    end
    always_comb begin
        cell_write_enable = '0;
        cell_write_data = '0;
        busy = 1'b0;
        done = 1'b0;
        case (state)
            IDLE: if (operational_write_enable && diagnosis_valid) begin
                for (integer b=0; b<WIDTH; b=b+1) begin
                    if (!uncorrectable_map[b]) begin
                        cell_write_enable[address_map[b]] = 1'b1;
                        cell_write_data[address_map[b]] = operational_write_data[b];
                    end
                end
            end
            WRITE_ZERO: begin busy=1'b1; cell_write_enable='1; cell_write_data='0; end
            CHECK_ZERO: busy=1'b1;
            WRITE_ONE: begin busy=1'b1; cell_write_enable='1; cell_write_data='1; end
            CHECK_ONE: busy=1'b1;
            ALLOCATE: busy=1'b1;
            REPORT: done=1'b1;
            default: begin end
        endcase
        for (integer b=0; b<WIDTH; b=b+1)
            corrected_data[b] = read_bits[address_map[b]];
    end
    generate
        for (genvar c=0; c<CELLS; c=c+1) begin : gen_cells
            wire [1:0] fault_mode = inject_lrs_fault_map[c] ? 2'b01 :
                (inject_hrs_fault_map[c] ? 2'b10 : 2'b00);
            publication_memristor_cell #(
                .R_ON_OHMS(R_ON_OHMS), .R_OFF_OHMS(R_OFF_OHMS),
                .R_THRESHOLD_OHMS(R_THRESHOLD_OHMS)
            ) mem_cell (
                .clk(clk), .reset(reset), .write_enable(cell_write_enable[c]),
                .write_data(cell_write_data[c]), .fault_mode(fault_mode),
                .read_data(read_bits[c]), .resistance_ohms(resistance[c])
            );
            assign in_lrs[c] = resistance[c] < R_THRESHOLD_OHMS;
            assign in_hrs[c] = resistance[c] >= R_THRESHOLD_OHMS;
        end
        for (genvar b=0; b<WIDTH; b=b+1) begin : gen_observe
            assign logical_to_physical_map[b*ADDR_BITS +: ADDR_BITS] = address_map[b];
        end
    endgenerate
    always_ff @(posedge clk) begin
        if (reset) begin
            state<=IDLE; logical_index<='0; spare_used<='0;
            lrs_fault_map<='0; hrs_fault_map<='0; uncorrectable_map<='0;
            fault_found<=0; diagnosis_valid<=0; bist_cycle_count<=0;
            for (integer b=0; b<WIDTH; b=b+1) address_map[b]<=ADDR_BITS'(b);
        end else begin
            case (state)
                IDLE: if (start) begin
                    state<=WRITE_ZERO; lrs_fault_map<='0; hrs_fault_map<='0;
                    uncorrectable_map<='0; spare_used<='0; logical_index<='0;
                    fault_found<=0; diagnosis_valid<=0; bist_cycle_count<=1;
                    for (integer b=0; b<WIDTH; b=b+1) address_map[b]<=ADDR_BITS'(b);
                end
                WRITE_ZERO: begin state<=CHECK_ZERO; bist_cycle_count<=bist_cycle_count+1'b1; end
                CHECK_ZERO: begin lrs_fault_map<=in_lrs; state<=WRITE_ONE; bist_cycle_count<=bist_cycle_count+1'b1; end
                WRITE_ONE: begin state<=CHECK_ONE; bist_cycle_count<=bist_cycle_count+1'b1; end
                CHECK_ONE: begin
                    hrs_fault_map<=in_hrs; fault_found<= (|lrs_fault_map) | (|in_hrs);
                    state<=ALLOCATE; bist_cycle_count<=bist_cycle_count+1'b1;
                end
                ALLOCATE: begin
                    bist_cycle_count<=bist_cycle_count+1'b1;
                    if (!cell_health_map[ADDR_BITS'(logical_index)]) begin
                        if (selected_spare >= 0) begin
                            address_map[logical_index]<=ADDR_BITS'(WIDTH+selected_spare);
                            spare_used[selected_spare]<=1'b1;
                        end else uncorrectable_map[logical_index]<=1'b1;
                    end
                    if (logical_index == INDEX_BITS'(WIDTH-1)) begin
                        diagnosis_valid<=1'b1; state<=REPORT;
                    end else logical_index<=logical_index+1'b1;
                end
                REPORT: if (!start) state<=IDLE;
                default: state<=IDLE;
            endcase
        end
    end
endmodule
