`timescale 1ns/1ps

module memristor_cell (
    input  logic        clk,
    input  logic        reset,
    input  logic        write_enable,
    input  logic        write_data,
    input  logic [1:0]  fault_mode,
    output logic        read_data,
    output logic [13:0] resistance_ohms
);

    localparam logic [1:0] NORMAL        = 2'b00;
    localparam logic [1:0] STUCK_AT_LRS  = 2'b01;
    localparam logic [1:0] STUCK_AT_HRS  = 2'b10;

    localparam logic [13:0] R_ON        = 14'd100;
    localparam logic [13:0] R_OFF       = 14'd10000;
    localparam logic [13:0] R_THRESHOLD = 14'd5050;

    logic [13:0] stored_resistance;
    logic [13:0] effective_resistance;

    // Behavioural memristive state: resistance changes only on reset or write.
    // It is retained while write_enable is low during powered operation.
    always_ff @(posedge clk) begin
        if (reset) begin
            stored_resistance <= R_OFF;
        end else if (write_enable) begin
            case (fault_mode)
                NORMAL:       stored_resistance <= write_data ? R_ON : R_OFF;
                STUCK_AT_LRS: stored_resistance <= R_ON;
                STUCK_AT_HRS: stored_resistance <= R_OFF;
                default:      stored_resistance <= write_data ? R_ON : R_OFF;
            endcase
        end
    end

    // A stuck fault overrides the stored resistance even when no write occurs.
    always_comb begin
        case (fault_mode)
            STUCK_AT_LRS: effective_resistance = R_ON;
            STUCK_AT_HRS: effective_resistance = R_OFF;
            default:      effective_resistance = stored_resistance;
        endcase
    end

    // The logical read value is derived from memristance, not stored separately.
    assign resistance_ohms = effective_resistance;
    assign read_data       = (effective_resistance < R_THRESHOLD);

endmodule
