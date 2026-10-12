`timescale 1ns/1ps

// Compact text controller for the ZedBoard 128x32 OLED (SSD1306 family).
// OLED_VDD and OLED_VBAT are active-low power enables on ZedBoard.
module zedboard_oled_status #(
    parameter integer CLK_HZ                 = 100_000_000,
    parameter integer SPI_HALF_PERIOD_CYCLES = 10,
    parameter integer VDD_DELAY_MS           = 1,
    parameter integer RESET_DELAY_MS         = 1,
    parameter integer VBAT_DELAY_MS          = 100,
    parameter integer OFF_DELAY_MS           = 100
) (
    input  logic       clk,
    input  logic       reset,
    input  logic       toggle_power,
    input  logic       detail_mode,
    input  logic       fault_enable,
    input  logic [1:0] fault_mode,
    input  logic [2:0] fault_bit_address,
    input  logic [1:0] fault_replica,
    input  logic       busy,
    input  logic       test_complete,
    input  logic       fault_found,
    input  logic       lrs_found,
    input  logic       hrs_found,
    input  logic [7:0] corrected_data,
    input  logic [13:0] detected_resistance_ohms,
    input  logic       comparison_mode,
    input  logic       comparison_ready,
    input  logic [1:0] fault_pair,
    input  logic       standard_pass,
    input  logic       proposed_pass,
    input  logic [7:0] standard_data,
    output logic       oled_on = 1'b0,
    output logic       OLED_DC = 1'b0,
    output logic       OLED_RES = 1'b0,
    output logic       OLED_SCLK,
    output logic       OLED_SDIN,
    output logic       OLED_VBAT = 1'b1,
    output logic       OLED_VDD = 1'b1
);

    localparam integer CYCLES_PER_MS = (CLK_HZ + 999) / 1000;
    localparam integer VDD_CYCLES    = CYCLES_PER_MS * VDD_DELAY_MS;
    localparam integer RESET_CYCLES  = CYCLES_PER_MS * RESET_DELAY_MS;
    localparam integer VBAT_CYCLES   = CYCLES_PER_MS * VBAT_DELAY_MS;
    localparam integer OFF_CYCLES    = CYCLES_PER_MS * OFF_DELAY_MS;

    localparam logic [4:0] ST_POWER_VDD       = 5'd0;
    localparam logic [4:0] ST_WAIT_VDD        = 5'd1;
    localparam logic [4:0] ST_SEND_OFF        = 5'd2;
    localparam logic [4:0] ST_WAIT_OFF        = 5'd3;
    localparam logic [4:0] ST_RESET_LOW       = 5'd4;
    localparam logic [4:0] ST_WAIT_RESET_LOW  = 5'd5;
    localparam logic [4:0] ST_RESET_HIGH      = 5'd6;
    localparam logic [4:0] ST_WAIT_RESET_HIGH = 5'd7;
    localparam logic [4:0] ST_SEND_PRE        = 5'd8;
    localparam logic [4:0] ST_WAIT_PRE        = 5'd9;
    localparam logic [4:0] ST_POWER_VBAT      = 5'd10;
    localparam logic [4:0] ST_WAIT_VBAT       = 5'd11;
    localparam logic [4:0] ST_SEND_POST       = 5'd12;
    localparam logic [4:0] ST_WAIT_POST       = 5'd13;
    localparam logic [4:0] ST_SEND_PAGE       = 5'd14;
    localparam logic [4:0] ST_WAIT_PAGE       = 5'd15;
    localparam logic [4:0] ST_SEND_PIXEL      = 5'd16;
    localparam logic [4:0] ST_WAIT_PIXEL      = 5'd17;
    localparam logic [4:0] ST_SHUTDOWN_OFF    = 5'd18;
    localparam logic [4:0] ST_WAIT_SHUT_OFF   = 5'd19;
    localparam logic [4:0] ST_SHUTDOWN_VBAT   = 5'd20;
    localparam logic [4:0] ST_WAIT_SHUT_VBAT  = 5'd21;
    localparam logic [4:0] ST_SHUTDOWN_VDD    = 5'd22;
    localparam logic [4:0] ST_POWERED_OFF     = 5'd23;

    logic [4:0]  state;
    logic [31:0] delay_counter;
    logic [4:0]  pre_command_index;
    logic [1:0]  page;
    logic [6:0]  pixel_column;
    logic [1:0]  page_command_index;
    logic [4:0]  character_index;
    logic [2:0]  glyph_column_index;
    logic        shutdown_requested;
    logic        initial_clear;

    logic       spi_start;
    logic       spi_busy;
    logic       spi_done;
    logic [7:0] spi_data;
    logic [7:0] pixel_data;
    logic [7:0] displayed_character;

    function automatic logic [31:0] delay_seed(input integer unsigned cycle_count);
        begin
            if (cycle_count > 0)
                delay_seed = cycle_count - 1;
            else
                delay_seed = 32'd0;
        end
    endfunction

    function automatic logic [7:0] pre_init_command(input logic [4:0] index);
        begin
            case (index)
                5'd0:  pre_init_command = 8'hD5; // Display clock command.
                5'd1:  pre_init_command = 8'h80;
                5'd2:  pre_init_command = 8'hA8; // 1/32 multiplex.
                5'd3:  pre_init_command = 8'h1F;
                5'd4:  pre_init_command = 8'hD3; // No vertical offset.
                5'd5:  pre_init_command = 8'h00;
                5'd6:  pre_init_command = 8'h40; // Start line zero.
                5'd7:  pre_init_command = 8'h8D; // Charge pump command.
                5'd8:  pre_init_command = 8'h14; // Enable charge pump.
                5'd9:  pre_init_command = 8'hA1; // Segment remap.
                5'd10: pre_init_command = 8'hC8; // Reverse COM scan.
                5'd11: pre_init_command = 8'hDA; // COM pin configuration.
                5'd12: pre_init_command = 8'h02;
                5'd13: pre_init_command = 8'h81; // Contrast command.
                5'd14: pre_init_command = 8'h8F;
                5'd15: pre_init_command = 8'hD9; // Pre-charge command.
                5'd16: pre_init_command = 8'hF1;
                5'd17: pre_init_command = 8'hDB; // VCOMH deselect level.
                5'd18: pre_init_command = 8'h40;
                5'd19: pre_init_command = 8'hA4; // Use display RAM.
                default: pre_init_command = 8'hA6; // Normal, not inverse.
            endcase
        end
    endfunction

    function automatic logic [7:0] fault_name_character(
        input logic [1:0] fault_name,
        input logic [4:0] position
    );
        begin
            fault_name_character = " ";
            case (fault_name)
                2'd1: begin // LRS
                    case (position)
                        3'd0: fault_name_character = "L";
                        3'd1: fault_name_character = "R";
                        3'd2: fault_name_character = "S";
                        default: fault_name_character = " ";
                    endcase
                end
                2'd2: begin // HRS
                    case (position)
                        3'd0: fault_name_character = "H";
                        3'd1: fault_name_character = "R";
                        3'd2: fault_name_character = "S";
                        default: fault_name_character = " ";
                    endcase
                end
                2'd3: begin // BOTH
                    case (position)
                        3'd0: fault_name_character = "B";
                        3'd1: fault_name_character = "O";
                        3'd2: fault_name_character = "T";
                        3'd3: fault_name_character = "H";
                        default: fault_name_character = " ";
                    endcase
                end
                default: begin // NONE
                    case (position)
                        3'd0: fault_name_character = "N";
                        3'd1: fault_name_character = "O";
                        3'd2: fault_name_character = "N";
                        3'd3: fault_name_character = "E";
                        default: fault_name_character = " ";
                    endcase
                end
            endcase
        end
    endfunction

    function automatic logic [7:0] result_name_character(
        input logic       is_busy,
        input logic       is_complete,
        input logic       is_pass,
        input logic [4:0] position
    );
        begin
            result_name_character = " ";
            if (is_busy) begin // RUN
                case (position)
                    3'd0: result_name_character = "R";
                    3'd1: result_name_character = "U";
                    3'd2: result_name_character = "N";
                    default: result_name_character = " ";
                endcase
            end else if (!is_complete) begin // READY
                case (position)
                    3'd0: result_name_character = "R";
                    3'd1: result_name_character = "E";
                    3'd2: result_name_character = "A";
                    3'd3: result_name_character = "D";
                    3'd4: result_name_character = "Y";
                    default: result_name_character = " ";
                endcase
            end else if (is_pass) begin // PASS
                case (position)
                    3'd0: result_name_character = "P";
                    3'd1: result_name_character = "A";
                    3'd2: result_name_character = "S";
                    3'd3: result_name_character = "S";
                    default: result_name_character = " ";
                endcase
            end else begin // FAIL
                case (position)
                    3'd0: result_name_character = "F";
                    3'd1: result_name_character = "A";
                    3'd2: result_name_character = "I";
                    3'd3: result_name_character = "L";
                    default: result_name_character = " ";
                endcase
            end
        end
    endfunction

    function automatic logic [7:0] resistance_digit_character(
        input logic [13:0] resistance_value,
        input logic [4:0]  digit_position
    );
        begin
            resistance_digit_character = "-";
            case (resistance_value)
                14'd100: begin
                    case (digit_position)
                        5'd0, 5'd1: resistance_digit_character = " ";
                        5'd2:       resistance_digit_character = "1";
                        5'd3, 5'd4: resistance_digit_character = "0";
                        default:    resistance_digit_character = " ";
                    endcase
                end

                14'd10000: begin
                    case (digit_position)
                        5'd0:       resistance_digit_character = "1";
                        5'd1, 5'd2,
                        5'd3, 5'd4: resistance_digit_character = "0";
                        default:    resistance_digit_character = " ";
                    endcase
                end

                default: resistance_digit_character = "-";
            endcase
        end
    endfunction

    function automatic logic [7:0] screen_character(
        input logic       show_details,
        input logic [1:0] screen_page,
        input logic [4:0] position,
        input logic       configured_fault_enable,
        input logic [1:0] configured_fault_mode,
        input logic [2:0] configured_fault_bit,
        input logic [1:0] configured_replica,
        input logic       bist_busy,
        input logic       bist_complete,
        input logic       detected_fault,
        input logic       detected_lrs,
        input logic       detected_hrs,
        input logic [7:0] corrected_word,
        input logic [13:0] detected_resistance
    );
        logic [1:0] shown_fault_name;
        logic       tmr_pass;
        begin
            screen_character = " ";
            tmr_pass = bist_complete && (corrected_word == 8'hFF);

            if (bist_complete && detected_fault) begin
                if (detected_lrs && detected_hrs)
                    shown_fault_name = 2'd3;
                else if (detected_lrs)
                    shown_fault_name = 2'd1;
                else if (detected_hrs)
                    shown_fault_name = 2'd2;
                else
                    shown_fault_name = 2'd0;
            end else if (bist_complete) begin
                shown_fault_name = 2'd0;
            end else if (configured_fault_enable) begin
                shown_fault_name = (configured_fault_mode == 2'b10) ? 2'd2 : 2'd1;
            end else begin
                shown_fault_name = 2'd0;
            end

            if (!show_details) begin
                case (screen_page)
                    2'd0: begin // "  CORRECTED OUTPUT"
                        case (position)
                            5'd2: screen_character = "C";
                            5'd3: screen_character = "O";
                            5'd4: screen_character = "R";
                            5'd5: screen_character = "R";
                            5'd6: screen_character = "E";
                            5'd7: screen_character = "C";
                            5'd8: screen_character = "T";
                            5'd9: screen_character = "E";
                            5'd10: screen_character = "D";
                            5'd12: screen_character = "O";
                            5'd13: screen_character = "U";
                            5'd14: screen_character = "T";
                            5'd15: screen_character = "P";
                            5'd16: screen_character = "U";
                            5'd17: screen_character = "T";
                            default: screen_character = " ";
                        endcase
                    end

                    2'd1: begin // "   BITS: 11111111"
                        case (position)
                            5'd3: screen_character = "B";
                            5'd4: screen_character = "I";
                            5'd5: screen_character = "T";
                            5'd6: screen_character = "S";
                            5'd7: screen_character = ":";
                            default: begin
                                if ((position >= 5'd9) && (position <= 5'd16))
                                    screen_character = corrected_word[5'd16 - position] ? "1" : "0";
                                else
                                    screen_character = " ";
                            end
                        endcase
                    end

                    2'd2: begin // BIST result.
                        case (position)
                            5'd4: screen_character = "B";
                            5'd5: screen_character = "I";
                            5'd6: screen_character = "S";
                            5'd7: screen_character = "T";
                            5'd8: screen_character = ":";
                            default: begin
                                if ((position >= 5'd10) && (position <= 5'd14))
                                    screen_character = result_name_character(
                                        bist_busy, bist_complete, bist_complete,
                                        position - 5'd10
                                    );
                                else
                                    screen_character = " ";
                            end
                        endcase
                    end

                    default: begin // "  LEDS: HEALTH MAP"
                        case (position)
                            5'd2: screen_character = "L";
                            5'd3: screen_character = "E";
                            5'd4: screen_character = "D";
                            5'd5: screen_character = "S";
                            5'd6: screen_character = ":";
                            5'd8: screen_character = "H";
                            5'd9: screen_character = "E";
                            5'd10: screen_character = "A";
                            5'd11: screen_character = "L";
                            5'd12: screen_character = "T";
                            5'd13: screen_character = "H";
                            5'd15: screen_character = "M";
                            5'd16: screen_character = "A";
                            5'd17: screen_character = "P";
                            default: screen_character = " ";
                        endcase
                    end
                endcase
            end else begin
                case (screen_page)
                    2'd0: begin // FAULT: type
                        case (position)
                            5'd2: screen_character = "F";
                            5'd3: screen_character = "A";
                            5'd4: screen_character = "U";
                            5'd5: screen_character = "L";
                            5'd6: screen_character = "T";
                            5'd7: screen_character = ":";
                            default: begin
                                if ((position >= 5'd9) && (position <= 5'd12))
                                    screen_character = fault_name_character(
                                        shown_fault_name, position - 5'd9
                                    );
                                else
                                    screen_character = " ";
                            end
                        endcase
                    end

                    2'd1: begin // BIT: n REP: A/B/C
                        case (position)
                            5'd2: screen_character = "B";
                            5'd3: screen_character = "I";
                            5'd4: screen_character = "T";
                            5'd5: screen_character = ":";
                            5'd7: screen_character = 8'h30 + {5'd0, configured_fault_bit};
                            5'd9: screen_character = "R";
                            5'd10: screen_character = "E";
                            5'd11: screen_character = "P";
                            5'd12: screen_character = ":";
                            5'd14: begin
                                case (configured_replica)
                                    2'd0: screen_character = "A";
                                    2'd1: screen_character = "B";
                                    2'd2: screen_character = "C";
                                    default: screen_character = "-";
                                endcase
                            end
                            default: screen_character = " ";
                        endcase
                    end

                    2'd2: begin // Detected resistance: "R:  100 OHM".
                        case (position)
                            5'd3: screen_character = "R";
                            5'd4: screen_character = ":";
                            5'd12: screen_character = "O";
                            5'd13: screen_character = "H";
                            5'd14: screen_character = "M";
                            default: begin
                                if ((position >= 5'd6) && (position <= 5'd10)) begin
                                    if (!(bist_complete && detected_fault))
                                        screen_character = "-";
                                    else
                                        screen_character = resistance_digit_character(
                                            detected_resistance, position - 5'd6
                                        );
                                end else begin
                                    screen_character = " ";
                                end
                            end
                        endcase
                    end

                    default: begin // "BIST:PASS TMR:PASS".
                        case (position)
                            5'd1: screen_character = "B";
                            5'd2: screen_character = "I";
                            5'd3: screen_character = "S";
                            5'd4: screen_character = "T";
                            5'd5: screen_character = ":";
                            5'd12: screen_character = "T";
                            5'd13: screen_character = "M";
                            5'd14: screen_character = "R";
                            5'd15: screen_character = ":";
                            default: begin
                                if ((position >= 5'd6) && (position <= 5'd10))
                                    screen_character = result_name_character(
                                        bist_busy, bist_complete, bist_complete,
                                        position - 5'd6
                                    );
                                else if ((position >= 5'd16) && (position <= 5'd20))
                                    screen_character = result_name_character(
                                        bist_busy, bist_complete, tmr_pass,
                                        position - 5'd16
                                    );
                                else
                                    screen_character = " ";
                            end
                        endcase
                    end
                endcase
            end
        end
    endfunction

    // Dedicated research screen used by the Q2 double-fault hardware top.
    // It displays the ordinary majority-voter result beside the proposed
    // diagnosis-guided result, making the improvement directly observable.
    function automatic logic [7:0] comparison_screen_character(
        input logic [1:0] compare_page,
        input logic [4:0] position,
        input logic [1:0] configured_fault_mode,
        input logic [2:0] configured_fault_bit,
        input logic [1:0] configured_pair,
        input logic       bist_busy,
        input logic       compare_complete,
        input logic       baseline_pass,
        input logic       adaptive_pass,
        input logic [7:0] baseline_word,
        input logic [7:0] adaptive_word
    );
        begin
            comparison_screen_character = " ";

            case (compare_page)
                2'd0: begin // " DOUBLE HRS FAULT"
                    case (position)
                        5'd1: comparison_screen_character = "D";
                        5'd2: comparison_screen_character = "O";
                        5'd3: comparison_screen_character = "U";
                        5'd4: comparison_screen_character = "B";
                        5'd5: comparison_screen_character = "L";
                        5'd6: comparison_screen_character = "E";
                        5'd12: comparison_screen_character = "F";
                        5'd13: comparison_screen_character = "A";
                        5'd14: comparison_screen_character = "U";
                        5'd15: comparison_screen_character = "L";
                        5'd16: comparison_screen_character = "T";
                        default: begin
                            if ((position >= 5'd8) && (position <= 5'd10))
                                comparison_screen_character = fault_name_character(
                                    (configured_fault_mode == 2'b10) ? 2'd2 : 2'd1,
                                    position - 5'd8
                                );
                            else
                                comparison_screen_character = " ";
                        end
                    endcase
                end

                2'd1: begin // " BIT:2 PAIR:A+B"
                    case (position)
                        5'd1: comparison_screen_character = "B";
                        5'd2: comparison_screen_character = "I";
                        5'd3: comparison_screen_character = "T";
                        5'd4: comparison_screen_character = ":";
                        5'd5: comparison_screen_character =
                            8'h30 + {5'd0, configured_fault_bit};
                        5'd7: comparison_screen_character = "P";
                        5'd8: comparison_screen_character = "A";
                        5'd9: comparison_screen_character = "I";
                        5'd10: comparison_screen_character = "R";
                        5'd11: comparison_screen_character = ":";
                        5'd12: begin
                            case (configured_pair)
                                2'd0, 2'd1: comparison_screen_character = "A";
                                2'd2:       comparison_screen_character = "B";
                                default:    comparison_screen_character = "-";
                            endcase
                        end
                        5'd13: comparison_screen_character = "+";
                        5'd14: begin
                            case (configured_pair)
                                2'd0:       comparison_screen_character = "B";
                                2'd1, 2'd2: comparison_screen_character = "C";
                                default:    comparison_screen_character = "-";
                            endcase
                        end
                        default: comparison_screen_character = " ";
                    endcase
                end

                2'd2: begin // " STD:FAIL NEW:PASS"
                    case (position)
                        5'd1: comparison_screen_character = "S";
                        5'd2: comparison_screen_character = "T";
                        5'd3: comparison_screen_character = "D";
                        5'd4: comparison_screen_character = ":";
                        5'd11: comparison_screen_character = "N";
                        5'd12: comparison_screen_character = "E";
                        5'd13: comparison_screen_character = "W";
                        5'd14: comparison_screen_character = ":";
                        default: begin
                            if ((position >= 5'd5) && (position <= 5'd9))
                                comparison_screen_character = result_name_character(
                                    bist_busy, compare_complete, baseline_pass,
                                    position - 5'd5
                                );
                            else if ((position >= 5'd15) && (position <= 5'd19))
                                comparison_screen_character = result_name_character(
                                    bist_busy, compare_complete, adaptive_pass,
                                    position - 5'd15
                                );
                            else
                                comparison_screen_character = " ";
                        end
                    endcase
                end

                default: begin // "S:xxxxxxxx N:xxxxxxxx"
                    case (position)
                        5'd0: comparison_screen_character = "S";
                        5'd1: comparison_screen_character = ":";
                        5'd11: comparison_screen_character = "N";
                        5'd12: comparison_screen_character = ":";
                        default: begin
                            if ((position >= 5'd2) && (position <= 5'd9))
                                comparison_screen_character =
                                    baseline_word[3'(5'd9 - position)] ? "1" : "0";
                            else if ((position >= 5'd13) && (position <= 5'd20))
                                comparison_screen_character =
                                    adaptive_word[3'(5'd20 - position)] ? "1" : "0";
                            else
                                comparison_screen_character = " ";
                        end
                    endcase
                end
            endcase
        end
    endfunction

    // Five columns per character. Bit 0 is the top OLED pixel in a page.
    function automatic logic [7:0] font_column(
        input logic [7:0] ascii_character,
        input logic [2:0] column_number
    );
        logic [39:0] glyph;
        begin
            case (ascii_character)
                "0": glyph = 40'h3E5149453E;
                "1": glyph = 40'h00427F4000;
                "2": glyph = 40'h4261514946;
                "3": glyph = 40'h2141454B31;
                "4": glyph = 40'h1814127F10;
                "5": glyph = 40'h2745454539;
                "6": glyph = 40'h3C4A494930;
                "7": glyph = 40'h0171090503;
                "8": glyph = 40'h3649494936;
                "9": glyph = 40'h064949291E;
                "A": glyph = 40'h7E1111117E;
                "B": glyph = 40'h7F49494936;
                "C": glyph = 40'h3E41414122;
                "D": glyph = 40'h7F4141221C;
                "E": glyph = 40'h7F49494941;
                "F": glyph = 40'h7F09090901;
                "G": glyph = 40'h3E4149497A;
                "H": glyph = 40'h7F0808087F;
                "I": glyph = 40'h00417F4100;
                "L": glyph = 40'h7F40404040;
                "M": glyph = 40'h7F020C027F;
                "N": glyph = 40'h7F0408107F;
                "O": glyph = 40'h3E4141413E;
                "P": glyph = 40'h7F09090906;
                "R": glyph = 40'h7F09192946;
                "S": glyph = 40'h4649494931;
                "T": glyph = 40'h01017F0101;
                "U": glyph = 40'h3F4040403F;
                "Y": glyph = 40'h0708700807;
                ":": glyph = 40'h0036360000;
                "-": glyph = 40'h0808080808;
                default: glyph = 40'h0000000000;
            endcase

            case (column_number)
                3'd0: font_column = glyph[39:32];
                3'd1: font_column = glyph[31:24];
                3'd2: font_column = glyph[23:16];
                3'd3: font_column = glyph[15:8];
                3'd4: font_column = glyph[7:0];
                default: font_column = 8'h00;
            endcase
        end
    endfunction

    always_comb begin
        if (comparison_mode && detail_mode) begin
            displayed_character = comparison_screen_character(
                page,
                character_index,
                fault_mode,
                fault_bit_address,
                fault_pair,
                busy,
                comparison_ready,
                standard_pass,
                proposed_pass,
                standard_data,
                corrected_data
            );
        end else begin
            displayed_character = screen_character(
                detail_mode,
                page,
                character_index,
                fault_enable,
                fault_mode,
                fault_bit_address,
                fault_replica,
                busy,
                test_complete,
                fault_found,
                lrs_found,
                hrs_found,
                corrected_data,
                detected_resistance_ohms
            );
        end

        if (glyph_column_index < 3'd5)
            pixel_data = font_column(displayed_character, glyph_column_index);
        else
            pixel_data = 8'h00;
    end

    oled_spi_byte #(
        .HALF_PERIOD_CYCLES(SPI_HALF_PERIOD_CYCLES)
    ) spi_transmitter (
        .clk   (clk),
        .reset (reset),
        .start (spi_start),
        .data  (spi_data),
        .busy  (spi_busy),
        .done  (spi_done),
        .sclk  (OLED_SCLK),
        .sdin  (OLED_SDIN)
    );

    always_ff @(posedge clk) begin
        if (reset) begin
            state                 <= ST_POWER_VDD;
            delay_counter         <= 32'd0;
            pre_command_index     <= 5'd0;
            page                  <= 2'd0;
            pixel_column          <= 7'd0;
            page_command_index    <= 2'd0;
            character_index       <= 5'd0;
            glyph_column_index    <= 3'd0;
            shutdown_requested    <= 1'b0;
            initial_clear         <= 1'b0;
            spi_start             <= 1'b0;
            spi_data              <= 8'h00;
            oled_on               <= 1'b0;
            OLED_DC               <= 1'b0;
            OLED_RES              <= 1'b0;
            OLED_VBAT             <= 1'b1;
            OLED_VDD              <= 1'b1;
        end else begin
            spi_start <= 1'b0;

            if (toggle_power && oled_on)
                shutdown_requested <= 1'b1;

            case (state)
                ST_POWER_VDD: begin
                    OLED_DC            <= 1'b0;
                    OLED_RES           <= 1'b1;
                    OLED_VBAT          <= 1'b1;
                    OLED_VDD           <= 1'b0;
                    oled_on            <= 1'b0;
                    shutdown_requested <= 1'b0;
                    initial_clear      <= 1'b0;
                    delay_counter      <= delay_seed(VDD_CYCLES);
                    state              <= ST_WAIT_VDD;
                end

                ST_WAIT_VDD: begin
                    if (delay_counter == 0)
                        state <= ST_RESET_LOW;
                    else
                        delay_counter <= delay_counter - 1'b1;
                end

                ST_SEND_OFF: begin
                    if (!spi_busy) begin
                        OLED_DC   <= 1'b0;
                        spi_data  <= 8'hAE;
                        spi_start <= 1'b1;
                        state     <= ST_WAIT_OFF;
                    end
                end

                ST_WAIT_OFF: begin
                    if (spi_done) begin
                        pre_command_index <= 5'd0;
                        state <= ST_SEND_PRE;
                    end
                end

                ST_RESET_LOW: begin
                    OLED_RES      <= 1'b0;
                    delay_counter <= delay_seed(RESET_CYCLES);
                    state         <= ST_WAIT_RESET_LOW;
                end

                ST_WAIT_RESET_LOW: begin
                    if (delay_counter == 0)
                        state <= ST_RESET_HIGH;
                    else
                        delay_counter <= delay_counter - 1'b1;
                end

                ST_RESET_HIGH: begin
                    OLED_RES         <= 1'b1;
                    delay_counter    <= delay_seed(RESET_CYCLES);
                    state            <= ST_WAIT_RESET_HIGH;
                end

                ST_WAIT_RESET_HIGH: begin
                    if (delay_counter == 0)
                        state <= ST_SEND_OFF;
                    else
                        delay_counter <= delay_counter - 1'b1;
                end

                ST_SEND_PRE: begin
                    if (!spi_busy) begin
                        OLED_DC   <= 1'b0;
                        spi_data  <= pre_init_command(pre_command_index);
                        spi_start <= 1'b1;
                        state     <= ST_WAIT_PRE;
                    end
                end

                ST_WAIT_PRE: begin
                    if (spi_done) begin
                        if (pre_command_index == 5'd20) begin
                            // The panel datasheet requires clearing RAM before
                            // enabling the high-voltage OLED supply.
                            initial_clear         <= 1'b1;
                            page                  <= 2'd0;
                            pixel_column          <= 7'd0;
                            page_command_index    <= 2'd0;
                            character_index       <= 5'd0;
                            glyph_column_index    <= 3'd0;
                            state                 <= ST_SEND_PAGE;
                        end
                        else begin
                            pre_command_index <= pre_command_index + 1'b1;
                            state <= ST_SEND_PRE;
                        end
                    end
                end

                ST_POWER_VBAT: begin
                    OLED_VBAT     <= 1'b0;
                    delay_counter <= delay_seed(VBAT_CYCLES);
                    state         <= ST_WAIT_VBAT;
                end

                ST_WAIT_VBAT: begin
                    if (delay_counter == 0)
                        state <= ST_SEND_POST;
                    else
                        delay_counter <= delay_counter - 1'b1;
                end

                ST_SEND_POST: begin
                    if (!spi_busy) begin
                        OLED_DC   <= 1'b0;
                        spi_data  <= 8'hAF;
                        spi_start <= 1'b1;
                        state     <= ST_WAIT_POST;
                    end
                end

                ST_WAIT_POST: begin
                    if (spi_done) begin
                        oled_on            <= 1'b1;
                        page               <= 2'd0;
                        pixel_column       <= 7'd0;
                        page_command_index <= 2'd0;
                        character_index    <= 5'd0;
                        glyph_column_index <= 3'd0;
                        state              <= ST_SEND_PAGE;
                    end
                end

                ST_SEND_PAGE: begin
                    if (!spi_busy) begin
                        OLED_DC <= 1'b0;
                        case (page_command_index)
                            2'd0: spi_data <= 8'hB0 | {6'b000000, page};
                            2'd1: spi_data <= 8'h00;
                            default: spi_data <= 8'h10;
                        endcase
                        spi_start <= 1'b1;
                        state <= ST_WAIT_PAGE;
                    end
                end

                ST_WAIT_PAGE: begin
                    if (spi_done) begin
                        if (page_command_index == 2'd2) begin
                            pixel_column       <= 7'd0;
                            character_index    <= 5'd0;
                            glyph_column_index <= 3'd0;
                            state              <= ST_SEND_PIXEL;
                        end else begin
                            page_command_index <= page_command_index + 1'b1;
                            state <= ST_SEND_PAGE;
                        end
                    end
                end

                ST_SEND_PIXEL: begin
                    if (!spi_busy) begin
                        OLED_DC   <= 1'b1;
                        spi_data  <= initial_clear ? 8'h00 : pixel_data;
                        spi_start <= 1'b1;
                        state     <= ST_WAIT_PIXEL;
                    end
                end

                ST_WAIT_PIXEL: begin
                    if (spi_done) begin
                        if (shutdown_requested || toggle_power) begin
                            shutdown_requested <= 1'b0;
                            oled_on            <= 1'b0;
                            state              <= ST_SHUTDOWN_OFF;
                        end else if (pixel_column == 7'd127) begin
                            pixel_column       <= 7'd0;
                            character_index    <= 5'd0;
                            glyph_column_index <= 3'd0;
                            page_command_index <= 2'd0;
                            if (page == 2'd3) begin
                                page <= 2'd0;
                                if (initial_clear) begin
                                    initial_clear <= 1'b0;
                                    state <= ST_POWER_VBAT;
                                end else begin
                                    state <= ST_SEND_PAGE;
                                end
                            end else begin
                                page <= page + 1'b1;
                                state <= ST_SEND_PAGE;
                            end
                        end else begin
                            pixel_column <= pixel_column + 1'b1;
                            if (glyph_column_index == 3'd5) begin
                                glyph_column_index <= 3'd0;
                                character_index <= character_index + 1'b1;
                            end else begin
                                glyph_column_index <= glyph_column_index + 1'b1;
                            end
                            state <= ST_SEND_PIXEL;
                        end
                    end
                end

                ST_SHUTDOWN_OFF: begin
                    if (!spi_busy) begin
                        OLED_DC   <= 1'b0;
                        spi_data  <= 8'hAE;
                        spi_start <= 1'b1;
                        state     <= ST_WAIT_SHUT_OFF;
                    end
                end

                ST_WAIT_SHUT_OFF: begin
                    if (spi_done)
                        state <= ST_SHUTDOWN_VBAT;
                end

                ST_SHUTDOWN_VBAT: begin
                    // Power off panel voltage first, then wait for discharge.
                    OLED_VBAT       <= 1'b1;
                    delay_counter   <= delay_seed(OFF_CYCLES);
                    state           <= ST_WAIT_SHUT_VBAT;
                end

                ST_WAIT_SHUT_VBAT: begin
                    if (delay_counter == 0)
                        state <= ST_SHUTDOWN_VDD;
                    else
                        delay_counter <= delay_counter - 1'b1;
                end

                ST_SHUTDOWN_VDD: begin
                    OLED_VDD <= 1'b1;
                    OLED_RES <= 1'b0;
                    state    <= ST_POWERED_OFF;
                end

                ST_POWERED_OFF: begin
                    OLED_DC   <= 1'b0;
                    OLED_VBAT <= 1'b1;
                    OLED_VDD  <= 1'b1;
                    oled_on   <= 1'b0;
                    if (toggle_power)
                        state <= ST_POWER_VDD;
                end

                default: state <= ST_POWER_VDD;
            endcase
        end
    end

endmodule


// SPI mode 0 byte transmitter: data is changed while SCLK is low and sampled
// by the OLED on each rising edge. The ZedBoard ties OLED chip-select low.
module oled_spi_byte #(
    parameter integer HALF_PERIOD_CYCLES = 10
) (
    input  logic       clk,
    input  logic       reset,
    input  logic       start,
    input  logic [7:0] data,
    output logic       busy,
    output logic       done,
    output logic       sclk = 1'b0,
    output logic       sdin = 1'b0
);

    logic [7:0]  shift_register;
    logic [2:0]  bit_index;
    logic [31:0] divider_counter;

    always_ff @(posedge clk) begin
        if (reset) begin
            shift_register <= 8'h00;
            bit_index       <= 3'd7;
            divider_counter <= 32'd0;
            busy            <= 1'b0;
            done            <= 1'b0;
            sclk            <= 1'b0;
            sdin            <= 1'b0;
        end else begin
            done <= 1'b0;

            if (!busy) begin
                sclk <= 1'b0;
                if (start) begin
                    shift_register <= data;
                    bit_index       <= 3'd7;
                    divider_counter <= (HALF_PERIOD_CYCLES > 0) ?
                                       HALF_PERIOD_CYCLES - 1 : 0;
                    sdin            <= data[7];
                    busy            <= 1'b1;
                end
            end else if (divider_counter != 0) begin
                divider_counter <= divider_counter - 1'b1;
            end else begin
                divider_counter <= (HALF_PERIOD_CYCLES > 0) ?
                                   HALF_PERIOD_CYCLES - 1 : 0;

                if (!sclk) begin
                    sclk <= 1'b1;
                end else begin
                    sclk <= 1'b0;
                    if (bit_index == 0) begin
                        busy <= 1'b0;
                        done <= 1'b1;
                        sdin <= 1'b0;
                    end else begin
                        bit_index <= bit_index - 1'b1;
                        sdin <= shift_register[bit_index - 1'b1];
                    end
                end
            end
        end
    end

endmodule
