module cartoonize #(
    parameter IMG_WIDTH  = 1280,
    parameter IMG_HEIGHT = 720,

    parameter QUANT_HI   = 4,

    parameter EDGE_TH    = 11'd150,

    parameter integer EDGE_DILATE = 0,

    parameter integer EDGE_DARK = 1,

    parameter EDGE_SRC   = 1,

    parameter [7:0] K_US_Q4  = 8'd48,

    parameter [7:0] K_QEN_Q4 = 8'd48,

    parameter [7:0] QEN_DCAP = 8'd64,

    parameter [6:0] QEN_NR_TH = 7'd4,

    parameter [7:0] QEN_MID_Q4 = 8'd32,

    parameter [7:0] CART_DN_Q4 = 8'd16,

    parameter [7:0] QEN_MID_US_Q4 = 8'd0,

    parameter integer TONE_EN = 1,

    parameter [7:0] TONE_S4 = 8'd16,

    parameter [7:0] TONE_TARGET = 8'd110,

    parameter [8:0] TONE_GAIN_MIN_Q8 = 9'd154,
    parameter [8:0] TONE_GAIN_MAX_Q8 = 9'd410,

    parameter integer TONE_IIR_SHIFT = 4,

    parameter [7:0] CONTRAST_Q4 = 8'd16,

    parameter integer BRIGHT_OFF = 0,

    parameter integer E_GAIN_S = 4,

    parameter SAT_K      = 2,

    parameter SAT_EN     = 0,

    parameter MONO       = 0,

    parameter PRE_SAT_K  = 1,

    parameter integer DIAG_MODE = 0,

    parameter integer DE_LAG = 2
)(
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire        I_de,
    input  wire        I_user,
    input  wire        I_last,

    input  wire [1:0]  I_mode,

    input  wire        I_qen,
    input  wire [3:0]  I_ev_gain,

    input  wire [7:0]  I_edge_th,

    input  wire [3:0]  I_quant_hi,
    input  wire [7:0]  I_k_us_q4,
    input  wire [3:0]  I_sat_k,
    input  wire        I_sat_en,
    input  wire [1:0]  I_edge_dark,
    input  wire [7:0]  I_contrast_q4,
    input  wire [23:0] I_data,
    output reg         O_de,
    output reg         O_user,
    output reg         O_last,
    output reg  [23:0] O_data,

    output reg  [7:0]  O_y_med,
    output reg         O_y_med_tog
);

    wire [7:0] i_r = I_data[23:16];
    wire [7:0] i_g = I_data[15: 8];
    wire [7:0] i_b = I_data[ 7: 0];

    wire [9:0] i_y_sum = {2'b00, i_r} + {1'b0, i_g, 1'b0} + {2'b00, i_b};
    wire [7:0] i_y     = (i_y_sum + 10'd2) >> 2;

    wire signed [8:0] i_dr = {1'b0, i_r} - {1'b0, i_y};
    wire signed [8:0] i_dg = {1'b0, i_g} - {1'b0, i_y};
    wire signed [8:0] i_db = {1'b0, i_b} - {1'b0, i_y};

    reg signed [10:0] pk_dr, pk_dg, pk_db;
    always @(*) begin
        case (PRE_SAT_K)
            1: begin pk_dr = {{2{i_dr[8]}}, i_dr};                       pk_dg = {{2{i_dg[8]}}, i_dg};                       pk_db = {{2{i_db[8]}}, i_db};                       end
            2: begin pk_dr = {{2{i_dr[8]}}, i_dr} <<< 1;                 pk_dg = {{2{i_dg[8]}}, i_dg} <<< 1;                 pk_db = {{2{i_db[8]}}, i_db} <<< 1;                 end
            3: begin pk_dr = ({{2{i_dr[8]}}, i_dr} <<< 1) + {{2{i_dr[8]}}, i_dr}; pk_dg = ({{2{i_dg[8]}}, i_dg} <<< 1) + {{2{i_dg[8]}}, i_dg}; pk_db = ({{2{i_db[8]}}, i_db} <<< 1) + {{2{i_db[8]}}, i_db}; end
            4: begin pk_dr = {{2{i_dr[8]}}, i_dr} <<< 2;                 pk_dg = {{2{i_dg[8]}}, i_dg} <<< 2;                 pk_db = {{2{i_db[8]}}, i_db} <<< 2;                 end
            default: begin pk_dr = {{2{i_dr[8]}}, i_dr};                 pk_dg = {{2{i_dg[8]}}, i_dg};                       pk_db = {{2{i_db[8]}}, i_db};                       end
        endcase
    end

    wire signed [10:0] pk_y = {3'b000, i_y};
    wire signed [10:0] pk_r = pk_y + pk_dr;
    wire signed [10:0] pk_g = pk_y + pk_dg;
    wire signed [10:0] pk_b = pk_y + pk_db;

    function [7:0] F_sat8;
        input signed [10:0] v;
        begin
            if (v[10])          F_sat8 = 8'd0;
            else if (v > 11'sd255) F_sat8 = 8'd255;
            else                F_sat8 = v[7:0];
        end
    endfunction

    wire [7:0] ps_r = (PRE_SAT_K == 1) ? i_r : F_sat8(pk_r);
    wire [7:0] ps_g = (PRE_SAT_K == 1) ? i_g : F_sat8(pk_g);
    wire [7:0] ps_b = (PRE_SAT_K == 1) ? i_b : F_sat8(pk_b);

    wire [23:0] I_data_sat = {ps_r, ps_g, ps_b};

    wire [9:0] hy_sum = {2'b00, ps_r} + {1'b0, ps_g, 1'b0} + {2'b00, ps_b};
    wire [7:0] hy_in  = (hy_sum + 10'd2) >> 2;

    localparam integer ED       = (EDGE_DILATE < 1) ? 1 : EDGE_DILATE;

    localparam integer LAT_PAD  = 4;
    localparam integer LAT_EDGE = 12 + LAT_PAD;

    localparam integer LAT_YQ   = LAT_EDGE - 6;

    localparam integer LAT_YB   = LAT_YQ + 1;

    wire [3:0]  q_hi     = I_quant_hi;
    wire [3:0]  low_bits = (q_hi >= 4'd8) ? 4'd0 : (4'd8 - q_hi);
    wire [7:0]  Q_KEEP   = (q_hi >= 4'd8) ? 8'hFF : (8'hFF << low_bits);
    wire [7:0]  Q_ADD    = (q_hi >= 4'd8) ? 8'h00 : ((~Q_KEEP + 8'h01) >> 1);

    reg [3:0] de_sr;
    reg [3:0] user_sr_in;
    reg [3:0] last_sr_in;

    always @(posedge I_clk) begin
        if (!I_rst_n) begin
            de_sr      <= 4'd0;
            user_sr_in <= 4'd0;
            last_sr_in <= 4'd0;
        end
        else begin
            de_sr      <= {de_sr[2:0],      I_de};
            user_sr_in <= {user_sr_in[2:0], I_user};
            last_sr_in <= {last_sr_in[2:0], I_last};
        end
    end

    wire de_align   = (DE_LAG == 0) ? I_de   : de_sr[DE_LAG-1];
    wire user_align = (DE_LAG == 0) ? I_user : user_sr_in[DE_LAG-1];
    wire last_align = (DE_LAG == 0) ? I_last : last_sr_in[DE_LAG-1];

    reg [10:0] addr;
    reg [10:0] addr_p1;
    reg [10:0] y_cnt;

    always @(posedge I_clk) begin
        if (!I_rst_n) begin
            addr    <= 11'd0;
            addr_p1 <= 11'd1;
            y_cnt   <= 11'd0;
        end
        else if (de_align) begin
            addr    <= (addr    == IMG_WIDTH-1) ? 11'd0 : addr    + 1'b1;
            addr_p1 <= (addr_p1 == IMG_WIDTH-1) ? 11'd0 : addr_p1 + 1'b1;
            if (addr == IMG_WIDTH-1)
                y_cnt <= (y_cnt == IMG_HEIGHT-1) ? 11'd0 : y_cnt + 1'b1;
        end
    end

    wire [9:0] ysum  = {2'b00, I_data_sat[23:16]} + {1'b0, I_data_sat[15:8], 1'b0} + {2'b00, I_data_sat[7:0]};
    wire [7:0] y_cur = ysum >> 2;

    reg [7:0] y_m, y_l;
    always @(posedge I_clk) begin
        if (de_align) begin
            y_m <= y_cur;
            y_l <= y_m;
        end
    end

    wire [9:0] hysum = {2'b00, y_cur} + {1'b0, y_m, 1'b0} + {2'b00, y_l};
    reg  [7:0] hy;
    always @(posedge I_clk) begin
        if (de_align) hy <= hysum[9:2];
    end

    (* ram_style = "block" *) reg [7:0] lb_y0 [0:IMG_WIDTH-1];
    (* ram_style = "block" *) reg [7:0] lb_y1 [0:IMG_WIDTH-1];

    reg [7:0] hy_m1, hy_m2;
    always @(posedge I_clk) begin
        if (de_align) begin
            hy_m1       <= lb_y0[addr_p1];
            lb_y0[addr] <= hy;
            hy_m2       <= lb_y1[addr_p1];
            lb_y1[addr] <= hy_m1;
        end
    end

    wire [9:0] vysum = {2'b00, hy_m2} + {1'b0, hy_m1, 1'b0} + {2'b00, hy};
    reg  [7:0] yb;
    always @(posedge I_clk) begin
        if (de_align) yb <= vysum[9:2];
    end

    wire [7:0] yq = (yb & Q_KEEP) + Q_ADD;

    reg [7:0] yq_d [1:LAT_YB];
    integer i;

    always @(posedge I_clk) begin
        if (de_align) begin
            yq_d[1] <= yq;
            for (i = 2; i <= LAT_YB; i = i + 1)
                yq_d[i] <= yq_d[i-1];
        end
    end

    wire [7:0] yq_al = yq_d[LAT_YB];

    reg [7:0] yb_d [1:LAT_YB];
    integer i2;

    always @(posedge I_clk) begin
        if (de_align) begin
            yb_d[1] <= yb;
            for (i2 = 2; i2 <= LAT_YB; i2 = i2 + 1)
                yb_d[i2] <= yb_d[i2-1];
        end
    end

    wire [7:0] yb_al = yb_d[LAT_YB];

    wire [7:0] edge_in = (EDGE_SRC != 0) ? yb : yq;

    (* ram_style = "block" *) reg [7:0] lb_q0 [0:IMG_WIDTH-1];
    (* ram_style = "block" *) reg [7:0] lb_q1 [0:IMG_WIDTH-1];

    reg [7:0] q_m1, q_m2;
    always @(posedge I_clk) begin
        if (de_align) begin
            q_m1        <= lb_q0[addr_p1];
            lb_q0[addr] <= edge_in;
            q_m2        <= lb_q1[addr_p1];
            lb_q1[addr] <= q_m1;
        end
    end

    reg [7:0] b0, b1, b2;
    reg [7:0] m0, m1, m2;
    reg [7:0] t0, t1, t2;

    always @(posedge I_clk) begin
        if (de_align) begin
            b0 <= edge_in;  b1 <= b0;  b2 <= b1;
            m0 <= q_m1;     m1 <= m0;  m2 <= m1;
            t0 <= q_m2;     t1 <= t0;  t2 <= t1;
        end
    end

    wire [10:0] gx_p = {2'b00, t0} + {1'b0, m0, 1'b0} + {2'b00, b0};
    wire [10:0] gx_n = {2'b00, t2} + {1'b0, m2, 1'b0} + {2'b00, b2};
    wire [10:0] gy_p = {2'b00, b0} + {1'b0, b1, 1'b0} + {2'b00, b2};
    wire [10:0] gy_n = {2'b00, t0} + {1'b0, t1, 1'b0} + {2'b00, t2};

    wire signed [11:0] gx = {1'b0, gx_p} - {1'b0, gx_n};
    wire signed [11:0] gy = {1'b0, gy_p} - {1'b0, gy_n};
    wire [11:0] gx_abs = gx[11] ? (~gx + 12'd1) : gx;
    wire [11:0] gy_abs = gy[11] ? (~gy + 12'd1) : gy;

    reg [7:0] edge_g_r;
    reg [7:0] edge_g_d [1:ED];
    integer e;

    wire [12:0] edge_sum  = {1'b0, gx_abs} + {1'b0, gy_abs};
    wire [13:0] edge_mul  = edge_sum + {edge_sum, 1'b0};
    wire [13:0] edge_sh   = edge_mul >> E_GAIN_S;

    wire [7:0]  edge_gray = (y_cnt > 11'd3) ? ((edge_sh > 14'd255) ? 8'd255 : edge_sh[7:0])
                                            : 8'd0;

    always @(posedge I_clk) begin
        if (de_align) begin
            edge_g_r    <= edge_gray;
            edge_g_d[1] <= edge_g_r;
            for (e = 2; e <= ED; e = e + 1)
                edge_g_d[e] <= edge_g_d[e-1];
        end
    end

    wire [7:0] edge_val = (EDGE_DILATE < 1) ? edge_g_r : edge_g_d[ED];

    wire edge_wide = (edge_val > I_edge_th);

    reg [23:0] c_d1, c_d2;
    (* ram_style = "block" *) reg [23:0] lb_c0 [0:IMG_WIDTH-1];
    reg [23:0] c_m1;

    always @(posedge I_clk) begin
        if (de_align) begin
            c_d1        <= I_data_sat;
            c_d2        <= c_d1;

            c_m1        <= lb_c0[addr_p1];
            lb_c0[addr] <= c_d2;
        end
    end

    localparam integer LAT_C = LAT_EDGE - 4;

    reg [23:0] c_f [1:LAT_C];
    integer j;

    always @(posedge I_clk) begin
        if (de_align) begin
            c_f[1] <= c_m1;
            for (j = 2; j <= LAT_C; j = j + 1)
                c_f[j] <= c_f[j-1];
        end
    end

    wire [23:0] c_cur = c_f[LAT_C];

    wire [7:0] c_r = c_cur[23:16];
    wire [7:0] c_g = c_cur[15: 8];
    wire [7:0] c_b = c_cur[ 7: 0];

    wire [9:0] y_orig_sum = {2'b00, c_r} + {1'b0, c_g, 1'b0} + {2'b00, c_b};
    wire [7:0] y_orig = (y_orig_sum + 10'd2) >> 2;

    wire signed [8:0] delta_post = {1'b0, yq_al} - {1'b0, y_orig};

    wire signed [8:0] detail = {1'b0, y_orig} - {1'b0, yb_al};

    wire signed [8:0] det_abs   = detail[8] ? (~detail + 9'sd1) : detail;
    wire signed [8:0] nr_th     = $signed({1'b0, QEN_NR_TH});
    wire        det_small = (det_abs <= nr_th);
    wire signed [8:0] det_sub   = det_abs - nr_th;
    wire signed [8:0] det_mag   = det_small ? 9'sd0 : det_sub;
    wire signed [8:0] detail_nr = detail[8] ? (~det_mag + 9'sd1) : det_mag;
    wire signed [8:0] det_noise = detail - detail_nr;

    wire [11:0] wsum9 = {1'b0, b0} + {1'b0, b1} + {1'b0, b2}
                      + {1'b0, m0} + {1'b0, m1} + {1'b0, m2}
                      + {1'b0, t0} + {1'b0, t1} + {1'b0, t2};

    wire [23:0] wmul  = wsum9 * 24'd455;
    wire [7:0]  wide  = (wmul + 24'd2048) >> 12;
    wire signed [8:0] detail_mid = $signed({1'b0, yb_al}) - $signed({1'b0, wide});

    wire signed [17:0] us_prod  = $signed(detail_nr) * $signed({1'b0, I_k_us_q4});
    wire signed [17:0] delta_us = us_prod >>> 4;
    wire signed [17:0] dn_prod  = $signed(det_noise) * $signed({1'b0, CART_DN_Q4});
    wire signed [17:0] delta_dn = dn_prod >>> 4;
    wire signed [17:0] midu_prod  = $signed(detail_mid) * $signed({1'b0, QEN_MID_US_Q4});
    wire signed [17:0] delta_mid_us = midu_prod >>> 4;

    wire signed [8:0]  y_ct     = {1'b0, y_orig} - 9'sd128;
    wire signed [8:0]  ct_k     = $signed({1'b0, I_contrast_q4}) - 9'sd16;
    wire signed [17:0] ct_prod  = $signed(y_ct) * ct_k;
    wire signed [17:0] ct_delta = ct_prod >>> 4;

    wire signed [17:0] delta_all = $signed({{9{delta_post[8]}}, delta_post}) + delta_us
                                                  - delta_dn + delta_mid_us;

    wire signed [17:0] dcap_pos =  $signed({10'b0, QEN_DCAP});
    wire signed [17:0] dcap_neg = -$signed({10'b0, QEN_DCAP});

    wire [7:0] cc_max = (c_r > c_g) ? ((c_r > c_b) ? c_r : c_b)
                                    : ((c_g > c_b) ? c_g : c_b);
    wire [7:0] cc_min = (c_r < c_g) ? ((c_r < c_b) ? c_r : c_b)
                                    : ((c_g < c_b) ? c_g : c_b);
    wire signed [17:0] room_hi =  $signed({10'b0, (8'd255 - cc_max)});
    wire signed [17:0] room_lo = -$signed({10'b0, cc_min});

    wire signed [17:0] lim_hi = (QEN_DCAP != 8'd0 && dcap_pos < room_hi) ? dcap_pos : room_hi;
    wire signed [17:0] lim_lo = (QEN_DCAP != 8'd0 && dcap_neg > room_lo) ? dcap_neg : room_lo;

    localparam signed [7:0]  B_OFF8 = BRIGHT_OFF;
    wire signed [17:0] b_off = {{10{B_OFF8[7]}}, B_OFF8};

    reg [19:0] hist [0:63];

    reg        de_d1t;
    reg [10:0] line_cnt;
    integer     hi;
    always @(posedge I_clk) begin
        if (!I_rst_n) begin
            de_d1t   <= 1'b0;
            line_cnt <= 11'd0;
        end else begin
            de_d1t <= I_de;
            if (de_d1t && !I_de) begin
                if (line_cnt == IMG_HEIGHT - 1) line_cnt <= 11'd0;
                else line_cnt <= line_cnt + 11'd1;
            end
        end
    end
    wire frame_end_pulse = de_d1t && !I_de && (line_cnt == IMG_HEIGHT - 1);

    localparam [2:0] TS_IDLE = 3'd0, TS_SUM = 3'd1, TS_SCAN = 3'd2,
                     TS_IIR = 3'd3, TS_GAIN = 3'd4, TS_MAP = 3'd5, TS_CLR = 3'd6;
    reg [2:0]  ts_state;
    reg [6:0]  ts_cnt;
    reg [19:0] ts_total;
    reg [19:0] ts_cum;
    reg [7:0]  ts_med_bin;
    reg        ts_med_found;
    reg [7:0]  med_s;
    reg [8:0]  g_q8;
    reg [7:0]  ts_idx;

    reg [15:0] dv_num;
    reg [7:0]  dv_den;
    reg [15:0] dv_rem;
    reg [15:0] dv_q;
    reg [4:0]  ga_cnt;

    (* ram_style = "block" *) reg signed [8:0] tone_lut [0:255];

    wire hist_active = I_de && (ts_state == TS_IDLE);

    reg  [5:0] h_bin;
    reg        h_we;
    always @(posedge I_clk) begin
        if (!I_rst_n) begin
            h_bin <= 6'd0;
            h_we  <= 1'b0;
        end else begin
            h_bin <= hy_in[7:2];
            h_we  <= hist_active;
        end
    end
    always @(posedge I_clk) begin
        if (!I_rst_n) begin
            for (hi = 0; hi < 64; hi = hi + 1)
                hist[hi] <= 20'd0;
        end else if (h_we) begin
            hist[h_bin] <= hist[h_bin] + 20'd1;
        end else if (ts_state == TS_CLR) begin
            hist[ts_cnt[5:0]] <= 20'd0;
        end
    end

    wire [20:0] cum_new = {1'b0, ts_cum} + {1'b0, hist[ts_cnt[5:0]]};

    wire [7:0]        med_tgt  = {ts_med_bin, 2'b00} + 8'd2;
    wire signed [9:0] med_diff = $signed({2'b00, med_tgt}) - $signed({2'b00, med_s});
    wire [7:0]        med_new  = med_s + ((med_diff + 10'sd8) >>> TONE_IIR_SHIFT);
    wire [7:0]        med_eff  = (med_s == 8'd0) ? 8'd1 : med_s;

    wire [15:0]       tgt_x256 = TONE_TARGET << 8;

    always @(posedge I_clk) begin
        if (!I_rst_n) begin
            ts_state     <= TS_IDLE;
            ts_cnt       <= 7'd0;
            ts_total     <= 20'd0;
            ts_cum       <= 20'd0;
            ts_med_bin   <= 8'd32;
            ts_med_found <= 1'b0;
            med_s        <= TONE_TARGET;
            g_q8         <= 9'd256;
            ts_idx       <= 8'd0;
            dv_num       <= 16'd0;
            dv_den       <= 8'd1;
            dv_rem       <= 16'd0;
            dv_q         <= 16'd0;
            ga_cnt       <= 5'd0;
            O_y_med      <= 8'd138;
            O_y_med_tog  <= 1'b0;
        end else begin
            case (ts_state)

            TS_IDLE: begin
                ts_cnt <= 7'd0;
                if (frame_end_pulse) begin
                    ts_state <= TS_SUM;
                    ts_total <= 20'd0;

                    O_y_med     <= med_s;
                    O_y_med_tog <= ~O_y_med_tog;
                end
            end

            TS_SUM: begin
                ts_total <= ts_total + hist[ts_cnt[5:0]];
                if (ts_cnt == 7'd63) begin
                    ts_state     <= TS_SCAN;
                    ts_cum       <= 20'd0;
                    ts_cnt       <= 7'd0;
                    ts_med_found <= 1'b0;
                    ts_med_bin   <= 8'd0;
                end else begin
                    ts_cnt <= ts_cnt + 7'd1;
                end
            end

            TS_SCAN: begin
                ts_cum <= cum_new[19:0];
                if (!ts_med_found && (cum_new >= {1'b0, ts_total[19:1]})) begin
                    ts_med_found <= 1'b1;
                    ts_med_bin   <= ts_cnt[5:0];
                end
                if (ts_cnt == 7'd63) begin
                    ts_state <= TS_IIR;
                    ts_cnt   <= 7'd0;
                end else begin
                    ts_cnt <= ts_cnt + 7'd1;
                end
            end

            TS_IIR: begin
                med_s    <= med_new;
                if (TONE_EN != 0) begin
                    ga_cnt   <= 5'd17;
                    ts_state <= TS_GAIN;
                end else begin
                    ts_cnt   <= 7'd0;
                    ts_state <= TS_CLR;
                end
            end

            TS_GAIN: begin
                if (ga_cnt == 5'd17) begin
                    dv_num <= tgt_x256;
                    dv_den <= med_eff;
                    dv_rem <= 16'd0;
                    dv_q   <= 16'd0;
                    ga_cnt <= 5'd16;
                end else if (ga_cnt != 5'd0) begin
                    dv_rem <= {dv_rem[14:0], dv_num[ga_cnt-5'd1]};
                    if ({dv_rem[14:0], dv_num[ga_cnt-5'd1]} >= {8'd0, dv_den}) begin
                        dv_rem <= {dv_rem[14:0], dv_num[ga_cnt-5'd1]} - {8'd0, dv_den};
                        dv_q[ga_cnt-5'd1] <= 1'b1;
                    end
                    ga_cnt <= ga_cnt - 5'd1;
                end else begin

                    g_q8     <= (dv_q > {7'd0, TONE_GAIN_MAX_Q8}) ? TONE_GAIN_MAX_Q8 :
                                ((dv_q < {7'd0, TONE_GAIN_MIN_Q8}) ? TONE_GAIN_MIN_Q8
                                                                   : dv_q[8:0]);
                    ts_idx   <= 8'd0;
                    ts_state <= TS_MAP;
                end
            end

            TS_MAP: begin
                begin : map_blk

                    reg [16:0] mpv;
                    reg signed [9:0]  md0;
                    reg signed [17:0] md1;
                    mpv = ({9'd0, ts_idx} * {8'd0, g_q8} + 17'd128) >> 8;
                    if (mpv > 17'd255) mpv = 17'd255;
                    md0 = $signed({2'b00, mpv[7:0]}) - $signed({2'b00, ts_idx});
                    if (md0 >  10'sd127) md0 =  10'sd127;
                    if (md0 < -10'sd128) md0 = -10'sd128;

                    md1 = $signed({{8{md0[9]}}, md0}) * $signed({{10{1'b0}}, TONE_S4});
                    md1 = (md1 + 18'sd8) >>> 4;
                    if (md1 >  18'sd127) md1 =  18'sd127;
                    if (md1 < -18'sd128) md1 = -18'sd128;
                    tone_lut[ts_idx] <= md1[8:0];
                end
                if (ts_idx == 8'd255) begin
                    ts_state <= TS_CLR;
                    ts_cnt   <= 7'd0;
                end else begin
                    ts_idx <= ts_idx + 8'd1;
                end
            end

            TS_CLR: begin
                if (ts_cnt == 7'd63) begin
                    ts_state <= TS_IDLE;
                    ts_cnt   <= 7'd0;
                end else begin
                    ts_cnt <= ts_cnt + 7'd1;
                end
            end
            default: ts_state <= TS_IDLE;
            endcase
        end
    end

    wire [23:0] c_pre = c_f[LAT_C-2];
    wire [9:0]  y_e_sum = {2'b00, c_pre[23:16]} + {1'b0, c_pre[15:8], 1'b0}
                        + {2'b00, c_pre[7:0]};
    wire [7:0]  y_e = (y_e_sum + 10'd2) >> 2;
    reg  [7:0]  tone_ra;
    reg  signed [8:0] tone_d_r;
    always @(posedge I_clk) begin
        tone_ra  <= y_e;
        tone_d_r <= (TONE_EN != 0) ? tone_lut[tone_ra] : 9'sd0;
    end

    wire signed [17:0] qen_prod  = $signed(detail_nr) * $signed({1'b0, K_QEN_Q4});

    wire signed [11:0] delta_sharp = qen_prod >>> 4;

    wire signed [17:0] mid_prod   = $signed(detail_mid) * $signed({1'b0, QEN_MID_Q4});
    wire signed [17:0] delta_mid  = mid_prod >>> 4;

    wire signed [11:0] delta_qen = delta_sharp - $signed({{3{det_noise[8]}}, det_noise})
                                                  + delta_mid;

    wire [10:0] diag_x = addr_d[LAT_EDGE];

    reg [23:0] raw_d [1:LAT_EDGE+1];
    integer n;
    always @(posedge I_clk) begin
        if (de_align) begin
            raw_d[1] <= I_data;
            for (n = 2; n <= LAT_EDGE+1; n = n + 1)
                raw_d[n] <= raw_d[n-1];
        end
    end
    wire [23:0] raw_al = raw_d[LAT_EDGE+1];

    reg [LAT_EDGE:1] de_d;
    reg [LAT_EDGE:1] user_d;
    reg [LAT_EDGE:1] last_d;
    integer k;

    always @(posedge I_clk) begin
        if (!I_rst_n) begin
            de_d   <= {LAT_EDGE{1'b0}};
            user_d <= {LAT_EDGE{1'b0}};
            last_d <= {LAT_EDGE{1'b0}};
        end
        else if (de_align) begin
            de_d[1]   <= 1'b1;
            user_d[1] <= user_align;
            last_d[1] <= last_align;
            for (k = 2; k <= LAT_EDGE; k = k + 1) begin
                de_d[k]   <= de_d[k-1];
                user_d[k] <= user_d[k-1];
                last_d[k] <= last_d[k-1];
            end
        end
        else begin
            de_d[1]   <= 1'b0;
            user_d[1] <= 1'b0;
            last_d[1] <= 1'b0;
            for (k = 2; k <= LAT_EDGE; k = k + 1) begin
                de_d[k]   <= de_d[k-1];
                user_d[k] <= user_d[k-1];
                last_d[k] <= last_d[k-1];
            end
        end
    end

    wire de_al   = de_d[LAT_EDGE];
    wire user_al = user_d[LAT_EDGE];
    wire last_al = last_d[LAT_EDGE];

    reg [10:0] addr_d [1:LAT_EDGE];
    integer m;

    always @(posedge I_clk) begin
        if (de_align) begin
            addr_d[1] <= addr;
            for (m = 2; m <= LAT_EDGE; m = m + 1)
                addr_d[m] <= addr_d[m-1];
        end
    end

    wire [10:0] out_x = addr_d[LAT_EDGE];
    wire line_head = (out_x < 11'd8);

    wire        draw_edge  = (I_edge_dark != 2'd0) && edge_wide && !line_head;

    wire [15:0] edge_boost = edge_val * I_ev_gain;
    wire [7:0]  edge_bt    = (edge_boost > 16'd255) ? 8'd255 : edge_boost[7:0];
    wire [7:0]  edge_out   = line_head ? 8'd0 : edge_bt;

    wire [23:0] edge_bin_view = edge_wide ? 24'hFFFFFF : 24'h000000;

    reg signed [17:0] P_us_q, P_dn_q, P_mid_q, P_ct_q;
    reg signed [17:0] P_qen_q, P_qmid_q;
    reg signed [8:0]  P_dpost_q, P_dnoise_q, P_tone_q;
    reg signed [17:0] P_limhi_q, P_limlo_q;
    reg [7:0]         P_cr_q, P_cg_q, P_cb_q, P_yq_q, P_edgeout_q;
    reg [23:0]        P_ccur_q;
    reg               P_drawedge_q, P_edgebin_q;

    always @(posedge I_clk) begin
        P_us_q       <= us_prod;
        P_dn_q       <= dn_prod;
        P_mid_q      <= midu_prod;
        P_ct_q       <= ct_prod;
        P_qen_q      <= qen_prod;
        P_qmid_q     <= mid_prod;
        P_dpost_q    <= delta_post;
        P_dnoise_q   <= det_noise;
        P_tone_q     <= tone_d_r;
        P_limhi_q    <= lim_hi;
        P_limlo_q    <= lim_lo;
        P_cr_q       <= c_r;
        P_cg_q       <= c_g;
        P_cb_q       <= c_b;
        P_yq_q       <= yq_al;
        P_edgeout_q  <= edge_out;
        P_ccur_q     <= c_cur;
        P_drawedge_q <= draw_edge;
        P_edgebin_q  <= edge_wide;
    end

    wire signed [17:0] d_us_q  = P_us_q  >>> 4;
    wire signed [17:0] d_dn_q  = P_dn_q  >>> 4;
    wire signed [17:0] d_mid_q = P_mid_q >>> 4;
    wire signed [17:0] d_ct_q  = P_ct_q  >>> 4;

    wire signed [17:0] delta_all_q = $signed({{9{P_dpost_q[8]}}, P_dpost_q})
                                   + d_us_q - d_dn_q + d_mid_q;

    wire signed [17:0] delta_all_bq = delta_all_q + b_off + d_ct_q + P_tone_q;
    wire signed [17:0] delta_all_lq = (delta_all_bq > P_limhi_q) ? P_limhi_q :
                                      ((delta_all_bq < P_limlo_q) ? P_limlo_q : delta_all_bq);

    wire signed [17:0] r_sum_q = $signed({10'b0, P_cr_q}) + delta_all_lq;
    wire signed [17:0] g_sum_q = $signed({10'b0, P_cg_q}) + delta_all_lq;
    wire signed [17:0] b_sum_q = $signed({10'b0, P_cb_q}) + delta_all_lq;

    wire [7:0] r_c = r_sum_q[17] ? 8'd0 : ((r_sum_q > 18'sd255) ? 8'd255 : r_sum_q[7:0]);
    wire [7:0] g_c = g_sum_q[17] ? 8'd0 : ((g_sum_q > 18'sd255) ? 8'd255 : g_sum_q[7:0]);
    wire [7:0] b_c = b_sum_q[17] ? 8'd0 : ((b_sum_q > 18'sd255) ? 8'd255 : b_sum_q[7:0]);

    wire [7:0] ct_r = r_c;
    wire [7:0] ct_g = g_c;
    wire [7:0] ct_b = b_c;

    wire [23:0] mono_pixel  = {P_yq_q, P_yq_q, P_yq_q};
    wire [23:0] color_pixel = (MONO != 0) ? mono_pixel : {ct_r, ct_g, ct_b};
    wire [23:0] sat_pixel   = color_pixel;

    wire [7:0] ek_r = (I_edge_dark <= 2'd1) ? 8'd0 : ((I_edge_dark == 2'd2) ? {1'b0, ct_r[7:1]} : {2'b00, ct_r[7:2]});
    wire [7:0] ek_g = (I_edge_dark <= 2'd1) ? 8'd0 : ((I_edge_dark == 2'd2) ? {1'b0, ct_g[7:1]} : {2'b00, ct_g[7:2]});
    wire [7:0] ek_b = (I_edge_dark <= 2'd1) ? 8'd0 : ((I_edge_dark == 2'd2) ? {1'b0, ct_b[7:1]} : {2'b00, ct_b[7:2]});
    wire [23:0] edge_color = {ek_r, ek_g, ek_b};

    wire [23:0] cart_pixel = sat_pixel;
    wire [23:0] ext_pixel  = P_drawedge_q ? edge_color : cart_pixel;

    wire [23:0] edge_view_q  = {P_edgeout_q, P_edgeout_q, P_edgeout_q};
    wire [23:0] edge_bin_q   = P_edgebin_q ? 24'hFFFFFF : 24'h000000;

    wire [23:0] mode_pixel = (I_mode == 2'd1) ? edge_view_q  :
                             (I_mode == 2'd2) ? P_ccur_q     :
                             (I_mode == 2'd3) ? edge_bin_q   :
                                                ext_pixel;

    wire [23:0] diag_pixel = (DIAG_MODE == 1) ?
                             ((diag_x < 11'd426) ? raw_al :
                             ((diag_x < 11'd853) ? P_ccur_q : sat_pixel)) :
                             sat_pixel;

    wire signed [11:0] d_sharp_q = P_qen_q >>> 4;
    wire signed [17:0] d_qmid_q  = P_qmid_q >>> 4;
    wire signed [11:0] delta_qen_q = d_sharp_q
                                   - $signed({{3{P_dnoise_q[8]}}, P_dnoise_q})
                                   + d_qmid_q;
    wire signed [11:0] delta_qen_bq = delta_qen_q + b_off + d_ct_q + P_tone_q;
    wire signed [11:0] delta_qen_lq = (delta_qen_bq > P_limhi_q) ? P_limhi_q :
                                      ((delta_qen_bq < P_limlo_q) ? P_limlo_q : delta_qen_bq);

    wire signed [12:0] qs_r = $signed({5'b0, P_cr_q}) + delta_qen_lq;
    wire signed [12:0] qs_g = $signed({5'b0, P_cg_q}) + delta_qen_lq;
    wire signed [12:0] qs_b = $signed({5'b0, P_cb_q}) + delta_qen_lq;

    wire [7:0] q_r = (qs_r < 0) ? 8'd0 : ((qs_r > 13'sd255) ? 8'd255 : qs_r[7:0]);
    wire [7:0] q_g = (qs_g < 0) ? 8'd0 : ((qs_g > 13'sd255) ? 8'd255 : qs_g[7:0]);
    wire [7:0] q_b = (qs_b < 0) ? 8'd0 : ((qs_b > 13'sd255) ? 8'd255 : qs_b[7:0]);
    wire [23:0] enh_pixel = {q_r, q_g, q_b};

    wire [23:0] out_sel    = I_qen ? enh_pixel : mode_pixel;

    function [23:0] F_sat24;
        input [23:0] p;
        reg  [9:0]  yy;
        reg  signed [12:0] dr, dg, db, kr, kg, kb, rr, gg, bb;
        begin
            yy = ({2'b00, p[23:16]} + {1'b0, p[15:8], 1'b0} + {2'b00, p[7:0]} + 10'd2) >> 2;
            dr = $signed({5'b00000, p[23:16]}) - $signed({5'b00000, yy[7:0]});
            dg = $signed({5'b00000, p[15: 8]}) - $signed({5'b00000, yy[7:0]});
            db = $signed({5'b00000, p[ 7: 0]}) - $signed({5'b00000, yy[7:0]});
            case (I_sat_k)
                1: begin kr = dr;             kg = dg;             kb = db;             end
                2: begin kr = dr + dr;        kg = dg + dg;        kb = db + db;        end
                3: begin kr = dr + (dr<<<1);  kg = dg + (dg<<<1);  kb = db + (db<<<1);  end
                4: begin kr = dr<<<2;         kg = dg<<<2;         kb = db<<<2;         end
                default: begin kr = dr;       kg = dg;             kb = db;             end
            endcase
            rr = $signed({5'b00000, yy[7:0]}) + kr;
            gg = $signed({5'b00000, yy[7:0]}) + kg;
            bb = $signed({5'b00000, yy[7:0]}) + kb;
            F_sat24 = { (rr[12] ? 8'd0 : ((rr > 13'sd255) ? 8'd255 : rr[7:0])),
                        (gg[12] ? 8'd0 : ((gg > 13'sd255) ? 8'd255 : gg[7:0])),
                        (bb[12] ? 8'd0 : ((bb > 13'sd255) ? 8'd255 : bb[7:0])) };
        end
    endfunction

    reg [23:0] out_sel_d;
    reg        de_al_d1, user_al_d1, last_al_d1;
    reg        de_al_d0, user_al_d0, last_al_d0;
    always @(posedge I_clk) begin
        if (!I_rst_n) begin
            out_sel_d  <= 24'd0;
            de_al_d1   <= 1'b0;
            user_al_d1 <= 1'b0;
            last_al_d1 <= 1'b0;
            de_al_d0   <= 1'b0;
            user_al_d0 <= 1'b0;
            last_al_d0 <= 1'b0;
        end else begin
            out_sel_d  <= out_sel;
            de_al_d0   <= de_al;
            user_al_d0 <= user_al;
            last_al_d0 <= last_al;
            de_al_d1   <= de_al_d0;
            user_al_d1 <= user_al_d0;
            last_al_d1 <= last_al_d0;
        end
    end

    wire [23:0] out_pixel = ((I_sat_en != 1'b0) && (MONO == 0)) ? F_sat24(out_sel_d) : out_sel_d;

    always @(posedge I_clk) begin
        if (!I_rst_n) begin
            O_de   <= 1'b0;
            O_user <= 1'b0;
            O_last <= 1'b0;
            O_data <= 24'd0;
        end
        else begin
            O_de   <= de_al_d1;
            O_user <= user_al_d1;
            O_last <= last_al_d1;
            if (de_al_d1) begin

                if (DIAG_MODE != 0)
                    O_data <= diag_pixel;
                else
                    O_data <= out_pixel;
            end
        end
    end

endmodule
