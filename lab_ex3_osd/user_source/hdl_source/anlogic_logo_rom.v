//=============================================================================
//  anlogic_logo_rom.v  --  安路 Logo 位图 ROM（ERAM 版）
//
//  ⚠ 2026-10-17：从 6390 行 case 表（LUT 分布式 ROM）改成 ERAM 原语
//
//  为什么改
//  ---------------------------------------------------------------------------
//  原来的 case 表被 TD 综合成 LUT 搭的分布式 ROM，占约 1,600~2,400 个 LUT6
//  （`u_hdmi_mixer` 的 logic lut 里，基线仅 54）。而 slice 已用到 95%，
//  加逐行轮廓后直接超限（21,960 > 21,216）。必须先把这块 LUT 腾出来。
//
//  为什么现在敢用 ERAM（2026-10-15 曾判断"风险太大"而放弃）
//  ---------------------------------------------------------------------------
//  找到了可工作的实例：`Multi-Function-Image-Processing-PLAT-main/MFIPP/al_ip/g0_rom.v`
//  就是 TD IP Generator 生成的 ROM，做法是
//    `PH1P_LOGIC_ERAM` + `MODE("SP")` + `INIT_FILE("mif/xxx.mif")`
//  同目录的 `g0.mif.dat` 是 TD 编译时自动生成的（不用手写）。
//  ⇒ MIF 是标准 Altera 格式，TD 自己会转 .dat。
//  PH1P 系列的原语定义在 `D:/TD/arch/ph1p_macro.v`。
//
//  数据
//  ---------------------------------------------------------------------------
//  `mif/logo.mif`：DEPTH=32768（覆盖 15 位地址）、WIDTH=17、DATA_RADIX=HEX
//    内容 = {alpha, R5, G6, B5}；未定义地址填 0（alpha=0 即透明）
//    共 6387 个不透明像素、159 种颜色（RGB565 量化后）
//  为防 INIT_FILE 相对路径基准不一致，mif 在两处各放了一份：
//    user_source/hdl_source/mif/logo.mif
//    td_project/mif/logo.mif
//
//  时序（重要）
//  ---------------------------------------------------------------------------
//  `REGMODE_A("NOREG")` = 异步读（组合输出），**与原来的 case 表行为一致**，
//  所以 hdmi_mixer 里"地址提前一拍（S_logo_addr 用 _1d 坐标寄存）"的结构
//  **一行都不用改**。
//  若改成 OUTREG（同步读，晚 1 拍），logo 会右移 1 像素，需要额外一级延迟。
//
//  容量
//  ---------------------------------------------------------------------------
//  32768 × 17 bit = 557 Kbit ÷ 20 Kbit/块 ≈ 28 块 ERAM
//  当前 ERAM 用量 42/108，改完约 70/108，仍有余量。
//
//  颜色
//  ---------------------------------------------------------------------------
//  RGB565；消费方（hdmi_mixer.v）还原成 RGB888 的公式：
//    R8={R5,R5[2:0]}  G8={G6,G6[1:0]}  B8={B5,B5[2:0]}
//
//  回退
//  ---------------------------------------------------------------------------
//  原 LUT 版保存在同目录 `anlogic_logo_rom.v.lutbak`，
//  把它改名回 `anlogic_logo_rom.v` 即可（注意端口要一起回退 I_clk）。
//=============================================================================

module anlogic_logo_rom (
    input  wire        I_clk,       // ERAM 时钟（74.25 MHz，与 hdmi_mixer 同域）
    input  wire [14:0] I_addr,      // y*160 + x，0..25599
    output wire [16:0] O_pixel      // {alpha, R5, G6, B5}
);

    //-------------------------------------------------------------------------
    // 单端口 ROM：只读，wea 恒 0
    //   dia 接 0（永不写）；B 口全部接静态值
    //-------------------------------------------------------------------------
    PH1P_LOGIC_ERAM #(
        .DATA_WIDTH_A          ( 17            ),
        .DATA_WIDTH_B          ( 17            ),
        .ADDR_WIDTH_A          ( 15            ),
        .ADDR_WIDTH_B          ( 15            ),
        .DATA_DEPTH_A          ( 32768         ),
        .DATA_DEPTH_B          ( 32768         ),
        .MODE                  ( "SP"          ),
        .REGMODE_A             ( "OUTREG"      ),   // ★ 2026-10-30：NOREG→OUTREG（时序修复）
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
        .INIT_FILE             ( "mif/logo.mif" ),
        .FILL_ALL              ( "NONE"        )
    ) u_logo_eram (
        .dia              ( 17'd0         ),
        .dib              ( 17'd0         ),
        .addra            ( I_addr        ),
        .addrb            ( 15'd0         ),
        .cea              ( 1'b1          ),
        .ceb              ( 1'b0          ),
        .ocea             ( 1'b1          ),
        .oceb             ( 1'b0          ),
        .clka             ( I_clk         ),
        .clkb             ( 1'b0          ),
        .wea              ( 1'b0          ),
        .web              ( 1'b0          ),
        .bea              ( 1'b0          ),
        .beb              ( 1'b0          ),
        .rsta             ( 1'b0          ),
        .rstb             ( 1'b0          ),
        .ecc_sbiterrinj   ( 1'b0          ),
        .ecc_dbiterrinj   ( 1'b0          ),
        .doa              ( O_pixel       ),
        .dob              (               ),
        .ecc_sbiterr      (               ),
        .ecc_dbiterr      (               )
    );

endmodule
