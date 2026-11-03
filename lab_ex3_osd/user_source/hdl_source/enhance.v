module enhance #(
    parameter IMG_WIDTH  = 1280,
    parameter IMG_HEIGHT = 720,

    parameter integer LIFT_SHIFT = 2,

    parameter [2:0] SAT_K = 3'd2,

    parameter integer DE_LAG = 6
)(
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire        I_de,
    input  wire [23:0] I_data,
    input  wire [3:0]  I_mode,
    input  wire [7:0]  I_edge_th,
    input  wire [7:0]  I_bin_th,

    input  wire [2:0]  I_lift_shift,
    input  wire [2:0]  I_enh_sat_k,
    output reg         O_de,
    output reg  [23:0] O_data
);

    reg [7:0] de_sr;

    always @(posedge I_clk) begin
        if (!I_rst_n) de_sr <= 4'd0;
        else          de_sr <= {de_sr[6:0], I_de};
    end

    wire de_align = de_sr[DE_LAG-1];

    reg  [23:0] I_data_d;
    always @(posedge I_clk) begin
        if (!I_rst_n) I_data_d <= 24'd0;
        else          I_data_d <= I_data;
    end

    wire [7:0] r_in = I_data[23:16];
    wire [7:0] g_in = I_data[15: 8];
    wire [7:0] b_in = I_data[ 7: 0];

    wire [7:0] r_d = I_data_d[23:16];
    wire [7:0] g_d = I_data_d[15: 8];
    wire [7:0] b_d = I_data_d[ 7: 0];

    wire [15:0] gray_sum = 16'd77 * {8'b0, r_in} + 16'd150 * {8'b0, g_in} + 16'd29 * {8'b0, b_in};

    reg  [7:0]  gray_val;
    always @(posedge I_clk) begin
        if (!I_rst_n) gray_val <= 8'd0;
        else          gray_val <= gray_sum[15:8];
    end

    wire [8:0] lift_r = (9'd255 - {1'b0, r_d}) >> I_lift_shift;
    wire [8:0] lift_g = (9'd255 - {1'b0, g_d}) >> I_lift_shift;
    wire [8:0] lift_b = (9'd255 - {1'b0, b_d}) >> I_lift_shift;

    wire [8:0] lr = {1'b0, r_d} + lift_r;
    wire [8:0] lg = {1'b0, g_d} + lift_g;
    wire [8:0] lb = {1'b0, b_d} + lift_b;

    wire [9:0] ly_sum = {1'b0, lr} + {lg, 1'b0} + {1'b0, lb};
    wire [7:0] ly_lum = ly_sum >> 2;

    wire signed [11:0] sd_r = {3'b000, lr} - {4'b0000, ly_lum};
    wire signed [11:0] sd_g = {3'b000, lg} - {4'b0000, ly_lum};
    wire signed [11:0] sd_b = {3'b000, lb} - {4'b0000, ly_lum};

    reg signed [11:0] kd_r, kd_g, kd_b;

    always @(*) begin
        case (I_enh_sat_k)
            3'd1: begin kd_r = sd_r;                kd_g = sd_g;                kd_b = sd_b;                end
            3'd2: begin kd_r = sd_r + sd_r;         kd_g = sd_g + sd_g;         kd_b = sd_b + sd_b;         end
            3'd3: begin kd_r = sd_r + (sd_r <<< 1); kd_g = sd_g + (sd_g <<< 1); kd_b = sd_b + (sd_b <<< 1); end
            3'd4: begin kd_r = (sd_r <<< 2);        kd_g = (sd_g <<< 2);        kd_b = (sd_b <<< 2);        end
            default: begin kd_r = sd_r; kd_g = sd_g; kd_b = sd_b; end
        endcase
    end

    wire signed [12:0] sr_new = {4'b0000, ly_lum} + {kd_r[11], kd_r};
    wire signed [12:0] sg_new = {4'b0000, ly_lum} + {kd_g[11], kd_g};
    wire signed [12:0] sb_new = {4'b0000, ly_lum} + {kd_b[11], kd_b};

    wire [12:0] sr_pos = sr_new[12] ? 13'd0 : sr_new;
    wire [12:0] sg_pos = sg_new[12] ? 13'd0 : sg_new;
    wire [12:0] sb_pos = sb_new[12] ? 13'd0 : sb_new;

    wire [7:0] br_r = (sr_pos > 13'd255) ? 8'd255 : sr_pos[7:0];
    wire [7:0] br_g = (sg_pos > 13'd255) ? 8'd255 : sg_pos[7:0];
    wire [7:0] br_b = (sb_pos > 13'd255) ? 8'd255 : sb_pos[7:0];

    wire [23:0] px_bright = {br_r, br_g, br_b};

    wire [7:0] ramp = {gray_val[5:0], 2'b00};

    wire [7:0] heat_r = (gray_val < 8'd128) ? 8'd0   :
                        (gray_val < 8'd192) ? ramp   : 8'd255;

    wire [7:0] heat_g = (gray_val < 8'd64)  ? ramp         :
                        (gray_val < 8'd192) ? 8'd255       :
                                              8'd255 - ramp;

    wire [7:0] heat_b = (gray_val < 8'd64)  ? 8'd255          :
                        (gray_val < 8'd128) ? 8'd255 - ramp   :
                                              8'd0;

    wire [23:0] px_heat = {heat_r, heat_g, heat_b};

    wire [23:0] px_invert = ~I_data_d;

    wire [23:0] px_gray = {gray_val, gray_val, gray_val};

    wire [23:0] px_binary = (gray_val >= I_bin_th) ? 24'hFFFFFF : 24'h000000;

    wire [8:0] sep_base = {1'b0, gray_val} + {2'b0, gray_val[7:2]};
    wire [8:0] sep_r9   = sep_base + {3'b0, sep_base[8:3]};
    wire [8:0] sep_b9   = sep_base - {2'b0, sep_base[8:2]};

    wire [7:0] sep_r = sep_r9[8]    ? 8'hFF : sep_r9[7:0];
    wire [7:0] sep_g = sep_base[8]  ? 8'hFF : sep_base[7:0];
    wire [7:0] sep_b = sep_b9[7:0];

    wire [23:0] px_sepia = {sep_r, sep_g, sep_b};

    wire [23:0] px_red = {r_d, 8'h00, 8'h00};

    wire [23:0] px_night = {8'h00, gray_val, 8'h00};

    wire [23:0] px_poster = {r_d[7:5], 5'b11111,
                             g_d[7:5], 5'b11111,
                             b_d[7:5], 5'b11111};

    reg [7:0] gv_d1, gv_d2;

    always @(posedge I_clk) begin
        gv_d1 <= gray_val;
        gv_d2 <= gv_d1;
    end

    localparam [11:0] W_LAST = IMG_WIDTH - 1;

    reg [11:0] col_cnt;

    always @(posedge I_clk) begin
        if (!I_rst_n)
            col_cnt <= 12'd0;
        else if (de_align) begin
            if (col_cnt >= W_LAST)
                col_cnt <= 12'd0;
            else
                col_cnt <= col_cnt + 12'd1;
        end
    end

    wire [9:0]  gsum3 = {2'b0, gv_d2} + {2'b0, gv_d1} + {2'b0, gray_val};

    wire [15:0] gx1   = {6'b0, gsum3};
    wire [15:0] gx4   = {6'b0, gsum3} << 2;
    wire [15:0] gx16  = {6'b0, gsum3} << 4;
    wire [15:0] gmul  = gx1 + gx4 + gx16;
    wire [7:0]  gsm   = gmul[13:6];

    reg [7:0] gsm_d1, gsm_d2;

    always @(posedge I_clk) begin
        gsm_d1 <= gsm;
        gsm_d2 <= gsm_d1;
    end

    wire [7:0] gx_abs = (gsm >= gsm_d2) ? (gsm - gsm_d2) : (gsm_d2 - gsm);

    wire e_raw = (gx_abs > I_edge_th);

    reg e_d1, e_d2;

    always @(posedge I_clk) begin
        e_d1 <= e_raw;
        e_d2 <= e_d1;
    end

    wire e_major = (e_raw & e_d1) | (e_raw & e_d2) | (e_d1 & e_d2);

    wire W_edge_ok = (col_cnt >= 12'd5);

    wire [23:0] px_edge = (e_major && W_edge_ok) ? 24'hFFFFFF : 24'h000000;

    reg [23:0] mode_pixel;

    always @(*) begin
        case (I_mode)
            4'd0:    mode_pixel = I_data_d;
            4'd1:    mode_pixel = px_bright;
            4'd2:    mode_pixel = px_heat;
            4'd3:    mode_pixel = px_invert;
            4'd4:    mode_pixel = px_gray;
            4'd5:    mode_pixel = px_binary;
            4'd6:    mode_pixel = px_sepia;
            4'd7:    mode_pixel = px_red;
            4'd8:    mode_pixel = px_night;
            4'd9:    mode_pixel = px_poster;
            4'd10:   mode_pixel = px_edge;
            default: mode_pixel = I_data_d;
        endcase
    end

    always @(posedge I_clk) begin
        if (!I_rst_n) begin
            O_de   <= 1'b0;
            O_data <= 24'd0;
        end
        else begin
            O_de <= de_align;
            if (de_align) O_data <= mode_pixel;
        end
    end

endmodule
