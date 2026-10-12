`timescale 1ns/1ps

// Generic extended-Hamming SECDED storage baseline. It corrects one activated
// code-bit error and detects/rejects two activated code-bit errors. No claim is
// made that SECDED corrects arbitrary double faults. The encoded word is held
// in behavioural resistance cells so Vivado measures the complete encoder,
// storage, classifier, syndrome, correction, and decoder logic.
module review_secded_memory #(
    parameter integer WIDTH = 8,
    parameter integer PARITY_BITS =
        (WIDTH <= 4)  ? 3 :
        (WIDTH <= 11) ? 4 :
        (WIDTH <= 26) ? 5 :
        (WIDTH <= 57) ? 6 : 7,
    parameter integer CODE_WIDTH = WIDTH + PARITY_BITS + 1,
    parameter logic [13:0] R_ON_OHMS = 14'd100,
    parameter logic [13:0] R_OFF_OHMS = 14'd10000,
    parameter logic [13:0] R_THRESHOLD_OHMS = 14'd5050
) (
    input  logic                    clk,
    input  logic                    reset,
    input  logic                    write_enable,
    input  logic [WIDTH-1:0]        write_data,
    input  logic [CODE_WIDTH-1:0]   inject_lrs_fault_map,
    input  logic [CODE_WIDTH-1:0]   inject_hrs_fault_map,
    output logic [WIDTH-1:0]        corrected_data,
    output logic                    error_detected,
    output logic                    single_error_corrected,
    output logic                    double_error_detected,
    output logic                    accepted,
    output logic [CODE_WIDTH-1:0]   observed_codeword
);

    localparam integer HAMMING_WIDTH = WIDTH + PARITY_BITS;

    function automatic logic [CODE_WIDTH-1:0] encode_secded(
        input logic [WIDTH-1:0] data_value
    );
        logic [CODE_WIDTH-1:0] code;
        logic parity_value;
        integer position;
        integer data_index;
        integer parity_index;
        begin
            code = '0;
            data_index = 0;
            for (position = 1; position <= HAMMING_WIDTH; position = position + 1) begin
                if ((position & (position - 1)) != 0) begin
                    code[position-1] = data_value[data_index];
                    data_index = data_index + 1;
                end
            end
            for (parity_index = 0; parity_index < PARITY_BITS; parity_index = parity_index + 1) begin
                parity_value = 1'b0;
                for (position = 1; position <= HAMMING_WIDTH; position = position + 1)
                    if ((position & (1 << parity_index)) != 0)
                        parity_value = parity_value ^ code[position-1];
                code[(1 << parity_index)-1] = parity_value;
            end
            code[CODE_WIDTH-1] = ^code[HAMMING_WIDTH-1:0];
            encode_secded = code;
        end
    endfunction

    logic [CODE_WIDTH-1:0] encoded_write_data;
    logic [CODE_WIDTH-1:0] corrected_codeword;
    logic                  parity_accumulator;
    logic                  overall_mismatch;
    integer                syndrome_value;
    integer                position;
    integer                parity_index;
    integer                decoded_index;

    assign encoded_write_data = encode_secded(write_data);

    generate
        for (genvar code_index = 0; code_index < CODE_WIDTH; code_index++) begin : gen_code_cells
            logic [1:0] fault_mode;
            always_comb begin
                fault_mode = 2'b00;
                if (inject_lrs_fault_map[code_index])
                    fault_mode = 2'b01;
                else if (inject_hrs_fault_map[code_index])
                    fault_mode = 2'b10;
            end
            publication_memristor_cell #(
                .R_ON_OHMS(R_ON_OHMS), .R_OFF_OHMS(R_OFF_OHMS),
                .R_THRESHOLD_OHMS(R_THRESHOLD_OHMS)
            ) code_cell (
                .clk(clk), .reset(reset), .write_enable(write_enable),
                .write_data(encoded_write_data[code_index]),
                .fault_mode(fault_mode),
                .read_data(observed_codeword[code_index]),
                .resistance_ohms()
            );
        end
    endgenerate

    always_comb begin
        syndrome_value = 0;
        for (parity_index = 0; parity_index < PARITY_BITS; parity_index = parity_index + 1) begin
            parity_accumulator = 1'b0;
            for (position = 1; position <= HAMMING_WIDTH; position = position + 1)
                if ((position & (1 << parity_index)) != 0)
                    parity_accumulator = parity_accumulator ^ observed_codeword[position-1];
            if (parity_accumulator)
                syndrome_value = syndrome_value | (1 << parity_index);
        end

        overall_mismatch = ^observed_codeword;
        corrected_codeword = observed_codeword;
        single_error_corrected = 1'b0;
        double_error_detected = 1'b0;

        if ((syndrome_value != 0) && overall_mismatch) begin
            corrected_codeword[syndrome_value-1] =
                ~corrected_codeword[syndrome_value-1];
            single_error_corrected = 1'b1;
        end else if ((syndrome_value == 0) && overall_mismatch) begin
            corrected_codeword[CODE_WIDTH-1] =
                ~corrected_codeword[CODE_WIDTH-1];
            single_error_corrected = 1'b1;
        end else if ((syndrome_value != 0) && !overall_mismatch) begin
            double_error_detected = 1'b1;
        end

        error_detected = single_error_corrected | double_error_detected;
        accepted = ~double_error_detected;
        corrected_data = '0;
        decoded_index = 0;
        for (position = 1; position <= HAMMING_WIDTH; position = position + 1) begin
            if ((position & (position - 1)) != 0) begin
                corrected_data[decoded_index] = corrected_codeword[position-1];
                decoded_index = decoded_index + 1;
            end
        end
    end

endmodule
