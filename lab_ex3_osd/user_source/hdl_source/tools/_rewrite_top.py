# -*- coding: utf-8 -*-
"""改写 design_top_wrapper.v：
   - 三类物体检测例化（改锥/魔方/黑色）
   - 删除 pose_detect 例化与信号
   - P26/P27 重命名并连接新端口
"""
import io

P = r"C:/Users/Lenovo/Desktop/lab_ex3_osd_SC500_720P/lab_ex3_osd/user_source/hdl_source/design_top_wrapper.v"
with io.open(P, "r", encoding="utf-8") as f:
    src = f.read()

def rep(text, old, new, n=1):
    c = text.count(old)
    if c != n:
        raise SystemExit("REPLACE FAIL (count=%d, expect=%d):\nOLD=%r" % (c, n, old[:120]))
    return text.replace(old, new)

# 1) 替换 target_detect 例化（原始文本）
OLD_TD_INST = """    target_detect #(
        .IMG_WIDTH  ( 1280 ),
        .IMG_HEIGHT ( 720  ),
        .DS_LOG2    ( 3    ),      // 8x8 -> 160x90（与 motion_stats 同网格）
        .DE_LAG     ( 2    ),      // 与 motion_stats 一致：rd_en 比数据早 2 拍
        .VMIN       ( 8'd60)       // 原始像素域，比显示域低
    ) u_target_detect (
        .I_clk      ( S_hdmi_pixel_clk ),
        .I_rst_n    ( S_hdmi_rst_n     ),
        // ★ 接 video_out 的原始像素（OSD 之前），检测不到 logo/数字
        .I_de       ( S_hdmi_window_rd_en ),
        .I_data     ( S_video_rd_data     ),
        .I_red_th   ( S_p_tgt_dom      ),   // P23
        .I_min_pix  ( S_p_tgt_min      ),   // P24
        .I_blk_th   ( S_p_tgt_blk      ),   // P25
        .O_red_valid( S_tgt_red_valid  ),
        .O_red_x0   ( S_tgt_red_x0     ),
        .O_red_x1   ( S_tgt_red_x1     ),
        .O_red_y0   ( S_tgt_red_y0     ),
        .O_red_y1   ( S_tgt_red_y1     ),
        .O_blk_valid( S_tgt_blk_valid  ),
        .O_blk_x0   ( S_tgt_blk_x0     ),
        .O_blk_x1   ( S_tgt_blk_x1     ),
        .O_blk_y0   ( S_tgt_blk_y0     ),
        .O_blk_y1   ( S_tgt_blk_y1     ),
        .O_win_blk  ( S_tgt_win_blk    )
    );"""

NEW_TD_INST = """    target_detect #(
        .IMG_WIDTH  ( 1280 ),
        .IMG_HEIGHT ( 720  ),
        .DS_LOG2    ( 3    ),      // 8x8 -> 160x90（与 motion_stats 同网格）
        .DE_LAG     ( 2    )       // 与 motion_stats 一致：rd_en 比数据早 2 拍
    ) u_target_detect (
        .I_clk         ( S_hdmi_pixel_clk ),
        .I_rst_n       ( S_hdmi_rst_n     ),
        // ★ 接 video_out 的原始像素（OSD 之前），检测不到 logo/数字
        .I_de          ( S_hdmi_window_rd_en ),
        .I_data        ( S_video_rd_data     ),
        .I_orange_th   ( S_p_tgt_dom      ),   // P23
        .I_orange_rmin ( S_p_orange_rmin  ),   // P27
        .I_vivid_sat   ( S_p_vivid_sat    ),   // P26
        .I_min_pix     ( S_p_tgt_min      ),   // P24
        .I_blk_th      ( S_p_tgt_blk      ),   // P25
        .O_orange_valid( S_tgt_orange_valid ),
        .O_orange_x0   ( S_tgt_orange_x0    ),
        .O_orange_x1   ( S_tgt_orange_x1    ),
        .O_orange_y0   ( S_tgt_orange_y0    ),
        .O_orange_y1   ( S_tgt_orange_y1    ),
        .O_vivid_valid ( S_tgt_vivid_valid  ),
        .O_vivid_x0    ( S_tgt_vivid_x0     ),
        .O_vivid_x1    ( S_tgt_vivid_x1     ),
        .O_vivid_y0    ( S_tgt_vivid_y0     ),
        .O_vivid_y1    ( S_tgt_vivid_y1     ),
        .O_dark_valid  ( S_tgt_dark_valid   ),
        .O_dark_x0     ( S_tgt_dark_x0      ),
        .O_dark_x1     ( S_tgt_dark_x1      ),
        .O_dark_y0     ( S_tgt_dark_y0      ),
        .O_dark_y1     ( S_tgt_dark_y1      ),
        .O_win_class   ( S_tgt_win_class    )
    );"""
src = rep(src, OLD_TD_INST, NEW_TD_INST)

# 2) 替换 target_osd 例化（原始文本）
OLD_OSD_INST = """    target_osd #(
        .IMG_WIDTH  ( 1280 ),
        .IMG_HEIGHT ( 720  ),
        .DE_LAG     ( 1    )
    ) u_target_osd (
        .I_clk        ( S_hdmi_pixel_clk ),
        .I_rst_n      ( S_hdmi_rst_n     ),
        // 接 enhance 输出（链路最后一级），所以不受任何滤镜影响
        .I_de         ( S_enh_de         ),
        .I_data       ( S_enh_data       ),
        .I_en         ( S_recog_en       ),   // SW2
        .I_red_valid  ( S_tgt_red_valid  ),
        .I_red_x0     ( S_tgt_red_x0     ),
        .I_red_x1     ( S_tgt_red_x1     ),
        .I_red_y0     ( S_tgt_red_y0     ),
        .I_red_y1     ( S_tgt_red_y1     ),
        .I_blk_valid  ( S_tgt_blk_valid  ),
        .I_blk_x0     ( S_tgt_blk_x0     ),
        .I_blk_x1     ( S_tgt_blk_x1     ),
        .I_blk_y0     ( S_tgt_blk_y0     ),
        .I_blk_y1     ( S_tgt_blk_y1     ),
        .I_win_blk    ( S_tgt_win_blk    ),
        .I_pose_valid ( S_pose_valid     ),
        .I_pose       ( S_pose           ),
        .I_pose_x0    ( S_pose_x0        ),
        .I_pose_x1    ( S_pose_x1        ),
        .I_pose_y0    ( S_pose_y0        ),
        .I_pose_y1    ( S_pose_y1        ),
        .I_pose_w     ( S_pose_w         ),
        .I_pose_h     ( S_pose_h         ),
        .O_de         ( S_tgt_osd_de     ),
        .O_data       ( S_tgt_osd_data   )
    );"""

NEW_OSD_INST = """    target_osd #(
        .IMG_WIDTH  ( 1280 ),
        .IMG_HEIGHT ( 720  ),
        .DE_LAG     ( 1    )
    ) u_target_osd (
        .I_clk         ( S_hdmi_pixel_clk ),
        .I_rst_n       ( S_hdmi_rst_n     ),
        // 接 enhance 输出（链路最后一级），所以不受任何滤镜影响
        .I_de          ( S_enh_de         ),
        .I_data        ( S_enh_data       ),
        .I_en          ( S_recog_en       ),   // SW2
        .I_orange_valid( S_tgt_orange_valid ),
        .I_orange_x0   ( S_tgt_orange_x0    ),
        .I_orange_x1   ( S_tgt_orange_x1    ),
        .I_orange_y0   ( S_tgt_orange_y0    ),
        .I_orange_y1   ( S_tgt_orange_y1    ),
        .I_vivid_valid ( S_tgt_vivid_valid  ),
        .I_vivid_x0    ( S_tgt_vivid_x0     ),
        .I_vivid_x1    ( S_tgt_vivid_x1     ),
        .I_vivid_y0    ( S_tgt_vivid_y0     ),
        .I_vivid_y1    ( S_tgt_vivid_y1     ),
        .I_dark_valid  ( S_tgt_dark_valid   ),
        .I_dark_x0     ( S_tgt_dark_x0      ),
        .I_dark_x1     ( S_tgt_dark_x1      ),
        .I_dark_y0     ( S_tgt_dark_y0      ),
        .I_dark_y1     ( S_tgt_dark_y1      ),
        .I_win_class   ( S_tgt_win_class    ),
        .O_de          ( S_tgt_osd_de       ),
        .O_data        ( S_tgt_osd_data     )
    );"""
src = rep(src, OLD_OSD_INST, NEW_OSD_INST)

# 3) 替换 param_ctrl 例化里的 pose 端口（原始文本）
OLD_PC = """        .O_tgt_dom     ( S_p_tgt_dom     ),   // P23 红色色度阈值
        .O_tgt_min     ( S_p_tgt_min     ),   // P24 最小采样点数
        .O_tgt_blk     ( S_p_tgt_blk     ),   // P25 黑色亮度上限
        .O_pose_std    ( S_p_pose_std    ),   // P26 姿态：站/坐分界
        .O_pose_sit    ( S_p_pose_sit    ),   // P27 姿态：坐/蹲分界"""
NEW_PC = """        .O_tgt_dom     ( S_p_tgt_dom     ),   // P23 改锥 R-B 阈值
        .O_tgt_min     ( S_p_tgt_min     ),   // P24 最小采样点数
        .O_tgt_blk     ( S_p_tgt_blk     ),   // P25 黑色亮度上限
        .O_vivid_sat   ( S_p_vivid_sat   ),   // P26 魔方饱和度下限
        .O_orange_rmin ( S_p_orange_rmin ),   // P27 改锥 R 亮度下限"""
src = rep(src, OLD_PC, NEW_PC)

# 4) 删除 pose_detect 例化 + 前面注释块
OLD_POSE = """    //--------------------------------------------------------------------------
    // ★ 2026-10-28 新增：姿态识别（简单姿态：站 / 蹲坐 / 躺）
    //
    //  直接吃 motion_stats 刚扫出来的逐行轮廓（每帧 90 拍流式输出），
    //  边收边求前景的外接矩形，帧末用宽高比判姿态 —— 不需要任何存储。
    //
    //  ⚠ 前提：前景来自**背景相减**。人站着不动 → 前景消失 → 没有姿态。
    //     模块内有 45 帧（0.75 秒）保持兜闪断，但长时间静立仍会丢。
    //     演示时请保持轻微晃动。多人时外接矩形会合并，也必须单人演示。
    //--------------------------------------------------------------------------
    pose_detect #(
        // ★ 2026-10-29：45 -> 120 帧（2 秒）
        //   现场问题：人一坐下/站定就不动了，背景相减立刻丢轮廓，
        //   姿态框 0.75 秒就消失 —— 演示时"刚坐下框就没了"。
        //   拉长到 2 秒，人停住后框还能稳稳挂一会儿，看起来才像"识别到了"。
        .MISS_HOLD ( 8'd120 ),
        // ★ 2026-10-29：MIN_H 16 -> 12（96 像素）
        //   16 格对"蹲"太严：蹲下时前景只有上半身，H 常常只有 12~16 格，
        //   门槛太高会直接判"没有姿态"，卡片一闪一闪。
        //   12 格仍能把"一只手"（约 5~8 格）挡在外面。
        .MIN_H     ( 8'd12 ),
        .MIN_W     ( 9'd3  )
    ) u_pose_detect (
        .I_clk         ( S_hdmi_pixel_clk ),
        .I_rst_n       ( S_hdmi_rst_n     ),
        .I_row_valid   ( S_contour_valid  ),
        .I_row_idx     ( S_contour_idx    ),
        .I_row_min     ( S_contour_min    ),
        .I_row_max     ( S_contour_max    ),
        .I_frame_valid ( S_mot_valid      ),
        .I_th_stand    ( S_p_pose_std     ),   // P26
        .I_th_sit      ( S_p_pose_sit     ),   // P27
        .O_pose        ( S_pose           ),
        .O_valid       ( S_pose_valid     ),
        // ★ 2026-10-29：人体外接框，OSD 用它"框住人体"
        .O_x0          ( S_pose_x0        ),
        .O_x1          ( S_pose_x1        ),
        .O_y0          ( S_pose_y0        ),
        .O_y1          ( S_pose_y1        ),
        .O_w           ( S_pose_w         ),
        .O_h           ( S_pose_h         )
    );"""
NEW_POSE = """    //--------------------------------------------------------------------------
    // ★ 2026-10-29：已删除人体姿态识别（pose_detect），只保留物体识别。
    //--------------------------------------------------------------------------"""
src = rep(src, OLD_POSE, NEW_POSE)

# 5) 全局重命名信号
src = src.replace("S_tgt_red_", "S_tgt_orange_")
src = src.replace("S_tgt_blk_", "S_tgt_dark_")
src = src.replace("S_p_pose_std", "S_p_vivid_sat")
src = src.replace("S_p_pose_sit", "S_p_orange_rmin")
src = src.replace("S_tgt_win_blk", "S_tgt_win_class")

# 6) 删除 pose 信号声明（4 行）
OLD_POSE_DECL = """    wire        S_pose_valid;
    wire [1:0]  S_pose;             // 0=STAND 1=SIT 2=LIE
    wire [7:0]  S_pose_x0, S_pose_x1, S_pose_y0, S_pose_y1;   // 人体框（网格坐标）
    wire [8:0]  S_pose_w, S_pose_h;                           // 平滑后的宽高（诊断）
"""
src = rep(src, OLD_POSE_DECL, "")

# 7) 在 dark_y1 声明后插入 vivid 声明
OLD_DARK_Y1 = "    wire [7:0]  S_tgt_dark_y0, S_tgt_dark_y1;\n"
NEW_DARK_Y1 = """    wire [7:0]  S_tgt_dark_y0, S_tgt_dark_y1;
    wire        S_tgt_vivid_valid;
    wire [8:0]  S_tgt_vivid_x0, S_tgt_vivid_x1;
    wire [7:0]  S_tgt_vivid_y0, S_tgt_vivid_y1;
"""
src = rep(src, OLD_DARK_Y1, NEW_DARK_Y1)

# 8) 更新 win_class 声明（原来的 win_blk 是 1bit，改成 2bit + 新注释）
OLD_WIN_COMMENT = "    wire        S_tgt_win_class;      // 1 = 黑色目标更大（卡片写在它身上）"
NEW_WIN_COMMENT = "    wire [1:0]  S_tgt_win_class;    // 0=改锥 1=魔方 2=黑色物体（卡片写在它身上）"
src = rep(src, OLD_WIN_COMMENT, NEW_WIN_COMMENT)

with io.open(P, "w", encoding="utf-8") as f:
    f.write(src)
print("design_top_wrapper.v rewritten OK, new length =", len(src))
