#=============================================================================
# timing.sdc — 时序约束（2026-10-30 首次添加内容）
#
# 背景：这个文件原来是空的，TD 完全不做时序分析，"编译成功"≠时序收敛。
#       现在加两条跨时钟域 false_path，消除 10 条虚假违例。
#
# 为什么是虚假违例：
#   S_ae_mode（顶层，HDMI_PIXEL_CLK 74.25MHz 域）
#     -> ae_set.I_ae_hi（pll_clk_24m 24MHz 域）
#   这条路径在 ae_set 内部有【两级同步器】ae_hi_sync，
#   属于标准跨时钟域处理，本来就不该受单周期约束。
#   不加 false_path 时，工具按 13.333ns 算 -> 报 -2.3ns 违例（共 10 条）。
#
# 只约束这一对时钟方向。其他跨域路径（DDR / MIPI / HDMI 串行）不动，
# 避免掩盖真实问题。
#=============================================================================

# 像素域 -> 24MHz 域（S_ae_mode -> ae_set.I_ae_hi，已两级同步）
set_false_path -from [get_clocks HDMI_PIXEL_CLK] -to [get_clocks pll_clk_24m]

# 24MHz 域 -> 像素域（ae_set 的曝光值/请求 -> 顶层，已有握手/慢速特性）
set_false_path -from [get_clocks pll_clk_24m] -to [get_clocks HDMI_PIXEL_CLK]
