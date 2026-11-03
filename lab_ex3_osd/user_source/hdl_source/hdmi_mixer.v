module hdmi_mixer #(
    parameter H_OFFSET = 128,
    parameter V_OFFSET = 60,
    parameter IMG_WIDTH = 1280,
    parameter IMG_HEIGHT = 720,
    parameter integer DEBUG_MODE = 0
)(
    input wire        I_clk,
    input wire        I_rst_n,

    input wire        I_video_vsync,
    input wire        I_video_hsync,
    input wire        I_video_de,

    input wire        I_rd_en,
    input wire        I_video_user,
    input wire        I_video_last,

    input wire[3:0]   I_debug_status,

    input wire[23:0]  I_bcd_cnt,
    input wire[23:0]  I_bcd_amp,
    input wire[23:0]  I_bcd_pix,
    input wire[23:0]  I_bcd_raw,
    input wire[11:0]  I_speed_bcd,

    input wire[8:0]   I_bb_x0,
    input wire[8:0]   I_bb_x1,
    input wire[7:0]   I_bb_y0,
    input wire[7:0]   I_bb_y1,
    input wire[7:0]   I_cx,
    input wire[6:0]   I_cy,

    input wire        I_row_valid,
    input wire[6:0]   I_row_idx,
    input wire[7:0]   I_row_min,
    input wire[7:0]   I_row_max,

    input wire        I_contour_sel,

    input wire        I_contour_en,

    input wire[7:0]   I_line_up,
    input wire[7:0]   I_line_dn,

    input wire[2:0]   I_sport_mode,

    input wire[3:0]   I_disp_mode,

    input wire[3:0]   I_lat_frames,

    input wire        I_dyn_osd_en,

    input wire        I_lat_en,

    input wire        I_tgt_valid,
    input wire [8:0]  I_tgt_x0, I_tgt_x1,
    input wire [7:0]  I_tgt_y0, I_tgt_y1,

    input wire        I_osd_full,

    input wire [1:0]  I_ae_mode,

    input wire        I_gimbal_on,
    input wire [23:0] I_bcd_cx,
    input wire [23:0] I_bcd_cy,
    input wire [3:0]  I_pwm_h,
    input wire [3:0]  I_pwm_t,
    input wire [3:0]  I_pwm_o,
    input wire [3:0]  I_ang_h,
    input wire [3:0]  I_ang_t,
    input wire [3:0]  I_ang_o,

    input wire        I_extra_en,

    output wire       O_video_rd_en,
    input wire[23:0]  I_video_rd_data,

    output reg        O_hdmi_vsync,
    output reg        O_hdmi_hsync,
    output reg        O_hdmi_de,
    output reg[23:0]  O_hdmi_data
);

    reg        S_video_vsync_1d;
    reg        S_video_vsync_2d;
    reg        S_video_hsync_1d;
    reg        S_video_hsync_2d;
    reg        S_video_de_1d;
    reg        S_video_de_2d;
    reg [23:0] S_video_data_1d;
    reg [23:0] S_video_data_2d;
    reg [11:0] S_x;
    reg [11:0] S_y;
    reg [11:0] S_x_1d;
    reg [11:0] S_x_2d;

    reg [11:0] S_x_2d_b1, S_x_2d_b2;
    reg [11:0] S_y_2d_b1, S_y_2d_b2;
    reg [11:0] S_y_1d;
    reg [11:0] S_y_2d;

    reg        S_osd_hit;
    reg [23:0] S_osd_color;
    reg        S_logo_in_r;
    reg        S_logo_in_r2;

    reg [3:0]  S_char_idx;
    reg [2:0]  S_char_row;
    reg [2:0]  S_char_col;
    reg [4:0]  S_char_bits;
    reg        S_char_on;
    reg        S_logo_blue_on;
    reg        S_logo_red_on;
    reg [11:0] S_logo_tmp_y;
    reg [3:0]  S_logo_red_band;
    reg [11:0] S_logo_red_x_start;
    reg [11:0] S_logo_red_x_end;
    reg [14:0] S_logo_addr;

    wire[16:0] S_logo_pixel;
    reg [11:0] S_dyn_x;
    reg [11:0] S_dyn_y;

    reg [6:0]  S_mode_lx;
    reg [6:0]  S_mode_ly;
    reg [7:0]  S_mode_char;
    reg [3:0]  S_dyn_line;
    reg [23:0] S_dyn_bcd;

    wire        W_is_run     = (I_sport_mode == 3'd5);

    wire [3:0]  W_src_line   = I_osd_full ? S_dyn_line :
                               (S_dyn_line == 4'd0) ? 4'd6 :
                               (S_dyn_line == 4'd1) ? 4'd5 :
                               (S_dyn_line == 4'd2) ? 4'd4 : 4'd15;
    wire        W_row_valid  = I_osd_full ? (S_dyn_line <= (I_gimbal_on ? 4'd9 : 4'd6))
                                          : (S_dyn_line <= 4'd2);

    wire [3:0]  W_lbl_sel    = (W_src_line == 4'd4) ? 4'd5
                                                    : (W_src_line == 4'd5) ? 4'd6
                                                    : (W_src_line == 4'd6) ? 4'd7
                                                    : (W_src_line == 4'd7) ? 4'd8
                                                    : (W_src_line == 4'd8) ? 4'd9
                                                    : (W_src_line == 4'd9) ? 4'd10
                                                    : (W_is_run && (W_src_line == 4'd3)) ? 4'd4
                                                                : W_src_line;

    wire [3:0]  W_mode_tens  = (I_disp_mode >= 4'd10) ? 4'd1 : 4'd0;
    wire [3:0]  W_mode_ones  = (I_disp_mode >= 4'd10) ? (I_disp_mode - 4'd10) : I_disp_mode;

    wire [3:0]  W_lat_tens   = (I_lat_frames >= 4'd10) ? 4'd1 : 4'd0;
    wire [3:0]  W_lat_ones   = (I_lat_frames >= 4'd10) ? (I_lat_frames - 4'd10) : I_lat_frames;

    wire        W_hide_digit = ((W_is_run && (S_dyn_line == 4'd3)) || (S_dyn_line == 4'd4)) &&
                               (S_dyn_digit_idx <= 4'd3);
    reg [3:0]  S_dyn_char;
    reg [2:0]  S_dyn_col;
    reg [2:0]  S_dyn_row;
    reg [4:0]  S_dyn_bits;
    reg        S_dyn_on;
    reg [3:0]  S_dyn_digit_idx;
    reg [11:0] S_dyn_digit_x;
    reg [6:0]  S_dyn_seg;
    reg [2:0]  S_lbl_row;
    reg [2:0]  S_lbl_col;
    reg [1:0]  S_lbl_idx;
    reg [4:0]  S_lbl_bits;
    reg [6:0]  S_lbl_local_x;
    reg [3:0]  S_dyn_dec_digit;
    reg [4:0]  S_cn_local_x;
    reg [4:0]  S_cn_local_y;
    reg [3:0]  S_cn_col;
    reg [3:0]  S_cn_row;
    reg [15:0] S_cn_row_bits;
    reg        S_cn_on;
    reg [9:0]  S_cn_scale_x;
    reg [9:0]  S_cn_scale_y;
    reg [7:0]  S_pf_char;
    reg [4:0]  S_pf_local_x;
    reg [4:0]  S_pf_local_y;
    reg [3:0]  S_pf_col;
    reg [3:0]  S_pf_row;
    wire [15:0] S_pf_row_bits;
    reg        S_pf_on;
    reg [9:0]  S_pf_scale_x;
    reg [9:0]  S_pf_scale_y;

    reg [7:0]  A_pf_char;
    reg [3:0]  A_pf_col;
    reg [3:0]  A_pf_row;
    reg        A_pf_ena;
    reg [23:0] A_pf_color;
    reg        A_logo_hit;
    reg [23:0] A_logo_color;
    reg        A_graph_hit;
    reg [23:0] A_graph_color;
    reg        A_tgt_hit;
    reg        A_line_hit;
    reg [23:0] A_line_color;
    reg        A_dot_hit;

    reg [7:0]  B_pf_char_q;
    reg [3:0]  B_pf_col_q;
    reg [3:0]  B_pf_row_q;
    reg        B_pf_ena_q;
    reg [23:0] B_pf_color_q;
    reg        B_logo_hit_q;
    reg [23:0] B_logo_color_q;
    reg        B_graph_hit_q;
    reg [23:0] B_graph_color_q;
    reg        B_tgt_hit_q;
    reg        B_line_hit_q;
    reg [23:0] B_line_color_q;
    reg        B_dot_hit_q;

    localparam LOGO_X = 12'd0;
    localparam LOGO_Y = 12'd0;
    localparam LOGO_W = 12'd160;
    localparam LOGO_H = 12'd160;

    localparam COLOR_LOGO_BLUE   = 24'h1f315c;
    localparam COLOR_LOGO_RED    = 24'hec1c2d;
    localparam COLOR_TEXT        = 24'h00e6ff;

    localparam DYN_OSD_X         = 12'd0;
    localparam DYN_OSD_Y         = 12'd168;
    localparam DYN_OSD_W         = 12'd200;
    localparam DYN_OSD_H         = 12'd320;
    localparam CN_Y_OFFSET       = 12'd2;
    localparam COLOR_DYN_TEXT    = 24'hfff200;
    localparam COLOR_BBOX        = 24'h00ff40;
    localparam COLOR_CROSS       = 24'hff2020;
    localparam COLOR_TGT         = 24'hff8000;
    localparam COLOR_CONTOUR     = 24'hff30ff;
    localparam COLOR_LINE_UP     = 24'h00ffff;
    localparam COLOR_LINE_DN     = 24'hff8000;

    localparam COLOR_MODE_TXT    = 24'hffffff;
    localparam MODE_X            = 12'd1000;
    localparam MODE_Y            = 12'd40;
    localparam MODE_W            = 12'd64;
    localparam MODE_H            = 12'd64;
    localparam CHAR_AN           = 8'h80;
    localparam CHAR_LU           = 8'h81;

    localparam CHAR_A            = 8'h41;

    localparam CHAR_L            = 8'h4c;
    localparam CHAR_C            = 8'h43;
    localparam CHAR_I            = 8'h49;
    localparam CHAR_M            = 8'h4d;
    localparam CHAR_N            = 8'h4e;
    localparam CHAR_O            = 8'h4f;
    localparam CHAR_P            = 8'h50;
    localparam CHAR_R            = 8'h52;
    localparam CHAR_T            = 8'h54;
    localparam CHAR_W            = 8'h57;
    localparam CHAR_X            = 8'h58;

    localparam CHAR_E            = 8'h45;
    localparam CHAR_H            = 8'h48;
    localparam CHAR_U            = 8'h55;

    localparam CHAR_G            = 8'h47;
    localparam CHAR_0            = 8'h30;
    localparam CHAR_COLON        = 8'h3a;

    localparam CHAR_J            = 8'h4a;
    localparam CHAR_B            = 8'h42;
    localparam CHAR_D            = 8'h44;
    localparam CHAR_S            = 8'h53;

    function [7:0] F_lbl_char;
        input [3:0] sel;
        input [1:0] pos;
        begin
            case (sel)
                2'd0:    F_lbl_char = (pos == 2'd0) ? CHAR_C :
                                      (pos == 2'd1) ? CHAR_N : CHAR_T;
                2'd1:    F_lbl_char = (pos == 2'd0) ? CHAR_A :
                                      (pos == 2'd1) ? CHAR_M : CHAR_P;
                2'd2:    F_lbl_char = (pos == 2'd0) ? CHAR_P :
                                      (pos == 2'd1) ? CHAR_I : CHAR_X;
                3'd3:    F_lbl_char = (pos == 2'd0) ? CHAR_R :
                                      (pos == 2'd1) ? CHAR_A : CHAR_W;
                3'd4:    F_lbl_char = (pos == 2'd0) ? CHAR_S :
                                      (pos == 2'd1) ? CHAR_P : CHAR_D;

                3'd5:    F_lbl_char = (pos == 2'd0) ? CHAR_M :
                                      (pos == 2'd1) ? CHAR_O : CHAR_D;

                3'd6:    F_lbl_char = (pos == 2'd0) ? CHAR_L :
                                      (pos == 2'd1) ? CHAR_A : CHAR_T;

                3'd7:    F_lbl_char = (pos == 2'd0) ? CHAR_E :
                                      (pos == 2'd1) ? CHAR_X : CHAR_P;

                4'd8:    F_lbl_char = (pos == 2'd0) ? CHAR_P :
                                      (pos == 2'd1) ? CHAR_O : CHAR_S;
                4'd9:    F_lbl_char = (pos == 2'd0) ? CHAR_P :
                                      (pos == 2'd1) ? CHAR_W : CHAR_M;
                4'd10:   F_lbl_char = (pos == 2'd0) ? CHAR_A :
                                      (pos == 2'd1) ? CHAR_N : CHAR_G;
                default: F_lbl_char = (pos == 2'd0) ? CHAR_C :
                                      (pos == 2'd1) ? CHAR_N : CHAR_T;
            endcase
        end
    endfunction

    function [4:0] F_logo_text_bits;
        input [3:0] I_char;
        input [2:0] I_row;
        begin
            case(I_char)
                4'd0: begin
                    case(I_row)
                        3'd0: F_logo_text_bits = 5'b01110;
                        3'd1: F_logo_text_bits = 5'b10001;
                        3'd2: F_logo_text_bits = 5'b10001;
                        3'd3: F_logo_text_bits = 5'b11111;
                        3'd4: F_logo_text_bits = 5'b10001;
                        3'd5: F_logo_text_bits = 5'b10001;
                        3'd6: F_logo_text_bits = 5'b10001;
                        default: F_logo_text_bits = 5'b00000;
                    endcase
                end
                4'd1: begin
                    case(I_row)
                        3'd0: F_logo_text_bits = 5'b10001;
                        3'd1: F_logo_text_bits = 5'b11001;
                        3'd2: F_logo_text_bits = 5'b10101;
                        3'd3: F_logo_text_bits = 5'b10011;
                        3'd4: F_logo_text_bits = 5'b10001;
                        3'd5: F_logo_text_bits = 5'b10001;
                        3'd6: F_logo_text_bits = 5'b10001;
                        default: F_logo_text_bits = 5'b00000;
                    endcase
                end
                4'd2: begin
                    case(I_row)
                        3'd0: F_logo_text_bits = 5'b10000;
                        3'd1: F_logo_text_bits = 5'b10000;
                        3'd2: F_logo_text_bits = 5'b10000;
                        3'd3: F_logo_text_bits = 5'b10000;
                        3'd4: F_logo_text_bits = 5'b10000;
                        3'd5: F_logo_text_bits = 5'b10000;
                        3'd6: F_logo_text_bits = 5'b11111;
                        default: F_logo_text_bits = 5'b00000;
                    endcase
                end
                4'd3: begin
                    case(I_row)
                        3'd0: F_logo_text_bits = 5'b01110;
                        3'd1: F_logo_text_bits = 5'b10001;
                        3'd2: F_logo_text_bits = 5'b10001;
                        3'd3: F_logo_text_bits = 5'b10001;
                        3'd4: F_logo_text_bits = 5'b10001;
                        3'd5: F_logo_text_bits = 5'b10001;
                        3'd6: F_logo_text_bits = 5'b01110;
                        default: F_logo_text_bits = 5'b00000;
                    endcase
                end
                4'd4: begin
                    case(I_row)
                        3'd0: F_logo_text_bits = 5'b01110;
                        3'd1: F_logo_text_bits = 5'b10001;
                        3'd2: F_logo_text_bits = 5'b10000;
                        3'd3: F_logo_text_bits = 5'b10111;
                        3'd4: F_logo_text_bits = 5'b10001;
                        3'd5: F_logo_text_bits = 5'b10001;
                        3'd6: F_logo_text_bits = 5'b01110;
                        default: F_logo_text_bits = 5'b00000;
                    endcase
                end
                4'd5: begin
                    case(I_row)
                        3'd0: F_logo_text_bits = 5'b11111;
                        3'd1: F_logo_text_bits = 5'b00100;
                        3'd2: F_logo_text_bits = 5'b00100;
                        3'd3: F_logo_text_bits = 5'b00100;
                        3'd4: F_logo_text_bits = 5'b00100;
                        3'd5: F_logo_text_bits = 5'b00100;
                        3'd6: F_logo_text_bits = 5'b11111;
                        default: F_logo_text_bits = 5'b00000;
                    endcase
                end
                4'd6: begin
                    case(I_row)
                        3'd0: F_logo_text_bits = 5'b01110;
                        3'd1: F_logo_text_bits = 5'b10001;
                        3'd2: F_logo_text_bits = 5'b10000;
                        3'd3: F_logo_text_bits = 5'b10000;
                        3'd4: F_logo_text_bits = 5'b10000;
                        3'd5: F_logo_text_bits = 5'b10001;
                        3'd6: F_logo_text_bits = 5'b01110;
                        default: F_logo_text_bits = 5'b00000;
                    endcase
                end
                default: F_logo_text_bits = 5'b00000;
            endcase
        end
    endfunction

    function [6:0] F_hex7seg;
        input [3:0] I_hex;
        begin
            case(I_hex)
                4'h0: F_hex7seg = 7'b1111110;
                4'h1: F_hex7seg = 7'b0110000;
                4'h2: F_hex7seg = 7'b1101101;
                4'h3: F_hex7seg = 7'b1111001;
                4'h4: F_hex7seg = 7'b0110011;
                4'h5: F_hex7seg = 7'b1011011;
                4'h6: F_hex7seg = 7'b1011111;
                4'h7: F_hex7seg = 7'b1110000;
                4'h8: F_hex7seg = 7'b1111111;
                4'h9: F_hex7seg = 7'b1111011;
                4'ha: F_hex7seg = 7'b1110111;
                4'hb: F_hex7seg = 7'b0011111;
                4'hc: F_hex7seg = 7'b1001110;
                4'hd: F_hex7seg = 7'b0111101;
                4'he: F_hex7seg = 7'b1001111;
                4'hf: F_hex7seg = 7'b1000111;
                default: F_hex7seg = 7'b0000000;
            endcase
        end
    endfunction

    function [4:0] F_cnt_label_bits;
        input [1:0] I_idx;
        input [2:0] I_row;
        begin
            case(I_idx)
                2'd0: begin
                    case(I_row)
                        3'd0: F_cnt_label_bits = 5'b01110;
                        3'd1: F_cnt_label_bits = 5'b10001;
                        3'd2: F_cnt_label_bits = 5'b10000;
                        3'd3: F_cnt_label_bits = 5'b10000;
                        3'd4: F_cnt_label_bits = 5'b10000;
                        3'd5: F_cnt_label_bits = 5'b10001;
                        3'd6: F_cnt_label_bits = 5'b01110;
                        default: F_cnt_label_bits = 5'b00000;
                    endcase
                end
                2'd1: begin
                    case(I_row)
                        3'd0: F_cnt_label_bits = 5'b10001;
                        3'd1: F_cnt_label_bits = 5'b11001;
                        3'd2: F_cnt_label_bits = 5'b10101;
                        3'd3: F_cnt_label_bits = 5'b10011;
                        3'd4: F_cnt_label_bits = 5'b10001;
                        3'd5: F_cnt_label_bits = 5'b10001;
                        3'd6: F_cnt_label_bits = 5'b10001;
                        default: F_cnt_label_bits = 5'b00000;
                    endcase
                end
                2'd2: begin
                    case(I_row)
                        3'd0: F_cnt_label_bits = 5'b11111;
                        3'd1: F_cnt_label_bits = 5'b00100;
                        3'd2: F_cnt_label_bits = 5'b00100;
                        3'd3: F_cnt_label_bits = 5'b00100;
                        3'd4: F_cnt_label_bits = 5'b00100;
                        3'd5: F_cnt_label_bits = 5'b00100;
                        3'd6: F_cnt_label_bits = 5'b00100;
                        default: F_cnt_label_bits = 5'b00000;
                    endcase
                end
                default: begin
                    case(I_row)
                        3'd2: F_cnt_label_bits = 5'b00100;
                        3'd5: F_cnt_label_bits = 5'b00100;
                        default: F_cnt_label_bits = 5'b00000;
                    endcase
                end
            endcase
        end
    endfunction

    function [15:0] F_cn16_row;
        input I_char;
        input [3:0] I_row;
        begin
            if(!I_char) begin
                case(I_row)
                    4'd0:  F_cn16_row = 16'h0200;
                    4'd1:  F_cn16_row = 16'h7ff0;
                    4'd2:  F_cn16_row = 16'h4410;
                    4'd3:  F_cn16_row = 16'h0400;
                    4'd4:  F_cn16_row = 16'h7ff0;
                    4'd5:  F_cn16_row = 16'h0840;
                    4'd6:  F_cn16_row = 16'h1040;
                    4'd7:  F_cn16_row = 16'h1c80;
                    4'd8:  F_cn16_row = 16'h0300;
                    4'd9:  F_cn16_row = 16'h0cc0;
                    4'd10: F_cn16_row = 16'h7020;
                    4'd11: F_cn16_row = 16'h0000;
                    4'd12: F_cn16_row = 16'h0000;
                    4'd13: F_cn16_row = 16'h0000;
                    4'd14: F_cn16_row = 16'h0000;
                    4'd15: F_cn16_row = 16'h0000;
                    default: F_cn16_row = 16'h0000;
                endcase
            end
            else begin
                case(I_row)
                    4'd0:  F_cn16_row = 16'h79e0;
                    4'd1:  F_cn16_row = 16'h4a20;
                    4'd2:  F_cn16_row = 16'h4d40;
                    4'd3:  F_cn16_row = 16'h7880;
                    4'd4:  F_cn16_row = 16'h1140;
                    4'd5:  F_cn16_row = 16'h1630;
                    4'd6:  F_cn16_row = 16'h5be0;
                    4'd7:  F_cn16_row = 16'h5220;
                    4'd8:  F_cn16_row = 16'h5220;
                    4'd9:  F_cn16_row = 16'h5be0;
                    4'd10: F_cn16_row = 16'h6220;
                    4'd11: F_cn16_row = 16'h0000;
                    4'd12: F_cn16_row = 16'h0000;
                    4'd13: F_cn16_row = 16'h0000;
                    4'd14: F_cn16_row = 16'h0000;
                    4'd15: F_cn16_row = 16'h0000;
                    default: F_cn16_row = 16'h0000;
                endcase
            end
        end
    endfunction

    function [4:0] F_dyn_char_bits;
        input [3:0] I_char;
        input [2:0] I_row;
        begin
            case(I_char)
                4'h0: begin case(I_row) 3'd0:F_dyn_char_bits=5'b01110; 3'd1:F_dyn_char_bits=5'b10001; 3'd2:F_dyn_char_bits=5'b10011; 3'd3:F_dyn_char_bits=5'b10101; 3'd4:F_dyn_char_bits=5'b11001; 3'd5:F_dyn_char_bits=5'b10001; 3'd6:F_dyn_char_bits=5'b01110; default:F_dyn_char_bits=5'b00000; endcase end
                4'h1: begin case(I_row) 3'd0:F_dyn_char_bits=5'b00100; 3'd1:F_dyn_char_bits=5'b01100; 3'd2:F_dyn_char_bits=5'b00100; 3'd3:F_dyn_char_bits=5'b00100; 3'd4:F_dyn_char_bits=5'b00100; 3'd5:F_dyn_char_bits=5'b00100; 3'd6:F_dyn_char_bits=5'b01110; default:F_dyn_char_bits=5'b00000; endcase end
                4'h2: begin case(I_row) 3'd0:F_dyn_char_bits=5'b01110; 3'd1:F_dyn_char_bits=5'b10001; 3'd2:F_dyn_char_bits=5'b00001; 3'd3:F_dyn_char_bits=5'b00110; 3'd4:F_dyn_char_bits=5'b01000; 3'd5:F_dyn_char_bits=5'b10000; 3'd6:F_dyn_char_bits=5'b11111; default:F_dyn_char_bits=5'b00000; endcase end
                4'h3: begin case(I_row) 3'd0:F_dyn_char_bits=5'b11110; 3'd1:F_dyn_char_bits=5'b00001; 3'd2:F_dyn_char_bits=5'b00001; 3'd3:F_dyn_char_bits=5'b01110; 3'd4:F_dyn_char_bits=5'b00001; 3'd5:F_dyn_char_bits=5'b00001; 3'd6:F_dyn_char_bits=5'b11110; default:F_dyn_char_bits=5'b00000; endcase end
                4'h4: begin case(I_row) 3'd0:F_dyn_char_bits=5'b00010; 3'd1:F_dyn_char_bits=5'b00110; 3'd2:F_dyn_char_bits=5'b01010; 3'd3:F_dyn_char_bits=5'b10010; 3'd4:F_dyn_char_bits=5'b11111; 3'd5:F_dyn_char_bits=5'b00010; 3'd6:F_dyn_char_bits=5'b00010; default:F_dyn_char_bits=5'b00000; endcase end
                4'h5: begin case(I_row) 3'd0:F_dyn_char_bits=5'b11111; 3'd1:F_dyn_char_bits=5'b10000; 3'd2:F_dyn_char_bits=5'b11110; 3'd3:F_dyn_char_bits=5'b00001; 3'd4:F_dyn_char_bits=5'b00001; 3'd5:F_dyn_char_bits=5'b10001; 3'd6:F_dyn_char_bits=5'b01110; default:F_dyn_char_bits=5'b00000; endcase end
                4'h6: begin case(I_row) 3'd0:F_dyn_char_bits=5'b00110; 3'd1:F_dyn_char_bits=5'b01000; 3'd2:F_dyn_char_bits=5'b10000; 3'd3:F_dyn_char_bits=5'b11110; 3'd4:F_dyn_char_bits=5'b10001; 3'd5:F_dyn_char_bits=5'b10001; 3'd6:F_dyn_char_bits=5'b01110; default:F_dyn_char_bits=5'b00000; endcase end
                4'h7: begin case(I_row) 3'd0:F_dyn_char_bits=5'b11111; 3'd1:F_dyn_char_bits=5'b00001; 3'd2:F_dyn_char_bits=5'b00010; 3'd3:F_dyn_char_bits=5'b00100; 3'd4:F_dyn_char_bits=5'b01000; 3'd5:F_dyn_char_bits=5'b01000; 3'd6:F_dyn_char_bits=5'b01000; default:F_dyn_char_bits=5'b00000; endcase end
                4'h8: begin case(I_row) 3'd0:F_dyn_char_bits=5'b01110; 3'd1:F_dyn_char_bits=5'b10001; 3'd2:F_dyn_char_bits=5'b10001; 3'd3:F_dyn_char_bits=5'b01110; 3'd4:F_dyn_char_bits=5'b10001; 3'd5:F_dyn_char_bits=5'b10001; 3'd6:F_dyn_char_bits=5'b01110; default:F_dyn_char_bits=5'b00000; endcase end
                4'h9: begin case(I_row) 3'd0:F_dyn_char_bits=5'b01110; 3'd1:F_dyn_char_bits=5'b10001; 3'd2:F_dyn_char_bits=5'b10001; 3'd3:F_dyn_char_bits=5'b01111; 3'd4:F_dyn_char_bits=5'b00001; 3'd5:F_dyn_char_bits=5'b00010; 3'd6:F_dyn_char_bits=5'b11100; default:F_dyn_char_bits=5'b00000; endcase end
                4'ha: begin case(I_row) 3'd0:F_dyn_char_bits=5'b01110; 3'd1:F_dyn_char_bits=5'b10001; 3'd2:F_dyn_char_bits=5'b10001; 3'd3:F_dyn_char_bits=5'b11111; 3'd4:F_dyn_char_bits=5'b10001; 3'd5:F_dyn_char_bits=5'b10001; 3'd6:F_dyn_char_bits=5'b10001; default:F_dyn_char_bits=5'b00000; endcase end
                4'hb: begin case(I_row) 3'd0:F_dyn_char_bits=5'b11110; 3'd1:F_dyn_char_bits=5'b10001; 3'd2:F_dyn_char_bits=5'b10001; 3'd3:F_dyn_char_bits=5'b11110; 3'd4:F_dyn_char_bits=5'b10001; 3'd5:F_dyn_char_bits=5'b10001; 3'd6:F_dyn_char_bits=5'b11110; default:F_dyn_char_bits=5'b00000; endcase end
                4'hc: begin case(I_row) 3'd0:F_dyn_char_bits=5'b01110; 3'd1:F_dyn_char_bits=5'b10001; 3'd2:F_dyn_char_bits=5'b10000; 3'd3:F_dyn_char_bits=5'b10000; 3'd4:F_dyn_char_bits=5'b10000; 3'd5:F_dyn_char_bits=5'b10001; 3'd6:F_dyn_char_bits=5'b01110; default:F_dyn_char_bits=5'b00000; endcase end
                4'hd: begin case(I_row) 3'd0:F_dyn_char_bits=5'b11110; 3'd1:F_dyn_char_bits=5'b10001; 3'd2:F_dyn_char_bits=5'b10001; 3'd3:F_dyn_char_bits=5'b10001; 3'd4:F_dyn_char_bits=5'b10001; 3'd5:F_dyn_char_bits=5'b10001; 3'd6:F_dyn_char_bits=5'b11110; default:F_dyn_char_bits=5'b00000; endcase end
                4'he: begin case(I_row) 3'd0:F_dyn_char_bits=5'b11111; 3'd1:F_dyn_char_bits=5'b10000; 3'd2:F_dyn_char_bits=5'b10000; 3'd3:F_dyn_char_bits=5'b11110; 3'd4:F_dyn_char_bits=5'b10000; 3'd5:F_dyn_char_bits=5'b10000; 3'd6:F_dyn_char_bits=5'b11111; default:F_dyn_char_bits=5'b00000; endcase end
                4'hf: begin case(I_row) 3'd0:F_dyn_char_bits=5'b11111; 3'd1:F_dyn_char_bits=5'b10000; 3'd2:F_dyn_char_bits=5'b10000; 3'd3:F_dyn_char_bits=5'b11110; 3'd4:F_dyn_char_bits=5'b10000; 3'd5:F_dyn_char_bits=5'b10000; 3'd6:F_dyn_char_bits=5'b10000; default:F_dyn_char_bits=5'b00000; endcase end
                default: F_dyn_char_bits = 5'b00000;
            endcase
        end
    endfunction

    function [15:0] F_osd_char16_row;
        input [7:0] I_char;
        input [3:0] I_row;
        begin
            case(I_char)
                CHAR_AN: begin
                    case(I_row)
                        4'd0:  F_osd_char16_row = 16'h0200;
                        4'd1:  F_osd_char16_row = 16'h7ff0;
                        4'd2:  F_osd_char16_row = 16'h4410;
                        4'd3:  F_osd_char16_row = 16'h0400;
                        4'd4:  F_osd_char16_row = 16'h7ff0;
                        4'd5:  F_osd_char16_row = 16'h0840;
                        4'd6:  F_osd_char16_row = 16'h1040;
                        4'd7:  F_osd_char16_row = 16'h1c80;
                        4'd8:  F_osd_char16_row = 16'h0300;
                        4'd9:  F_osd_char16_row = 16'h0cc0;
                        4'd10: F_osd_char16_row = 16'h7020;
                        default: F_osd_char16_row = 16'h0000;
                    endcase
                end
                CHAR_LU: begin
                    case(I_row)
                        4'd0:  F_osd_char16_row = 16'h79e0;
                        4'd1:  F_osd_char16_row = 16'h4a20;
                        4'd2:  F_osd_char16_row = 16'h4d40;
                        4'd3:  F_osd_char16_row = 16'h7880;
                        4'd4:  F_osd_char16_row = 16'h1140;
                        4'd5:  F_osd_char16_row = 16'h1630;
                        4'd6:  F_osd_char16_row = 16'h5be0;
                        4'd7:  F_osd_char16_row = 16'h5220;
                        4'd8:  F_osd_char16_row = 16'h5220;
                        4'd9:  F_osd_char16_row = 16'h5be0;
                        4'd10: F_osd_char16_row = 16'h6220;
                        default: F_osd_char16_row = 16'h0000;
                    endcase
                end
                CHAR_C: begin
                    case(I_row)
                        4'd2:  F_osd_char16_row = 16'h03f0;
                        4'd3:  F_osd_char16_row = 16'h0c0c;
                        4'd4:  F_osd_char16_row = 16'h1800;
                        4'd5:  F_osd_char16_row = 16'h3000;
                        4'd6:  F_osd_char16_row = 16'h3000;
                        4'd7:  F_osd_char16_row = 16'h3000;
                        4'd8:  F_osd_char16_row = 16'h3000;
                        4'd9:  F_osd_char16_row = 16'h3000;
                        4'd10: F_osd_char16_row = 16'h1800;
                        4'd11: F_osd_char16_row = 16'h0c0c;
                        4'd12: F_osd_char16_row = 16'h03f0;
                        default: F_osd_char16_row = 16'h0000;
                    endcase
                end
                CHAR_N: begin
                    case(I_row)
                        4'd2:  F_osd_char16_row = 16'h300c;
                        4'd3:  F_osd_char16_row = 16'h380c;
                        4'd4:  F_osd_char16_row = 16'h3c0c;
                        4'd5:  F_osd_char16_row = 16'h360c;
                        4'd6:  F_osd_char16_row = 16'h330c;
                        4'd7:  F_osd_char16_row = 16'h318c;
                        4'd8:  F_osd_char16_row = 16'h30cc;
                        4'd9:  F_osd_char16_row = 16'h306c;
                        4'd10: F_osd_char16_row = 16'h303c;
                        4'd11: F_osd_char16_row = 16'h301c;
                        4'd12: F_osd_char16_row = 16'h300c;
                        default: F_osd_char16_row = 16'h0000;
                    endcase
                end
                CHAR_T: begin
                    case(I_row)
                        4'd2:  F_osd_char16_row = 16'h3ffc;
                        4'd3:  F_osd_char16_row = 16'h03c0;
                        4'd4:  F_osd_char16_row = 16'h03c0;
                        4'd5:  F_osd_char16_row = 16'h03c0;
                        4'd6:  F_osd_char16_row = 16'h03c0;
                        4'd7:  F_osd_char16_row = 16'h03c0;
                        4'd8:  F_osd_char16_row = 16'h03c0;
                        4'd9:  F_osd_char16_row = 16'h03c0;
                        4'd10: F_osd_char16_row = 16'h03c0;
                        4'd11: F_osd_char16_row = 16'h03c0;
                        4'd12: F_osd_char16_row = 16'h03c0;
                        default: F_osd_char16_row = 16'h0000;
                    endcase
                end
                CHAR_COLON: begin
                    case(I_row)
                        4'd6:  F_osd_char16_row = 16'h0180;
                        4'd7:  F_osd_char16_row = 16'h0180;
                        4'd10: F_osd_char16_row = 16'h0180;
                        4'd11: F_osd_char16_row = 16'h0180;
                        default: F_osd_char16_row = 16'h0000;
                    endcase
                end
                default: F_osd_char16_row = 16'h0000;
            endcase
        end
    endfunction

    assign O_video_rd_en = I_rd_en;

    anlogic_logo_rom u_anlogic_logo_rom(
        .I_clk   ( I_clk        ),
        .I_addr  ( S_logo_addr  ),
        .O_pixel ( S_logo_pixel )
    );

    osd_char_lib u_osd_char_lib(
        .I_char     ( B_pf_char_q   ),
        .I_row      ( B_pf_row_q    ),
        .O_row_bits ( S_pf_row_bits )
    );

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_x <= 12'd0;
            S_y <= 12'd0;
        end
        else if(I_video_user) begin
            S_x <= 12'd0;
            S_y <= 12'd0;
        end
        else if(I_video_de) begin
            if(I_video_last) begin
                S_x <= 12'd0;
                S_y <= S_y + 12'd1;
            end
            else begin
                S_x <= S_x + 12'd1;
            end
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_x_1d <= 12'd0;
            S_x_2d <= 12'd0;
            S_x_2d_b1 <= 12'd0;
            S_x_2d_b2 <= 12'd0;
            S_y_1d <= 12'd0;
            S_y_2d <= 12'd0;
            S_y_2d_b1 <= 12'd0;
            S_y_2d_b2 <= 12'd0;
        end
        else begin
            S_x_1d <= S_x;
            S_x_2d <= S_x_1d;
            S_x_2d_b1 <= S_x_1d;
            S_x_2d_b2 <= S_x_1d;
            S_y_1d <= S_y;
            S_y_2d <= S_y_1d;
            S_y_2d_b1 <= S_y_1d;
            S_y_2d_b2 <= S_y_1d;
        end
    end

    wire W_logo_in_1d = S_video_de_1d &&
                        (S_x_1d >= LOGO_X) && (S_x_1d < (LOGO_X + LOGO_W)) &&
                        (S_y_1d >= LOGO_Y) && (S_y_1d < (LOGO_Y + LOGO_H));

    wire [11:0] W_logo_dx_1d = S_x_1d - LOGO_X;
    wire [11:0] W_logo_dy_1d = S_y_1d - LOGO_Y;

    wire [14:0] W_logo_addr_1d = (LOGO_W == 160)
        ? ({W_logo_dy_1d[7:0], 7'b0}
         + {2'b0, W_logo_dy_1d[7:0], 5'b0}
         + {7'b0, W_logo_dx_1d[7:0]})
        : (W_logo_dy_1d * LOGO_W + W_logo_dx_1d);

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_logo_addr <= 15'd0;
            S_logo_in_r <= 1'b0;
            S_logo_in_r2 <= 1'b0;
        end
        else begin
            S_logo_addr <= W_logo_in_1d ? W_logo_addr_1d : 15'd0;
            S_logo_in_r <= W_logo_in_1d;

            S_logo_in_r2 <= S_logo_in_r;
        end
    end

    function [11:0] F_absdiff;
        input [11:0] a, b;
        begin
            F_absdiff = (a > b) ? (a - b) : (b - a);
        end
    endfunction

    reg S_vs_d;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) S_vs_d <= 1'b0;
        else         S_vs_d <= I_video_vsync;
    end
    wire W_vs_rise = I_video_vsync & ~S_vs_d;

    reg [8:0] S_bb_x0_r, S_bb_x1_r;
    reg [7:0] S_bb_y0_r, S_bb_y1_r;
    reg [7:0] S_line_up_r, S_line_dn_r;
    reg [7:0] S_cx_r;
    reg [6:0] S_cy_r;

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_bb_x0_r   <= 9'd0;
            S_bb_x1_r   <= 9'd0;
            S_bb_y0_r   <= 8'd0;
            S_bb_y1_r   <= 8'd0;
            S_line_up_r <= 8'hFF;
            S_line_dn_r <= 8'hFF;
            S_cx_r      <= 8'd0;
            S_cy_r      <= 7'd0;
        end
        else if(W_vs_rise) begin

            S_bb_x0_r   <= I_bb_x0;
            S_bb_x1_r   <= I_bb_x1;
            S_bb_y0_r   <= I_bb_y0;
            S_bb_y1_r   <= I_bb_y1;
            S_line_up_r <= I_line_up;
            S_line_dn_r <= I_line_dn;
            S_cx_r      <= I_cx;
            S_cy_r      <= I_cy;
        end
    end

    wire [11:0] W_bb_x0 = {S_bb_x0_r, 3'b000};
    wire [11:0] W_bb_x1 = {S_bb_x1_r, 3'b000};
    wire [11:0] W_bb_y0 = {S_bb_y0_r, 3'b000};
    wire [11:0] W_bb_y1 = {S_bb_y1_r, 3'b000};
    wire [11:0] W_cx    = {S_cx_r,    3'b000};
    wire [11:0] W_cy    = {S_cy_r,    3'b000};

    wire [11:0] W_dx0 = F_absdiff(S_x_2d, W_bb_x0);
    wire [11:0] W_dx1 = F_absdiff(S_x_2d, W_bb_x1);
    wire [11:0] W_dy0 = F_absdiff(S_y_2d, W_bb_y0);
    wire [11:0] W_dy1 = F_absdiff(S_y_2d, W_bb_y1);

    wire W_bb_valid = (S_bb_x0_r <= S_bb_x1_r) && (S_bb_y0_r <= S_bb_y1_r);

    wire W_bb_on_1d = W_bb_valid &&
                  ( (((F_absdiff(S_y_1d, W_bb_y0) < 12'd3) || (F_absdiff(S_y_1d, W_bb_y1) < 12'd3)) &&
                     (S_x_1d >= W_bb_x0) && (S_x_1d <= W_bb_x1))
                 || (((F_absdiff(S_x_1d, W_bb_x0) < 12'd3) || (F_absdiff(S_x_1d, W_bb_x1) < 12'd3)) &&
                     (S_y_1d >= W_bb_y0) && (S_y_1d <= W_bb_y1)) );

    wire W_cross_on_1d = ((F_absdiff(S_y_1d, W_cy) < 12'd2) && (F_absdiff(S_x_1d, W_cx) < 12'd40)) ||
                         ((F_absdiff(S_x_1d, W_cx) < 12'd2) && (F_absdiff(S_y_1d, W_cy) < 12'd40));

    reg W_bb_on_r, W_cross_on_r;

    always @(posedge I_clk) begin
        W_bb_on_r    <= W_bb_on_1d;
        W_cross_on_r <= W_cross_on_1d;
    end

    reg [15:0] S_contour [0:89];

    always @(posedge I_clk) begin
        if (I_row_valid) S_contour[I_row_idx] <= {I_row_min, I_row_max};
    end

    wire [6:0]  W_contour_addr = S_y_1d[9:3];
    reg  [15:0] S_contour_r;

    always @(posedge I_clk) begin
        S_contour_r <= S_contour[W_contour_addr];
    end

    wire [7:0]  W_row_min = S_contour_r[15:8];
    wire [7:0]  W_row_max = S_contour_r[7:0];

    wire [11:0] W_cmin = {W_row_min, 3'b000};
    wire [11:0] W_cmax = {W_row_max, 3'b000};
    wire        W_contour_ok = (W_row_min <= W_row_max);

    wire W_contour_lr = W_contour_ok &&
                        ( (F_absdiff(S_x_2d_b1, W_cmin) < 12'd2) ||
                          (F_absdiff(S_x_2d_b1, W_cmax) < 12'd2) );

    wire W_contour_tb = W_contour_ok &&
                        ( (S_y_2d_b1[9:3] == S_bb_y0_r[6:0]) ||
                          (S_y_2d_b1[9:3] == S_bb_y1_r[6:0]) ) &&
                        (S_x_2d_b1 >= W_cmin) && (S_x_2d_b1 <= W_cmax);

    wire W_contour_on = W_contour_lr || W_contour_tb;

    reg S_contour_on_r;
    always @(posedge I_clk) S_contour_on_r <= W_contour_on;

    wire [11:0] W_line_up = {S_line_up_r, 3'b000};
    wire [11:0] W_line_dn = {S_line_dn_r, 3'b000};

    wire W_line_dash = S_x_2d_b1[4];

    reg W_line_up_row_r, W_line_dn_row_r;

    always @(posedge I_clk) begin
        W_line_up_row_r <= (F_absdiff(S_y_1d, W_line_up) < 12'd3);
        W_line_dn_row_r <= (F_absdiff(S_y_1d, W_line_dn) < 12'd3);
    end

    wire W_line_up_on = I_extra_en && W_line_dash && (S_line_up_r != 8'hFF) && W_line_up_row_r;
    wire W_line_dn_on = I_extra_en && W_line_dash && (S_line_dn_r != 8'hFF) && W_line_dn_row_r;

    wire W_graph_hit = I_contour_en &&
                       (I_contour_sel ? (W_bb_on_r || W_cross_on_r)
                                      : (S_contour_on_r || W_cross_on_r));
    wire [23:0] W_graph_color = I_contour_sel
                              ? (W_bb_on_r ? COLOR_BBOX : COLOR_CROSS)
                              : (S_contour_on_r ? COLOR_CONTOUR : COLOR_CROSS);

    wire W_line_hit = W_line_up_on || W_line_dn_on;
    wire [23:0] W_line_color = W_line_up_on ? COLOR_LINE_UP : COLOR_LINE_DN;

    wire [11:0] W_tgt_x0 = {I_tgt_x0, 3'b000};
    wire [11:0] W_tgt_x1 = {I_tgt_x1, 3'b000} + 12'd7;
    wire [11:0] W_tgt_y0 = {I_tgt_y0, 3'b000};
    wire [11:0] W_tgt_y1 = {I_tgt_y1, 3'b000} + 12'd7;

    wire W_tgt_in  = I_tgt_valid &&
                     (S_x_2d_b2 >= W_tgt_x0) && (S_x_2d_b2 <= W_tgt_x1) &&
                     (S_y_2d_b2 >= W_tgt_y0) && (S_y_2d_b2 <= W_tgt_y1);
    wire W_tgt_hit = W_tgt_in &&
                     ( (F_absdiff(S_x_2d_b2, W_tgt_x0) < 12'd2) ||
                       (F_absdiff(S_x_2d_b2, W_tgt_x1) < 12'd2) ||
                       (F_absdiff(S_y_2d_b2, W_tgt_y0) < 12'd2) ||
                       (F_absdiff(S_y_2d_b2, W_tgt_y1) < 12'd2) );

    always @(*) begin

        A_pf_ena      = 1'b0;
        A_pf_color    = COLOR_MODE_TXT;
        A_dot_hit     = 1'b0;

        A_logo_hit    = 1'b0;
        A_logo_color  = 24'd0;
        A_graph_hit   = 1'b0;
        A_graph_color = 24'd0;
        A_tgt_hit     = 1'b0;
        A_line_hit    = 1'b0;
        A_line_color  = 24'd0;

        S_pf_char     = 8'd0;
        S_pf_col      = 4'd0;
        S_pf_row      = 4'd0;
        S_pf_local_x  = 5'd0;
        S_pf_local_y  = 5'd0;
        S_pf_scale_x  = 10'd0;
        S_pf_scale_y  = 10'd0;

        S_mode_lx     = 7'd0;
        S_mode_ly     = 7'd0;
        S_mode_char   = CHAR_R;

        S_dyn_x         = 12'd0;
        S_dyn_y         = 12'd0;
        S_dyn_line      = 4'd0;
        S_dyn_bcd       = 24'd0;
        S_dyn_digit_idx = 4'd0;
        S_dyn_digit_x   = 12'd0;
        S_dyn_dec_digit = 4'd0;

        S_char_idx = 4'd0;   S_char_row = 3'd0;   S_char_col = 3'd0;
        S_char_bits = 5'd0;  S_char_on  = 1'b0;
        S_logo_blue_on = 1'b0; S_logo_red_on = 1'b0;
        S_logo_tmp_y = 12'd0;  S_logo_red_band = 4'd0;
        S_logo_red_x_start = 12'd0; S_logo_red_x_end = 12'd0;
        S_dyn_char = 4'd0;   S_dyn_col = 3'd0;    S_dyn_row = 3'd0;
        S_dyn_bits = 5'd0;   S_dyn_on  = 1'b0;
        S_lbl_row = 3'd0;    S_lbl_col = 3'd0;    S_lbl_idx = 2'd0;
        S_lbl_bits = 5'd0;   S_lbl_local_x = 7'd0;
        S_cn_local_x = 5'd0; S_cn_local_y = 5'd0;
        S_cn_col = 4'd0;     S_cn_row = 4'd0;     S_cn_row_bits = 16'd0;
        S_cn_on = 1'b0;      S_cn_scale_x = 10'd0; S_cn_scale_y = 10'd0;
        S_pf_on = 1'b0;

        A_graph_hit   = W_graph_hit;
        A_graph_color = W_graph_color;
        A_tgt_hit     = W_tgt_hit;
        A_line_hit    = W_line_hit;
        A_line_color  = W_line_color;

        if(S_video_de_2d && S_logo_in_r2 && S_logo_pixel[16]) begin
            A_logo_hit   = 1'b1;
            A_logo_color = {
                S_logo_pixel[15:11], S_logo_pixel[15:13],
                S_logo_pixel[10:5],  S_logo_pixel[10:9],
                S_logo_pixel[4:0],   S_logo_pixel[4:2]
            };
        end

        if(S_video_de_2d) begin

            if(I_extra_en &&
               (S_y_2d_b2 >= MODE_Y) && (S_y_2d_b2 < (MODE_Y + MODE_H)) &&
               (((S_x_2d_b2 >= MODE_X) && (S_x_2d_b2 < (MODE_X + MODE_W))) ||
                ((S_x_2d_b2 >= 12'd1080) && (S_x_2d_b2 < 12'd1208)))) begin

                if(S_x_2d_b2 < (MODE_X + MODE_W)) begin

                    S_mode_lx  = (S_x_2d_b2 - MODE_X) >> 2;
                    S_mode_ly  = (S_y_2d_b2 - MODE_Y) >> 2;

                    S_mode_char = (I_sport_mode == 3'd0) ? CHAR_R :
                                  (I_sport_mode == 3'd1) ? CHAR_S :
                                  (I_sport_mode == 3'd2) ? CHAR_J :
                                  (I_sport_mode == 3'd3) ? CHAR_A :
                                  (I_sport_mode == 3'd4) ? CHAR_T : CHAR_B;
                    S_pf_char    = S_mode_char;
                    S_pf_local_x = S_mode_lx[4:0];
                    S_pf_local_y = S_mode_ly[4:0];
                end
                else begin

                    S_mode_lx    = S_x_2d_b2 - 12'd1080;
                    S_mode_ly    = S_y_2d_b2 - MODE_Y;
                    S_pf_char    = (S_mode_lx < 12'd64)
                                 ? (CHAR_0 + {4'd0, W_mode_tens})
                                 : (CHAR_0 + {4'd0, W_mode_ones});
                    S_pf_local_x = {1'b0, S_mode_lx[5:2]};
                    S_pf_local_y = {1'b0, S_mode_ly[5:2]};
                end

                if((S_pf_local_x < 5'd16) && (S_pf_local_y < 5'd16)) begin
                    S_pf_col   = S_pf_local_x[3:0];
                    S_pf_row   = S_pf_local_y[3:0];
                    A_pf_ena   = 1'b1;
                    A_pf_color = COLOR_MODE_TXT;
                end
            end

            if(I_dyn_osd_en &&
               (S_x_2d_b2 >= DYN_OSD_X) && (S_x_2d_b2 < (DYN_OSD_X + DYN_OSD_W)) &&
               (S_y_2d_b2 >= DYN_OSD_Y) && (S_y_2d_b2 < (DYN_OSD_Y + DYN_OSD_H))) begin

                S_dyn_x    = S_x_2d_b2 - DYN_OSD_X;
                S_dyn_line = (S_y_2d_b2 - DYN_OSD_Y) >> 5;
                S_dyn_y    = (S_y_2d_b2 - DYN_OSD_Y) & 12'd31;

                S_dyn_bcd  = (W_src_line == 4'd0) ? I_bcd_cnt :
                             (W_src_line == 4'd1) ? I_bcd_amp :
                             (W_src_line == 4'd2) ? I_bcd_pix :
                             (W_src_line == 4'd4) ? {16'd0, W_mode_tens, W_mode_ones} :
                             (W_src_line == 4'd5) ? {16'd0, W_lat_tens,  W_lat_ones } :
                             (W_src_line == 4'd6) ? 24'd0 :
                             (W_src_line == 4'd7) ? {I_bcd_cx[11:0], 4'hF, I_bcd_cy[7:0]} :
                             (W_src_line == 4'd8) ? {I_pwm_h, I_pwm_t, I_pwm_o, 4'hF, 4'hF, 4'hF} :
                             (W_src_line == 4'd9) ? {I_ang_h, I_ang_t, I_ang_o, 4'hF, 4'hF, 4'hF} :
                             (W_is_run)           ? {12'd0, I_speed_bcd} : I_bcd_raw;

                if((S_dyn_x < 12'd108) && (S_dyn_y < 12'd24)) begin
                    if(S_dyn_x < 12'd48) begin

                        if(S_dyn_y >= CN_Y_OFFSET)
                            S_pf_local_y = S_dyn_y - CN_Y_OFFSET;
                        else
                            S_pf_local_y = 5'd31;

                        if(S_dyn_x < 12'd24) begin
                            S_pf_char    = CHAR_AN;
                            S_pf_local_x = S_dyn_x;
                        end
                        else begin
                            S_pf_char    = CHAR_LU;
                            S_pf_local_x = S_dyn_x - 12'd24;
                        end

                        if((S_pf_local_x < 5'd24) && (S_pf_local_y < 5'd24)) begin
                            S_pf_scale_x = S_pf_local_x * 10'd16;
                            S_pf_scale_y = S_pf_local_y * 10'd16;
                            S_pf_col   = S_pf_scale_x / 10'd24;
                            S_pf_row   = S_pf_scale_y / 10'd24;
                            A_pf_ena   = 1'b1;
                            A_pf_color = COLOR_DYN_TEXT;
                        end
                    end
                    else if((S_dyn_x >= 12'd52) && (S_dyn_x < 12'd100) &&
                            (S_dyn_y >= 12'd4) && (S_dyn_y < 12'd20)) begin

                        if(S_dyn_x < 12'd68) begin
                            S_pf_char    = F_lbl_char(W_lbl_sel, 2'd0);
                            S_pf_local_x = S_dyn_x - 12'd52;
                        end
                        else if(S_dyn_x < 12'd84) begin
                            S_pf_char    = F_lbl_char(W_lbl_sel, 2'd1);
                            S_pf_local_x = S_dyn_x - 12'd68;
                        end
                        else begin
                            S_pf_char    = F_lbl_char(W_lbl_sel, 2'd2);
                            S_pf_local_x = S_dyn_x - 12'd84;
                        end
                        S_pf_local_y = S_dyn_y - 12'd4;
                        S_pf_col     = S_pf_local_x[3:0];
                        S_pf_row     = S_pf_local_y[3:0];
                        A_pf_ena     = 1'b1;
                        A_pf_color   = COLOR_DYN_TEXT;
                    end
                    else if((S_dyn_x >= 12'd100) && (S_dyn_y >= 12'd4) && (S_dyn_y < 12'd20)) begin

                        S_pf_char    = CHAR_COLON;
                        S_pf_local_x = S_dyn_x - 12'd100;
                        S_pf_local_y = S_dyn_y - 12'd4;
                        S_pf_scale_x = S_pf_local_x * 10'd16;
                        S_pf_col     = S_pf_scale_x / 10'd8;
                        S_pf_row     = S_pf_local_y[3:0];
                        A_pf_ena     = 1'b1;
                        A_pf_color   = COLOR_DYN_TEXT;
                    end
                end

                if((S_dyn_x >= 12'd110) && (S_dyn_x < 12'd200)) begin
                    if(S_dyn_x < 12'd125) begin
                        S_dyn_digit_idx = 4'd0;
                        S_dyn_digit_x   = S_dyn_x - 12'd110;
                        S_dyn_dec_digit = S_dyn_bcd[23:20];
                    end
                    else if(S_dyn_x < 12'd140) begin
                        S_dyn_digit_idx = 4'd1;
                        S_dyn_digit_x   = S_dyn_x - 12'd125;
                        S_dyn_dec_digit = S_dyn_bcd[19:16];
                    end
                    else if(S_dyn_x < 12'd155) begin
                        S_dyn_digit_idx = 4'd2;
                        S_dyn_digit_x   = S_dyn_x - 12'd140;
                        S_dyn_dec_digit = S_dyn_bcd[15:12];
                    end
                    else if(S_dyn_x < 12'd170) begin
                        S_dyn_digit_idx = 4'd3;
                        S_dyn_digit_x   = S_dyn_x - 12'd155;
                        S_dyn_dec_digit = S_dyn_bcd[11:8];
                    end
                    else if(S_dyn_x < 12'd185) begin
                        S_dyn_digit_idx = 4'd4;
                        S_dyn_digit_x   = S_dyn_x - 12'd170;
                        S_dyn_dec_digit = S_dyn_bcd[7:4];
                    end
                    else begin
                        S_dyn_digit_idx = 4'd5;
                        S_dyn_digit_x   = S_dyn_x - 12'd185;
                        S_dyn_dec_digit = S_dyn_bcd[3:0];
                    end

                    if((S_dyn_digit_x < 12'd15) && (S_dyn_y < 12'd24) &&
                       (S_dyn_dec_digit != 4'hF) &&
                       ((W_src_line != 4'd6) || (S_dyn_digit_idx <= 4'd1)) &&
                       (!W_hide_digit)) begin

                        S_pf_char = (W_src_line == 4'd6)
                            ? ( (S_dyn_digit_idx == 4'd0)
                                ? ((I_ae_mode == 2'd2) ? CHAR_A : (I_ae_mode == 2'd1) ? CHAR_H : CHAR_L)
                                : ((I_ae_mode == 2'd2) ? CHAR_U : CHAR_O) )
                            : (CHAR_0 + {4'd0, S_dyn_dec_digit});
                        S_pf_local_x = S_dyn_digit_x[4:0];
                        S_pf_local_y = S_dyn_y[4:0];
                        S_pf_scale_x = S_pf_local_x * 10'd16;
                        S_pf_scale_y = S_pf_local_y * 10'd16;
                        S_pf_col     = S_pf_scale_x / 10'd15;
                        S_pf_row     = S_pf_scale_y / 10'd24;
                        A_pf_ena     = 1'b1;
                        A_pf_color   = COLOR_DYN_TEXT;
                    end
                end

                if(W_is_run && (S_dyn_line == 4'd3) &&
                   (S_dyn_x >= 12'd181) && (S_dyn_x < 12'd185) &&
                   (S_dyn_y >= 12'd20) && (S_dyn_y < 12'd23))
                    A_dot_hit = 1'b1;

                if(!W_row_valid || ((W_src_line == 3'd5) && !I_lat_en)) begin
                    A_pf_ena  = 1'b0;
                    A_dot_hit = 1'b0;
                end
            end
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            B_pf_char_q    <= 8'd0;
            B_pf_col_q     <= 4'd0;
            B_pf_row_q     <= 4'd0;
            B_pf_ena_q     <= 1'b0;
            B_pf_color_q   <= 24'd0;
            B_logo_hit_q   <= 1'b0;
            B_logo_color_q <= 24'd0;
            B_graph_hit_q  <= 1'b0;
            B_graph_color_q<= 24'd0;
            B_tgt_hit_q    <= 1'b0;
            B_line_hit_q   <= 1'b0;
            B_line_color_q <= 24'd0;
            B_dot_hit_q    <= 1'b0;
        end
        else begin
            B_pf_char_q    <= S_pf_char;
            B_pf_col_q     <= S_pf_col;
            B_pf_row_q     <= S_pf_row;
            B_pf_ena_q     <= A_pf_ena;
            B_pf_color_q   <= A_pf_color;
            B_logo_hit_q   <= A_logo_hit;
            B_logo_color_q <= A_logo_color;
            B_graph_hit_q  <= A_graph_hit;
            B_graph_color_q<= A_graph_color;
            B_tgt_hit_q    <= A_tgt_hit;
            B_line_hit_q   <= A_line_hit;
            B_line_color_q <= A_line_color;
            B_dot_hit_q    <= A_dot_hit;
        end
    end

    wire W_pf_bit = S_pf_row_bits[4'd15 - B_pf_col_q];
    wire W_pf_on  = B_pf_ena_q & W_pf_bit;

    wire W_osd_hit_n = B_logo_hit_q | B_graph_hit_q | B_tgt_hit_q |
                       B_line_hit_q | W_pf_on      | B_dot_hit_q;

    wire [23:0] W_col_a  = B_logo_hit_q ? B_logo_color_q : B_graph_color_q;
    wire [23:0] W_col_b  = B_tgt_hit_q  ? COLOR_TGT      : B_line_color_q;
    wire [23:0] W_col_c  = W_pf_on      ? B_pf_color_q   : COLOR_DYN_TEXT;
    wire [23:0] W_col_ab = (B_logo_hit_q | B_graph_hit_q) ? W_col_a
                         : (B_tgt_hit_q  | B_line_hit_q)  ? W_col_b : W_col_c;

    always @(*) begin
        S_osd_hit   = W_osd_hit_n;
        S_osd_color = W_col_ab;
    end

    reg        S_osd_hit_r;
    reg [23:0] S_osd_color_r;
    reg [23:0] S_video_data_2d_r;
    reg [23:0] S_video_data_3d_r;
    reg        S_video_vsync_3d;
    reg        S_video_hsync_3d;
    reg        S_video_de_3d;
    reg        S_video_vsync_4d;
    reg        S_video_hsync_4d;
    reg        S_video_de_4d;

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_osd_hit_r       <= 1'b0;
            S_osd_color_r     <= 24'd0;
            S_video_data_2d_r <= 24'd0;
            S_video_data_3d_r <= 24'd0;
            S_video_vsync_3d  <= 1'b0;
            S_video_hsync_3d  <= 1'b0;
            S_video_de_3d     <= 1'b0;
            S_video_vsync_4d  <= 1'b0;
            S_video_hsync_4d  <= 1'b0;
            S_video_de_4d     <= 1'b0;
        end
        else begin
            S_osd_hit_r       <= S_osd_hit;
            S_osd_color_r     <= S_osd_color;
            S_video_data_2d_r <= S_video_data_2d;
            S_video_data_3d_r <= S_video_data_2d_r;
            S_video_vsync_3d  <= S_video_vsync_2d;
            S_video_hsync_3d  <= S_video_hsync_2d;
            S_video_de_3d     <= S_video_de_2d;
            S_video_vsync_4d  <= S_video_vsync_3d;
            S_video_hsync_4d  <= S_video_hsync_3d;
            S_video_de_4d     <= S_video_de_3d;
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n) begin
            S_video_vsync_1d <= 1'b0;
            S_video_vsync_2d <= 1'b0;
            S_video_hsync_1d <= 1'b0;
            S_video_hsync_2d <= 1'b0;
            S_video_de_1d    <= 1'b0;
            S_video_de_2d    <= 1'b0;
            O_hdmi_vsync     <= 1'b0;
            O_hdmi_hsync     <= 1'b0;
            O_hdmi_de        <= 1'b0;
            O_hdmi_data      <= 24'd0;
        end
        else begin
            S_video_vsync_1d <= I_video_vsync;
            S_video_vsync_2d <= S_video_vsync_1d;
            O_hdmi_vsync     <= S_video_vsync_4d;

            S_video_hsync_1d <= I_video_hsync;
            S_video_hsync_2d <= S_video_hsync_1d;
            O_hdmi_hsync     <= S_video_hsync_4d;

            S_video_de_1d    <= I_video_de;
            S_video_de_2d    <= S_video_de_1d;
            O_hdmi_de        <= S_video_de_4d;
            S_video_data_1d  <= I_video_rd_data;
            S_video_data_2d  <= S_video_data_1d;

            if(DEBUG_MODE == 1) begin
                if(S_video_de_2d) begin
                    if(S_x < 12'd128)
                        O_hdmi_data <= 24'hff0000;
                    else if(S_x < 12'd256)
                        O_hdmi_data <= 24'h00ff00;
                    else if(S_x < 12'd384)
                        O_hdmi_data <= 24'h0000ff;
                    else if(S_x < 12'd512)
                        O_hdmi_data <= 24'hffff00;
                    else if(S_x < 12'd640)
                        O_hdmi_data <= 24'h00ffff;
                    else if(S_x < 12'd768)
                        O_hdmi_data <= 24'hff00ff;
                    else if(S_x < 12'd896)
                        O_hdmi_data <= 24'hffffff;
                    else
                        O_hdmi_data <= 24'h202020;
                end
                else begin
                    O_hdmi_data <= 24'd0;
                end
            end
            else if(DEBUG_MODE == 2) begin
                if(S_video_de_2d) begin
                    case (I_debug_status)
                        4'b0000: O_hdmi_data <= 24'h000000;
                        4'b0001: O_hdmi_data <= 24'hff0000;
                        4'b0011: O_hdmi_data <= 24'hffff00;
                        4'b0111: O_hdmi_data <= 24'h00ff00;
                        4'b1111: O_hdmi_data <= I_video_rd_data;
                        default: O_hdmi_data <= 24'h0000ff;
                    endcase
                end
                else begin
                    O_hdmi_data <= 24'd0;
                end
            end
            else if(DEBUG_MODE == 3) begin
                if(S_video_de_2d) begin
                    if(S_x < 12'd256)
                        O_hdmi_data <= I_debug_status[0] ? 24'hff8000 : 24'h201000;
                    else if(S_x < 12'd512)
                        O_hdmi_data <= I_debug_status[1] ? 24'hffff00 : 24'h202000;
                    else if(S_x < 12'd768)
                        O_hdmi_data <= I_debug_status[2] ? 24'hff0000 : 24'h200000;
                    else
                        O_hdmi_data <= I_debug_status[3] ? 24'h00ffff : 24'h002020;
                end
                else begin
                    O_hdmi_data <= 24'd0;
                end
            end
            else begin
                if(S_osd_hit_r)
                    O_hdmi_data <= S_osd_color_r;
                else
                    O_hdmi_data <= S_video_data_3d_r;
            end
        end
    end

endmodule
