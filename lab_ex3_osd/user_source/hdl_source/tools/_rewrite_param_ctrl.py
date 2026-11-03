# -*- coding: utf-8 -*-
"""重写 param_ctrl.v：
   1) 用 target_detect v4（改锥/魔方/黑色物体 三类）替换原 target_detect + 删除 pose_detect
   2) 重写 target_osd v4（三类框 + 名称卡片，去掉姿态）
   3) 端口/默认值/串口分支：P26/P27 改作 魔方饱和度 / 改锥亮度下限
   4) 顶部参数文档、P23 注释同步
"""
import io, sys

P = r"C:/Users/Lenovo/Desktop/lab_ex3_osd_SC500_720P/lab_ex3_osd/user_source/hdl_source/param_ctrl.v"
with io.open(P, "r", encoding="utf-8") as f:
    src = f.read()

# ---------------------------------------------------------------------------
# 1) 替换 target_detect 模块 + 删除 pose_detect 模块
# ---------------------------------------------------------------------------
A = "//  来自原 target_detect.v（284 行）"
B = "//  来自原 target_osd.v（510 行）"
ia = src.index(A)
ib = src.index(B)

NEW_TD = r'''//  来自原 target_detect.v（284 行），2026-10-29 重写为三类
//---------------------------------------------------------------------------
//=============================================================================
//  target_detect  v4  --  三类物体检测（改锥 / 魔方 / 黑色物体）
//                         （带行投影阈值 + 帧间保持，沿用 v3 的抗抖/抗闪断）
//
//  2026-10-29：在 v3（红/黑两类）基础上扩成三类，并删除人体姿态识别。
//  三类判据（全部基于 video_out 原始像素，OSD 之前，不受滤镜/logo 影响）：
//    改锥(orange)：R 最大 且 (R-B) >= P23 且 R >= P27
//                  —— 橙色手柄 raw (246,89,40) -> R-B=206，远超阈值
//    魔方(vivid) ：饱和度 sat_v >= P26 且（G 最大 或 B 最大）
//                  —— 黄面(G max, sat 67) / 蓝面(B max, sat 103) 命中；
//                    红面(R max) 不算 vivid（靠其它彩色面认魔方）
//    黑色(dark)  ：max(R,G,B) < P25 且 sat_v < 32（无色度）
//                  —— 黑色物体 raw max<70、饱和≈0；亮背景不会误检
//
//  ⚠ 优先级天然互斥：orange 要求 R 主导；vivid 要求 G/B 主导；dark 要求低饱和。
//    所以同一像素不会进两类。魔方黄色面 raw mx=69（<P25=70）但 sat 高 -> vivid，
//    不会误判成黑色；这正是 P25 不必对彩色面放宽的原因。
//
//  其余（8x8 降采样、行投影阈值、帧间保持、网格对齐）与 v3 完全一致，
//  资源约 ~420 LUT + ~260 DFF，0 ERAM，0 DSP。
//=============================================================================

module target_detect #(
    parameter IMG_WIDTH  = 1280,
    parameter IMG_HEIGHT = 720,
    parameter DS_LOG2    = 3,          // 8x8 -> 160x90
    parameter DE_LAG     = 1,
    parameter [7:0]  BLK_SAT = 8'd32,  // 黑色要求"无色度"：max-min < 32
    parameter [7:0]  PROJ_TH = 8'd2,   // 行投影阈值：本行至少几个命中才作数
    parameter [7:0]  HOLD_N  = 8'd30,  // 丢失后保持多少帧（0.5 秒 @60fps）
    parameter [8:0]  MAX_W   = 9'd150, // 任意类宽度上限（格）：防半屏误检
    parameter [8:0]  MAX_H   = 9'd88   // 任意类高度上限（格）
)(
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire        I_de,
    input  wire [23:0] I_data,      // {R,G,B}

    input  wire [7:0]  I_orange_th,    // P23 改锥 R-B 主导阈值
    input  wire [7:0]  I_orange_rmin,  // P27 改锥 R 亮度下限（原 VMIN）
    input  wire [7:0]  I_blk_th,       // P25 黑色亮度上限（原始像素域）
    input  wire [7:0]  I_vivid_sat,    // P26 魔方饱和度下限
    input  wire [15:0] I_min_pix,      // P24 最小采样点数

    output reg         O_orange_valid,
    output reg  [8:0]  O_orange_x0, O_orange_x1,
    output reg  [7:0]  O_orange_y0, O_orange_y1,

    output reg         O_vivid_valid,
    output reg  [8:0]  O_vivid_x0, O_vivid_x1,
    output reg  [7:0]  O_vivid_y0, O_vivid_y1,

    output reg         O_dark_valid,
    output reg  [8:0]  O_dark_x0, O_dark_x1,
    output reg  [7:0]  O_dark_y0, O_dark_y1,

    output reg  [1:0]  O_win_class     // 0=改锥 1=魔方 2=黑色物体（胜者）
);

    localparam W = IMG_WIDTH  >> DS_LOG2;
    localparam H = IMG_HEIGHT >> DS_LOG2;
    localparam [8:0] X0_INIT = 9'h1FF;
    localparam [7:0] Y0_INIT = 8'hFF;

    // 1. de 对齐 + 行列计数
    reg [3:0] de_sr;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) de_sr <= 4'd0;
        else          de_sr <= {de_sr[2:0], I_de};
    end
    wire de_a = de_sr[DE_LAG-1];

    reg [10:0] x_cnt, y_cnt;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin x_cnt <= 11'd0; y_cnt <= 11'd0; end
        else if (de_a) begin
            if (x_cnt == IMG_WIDTH-1) begin
                x_cnt <= 11'd0;
                if (y_cnt == IMG_HEIGHT-1) y_cnt <= 11'd0;
                else y_cnt <= y_cnt + 1'b1;
            end else x_cnt <= x_cnt + 1'b1;
        end
    end

    wire frame_end = de_a && (x_cnt == IMG_WIDTH-1) && (y_cnt == IMG_HEIGHT-1);
    wire sample    = de_a && (x_cnt[DS_LOG2-1:0] == 0) && (y_cnt[DS_LOG2-1:0] == 0);
    wire [8:0] s_x = x_cnt >> DS_LOG2;
    wire [7:0] s_y = y_cnt >> DS_LOG2;
    wire row_end = sample && (s_x == (W-1));

    // 2. 判色
    wire [7:0] r = I_data[23:16];
    wire [7:0] g = I_data[15:8];
    wire [7:0] b = I_data[7:0];

    wire r_gt_g = (r > g);
    wire r_gt_b = (r > b);
    wire [7:0] d_rb = r_gt_b ? (r - b) : (b - r);   // R/B 差绝对值

    wire [7:0] mx_rg = (r > g) ? r : g;
    wire [7:0] mx    = (mx_rg > b) ? mx_rg : b;
    wire [7:0] mn_rg = (r < g) ? r : g;
    wire [7:0] mn    = (mn_rg < b) ? mn_rg : b;
    wire [7:0] sat_v = mx - mn;

    wire is_orange = r_gt_g && r_gt_b && (d_rb >= I_orange_th) && (r >= I_orange_rmin);
    wire is_vivid  = (sat_v >= I_vivid_sat) && ((g >= r && g >= b) || (b >= r && b >= g));
    wire is_dark   = (mx < I_blk_th) && (sat_v < BLK_SAT);

    // 3. 行累加器（每类一套）
    reg [7:0] ol_cnt, vl_cnt, dl_cnt;
    reg [8:0] ol_min, ol_max, vl_min, vl_max, dl_min, dl_max;

    wire        orange_now = sample && is_orange;
    wire        vivid_now  = sample && is_vivid;
    wire        dark_now   = sample && is_dark;

    wire [7:0] ol_cnt_n = ol_cnt + (orange_now ? 8'd1 : 8'd0);
    wire [8:0] ol_min_n = (orange_now && (s_x < ol_min)) ? s_x : ol_min;
    wire [8:0] ol_max_n = (orange_now && (s_x > ol_max)) ? s_x : ol_max;
    wire [7:0] vl_cnt_n = vl_cnt + (vivid_now ? 8'd1 : 8'd0);
    wire [8:0] vl_min_n = (vivid_now && (s_x < vl_min)) ? s_x : vl_min;
    wire [8:0] vl_max_n = (vivid_now && (s_x > vl_max)) ? s_x : vl_max;
    wire [7:0] dl_cnt_n = dl_cnt + (dark_now ? 8'd1 : 8'd0);
    wire [8:0] dl_min_n = (dark_now && (s_x < dl_min)) ? s_x : dl_min;
    wire [8:0] dl_max_n = (dark_now && (s_x > dl_max)) ? s_x : dl_max;

    // 4. 帧累加器（外接框）
    reg [8:0] ox0, ox1, vx0, vx1, dx0, dx1;
    reg [7:0] oy0, oy1, vy0, vy1, dy0, dy1;
    reg       clr;
    reg [7:0] o_miss, v_miss, d_miss;
    reg [13:0] o_total, v_total, d_total;

    wire o_ok = (ox0<=ox1)&&(oy0<=oy1)&&((ox1-ox0)>=9'd1)&&((oy1-oy0)>=8'd1)&&((ox1-ox0)<=MAX_W)&&((oy1-oy0)<=MAX_H);
    wire v_ok = (vx0<=vx1)&&(vy0<=vy1)&&((vx1-vx0)>=9'd1)&&((vy1-vy0)>=8'd1)&&((vx1-vx0)<=MAX_W)&&((vy1-vy0)<=MAX_H);
    wire d_ok = (dx0<=dx1)&&(dy0<=dy1)&&((dx1-dx0)>=9'd1)&&((dy1-dy0)>=8'd1)&&((dx1-dx0)<=MAX_W)&&((dy1-dy0)<=MAX_H);

    wire cand_o = o_ok && (o_total >= I_min_pix);
    wire cand_v = v_ok && (v_total >= I_min_pix);
    wire cand_d = d_ok && (d_total >= I_min_pix);

    // 5. 主时序
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            clr <= 1'b0;
            ol_cnt<=8'd0; ol_min<=X0_INIT; ol_max<=9'd0;
            vl_cnt<=8'd0; vl_min<=X0_INIT; vl_max<=9'd0;
            dl_cnt<=8'd0; dl_min<=X0_INIT; dl_max<=9'd0;
            ox0<=X0_INIT; ox1<=9'd0; oy0<=Y0_INIT; oy1<=8'd0;
            vx0<=X0_INIT; vx1<=9'd0; vy0<=Y0_INIT; vy1<=8'd0;
            dx0<=X0_INIT; dx1<=9'd0; dy0<=Y0_INIT; dy1<=8'd0;
            o_total<=14'd0; v_total<=14'd0; d_total<=14'd0;
            o_miss<=8'd0; v_miss<=8'd0; d_miss<=8'd0;
            O_orange_valid<=1'b0; O_vivid_valid<=1'b0; O_dark_valid<=1'b0;
            O_orange_x0<=9'd0;O_orange_x1<=9'd0;O_orange_y0<=8'd0;O_orange_y1<=8'd0;
            O_vivid_x0<=9'd0; O_vivid_x1<=9'd0; O_vivid_y0<=8'd0; O_vivid_y1<=8'd0;
            O_dark_x0<=9'd0;  O_dark_x1<=9'd0;  O_dark_y0<=8'd0;  O_dark_y1<=8'd0;
            O_win_class<=2'd0;
        end else begin
            clr <= 1'b0;

            if (clr) begin
                ox0<=X0_INIT; ox1<=9'd0; oy0<=Y0_INIT; oy1<=8'd0;
                vx0<=X0_INIT; vx1<=9'd0; vy0<=Y0_INIT; vy1<=8'd0;
                dx0<=X0_INIT; dx1<=9'd0; dy0<=Y0_INIT; dy1<=8'd0;
                o_total<=14'd0; v_total<=14'd0; d_total<=14'd0;
            end

            if (sample) begin
                ol_cnt<=ol_cnt_n; ol_min<=ol_min_n; ol_max<=ol_max_n;
                vl_cnt<=vl_cnt_n; vl_min<=vl_min_n; vl_max<=vl_max_n;
                dl_cnt<=dl_cnt_n; dl_min<=dl_min_n; dl_max<=dl_max_n;
                if (orange_now) o_total <= o_total + 14'd1;
                if (vivid_now)  v_total <= v_total + 14'd1;
                if (dark_now)   d_total <= d_total + 14'd1;
            end

            if (row_end) begin
                if ((ol_cnt_n >= PROJ_TH) && (ol_min_n <= ol_max_n)) begin
                    if (s_y < oy0) oy0 <= s_y;
                    if (s_y > oy1) oy1 <= s_y;
                    if (ol_min_n < ox0) ox0 <= ol_min_n;
                    if (ol_max_n > ox1) ox1 <= ol_max_n;
                end
                if ((vl_cnt_n >= PROJ_TH) && (vl_min_n <= vl_max_n)) begin
                    if (s_y < vy0) vy0 <= s_y;
                    if (s_y > vy1) vy1 <= s_y;
                    if (vl_min_n < vx0) vx0 <= vl_min_n;
                    if (vl_max_n > vx1) vx1 <= vl_max_n;
                end
                if ((dl_cnt_n >= PROJ_TH) && (dl_min_n <= dl_max_n)) begin
                    if (s_y < dy0) dy0 <= s_y;
                    if (s_y > dy1) dy1 <= s_y;
                    if (dl_min_n < dx0) dx0 <= dl_min_n;
                    if (dl_max_n > dx1) dx1 <= dl_max_n;
                end
                ol_cnt<=8'd0; ol_min<=X0_INIT; ol_max<=9'd0;
                vl_cnt<=8'd0; vl_min<=X0_INIT; vl_max<=9'd0;
                dl_cnt<=8'd0; dl_min<=X0_INIT; dl_max<=9'd0;
            end

            if (frame_end) begin
                // 改锥
                if (cand_o) begin
                    O_orange_valid<=1'b1;
                    O_orange_x0<=ox0; O_orange_x1<=ox1;
                    O_orange_y0<=oy0; O_orange_y1<=oy1;
                    o_miss<=8'd0;
                end else if (o_miss < HOLD_N) o_miss <= o_miss + 8'd1;
                else O_orange_valid <= 1'b0;
                // 魔方
                if (cand_v) begin
                    O_vivid_valid<=1'b1;
                    O_vivid_x0<=vx0; O_vivid_x1<=vx1;
                    O_vivid_y0<=vy0; O_vivid_y1<=vy1;
                    v_miss<=8'd0;
                end else if (v_miss < HOLD_N) v_miss <= v_miss + 8'd1;
                else O_vivid_valid <= 1'b0;
                // 黑色
                if (cand_d) begin
                    O_dark_valid<=1'b1;
                    O_dark_x0<=dx0; O_dark_x1<=dx1;
                    O_dark_y0<=dy0; O_dark_y1<=dy1;
                    d_miss<=8'd0;
                end else if (d_miss < HOLD_N) d_miss <= d_miss + 8'd1;
                else O_dark_valid <= 1'b0;

                // 胜者（按采样点数取最大；都不行则保持上一帧）
                if (cand_o && (!cand_v || o_total >= v_total) && (!cand_d || o_total >= d_total))
                    O_win_class <= 2'd0;
                else if (cand_v && (!cand_d || v_total >= d_total))
                    O_win_class <= 2'd1;
                else if (cand_d)
                    O_win_class <= 2'd2;

                clr <= 1'b1;
            end
        end
    end

endmodule

'''

src = src[:ia] + NEW_TD + src[ib:]

# ---------------------------------------------------------------------------
# 2) 重写 target_osd 模块（从 "module target_osd #(" 到 EOF）
# ---------------------------------------------------------------------------
C = "module target_osd #("
ic = src.index(C)

NEW_OSD = r'''module target_osd #(
    parameter IMG_WIDTH  = 1280,
    parameter IMG_HEIGHT = 720,
    parameter DE_LAG     = 1
)(
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire        I_de,
    input  wire [23:0] I_data,
    input  wire        I_en,

    // 改锥（橙色）
    input  wire        I_orange_valid,
    input  wire [8:0]  I_orange_x0, I_orange_x1,
    input  wire [7:0]  I_orange_y0, I_orange_y1,
    // 魔方（彩色）
    input  wire        I_vivid_valid,
    input  wire [8:0]  I_vivid_x0, I_vivid_x1,
    input  wire [7:0]  I_vivid_y0, I_vivid_y1,
    // 黑色物体
    input  wire        I_dark_valid,
    input  wire [8:0]  I_dark_x0, I_dark_x1,
    input  wire [7:0]  I_dark_y0, I_dark_y1,
    // 胜者类别：0=改锥 1=魔方 2=黑色（卡片写在它身上）
    input  wire [1:0]  I_win_class,

    output reg         O_de,
    output reg  [23:0] O_data
);

    // 字库索引（必须和 tools/gen_font_mif.py 的 ORDER/ZH_CHARS 一致）
    localparam [5:0] C_A=6'd0,C_B=6'd1,C_C=6'd2,C_D=6'd3,C_E=6'd4,C_F=6'd5,
                     C_G=6'd6,C_H=6'd7,C_I=6'd8,C_J=6'd9,C_K=6'd10,C_L=6'd11,
                     C_M=6'd12,C_N=6'd13,C_O=6'd14,C_P=6'd15,C_Q=6'd16,C_R=6'd17,
                     C_S=6'd18,C_T=6'd19,C_U=6'd20,C_V=6'd21,C_W=6'd22,C_X=6'd23,
                     C_Y=6'd24,C_Z=6'd25,
                     C_0=6'd26,C_1=6'd27,C_2=6'd28,C_3=6'd29,C_4=6'd30,C_5=6'd31,
                     C_6=6'd32,C_7=6'd33,C_8=6'd34,C_9=6'd35,
                     C_SP=6'd36,
                     C_GAI=6'd41, C_ZHUI=6'd42, C_MO=6'd43, C_FANG=6'd44,
                     C_HEI=6'd45, C_SE=6'd46, C_WU=6'd47, C_TI=6'd48;

    //-------------------------------------------------------------------------
    // 1. 行列计数（靠自身归零对齐，不依赖 vsync）
    //-------------------------------------------------------------------------
    reg [3:0] de_sr;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) de_sr <= 4'd0;
        else          de_sr <= {de_sr[2:0], I_de};
    end
    wire de_a = de_sr[DE_LAG-1];

    reg [10:0] x_cnt, y_cnt;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin x_cnt <= 11'd0; y_cnt <= 11'd0; end
        else if (de_a) begin
            if (x_cnt == IMG_WIDTH-1) begin
                x_cnt <= 11'd0;
                if (y_cnt == IMG_HEIGHT-1) y_cnt <= 11'd0;
                else y_cnt <= y_cnt + 1'b1;
            end else x_cnt <= x_cnt + 1'b1;
        end
    end
    wire [11:0] px = {1'b0, x_cnt};
    wire [11:0] py = {1'b0, y_cnt};

    //-------------------------------------------------------------------------
    // 2. 胜者坐标 -> BCD（只算 cx/cy 两个值，全在消隐期）
    //    卡片第 2 行要显示 "X 640 Y360" 这种像素坐标
    //-------------------------------------------------------------------------
    wire [8:0] wx0 = (I_win_class==2'd0) ? I_orange_x0 : (I_win_class==2'd1) ? I_vivid_x0 : I_dark_x0;
    wire [8:0] wx1 = (I_win_class==2'd0) ? I_orange_x1 : (I_win_class==2'd1) ? I_vivid_x1 : I_dark_x1;
    wire [7:0] wy0 = (I_win_class==2'd0) ? I_orange_y0 : (I_win_class==2'd1) ? I_vivid_y0 : I_dark_y0;
    wire [7:0] wy1 = (I_win_class==2'd0) ? I_orange_y1 : (I_win_class==2'd1) ? I_vivid_y1 : I_dark_y1;

    // 中心像素坐标：((x0+x1+1)/2)*8 = (x0+x1+1)*4
    wire [8:0]  cx_g = wx0 + wx1 + 9'd1;                 // <= 319
    wire [7:0]  cy_g = wy0 + wy1 + 8'd1;                 // <= 179
    wire [10:0] cx_px = {2'b00, cx_g} << 2;              // <= 1276
    wire [9:0]  cy_px = {2'b00, cy_g} << 2;              // <= 716

    reg [5:0]  bc_ph;      // 0..24：x（11 次移位）+ y（11 次移位）
    reg [10:0] bc_sr;      // 被转换的值
    reg [15:0] bc_d;       // BCD 累加器（4 位）
    reg [15:0] dx_bcd;     // 目标 x
    reg [15:0] dy_bcd;     // 目标 y

    wire bc_shift = ((bc_ph >= 7'd1)  && (bc_ph <= 7'd11)) ||
                    ((bc_ph >= 7'd13) && (bc_ph <= 7'd23));

    wire [3:0] b0 = bc_d[3:0];
    wire [3:0] b1 = bc_d[7:4];
    wire [3:0] b2 = bc_d[11:8];
    wire [3:0] b3 = bc_d[15:12];
    wire [3:0] a0 = (b0 > 4'd4) ? (b0 + 4'd3) : b0;
    wire [3:0] a1 = (b1 > 4'd4) ? (b1 + 4'd3) : b1;
    wire [3:0] a2 = (b2 > 4'd4) ? (b2 + 4'd3) : b2;
    wire [3:0] a3 = (b3 > 4'd4) ? (b3 + 4'd3) : b3;

    wire [26:0] bc_sh = {a3, a2, a1, a0, bc_sr} << 1;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            bc_ph  <= 7'd0;
            bc_sr  <= 11'd0;
            bc_d   <= 16'd0;
            dx_bcd <= 16'd0;
            dy_bcd <= 16'd0;
        end else begin
            bc_ph <= (bc_ph == 7'd24) ? 7'd0 : (bc_ph + 7'd1);

            if (bc_shift) begin
                bc_sr <= bc_sh[10:0];
                bc_d  <= bc_sh[26:11];
            end
            else if (bc_ph == 7'd0) begin
                bc_sr <= cx_px;               // 装载目标 x
                bc_d  <= 16'd0;
            end
            else if (bc_ph == 7'd12) begin
                dx_bcd <= bc_d;               // 目标 x 完成
                bc_sr  <= {1'b0, cy_px};      // 装载目标 y
                bc_d   <= 16'd0;
            end
            else if (bc_ph == 7'd24) begin
                dy_bcd <= bc_d;               // 目标 y 完成
            end
        end
    end

    // 数字位
    wire [3:0] xd3 = dx_bcd[15:12];
    wire [3:0] xd2 = dx_bcd[11:8];
    wire [3:0] xd1 = dx_bcd[7:4];
    wire [3:0] xd0 = dx_bcd[3:0];
    wire [3:0] yd2 = dy_bcd[11:8];
    wire [3:0] yd1 = dy_bcd[7:4];
    wire [3:0] yd0 = dy_bcd[3:0];

    // 前导零不显示（用空格占位，避免文字左右跳）
    wire x_lt1000 = (cx_px < 11'd1000);
    wire x_lt100  = (cx_px < 11'd100);
    wire y_lt100  = (cy_px < 10'd100);

    //-------------------------------------------------------------------------
    // 3. 三个检测框（网格 -> 屏幕像素，1 格 = 8 像素）
    //-------------------------------------------------------------------------
    wire [11:0] ox0p = {3'b000, I_orange_x0} << 3;
    wire [11:0] ox1p = ({3'b000, I_orange_x1} << 3) + 12'd7;
    wire [11:0] oy0p = {4'b0000, I_orange_y0} << 3;
    wire [11:0] oy1p = ({4'b0000, I_orange_y1} << 3) + 12'd7;

    wire [11:0] vx0p = {3'b000, I_vivid_x0} << 3;
    wire [11:0] vx1p = ({3'b000, I_vivid_x1} << 3) + 12'd7;
    wire [11:0] vy0p = {4'b0000, I_vivid_y0} << 3;
    wire [11:0] vy1p = ({4'b0000, I_vivid_y1} << 3) + 12'd7;

    wire [11:0] kx0p = {3'b000, I_dark_x0} << 3;
    wire [11:0] kx1p = ({3'b000, I_dark_x1} << 3) + 12'd7;
    wire [11:0] ky0p = {4'b0000, I_dark_y0} << 3;
    wire [11:0] ky1p = ({4'b0000, I_dark_y1} << 3) + 12'd7;

    wire orange_on = I_en && I_orange_valid &&
                  (px >= ox0p) && (px <= ox1p) && (py >= oy0p) && (py <= oy1p) &&
                  (((px < (ox0p + 12'd2)) || (px > (ox1p - 12'd2))) ||
                   ((py < (oy0p + 12'd2)) || (py > (oy1p - 12'd2))));

    wire vivid_on = I_en && I_vivid_valid &&
                  (px >= vx0p) && (px <= vx1p) && (py >= vy0p) && (py <= vy1p) &&
                  (((px < (vx0p + 12'd2)) || (px > (vx1p - 12'd2))) ||
                   ((py < (vy0p + 12'd2)) || (py > (vy1p - 12'd2))));

    wire dark_on = I_en && I_dark_valid &&
                  (px >= kx0p) && (px <= kx1p) && (py >= ky0p) && (py <= ky1p) &&
                  (((px < (kx0p + 12'd2)) || (px > (kx1p - 12'd2))) ||
                   ((py < (ky0p + 12'd2)) || (py > (ky1p - 12'd2))));

    //-------------------------------------------------------------------------
    // 4. 说明卡片（贴在"胜者"框上方；上面放不下就挪到下方）
    //    版面：10 列 x 2 行，每格 32x32 像素（16x16 点阵放大 2 倍）
    //          文字区 320x64，四周各留 4 像素黑边 -> 牌面 328x72
    //-------------------------------------------------------------------------
    localparam [11:0] CARD_W = 12'd328,
                      CARD_H = 12'd72,
                      TXT_W  = 12'd320,
                      TXT_H  = 12'd64;

    wire [11:0] wx0_p = {3'b000, wx0} << 3;
    wire [11:0] wx1_p = ({3'b000, wx1} << 3) + 12'd7;
    wire [11:0] wy0_p = {4'b0000, wy0} << 3;
    wire [11:0] wy1_p = ({4'b0000, wy1} << 3) + 12'd7;

    wire card_show = I_en && (I_orange_valid || I_vivid_valid || I_dark_valid);

    wire [11:0] lx_raw = (wx0_p > (IMG_WIDTH  - CARD_W)) ? (IMG_WIDTH  - CARD_W) : wx0_p;
    wire [11:0] ly_abv = wy0_p - 12'd80;
    wire [11:0] ly_bel = wy1_p + 12'd6;
    wire [11:0] ly_raw = (wy0_p >= 12'd80) ? ly_abv : ly_bel;
    wire [11:0] ly     = (ly_raw > (IMG_HEIGHT - CARD_H)) ? (IMG_HEIGHT - CARD_H) : ly_raw;

    wire in_card = card_show &&
                   (px >= lx_raw) && (px < (lx_raw + CARD_W)) &&
                   (py >= ly)     && (py < (ly + CARD_H));

    wire [11:0] tx  = px - lx_raw;
    wire [11:0] ty  = py - ly;
    wire in_txt = in_card && (tx >= 12'd4) && (tx < (12'd4 + TXT_W)) &&
                             (ty >= 12'd4) && (ty < (12'd4 + TXT_H));

    wire [11:0] clx = tx - 12'd4;      // 0..319
    wire [11:0] cly = ty - 12'd4;      // 0..63
    wire [3:0]  c_ci   = clx[8:5];     // 第几列字符 0..9
    wire [3:0]  c_col  = clx[4:1];     // 字符内列 0..15
    wire        c_line = cly[5];       // 第几行 0/1
    wire [3:0]  c_row  = cly[4:1];     // 字符内行 0..15

    reg [5:0] c_code;
    always @(*) begin
        c_code = C_SP;
        if (c_line == 1'b0) begin
            // ---------------- 第 1 行：物体名称 ----------------
            case (c_ci)
                4'd4: case (I_win_class)
                        2'd0: c_code = C_GAI;   // 改
                        2'd1: c_code = C_MO;    // 魔
                        default: c_code = C_HEI; // 黑
                      endcase
                4'd5: case (I_win_class)
                        2'd0: c_code = C_ZHUI;  // 锥
                        2'd1: c_code = C_FANG;  // 方
                        default: c_code = C_SE;  // 色
                      endcase
                4'd6: if (I_win_class == 2'd2) c_code = C_WU;   // 物
                4'd7: if (I_win_class == 2'd2) c_code = C_TI;   // 体
                default: c_code = C_SP;
            endcase
        end
        else begin
            // ---------------- 第 2 行：中心坐标 ----------------
            case (c_ci)
                4'd0: c_code = C_X;
                4'd1: c_code = x_lt1000 ? C_SP : (C_0 + xd3);
                4'd2: c_code = x_lt100  ? C_SP : (C_0 + xd2);
                4'd3: c_code = C_0 + xd1;
                4'd4: c_code = C_0 + xd0;
                4'd5: c_code = C_SP;
                4'd6: c_code = C_Y;
                4'd7: c_code = y_lt100 ? C_SP : (C_0 + yd2);
                4'd8: c_code = C_0 + yd1;
                4'd9: c_code = C_0 + yd0;
                default: c_code = C_SP;
            endcase
        end
    end

    //-------------------------------------------------------------------------
    // 5. 一级流水：坐标比较 / 选字符 / 字库地址 全部寄存
    //-------------------------------------------------------------------------
    reg        d1_de;
    reg [23:0] d1_data;
    reg        d1_txt;
    reg        d1_card;
    reg        d1_orange;
    reg        d1_vivid;
    reg        d1_dark;
    reg [3:0]  d1_col;
    reg [9:0]  d1_addr;

    wire        any_txt  = in_txt;
    wire [3:0]  sel_col  = c_col;
    wire [9:0]  sel_addr = {c_code, c_row};

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            d1_de   <= 1'b0;
            d1_data <= 24'd0;
            d1_txt  <= 1'b0;
            d1_card <= 1'b0;
            d1_orange<= 1'b0;
            d1_vivid<= 1'b0;
            d1_dark <= 1'b0;
            d1_col  <= 4'd0;
            d1_addr <= 10'd0;
        end
        else begin
            d1_de   <= I_de;
            d1_data <= I_data;
            d1_txt  <= any_txt;
            d1_card <= in_card;
            d1_orange<= orange_on;
            d1_vivid<= vivid_on;
            d1_dark <= dark_on;
            d1_col  <= sel_col;
            d1_addr <= sel_addr;
        end
    end

    //-------------------------------------------------------------------------
    // 6. 二级流水：字库 ERAM（1024x16，异步读）+ 列选 + 二选一
    //    addr = {字符号[5:0], 行号[3:0]}
    //    bit15 = 最左像素 ... bit0 = 最右像素（与 osd_char_lib 一致）
    //-------------------------------------------------------------------------
    wire [15:0] font_row;

    PH1P_LOGIC_ERAM #(
        .DATA_WIDTH_A          ( 16            ),
        .DATA_WIDTH_B          ( 16            ),
        .ADDR_WIDTH_A          ( 10            ),
        .ADDR_WIDTH_B          ( 10            ),
        .DATA_DEPTH_A          ( 1024          ),
        .DATA_DEPTH_B          ( 1024          ),
        .MODE                  ( "SP"          ),
        .REGMODE_A             ( "NOREG"       ),
        .REGMODE_B             ( "NOREG"       ),
        .WRITEMODE_A           ( "NORMAL"      ),
        .WRITEMODE_B           ( "NORMAL"      ),
        .IMPLEMENT             ( "20K"         ),
        .ECC_ENCODE            ( "DISABLE"     ),
        .ECC_DECODE            ( "DISABLE"     ),
        .CLKMODE               ( "ASYNC"       ),
        .SSROVERCE             ( "DISABLE"     ),
        .OREGSET_A             ( "SET"         ),
        .OREGSET_B             ( "SET"         ),
        .RESETMODE_A           ( "ASYNC"       ),
        .RESETMODE_B           ( "ASYNC"       ),
        .ASYNC_RESET_RELEASE_A ( "SYNC"        ),
        .ASYNC_RESET_RELEASE_B ( "SYNC"        ),
        .DEBUGGABLE            ( "NO"          ),
        .PACKABLE              ( "NO"          ),
        .INIT_FILE             ( "mif/font16.mif" ),
        .FILL_ALL              ( "NONE"        )
    ) u_font_eram (
        .dia              ( 16'd0        ),
        .dib              ( 16'd0        ),
        .addra            ( d1_addr      ),
        .addrb            ( 10'd0        ),
        .cea              ( 1'b1         ),
        .ceb              ( 1'b0         ),
        .ocea             ( 1'b1         ),
        .oceb             ( 1'b0         ),
        .clka             ( I_clk        ),
        .clkb             ( 1'b0         ),
        .wea              ( 1'b0         ),
        .web              ( 1'b0         ),
        .bea              ( 1'b0         ),
        .beb              ( 1'b0         ),
        .rsta             ( 1'b0         ),
        .rstb             ( 1'b0         ),
        .ecc_sbiterrinj   ( 1'b0         ),
        .ecc_dbiterrinj   ( 1'b0         ),
        .doa              ( font_row     ),
        .dob              (              ),
        .ecc_sbiterr      (              ),
        .ecc_dbiterr      (              )
    );

    reg pix_on;
    always @(*) begin
        case (d1_col)
            4'd0:  pix_on = font_row[15];
            4'd1:  pix_on = font_row[14];
            4'd2:  pix_on = font_row[13];
            4'd3:  pix_on = font_row[12];
            4'd4:  pix_on = font_row[11];
            4'd5:  pix_on = font_row[10];
            4'd6:  pix_on = font_row[9];
            4'd7:  pix_on = font_row[8];
            4'd8:  pix_on = font_row[7];
            4'd9:  pix_on = font_row[6];
            4'd10: pix_on = font_row[5];
            4'd11: pix_on = font_row[4];
            4'd12: pix_on = font_row[3];
            4'd13: pix_on = font_row[2];
            4'd14: pix_on = font_row[1];
            default: pix_on = font_row[0];
        endcase
    end

    //-------------------------------------------------------------------------
    // 7. 合成
    //    ⚠ 黑色目标的框用青色：黑框画在黑色物体上等于没画
    //-------------------------------------------------------------------------
    wire text_on = d1_txt && pix_on;

    wire [23:0] orange_col = 24'hFF9010;   // 改锥：橙框
    wire [23:0] vivid_col  = 24'h20FF20;   // 魔方：绿框
    wire [23:0] dark_col   = 24'h00E0FF;   // 黑色：青框

    wire        hit  = text_on || d1_card || d1_orange || d1_vivid || d1_dark;
    wire [23:0] over = text_on  ? 24'hFFFFFF :     // 白字
                       d1_card  ? 24'h000000 :     // 卡片黑底
                       d1_dark  ? dark_col  :      // 黑目标框（青）
                       d1_vivid ? vivid_col :      // 魔方框（绿）
                                  orange_col;      // 改锥框（橙）

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            O_de   <= 1'b0;
            O_data <= 24'd0;
        end
        else begin
            O_de   <= d1_de;
            O_data <= (d1_de && hit) ? over : d1_data;
        end
    end

endmodule
'''

src = src[:ic] + NEW_OSD

# ---------------------------------------------------------------------------
# 3) 端口 / 默认值 / 串口分支 / 文档注释（只替换肯定能匹配的片段）
# ---------------------------------------------------------------------------
def rep(text, old, new, n=1):
    c = text.count(old)
    if c != n:
        raise SystemExit("REPLACE FAIL (count=%d, expect=%d):\nOLD=%r" % (c, n, old))
    return text.replace(old, new)

# 端口声明
src = rep(src,
    "    output reg  [7:0]  O_pose_std,\n    output reg  [7:0]  O_pose_sit,\n",
    "    output reg  [7:0]  O_vivid_sat,\n    output reg  [7:0]  O_orange_rmin,\n")

# 默认值
src = rep(src,
    "            O_pose_std   <= 8'd85;         // P26 站/坐分界：H/Hmax >= 0.85 -> 站",
    "            O_vivid_sat   <= 8'd40;         // P26 魔方饱和度下限（原始像素域）")
src = rep(src,
    "            O_pose_sit   <= 8'd55;         // P27 坐/蹲分界：H/Hmax >= 0.55 -> 坐，否则蹲",
    "            O_orange_rmin <= 8'd60;         // P27 改锥 R 亮度下限（原 VMIN）")

# 串口分支
src = rep(src,
    "                                8'd26: O_pose_std    <= val[7:0];   // 姿态：站/坐分界",
    "                                8'd26: O_vivid_sat   <= val[7:0];   // 魔方饱和度下限")
src = rep(src,
    "                                8'd27: O_pose_sit    <= val[7:0];   // 姿态：坐/蹲分界",
    "                                8'd27: O_orange_rmin <= val[7:0];   // 改锥 R 亮度下限")

# 顶部参数文档 23
src = rep(src,
    "     23  TGT_DOM      目标识别：色度主导阈值（默认 55，小=敏感）  ★2026-10-28",
    "     23  TGT_DOM      目标识别：改锥(橙色) R-B 主导阈值（默认 100，原始像素域）")
# 顶部参数文档 25
src = rep(src,
    "     25  TGT_EN       目标框/文字叠加总开关（默认 1）",
    "     25  TGT_BLK      目标识别：黑色物体亮度上限（默认 70，原始像素域）")
# 在 24 行之后插入 26/27
old24 = "     24  TGT_MIN_PIX  目标识别：最小采样点数（默认 15，约 40x40 像素）"
new24 = "     24  TGT_MIN_PIX  目标识别：最小采样点数（默认 15，约 40x40 像素）\n     26  TGT_VIVID    目标识别：魔方(彩色)饱和度下限（默认 40，原始像素域）\n     27  TGT_ORANGE_R 目标识别：改锥 R 亮度下限（默认 60，原始像素域）"
src = rep(src, old24, new24)

# P23 注释行
src = rep(src,
    "    // P23 红色色度主导阈值：R 要领先 G、B 多少才判\"红色\"",
    "    // P23 改锥(橙色)色度主导阈值：R-B 要>=它才判\"改锥\"（橙色手柄 R-B≈206）")

# （注释替换跳过：旧注释 harmless，不必强求匹配）
# src = rep(src,
#     "    // ★ 2026-10-28：目标检测与识别（target_detect / target_osd）的 3 个参数",
#     "    // ★ 2026-10-28 改：目标检测与识别（target_detect / target_osd）的 5 个参数（P23~P27）")
# src = rep(src,
#     "//  下面 3 个模块（target_detect / pose_detect / target_osd）",
#     "//  下面 2 个模块（target_detect / target_osd）")

with io.open(P, "w", encoding="utf-8") as f:
    f.write(src)
print("param_ctrl.v rewritten OK, new length =", len(src))
