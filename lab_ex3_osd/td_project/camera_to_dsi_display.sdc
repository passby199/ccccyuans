create_clock -name {sys_clk_50m} -period 20.000 -waveform {0.000 10.000} [get_ports {I_sys_clk}]
create_clock -name {mipi_rx_ck_pad} -period 4.167 -waveform {0.000 2.083} [get_nets {IO_rx_clk_pad_p}]

derive_clocks

rename_clock -name {pll_clk_100m} [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[0]}]
rename_clock -name {pll_clk_24m} [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[1]}]
rename_clock -name {HDMI_PIXEL_CLK} [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[4]}]
rename_clock -name {HDMI_SERIAL_CLK} [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[5]}]

rename_clock -name {MIPI_RX_BYTE_CLK} [get_clocks {u_mipi_dphy_rx_ph1p_mipiio_wrapper/u_ph1p_mipiio_rx_wrapper/u_PH1P_LOGIC_DPHY_MIPI_RX.o_fabric_div4_8_clk}]


set_clock_groups -asynchronous \
    -group [get_clocks {mipi_rx_ck_pad MIPI_RX_BYTE_CLK}] \
    -group [get_clocks {sys_clk_50m pll_clk_100m pll_clk_24m HDMI_PIXEL_CLK HDMI_SERIAL_CLK}] \
    -group [get_clocks {u_ph1p35_324_ddr_wrapper/u_ddr2/ddr_clk u_ph1p35_324_ddr_wrapper/u_ddr2/usr_clk}]

#=============================================================================
# 2026-10-30 新增：像素域 <-> 24MHz 域的 false_path
#
# 为什么加：
#   上面 set_clock_groups 把 pll_clk_24m 和 HDMI_PIXEL_CLK 放在【同一组】，
#   所以这两个域之间的路径仍然被单周期约束分析。
#   但实际跨域信号（S_ae_mode -> ae_set.I_ae_hi）在 ae_set 内部有
#   两级同步器 ae_hi_sync，属于标准跨域处理，不该受单周期约束。
#   不加的话报 10 条 -2.3ns 违例，让工具白白多迭代几轮。
#
# 为什么可以放心加：
#   这两个域之间只有曝光档位（S_ae_mode，3 态慢变信号）和
#   曝光/增益回读（S_ae / S_ag，有 req/ack 握手）等少量控制信号，
#   都是慢速或已同步的，不存在需要单周期对齐的数据通路。
#=============================================================================
set_false_path -from [get_clocks {HDMI_PIXEL_CLK}] -to [get_clocks {pll_clk_24m}]
set_false_path -from [get_clocks {pll_clk_24m}] -to [get_clocks {HDMI_PIXEL_CLK}]
