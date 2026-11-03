//=============================================================================
//  motion_stats.v  --  运动统计（帧差 + 降采样 + 前景统计）
//
//  这是跳绳判断链路的第 1 级。它只做「观察」，不做任何判断，
//  每帧输出一组统计量给后面的模块用。
//
//  处理流程
//  ---------------------------------------------------------------------------
//      video_out 的原始像素（1280x720，S_hdmi_pixel_clk 域）
//        |
//        +-- 每 DS x DS 个像素取 1 个  -> 降采样到 320x180
//        +-- 灰度化  R/4 + G/2 + B/4
//        +-- 与帧缓存里的上一帧比较    -> 前景标志 fg
//        +-- 用 fg 增量累加统计量
//        |
//        +-- 每帧末尾输出一次统计结果
//
//  为什么降采样
//  ---------------------------------------------------------------------------
//  帧缓存是这块模块唯一的大开销，而 **TD 6.2 认不出本模块的 RAM 推断模式**
//  （详见下方帧缓存处的注释），所以它最终会被综合成 LUT 搭的分布式 RAM。
//  分布式 RAM 约 56 bit/LUT6，而本工程留给 RAM 的 LUT 预算只有约 4794 个
//  （slice 上限 21216，HDMI/ISP/DDR 通路已占 16422）→ 最多只能放约 268 Kbit。
//
//  所以分辨率必须压到"全用 LUT 也装得下"：
//      1280x720  7.4 Mbit  不可能
//      320x180   460 Kbit  需要 8000+ LUT，撑爆（实测报 mslice 8600 > 8112）
//      160x90    115 Kbit  约 2250 LUT，总占用 88.6%，✓ 当前选择
//
//  代价是垂直分辨率变粗（90 行对应 720 像素，8 像素/行）。跳绳时质心上下
//  移动约 4~5 行，配合加权质心的亚行精度仍然够用。
//  若以后要回到 320x180，两条路：① 用 TD 的 IP 生成器造块 RAM；
//  ② 改成分行/分列投影累加（不存整帧，只存上一帧的行列投影，约 8 Kbit）。
//
//  为什么不求质心
//  ---------------------------------------------------------------------------
//  质心 = Σy / 面积，需要除法。但跳绳判断只需要 Σy 的「振荡」，
//  而跳绳时前景面积基本不变，所以 Σy 本身就与质心成正比。
//  这里直接输出 Σy，省掉整个除法器。
//
//  统计量
//  ---------------------------------------------------------------------------
//      O_area  前景像素数（相当于人的大小）        ] 增量累加，
//      O_sy    Σy，y 是行号（0 在顶部）           ] 不需要扫描
//      O_sx    Σx                                 ] 人跳起来时 y 变小 -> Σy 变小
//      O_x0/x1/y0/y1  包围框
//         ★ 框不是 min/max，而是「行列投影 + 阈值裁剪」扫描出来的：
//           每行/每列统计前景格子数，投影 >= PROJ_TH 的行列才参与定位。
//           这样一个跑到画面边缘的孤立噪声格子不会再把框撑大。
//           （详见下方「行列投影 + 扫描裁剪」一节）
//  延迟对齐
//  ---------------------------------------------------------------------------
//  I_de 接 S_hdmi_window_rd_en（与 enhance 同一个信号），DE_LAG 同样取 2。
//  采样判决是**寄存一拍**的：采样那一拍锁存 gray/bg 与坐标，下一拍判决，
//  所以累加器用寄存后的 sx_r / sy_r。
//
//  每帧时序
//  ---------------------------------------------------------------------------
//  有效像素期  : 累加 area/Σ/Σ² + 行列投影 +1
//  帧末空白期  : 扫描投影（H+W+2 拍），更新包围框，然后才发 O_valid
//  排错基准：DIFF_TH 设成 255 时应当完全没有前景（O_area 恒为 0）。
//=============================================================================

module motion_stats #(
    parameter IMG_WIDTH  = 1280,
    parameter IMG_HEIGHT = 720,
    // 降采样：DS_LOG2=3 -> 8x8 -> 160x90（115 Kbit，全用 LUT 约 2250 个，推荐）
    //         DS_LOG2=2 -> 4x4 -> 320x180（460 Kbit，会撑爆资源，见下方帧缓存注释）
    parameter DS_LOG2    = 3,
    // 背景自适应速度：每帧向当前灰度靠拢 1/2^BG_SHIFT
    //   5 -> 时间常数 32 帧 ≈ 1.07 秒（推荐）
    //   调小 = 背景更新快 = 慢速运动容易被吸收；调大 = 背景更新慢 = 容易留鬼影
    parameter integer BG_SHIFT = 5,
    // 前景判决阈值的【默认值】，实际用 I_diff_th 端口传入（可在线切换）
    parameter [7:0] DIFF_TH = 8'd10,
    //------------------------------------------------------------------
    // 亮度门：灰度必须落在这个区间内，才【有资格】被判成前景
    //
    //   为什么需要
    //     灯光会被误判成前景，原因有三：
    //       ① 市电 50Hz 让灯以 100Hz 闪烁，相机 60fps 采到每帧亮度都不同
    //       ② 画面里有强光源时相机自动曝光来回调整，整体亮度周期性变化
    //       ③ 相机配置是 4 倍模拟增益，亮区噪声被放大 4 倍
    //     结果：灯那一整片 |灰度-背景| 都超阈值 → 包围框撑满全屏、质心被拉走。
    //
    //   原理
    //     灯通常是过亮/接近饱和的（灰度很高），深阴影区则是噪声主导（灰度很低）。
    //     把这两头切掉，中间的正常亮度区间才参与判决。
    //
    //   调法
    //     · 灯还是被锁 → GRAY_HI 调小（如 200）
    //     · 人穿白衣服/在强光下被漏掉 → GRAY_HI 调大（如 245）
    //     · 暗处噪声多 → GRAY_LO 调大（如 30）
    //------------------------------------------------------------------
    parameter [7:0] GRAY_LO = 8'd16,      // 仅作为「没接串口时」的默认值（见 param_ctrl）
    parameter [7:0] GRAY_HI = 8'd235,     // 运行值由 I_gray_lo / I_gray_hi 端口给
    //------------------------------------------------------------------
    // 包围框「投影裁剪」阈值（详见下方同名小节）
    //
    //   一行 / 一列里的前景格子数 >= PROJ_TH，才算「有效行列」，参与框的定位。
    //   正常人的一行通常有 3~5 个前景格子，孤立噪声只有 1~2 个。
    //     2 = 保守（人站得远、目标小时也留得住）  ← 默认
    //     3 = 更狠（噪声滤得更干净，但远距离小目标可能被裁掉一截）
    //     1 = 几乎不过滤（只在确认没有噪声时用）
    //   ⚠ 2026-10-13 起改为端口 I_proj_th，可用串口在线调（命令 P3=<值>）
    //------------------------------------------------------------------
    parameter [7:0] PROJ_TH = 8'd2,       // 仅作默认值，运行值由 I_proj_th 给
    // 连续多少帧没找到前景后，才开始把框慢慢收掉。
    //   12 帧 @60fps = 0.2 秒。加这个是为了避免"偶发一帧 area=0"把框抖小两格。
    parameter [3:0] MISS_HOLD = 4'd12,
    // I_de 相对 I_data 的超前拍数（video_out 输出滞后 rd_en 2 拍）
    parameter integer DE_LAG = 2
)(
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire        I_de,          // 数据有效，接 S_hdmi_window_rd_en
    input  wire [23:0] I_data,        // 原始像素 {R,G,B}
    input  wire [ 7:0] I_diff_th,     // 前景判决阈值（拨码开关 SW2/SW3 或串口）
    //------------------------------------------------------------------
    // 2026-10-13 起以下 3 个改为端口，由 param_ctrl 驱动 —— 串口在线调参，
    // 不用再重新编译（本工程一次编译要 75~92 分钟）。
    // 上电默认值由 param_ctrl 给，与原 parameter 原值一致。
    //------------------------------------------------------------------
    input  wire [ 7:0] I_gray_lo,     // 亮度门下限（原 GRAY_LO=16）
    input  wire [ 7:0] I_gray_hi,     // 亮度门上限（原 GRAY_HI=235）
    input  wire [ 7:0] I_proj_th,     // 包围框投影裁剪阈值（原 PROJ_TH=2）
    // ★ 2026-10-29：背景自适应速度（串口 P23），2~5，默认 3
    //   2=0.07s（极快）3=0.13s（快，推荐）4=0.27s（中）5=0.5s（慢，拖影明显）
    input  wire [ 3:0] I_bg_shift,
    // ★ 2026-10-29：帧差法（与背景相减 OR 合并），SW4 控制
    //   I_fd_en=1 时：前景 = 背景相减 OR 帧差
    //   好处：帧差对快速移动立刻响应，背景相减补静止目标
    //   ⚠ 注意：OR 是并集，不会消除背景相减那一路的拖影
    input  wire        I_fd_en,
    input  wire [ 7:0] I_fd_th,       // 帧差阈值（串口 P24），默认 12

    output reg         O_valid,       // 每帧末尾一个脉冲
    output reg  [16:0] O_area,        // 前景像素数（320x180 域，最大 57600）
    output reg  [24:0] O_sy,          // Σy
    output reg  [24:0] O_sx,          // Σx
    //------------------------------------------------------------------
    // 二阶矩（Σx²、Σy²）—— 给形状特征用
    //
    //   参考：2024 国二作品「多功能图像处理平台」（Hu 不变矩手势识别）
    //   用 M_00/M_10/M_01/M_20/M_02/M_11 六个矩做手势分类。
    //   我们原来只有前三个（area/Σx/Σy），加上二阶矩之后可以导出：
    //     · 分散度  μ20+μ02 —— 姿态紧凑还是舒展
    //     · 细长度  μ20 vs μ02 —— 跳绳（细长）vs 深蹲（敦实）vs 开合跳（宽）
    //   注意：这两个是**原始矩**，不是中心矩，做分类时要用面积归一化。
    //   不输出 Σxy（方向/离心率用），因为人的姿态基本是竖直的，用不上，
    //   省一个乘法器。
    //------------------------------------------------------------------
    output reg  [29:0] O_sx2,         // Σx²
    output reg  [29:0] O_sy2,         // Σy²
    output reg  [8:0]  O_x0,          // 包围框左
    output reg  [8:0]  O_x1,          // 包围框右
    output reg  [7:0]  O_y0,          // 包围框上
    output reg  [7:0]  O_y1,          // 包围框下

    // ---- 逐行轮廓（每帧扫行时流式输出 90 行）----
    //   用途：OSD 画"贴紧人体、有棱有角"的轮廓，替代/补充整体外接矩形。
    //   row_bbox 在累加期按行维护，扫行时流式输出（90 拍）。
    //   注意：扫行时【只读不清零】—— 见下方 S_SCANR 里的说明。
    output reg         O_row_valid,   // 扫行期间为 1（90 拍）
    output reg  [6:0]  O_row_idx,     // 行号 0..89
    output reg  [7:0]  O_row_min,     // 该行最左前景列（8'hFF = 本行无前景）
    output reg  [7:0]  O_row_max      // 该行最右前景列（0 = 本行无前景）
);

    localparam W = IMG_WIDTH  >> DS_LOG2;    // DS_LOG2=3 -> 160（=2 -> 320）
    localparam H = IMG_HEIGHT >> DS_LOG2;    // DS_LOG2=3 ->  90（=2 -> 180）

    //-------------------------------------------------------------------------
    // 输入侧 de 对齐
    //-------------------------------------------------------------------------
    reg [3:0] de_sr;

    always @(posedge I_clk) begin
        if (!I_rst_n) de_sr <= 4'd0;
        else          de_sr <= {de_sr[2:0], I_de};
    end

    wire de_align = de_sr[DE_LAG-1];

    //-------------------------------------------------------------------------
    // 行列计数（只在 de_align 有效时推进）
    //-------------------------------------------------------------------------
    reg [10:0] x_cnt;
    reg [10:0] y_cnt;

    always @(posedge I_clk) begin
        if (!I_rst_n) begin
            x_cnt <= 11'd0;
            y_cnt <= 11'd0;
        end
        else if (de_align) begin
            if (x_cnt == IMG_WIDTH-1) begin
                x_cnt <= 11'd0;
                if (y_cnt == IMG_HEIGHT-1) y_cnt <= 11'd0;
                else                       y_cnt <= y_cnt + 1'b1;
            end
            else begin
                x_cnt <= x_cnt + 1'b1;
            end
        end
    end

    // 帧结束脉冲（最后一个有效像素处）
    wire frame_end = de_align && (x_cnt == IMG_WIDTH-1) && (y_cnt == IMG_HEIGHT-1);

    //-------------------------------------------------------------------------
    // 采样点：每 DS x DS 个像素取 1 个
    //   灰度用 R/4 + G/2 + B/4（与 edge_detect_96 一致）
    //-------------------------------------------------------------------------
    wire sample = de_align && (x_cnt[DS_LOG2-1:0] == 0) && (y_cnt[DS_LOG2-1:0] == 0);

    wire [9:0] gsum = {2'b00, I_data[23:16]} + {1'b0, I_data[15:8], 1'b0} + {2'b00, I_data[7:0]};
    wire [7:0] gray = gsum >> 2;

    wire [8:0] samp_x = x_cnt >> DS_LOG2;    // 0..319
    wire [7:0] samp_y = y_cnt >> DS_LOG2;    // 0..179

    //-------------------------------------------------------------------------
    // 帧缓存地址 = samp_y * W + samp_x
    //   不用乘法：W 是常量，拆成移位加法
    //     W=320（DS_LOG2=2）= 256 + 64
    //     W=160（DS_LOG2=3）= 128 + 32
    //   条件里的 W 是 localparam，综合时会被常量折叠，只留一个分支。
    //   想省 ERAM 就把 DS_LOG2 改成 3，这里不用动。
    //-------------------------------------------------------------------------
    wire [16:0] fb_addr = (W == 320) ? ({samp_y, 8'b0} + {1'b0, samp_y, 6'b0} + {1'b0, samp_x})
                                     : ({samp_y, 7'b0} + {1'b0, samp_y, 5'b0} + {1'b0, samp_x});

    //-------------------------------------------------------------------------
    // 帧缓存（故意不复位）
    //   同一拍「先读旧值、再写新值」，Verilog 非阻塞赋值天然保证这个顺序
    //
    //   ⚠️⚠️ 关于 ERAM：实测 TD 6.2 **认不出**这个 RAM 推断模式，两块属性都没用
    //     (* ram_style = "block" *)   —— Verilog 属性语法，静默忽略（值也非法）
    //     /* synthesis force_ram */ + /* synthesis ram_style = bram */ —— 也没生效
    //   两次编译 dram lut 都恒为 8192、eram 恒为 0。
    //   TD 官方模板（D:/TD/ip/depot/AXI_Ethernet_Lite_1.0/.../ram_infer.v）
    //   要求读写分块 + 写模式保护 + 输出寄存器带复位，本模块的
    //   「同拍同地址读旧值+写新值」不符合它的识别条件。
    //
    //   → 结论：**不要指望这块数组进 ERAM**，而是把规模压到"全用 LUT 也装得下"。
    //     DS_LOG2=3（160x90）时是 115 Kbit ≈ 2,250 个 LUT6，占总预算的 88.6%，能过。
    //     想回到 320x180 就必须改用 TD 的 IP 生成器造块 RAM，或改成分行/分列
    //     投影累加（不存整帧，只存上一帧的行和列投影，约 8 Kbit）。
    //-------------------------------------------------------------------------
    //--------------------------------------------------------------------------
    // ⚠ 2026-10-23：背景数组从 LUT RAM 搬到 ERAM
    //
    //  为什么
    //    bg 是 160x90x8bit = 115 Kbit，用 LUT RAM 实现吃掉 2,344 个 LUT，
    //    资源利用率 92.1%，布线拥塞导致 Setup WNS = -6.095ns（235 个违例）。
    //    搬到 ERAM 能省约 586 个 slice。
    //
    //  和 2026-10-18 那次失败（8x4 改造）的关键区别
    //    那次【同时】改了网格尺寸（90→180 行）+ 搬 ERAM + 改位宽，15 处联动，
    //    出问题分不清是谁的错。这次只搬存储，网格/阈值/坐标/位宽一行不动。
    //
    //  流水线（这次必须做对，上次就是这里错的）
    //    t    拍：sample=1，锁存 addr_r / gray_r / sx_r / sy_r，samp_r<=1
    //    t+1  拍：samp_r=1 → wea=1，同址读写 addr_r；
    //            READBEFOREWRITE 保证 doa 输出【写之前的旧值】；
    //            bg_next 用 gray_r + bg_val 算（两者都是 t+1 拍、同一格）
    //    t+2  拍：samp_r2=1，bdiff = |gray_r - bg_r| → fg
    //
    //  地址 14 位（16,384 >= 14,400），单块 ERAM 20Kbit → 约 6 块。
    //--------------------------------------------------------------------------
    reg  [13:0] addr_r;
    wire [7:0]  bg_val;          // ERAM 输出，比 addr_r 晚 1 拍
    wire [7:0]  prev_val;        // ★ 帧差用：上一帧同位置灰度（与 bg_val 同拍）

    //-------------------------------------------------------------------------
    // ⚠️ 采样判决必须【寄存一拍】，不要改成组合逻辑！
    //
    //   曾经试过"采样那一拍直接用 gray 和 bg[fb_addr] 相减"（省掉流水线），
    //   结果是上电后画面全黑、计数乱跳。原因：
    //     timing.sdc 是空的 -> TD **完全不做时序分析**，编译永远"成功"，
    //     组合路径超时也不报警。
    //     组合版的关键路径变成：
    //       fb_addr -> LUT RAM 异步读 -> 8位减法 -> 比较 -> 25位加法器进位链
    //     在 74.25MHz（13.5ns）下大概率超时。
    //
    //   所以这里保留原始写法：采样时寄存 gray/bg，下一拍再判决。
    //   代价是 fg 比采样晚一拍，累加器要用寄存后的 sx_r / sy_r。
    //-------------------------------------------------------------------------
    reg [7:0] bg_r;
    reg [7:0] prev_r;              // ★ 帧差用：上一帧同位置灰度（与 bg_r 同拍）
    reg [7:0] gray_r;
    reg [8:0] sx_r;
    reg [7:0] sy_r;
    reg       samp_r;

    // 背景更新：每帧向当前灰度靠拢 1/2^BG_SHIFT
    //   差异小时 (>>BG_SHIFT) 会变成 0，背景就永远追不上，
    //   所以强制至少动 1。DIFF_TH 远大于 1，所以这点抖动不会被判成前景。
    //   ⚠ 必须用 gray_r（t 拍锁存的灰度），不能用 gray ——
    //     bg_val 对应的是 addr_r 那一格，而 addr_r 是 t 拍锁存的。
    //--------------------------------------------------------------------------
    // ⚠ 第一帧播种（ERAM 上电内容未知，必须填一次）
    //
    //  如果 ERAM 上电是 X，那么 bg_next = f(gray_r, X) 仍然是 X，
    //  写回去还是 X —— 背景永远好不了，前景恒 0，画面无框。
    //  这是 2026-10-18 那次"全 0"最可能的原因之一。
    //
    //  用独立计数器数满一帧的采样点（14,400 个）就直接写当前灰度，
    //  一帧之后所有格子都有初值，之后才切到增量更新。
    //  第一帧本来就不输出统计（frame_ok 要求 frame_idx >= 64），所以无副作用。
    //  ⚠ 不能用 frame_idx：它声明在文件后半部分，Verilog 的 reg 不能前向引用。
    //--------------------------------------------------------------------------
    reg [15:0] seed_cnt;

    always @(posedge I_clk) begin
        if (!I_rst_n)
            seed_cnt <= 16'd0;
        else if (sample && (seed_cnt != 16'hFFFF))
            seed_cnt <= seed_cnt + 16'd1;
    end

    wire       bg_seed = (seed_cnt < 16'd14400);

    wire [7:0] bg_gap  = (gray_r > bg_val) ? (gray_r - bg_val) : (bg_val - gray_r);
    // ★ 2026-10-29：BG_SHIFT 从编译期常量改成【运行期可调】（串口 P23）
    //   原因：用户反复调"轮廓贴合速度"，每次都要重编译（10 分钟），效率太低。
    //   实现：用 case 选常量移位——常量移位在综合后只是"选位"，不占 LUT；
    //         4 选 1 的 8 位 MUX 约 8 个 LUT6，资源可接受。
    //   范围 2~5：2=0.07s（极快，站着框几乎立刻消失）
    //             3=0.13s（快，推荐）
    //             4=0.27s（中）
    //             5=0.5s （慢，拖影明显）
    reg [7:0] bg_shr;
    always @(*) begin
        case (I_bg_shift)
            4'd2:    bg_shr = bg_gap >> 2;
            4'd3:    bg_shr = bg_gap >> 3;
            4'd4:    bg_shr = bg_gap >> 4;
            4'd5:    bg_shr = bg_gap >> 5;
            default: bg_shr = bg_gap >> 3;   // 默认 3（0.13s）
        endcase
    end
    wire [7:0] bg_step = (bg_shr == 8'd0) ? 8'd1 : bg_shr;   // 最小步长 1，保证最终能追上
    wire [7:0] bg_upd  = (gray_r > bg_val) ? (bg_val + bg_step) : (bg_val - bg_step);
    wire [7:0] bg_next = bg_seed ? gray_r : bg_upd;

    PH1P_LOGIC_ERAM #(
        .DATA_WIDTH_A          ( 8             ),
        .DATA_WIDTH_B          ( 8             ),
        .ADDR_WIDTH_A          ( 14            ),
        .ADDR_WIDTH_B          ( 14            ),
        .DATA_DEPTH_A          ( 16384         ),
        .DATA_DEPTH_B          ( 16384         ),
        .MODE                  ( "DP"          ),
        .REGMODE_A             ( "NOREG"       ),
        .REGMODE_B             ( "NOREG"       ),
        .WRITEMODE_A           ( "NORMAL"      ),
        .WRITEMODE_B           ( "NORMAL"      ),
        .IMPLEMENT             ( "20K(FAST)"   ),
        .ECC_ENCODE            ( "DISABLE"     ),
        .ECC_DECODE            ( "DISABLE"     ),
        .CLKMODE               ( "ASYNC"       ),
        .SSROVERCE             ( "DISABLE"     ),
        .OREGSET_A             ( "RESET"       ),
        .OREGSET_B             ( "RESET"       ),
        .RESETMODE_A           ( "ASYNC"       ),
        .RESETMODE_B           ( "ASYNC"       ),
        .ASYNC_RESET_RELEASE_A ( "ASYNC"       ),
        .ASYNC_RESET_RELEASE_B ( "ASYNC"       ),
        .DEBUGGABLE            ( "NO"          ),
        .PACKABLE              ( "NO"          ),
        .INIT_FILE             ( "NONE"        ),
        .FILL_ALL              ( "NONE"        )
    ) u_bg_eram (
        // ---- A 口：只读，地址是【当前采样点】(fb_addr) ----
        //   t 拍给地址 A0，块 RAM 同步读，doa 在 t+1 拍输出 mem[A0]（旧值）
        .dia              ( 8'd0           ),
        .addra            ( fb_addr[13:0]  ),
        .cea              ( 1'b1           ),
        .ocea             ( 1'b1           ),
        .clka             ( I_clk          ),
        .wea              ( 1'b0           ),
        .bea              ( 1'b1           ),
        .rsta             ( 1'b0           ),
        .doa              ( bg_val         ),
        // ---- B 口：只写，地址是【锁存的上一个采样点】(addr_r) ----
        //   t 拍锁存 addr_r<=A0；t+1 拍 web=1 把 bg_next 写到 A0。
        //   此时 A 口读的是 A1，读写地址不同 → 彻底避开同址冲突
        //   （2026-10-18 那次就是读写同址，读到刚写的新值，前景恒 0）
        .dib              ( bg_next        ),
        .addrb            ( addr_r         ),
        .ceb              ( 1'b1           ),
        .oceb             ( 1'b0           ),
        .clkb             ( I_clk          ),
        .web              ( samp_r         ),
        .beb              ( 1'b1           ),
        .rstb             ( 1'b0           ),
        .dob              (                ),
        .ecc_sbiterrinj   ( 1'b0           ),
        .ecc_dbiterrinj   ( 1'b0           ),
        .ecc_sbiterr      (                ),
        .ecc_dbiterr      (                )
    );

    //--------------------------------------------------------------------------
    // ★ 2026-10-29：第二块 ERAM —— 存"上一帧"，用于帧差法
    //   结构和 u_bg_eram 完全一致：
    //     A 口：读当前采样点的上一帧灰度 → prev_val（t+1 拍）
    //     B 口：把当前帧灰度写回同一地址 → 下一帧就是"上一帧"
    //   时序：dib=gray_r 在 t+1 拍是 gray(t)，addrb=addr_r 是 t 拍锁存的地址 ✅
    //   资源：多占约 10 块 ERAM（剩 32 块，够）
    //--------------------------------------------------------------------------
    PH1P_LOGIC_ERAM #(
        .DATA_WIDTH_A          ( 8             ),
        .DATA_WIDTH_B          ( 8             ),
        .ADDR_WIDTH_A          ( 14            ),
        .ADDR_WIDTH_B          ( 14            ),
        .DATA_DEPTH_A          ( 16384         ),
        .DATA_DEPTH_B          ( 16384         ),
        .MODE                  ( "DP"          ),
        .REGMODE_A             ( "NOREG"       ),
        .REGMODE_B             ( "NOREG"       ),
        .WRITEMODE_A           ( "NORMAL"      ),
        .WRITEMODE_B           ( "NORMAL"      ),
        .IMPLEMENT             ( "20K(FAST)"   ),
        .ECC_ENCODE            ( "DISABLE"     ),
        .ECC_DECODE            ( "DISABLE"     ),
        .CLKMODE               ( "ASYNC"       ),
        .SSROVERCE             ( "DISABLE"     ),
        .OREGSET_A             ( "RESET"       ),
        .OREGSET_B             ( "RESET"       ),
        .RESETMODE_A           ( "ASYNC"       ),
        .RESETMODE_B           ( "ASYNC"       ),
        .ASYNC_RESET_RELEASE_A ( "ASYNC"       ),
        .ASYNC_RESET_RELEASE_B ( "ASYNC"       ),
        .DEBUGGABLE            ( "NO"          ),
        .PACKABLE              ( "NO"          ),
        .INIT_FILE             ( "NONE"        ),
        .FILL_ALL              ( "NONE"        )
    ) u_prev_eram (
        .dia              ( 8'd0           ),
        .addra            ( fb_addr[13:0]  ),
        .cea              ( 1'b1           ),
        .ocea             ( 1'b1           ),
        .clka             ( I_clk          ),
        .wea              ( 1'b0           ),
        .bea              ( 1'b1           ),
        .rsta             ( 1'b0           ),
        .doa              ( prev_val       ),
        .dib              ( gray_r         ),   // 当前帧灰度，覆盖上一帧
        .addrb            ( addr_r         ),
        .ceb              ( 1'b1           ),
        .oceb             ( 1'b0           ),
        .clkb             ( I_clk          ),
        .web              ( samp_r         ),
        .beb              ( 1'b1           ),
        .rstb             ( 1'b0           ),
        .dob              (                ),
        .ecc_sbiterrinj   ( 1'b0           ),
        .ecc_dbiterrinj   ( 1'b0           ),
        .ecc_sbiterr      (                ),
        .ecc_dbiterr      (                )
    );

    reg samp_r2;                     // 判决脉冲（比采样晚 2 拍）

    always @(posedge I_clk) begin
        if (sample) begin
            addr_r  <= fb_addr[13:0];    // 锁存本格地址
            gray_r  <= gray;
            sx_r    <= samp_x;
            sy_r    <= samp_y;
            samp_r  <= 1'b1;
        end
        else begin
            samp_r  <= 1'b0;
        end
    end

    always @(posedge I_clk) begin
        samp_r2 <= samp_r;
        if (samp_r) bg_r <= bg_val;  // 锁存 t+1 拍读出的旧背景
        if (samp_r) prev_r <= prev_val;  // ★ 锁存 t+1 拍读出的上一帧（与 bg_r 同拍对齐）
    end

    //-------------------------------------------------------------------------
    // 前景判决：与「背景」的差异，而不是与「上一帧」的差异
    //
    //   为什么不用帧差
    //     帧差只能检测"变化的边缘"——人物内部几乎不产生差异。
    //     再叠加每 8x8 只采样一个点，远处的人几乎检不出东西
    //     （实测用户站远处跳绳时 Σy 峰峰值只有 8~9，等于没有信号）。
    //
    //   背景相减
    //     维护一幅缓慢自适应的背景（时间常数 2^BG_SHIFT 帧 ≈ 1 秒）。
    //       静止背景 -> 背景收敛到它 -> 差异 0 -> 无前景 ✓
    //       运动的人 -> 与背景差异大 -> **整个轮廓**都是前景，不是只有边缘 ✓
    //
    //     副作用：站着不动超过约 1 秒，人会被"吸收"进背景、前景消失。
    //     对跳绳来说正合适 —— 停下来了本来就不该有前景。
    //
    //   启动瞬态：背景初值未知，上电后需要约 2 秒收敛，
    //     所以 frame_ok 要等到 64 帧之后才输出（见下面的帧计数）。
    //-------------------------------------------------------------------------
    wire [7:0] bdiff = (gray_r > bg_r) ? (gray_r - bg_r) : (bg_r - gray_r);

    // 亮度门：过亮（灯 / 窗 / 反光）和过暗（深阴影噪声主导）的像素直接排除。
    //   比较对象是【当前像素】gray_r，不是背景 —— 因为要判的是"这个地方亮不亮"。
    //   这一级是纯组合分支，和 bdiff 并行算，只给 fg 的与门加一级 LUT，不影响时序。
    wire gray_ok = (gray_r >= I_gray_lo) && (gray_r <= I_gray_hi);

    // ★ 2026-10-29：帧差法（SW4 控制），与背景相减 OR 合并
    //   fdiff = |当前帧 - 上一帧|：只检测"变化"，快速移动立刻响应
    //   bdiff = |当前帧 - 背景模型|：检测所有前景，静止目标保留
    //   两者 OR = 并集（更灵敏），但【不会消除】背景相减那一路的拖影
    wire [7:0] fdiff = (gray_r > prev_r) ? (gray_r - prev_r) : (prev_r - gray_r);
    wire       fg_bg = (bdiff > I_diff_th);
    wire       fg_fd = (fdiff > I_fd_th);
    wire       fg    = samp_r2 && !bg_seed && (I_fd_en ? (fg_bg | fg_fd) : fg_bg) && gray_ok;  // ERAM 多 1 拍 + 播种期屏蔽



    //-------------------------------------------------------------------------
    // 帧结束延迟几拍，等最后一个采样点累加完
    //-------------------------------------------------------------------------
    // 2026-10-23：ERAM 让 fg 多晚 1 拍，这里同步加深 1 拍，
    //   否则最后一个采样点还没累加完就发 frame_done，会漏统计。
    reg [3:0] fe_dly;

    always @(posedge I_clk) begin
        if (!I_rst_n) fe_dly <= 4'd0;
        else          fe_dly <= {fe_dly[2:0], frame_end};
    end

    wire frame_done = fe_dly[3];

    //-------------------------------------------------------------------------
    // 帧计数：等背景收敛后再输出
    //   背景是自适应收敛的，上电后需要约 2 秒（60 帧）才能稳定。
    //   这期间输出的统计量没有意义，所以 frame_ok 要求 frame_idx >= 64。
    //-------------------------------------------------------------------------
    reg [6:0] frame_idx;

    always @(posedge I_clk) begin
        if (!I_rst_n) frame_idx <= 7'd0;
        else if (frame_done && (frame_idx != 7'd127)) frame_idx <= frame_idx + 1'b1;
    end

    wire frame_ok = (frame_idx >= 7'd64);

    //-------------------------------------------------------------------------
    // 行列投影 + 扫描裁剪：让包围框「贴住人」
    //
    //   原来的框 = 所有前景格子的 min/max
    //     → 任意一个噪声格子跑到画面边缘，框就被推出去老远；下一帧噪声没了又缩回来。
    //       看起来就是「框很大、框在抖、框不贴人」。
    //
    //   现在分两步：
    //     ① 统计（累加期）：每行、每列各有多少个前景格子
    //            row_proj[0..H-1]   每行前景格子数（最大 W=160）
    //            col_proj[0..W-1]   每列前景格子数（最大 H=90）
    //     ② 扫描（帧末空白期）：只保留投影 >= PROJ_TH 的行/列，取首末
    //            孤立噪声（1 个格子）投影 = 1 < PROJ_TH → 直接丢掉，框不受影响
    //
    //   为什么扫描放帧末
    //     720p60 每帧 1650x750，有效像素只有 1280x720 →
    //     每帧空白期约 (1650*750 - 1280*720) / 74.25MHz ≈ 4.2 ms ≈ 31 万拍。
    //     扫描只要 H+W+2 = 252 拍，余量巨大；而且空白期根本没有采样，
    //     不会和累加打架。
    //
    //   投影的读-改-写拆成三拍
    //     LUT RAM 的「异步读 -> 加 1 -> 写回」若挤在一拍，长路径会吃时序，
    //     而本工程的 timing.sdc 是空的（TD 不做时序分析，超时也不报错）→
    //     宁可多花两拍。采样点之间隔 64 个像素，三拍绰绰有余。
    //
    //   ⚠ 本次只改「框」，area / Σy / Σx / Σx² / Σy² 的累加逻辑一个字没动，
    //     所以计数链路（jump_counter）不受影响。
    //-------------------------------------------------------------------------
    reg [7:0] row_proj [0:H-1];

    //=========================================================================
    // ★★ 2026-10-30：col_proj 从「LUT RAM」改成「ERAM（块 RAM）」
    //
    //   为什么只改这一个（方案 B，低风险）
    //     col_proj 是三个投影数组里最大的（160×8 = 1,280 bit），
    //     TD 把它推断成分布式 RAM，占约 1,000 个 slice。
    //     只改它就能省约 1,000 slice（94.3% → 89.6%），
    //     且只影响"框的左右边界"，验证简单（看框左右是否贴边）。
    //     row_proj / row_bbox 暂不动（它们的扫描状态机更复杂，风险更高）。
    //
    //   ⚠ 时序变化（关键）
    //     · 累加：ph1 给地址（rmw_x），ph2 用 ERAM 输出（cp_dout）→ 3 相位不变
    //     · 扫描：原来每列 1 拍，现在每列 2 拍（子相位 0 给地址、1 用数据）
    //     · 清零：延后 1 拍写（用 sidx_d），最后列额外多等 1 拍
    //=========================================================================
    reg [7:0]  sidx_d;                     // 上一拍的扫描索引（用于延后清零）
    reg        scan_ph;                    // S_SCANC 的子相位：0=给地址 1=用数据
    reg        scan_tail;                  // 最后一列的清零补拍
    wire [7:0] cp_dout;                    // ERAM 输出

    // ★ 2026-10-30：sidx 的 1 拍延迟（清零写地址用，避免同拍读写同地址）
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) sidx_d <= 8'd0;
        else          sidx_d <= sidx[7:0];
    end

    wire [7:0] W_cp_raddr = (st == S_SCANC) ? sidx[7:0] : rmw_x[7:0];
    wire [7:0] W_cp_waddr = (st == S_SCANC) ? sidx_d     : rmw_x[7:0];
    wire       W_cp_we    = (st == S_SCANC) ? (scan_ph & ~scan_tail) : (rmw_ph == 2'd2);
    wire [7:0] W_cp_din   = (st == S_SCANC) ? 8'd0 : (cp_dout + 8'd1);

    PH1P_LOGIC_ERAM #(
        .DATA_WIDTH_A (8), .DATA_WIDTH_B (8),
        .ADDR_WIDTH_A (8), .ADDR_WIDTH_B (8),
        .DATA_DEPTH_A (256), .DATA_DEPTH_B (256),
        .MODE ("DP"), .REGMODE_A ("NOREG"), .REGMODE_B ("NOREG"),
        .WRITEMODE_A ("NORMAL"), .WRITEMODE_B ("NORMAL"),
        .IMPLEMENT ("20K(FAST)"),
        .ECC_ENCODE ("DISABLE"), .ECC_DECODE ("DISABLE"),
        .CLKMODE ("ASYNC"), .SSROVERCE ("DISABLE"),
        .OREGSET_A ("RESET"), .OREGSET_B ("RESET"),
        .RESETMODE_A ("ASYNC"), .RESETMODE_B ("ASYNC"),
        .ASYNC_RESET_RELEASE_A ("ASYNC"), .ASYNC_RESET_RELEASE_B ("ASYNC"),
        .DEBUGGABLE ("NO"), .PACKABLE ("NO"),
        .INIT_FILE ("NONE"), .FILL_ALL ("NONE")
    ) u_col_proj_eram (
        .dia (8'd0),
        .addra (W_cp_raddr), .cea (1'b1), .ocea (1'b1), .clka (I_clk),
        .wea (1'b0), .bea (1'b1), .rsta (1'b0), .doa (cp_dout),
        .dib (W_cp_din), .addrb (W_cp_waddr), .ceb (1'b1), .oceb (1'b0),
        .clkb (I_clk), .web (W_cp_we), .beb (1'b1), .rstb (1'b0), .dob (),
        .ecc_sbiterrinj (1'b0), .ecc_dbiterrinj (1'b0),
        .ecc_sbiterr (), .ecc_dbiterr ()
    );

    // 逐行左右边界（轮廓框）：{minx, maxx} 合并成一个 16 位数组
    //   ⚠ 必须让 TD 推断成 RAM，否则会退化成 1440 个 FF + 90:1 mux 树
    //     （实测：logic +4,243 / seq +2,957，slice 直接爆到 21,567）。
    //   推断的关键是【不要在扫描时同拍读写同一地址】—— 所以扫描只读、不清零。
    //   不清零是安全的：rmw 用 (rmw_rv==0) 判断"本行第一个前景格子"直接赋值；
    //   本行无前景时输出端用 row_proj==0 屏蔽，与数组旧值无关。
    reg [15:0] row_bbox [0:H-1];

    localparam S_ACC    = 3'd0,   // 累加期
               S_SCANR  = 3'd1,   // 扫行
               S_SCANC  = 3'd2,   // 扫列
               S_LATCH  = 3'd3,   // 把扫描结果锁进 O_x0..
               S_VALID  = 3'd4;   // 再等一拍才断言 O_valid（让下游取到新框）

    reg [2:0] st;
    reg [8:0] sidx;               // 扫描索引
    reg       fr, fc;             // 行 / 列 是否找到有效投影
    // ★ 2026-10-16：扫描时记录"上一行/上一列是否合格"，
    //   用于要求【连续两行/两列】才确定边界（过滤孤立的投影读错）
    reg       prev_rok, prev_cok;
    reg [7:0] sy0n, sy1n;         // 扫描得到的上下边
    reg [8:0] sx0n, sx1n;         // 扫描得到的左右边
    // ★ 2026-10-16 新增：投影的两级延迟，用于把边界【向外扩 1 列/行】
    //   为什么要扩：人体的最外沿那一列/行往往只有 1 个前景格子
    //   （col_proj = 1 < PROJ_TH），按"强列"判定就会把边界停在人体内部
    //   —— 现象就是"框不贴紧人体"。有了 d2/d1，就能在确定边界时
    //   回看外面那一列有没有前景，有就一起包进来。
    reg [7:0] rp_d1, rp_d2;       // row_proj[sidx-1], row_proj[sidx-2]
    reg [7:0] cp_d1, cp_d2;       // col_proj[sidx-1], col_proj[sidx-2]

    reg [1:0] rmw_ph;             // 投影读改写相位
    reg [8:0] rmw_x;
    reg [7:0] rmw_y;
    reg [7:0] rmw_rv, rmw_cv;
    reg [15:0] rmw_bb;            // row_bbox 的旧值 {minx, maxx}
    // frame_done 只持续 1 拍，若那一拍恰好有未完成的读改写就会漏掉扫描
    // （空白期虽然不会发生，但万一发生就会永久卡住、框再也不更新）
    // → 先记下来，等读改写做完再启动扫描。
    reg       frame_pending;

    // 锁存框（比 O_valid 早一拍，好让 motion_report 采到的是新框）
    wire scn_latch = (st == S_LATCH);
    wire scn_valid = (st == S_VALID);

    always @(posedge I_clk) begin
        if (!I_rst_n) begin
            st     <= S_ACC;
            sidx   <= 9'd0;
            fr     <= 1'b0;
            fc     <= 1'b0;
            sy0n   <= 8'd0;
            sy1n   <= 8'd0;
            sx0n   <= 9'd0;
            sx1n   <= 9'd0;
            rmw_ph <= 2'd0;
            rmw_x  <= 9'd0;
            rmw_y  <= 8'd0;
            rmw_rv <= 8'd0;
            rmw_cv <= 8'd0;
            rmw_bb <= 16'd0;
            // ★ 2026-10-30：col_proj 改 ERAM 后新增的状态
            //   （sidx_d 在独立 always 块里复位，这里不能重复赋值，否则多驱动）
            scan_ph    <= 1'b0;
            scan_tail  <= 1'b0;
            O_row_valid <= 1'b0;
            O_row_idx   <= 7'd0;
            O_row_min   <= 8'hFF;
            O_row_max   <= 8'd0;
            frame_pending <= 1'b0;
            rp_d1  <= 8'd0;
            rp_d2  <= 8'd0;
            cp_d1  <= 8'd0;
            cp_d2  <= 8'd0;
        end
        else begin
            case (st)
                //--------------------------------------------------------------
                // 累加期：每采样到一个前景格子，就把对应行列投影 +1
                //--------------------------------------------------------------
                S_ACC: begin
                    case (rmw_ph)
                        2'd0: if (fg) begin
                                  rmw_x  <= sx_r;
                                  rmw_y  <= sy_r;
                                  rmw_ph <= 2'd1;
                              end
                        2'd1: begin
                                  rmw_rv <= row_proj[rmw_y];
                                  // ★ 2026-10-30：col_proj 改 ERAM 后不再组合读，
                                  //   这里给地址（addra=rmw_x），ph2 拍用 cp_dout
                                  rmw_bb <= row_bbox[rmw_y];
                                  rmw_ph <= 2'd2;
                              end
                        default: begin
                                  row_proj[rmw_y] <= rmw_rv + 8'd1;
                                  // ★ 2026-10-30：col_proj 的写由 ERAM 的 web/dib 完成
                                  //   （W_cp_din = cp_dout + 1，W_cp_we = ph2）
                                  // 逐行左右边界：本行【第一个】前景格子直接赋值，
                                  // 之后取 min/max。不依赖数组初值 —— 所以扫描时不用清零。
                                  row_bbox[rmw_y] <= (rmw_rv == 8'd0)
                                                     ? {rmw_x[7:0], rmw_x[7:0]}
                                                     : { (rmw_bb[15:8] < rmw_x[7:0]) ? rmw_bb[15:8] : rmw_x[7:0],
                                                         (rmw_bb[ 7:0] > rmw_x[7:0]) ? rmw_bb[ 7:0] : rmw_x[7:0] };
                                  rmw_ph <= 2'd0;
                              end
                    endcase

                    // 帧末先记下来；等读改写做完再启动扫描
                    if (frame_done) frame_pending <= 1'b1;

                    if (frame_pending && (rmw_ph == 2'd0)) begin
                        st            <= S_SCANR;
                        sidx          <= 9'd0;
                        fr            <= 1'b0;
                        fc            <= 1'b0;
                        prev_rok      <= 1'b0;   // 连续合格判定用，扫描开始清空
                        prev_cok      <= 1'b0;
                        // ⚠ 2026-10-16 补两处复位，修一个会注入"投影野值"的竞态
                        //
                        // ① 中止可能残留的半截读改写
                        //    phase0 里 `if (fg) rmw_ph <= 1` 与这里的
                        //    `if (frame_pending && rmw_ph==0) st <= S_SCANR`
                        //    有可能在【同一拍】同时成立 —— 那样 FSM 带着
                        //    rmw_ph=1 离开 S_ACC。等扫描结束回到 S_ACC，
                        //    phase1/phase2 会用【上一帧的旧 rmw_x/rmw_y】完成一次
                        //    读改写，把陈旧采样加到【新一帧】的投影上。
                        //    投影一旦多出孤立格子，列扫描就可能把
                        //    sx0n 判成 0 附近 -> 框瞬间连到画面最左边。
                        //    （用户实测就是这个症状：一瞬间、质心十字还在右边、
                        //      PIX 不变 —— 说明只有框坐标出现单帧野值。）
                        rmw_ph        <= 2'd0;
                        // ② 显式复位扫描结果
                        //    虽然 fr/fc=0 时下游不会使用它们，但显式复位更保险，
                        //    避免任何"旧值残留"导致框跳到历史位置。
                        sx0n          <= 9'd0;
                        sx1n          <= 9'd0;
                        sy0n          <= 8'd0;
                        sy1n          <= 8'd0;
                        frame_pending <= 1'b0;
                    end
                end

                //--------------------------------------------------------------
                // 扫行：只认投影 >= PROJ_TH 的行；顺手清零，下一帧重新累加
                //--------------------------------------------------------------
                S_SCANR: begin
                    // 两级延迟：本拍 rp_d1 = row_proj[sidx-1]、rp_d2 = row_proj[sidx-2]
                    rp_d1 <= row_proj[sidx[7:0]];
                    rp_d2 <= rp_d1;

                    if (row_proj[sidx[7:0]] >= I_proj_th) begin
                        // ★ 2026-10-16：要求【连续两行】都合格才确定上边。
                        //   为什么：投影数组是 LUT RAM，扫描时
                        //   `row_proj[sidx] >= I_proj_th` 是一条很长的组合路径
                        //   （mux 树 + 比较）。一次孤立的读错就会把某个
                        //   不该合格的行判成合格，把框的上边拉到画面顶部。
                        //   注意这种错误【不会影响 area】（area 走独立累加通路），
                        //   所以现象正是用户描述的"PIX 不变但框突然扩大"。
                        //   真人必然占据连续多行，"连续两行"不会漏掉真人。
                        if (!fr && prev_rok) begin
                            // ★ 再【向外扩 1 行】：sidx-2 那一行哪怕只有 1 个
                            //   前景格子（rp_d2 != 0），也把它包进来 —— 这样
                            //   框才贴紧人体的上沿。
                            sy0n <= (sidx >= 9'd2 && rp_d2 != 8'd0)
                                    ? (sidx[7:0] - 8'd2) : (sidx[7:0] - 8'd1);
                            fr   <= 1'b1;
                        end
                        // ⚠⚠ 2026-10-16 二次修复：下边【也必须】要求连续两行！
                        //
                        //   原来的写法是 `sy1n <= sidx`（无条件采纳每一个合格行），
                        //   而上边却有"连续两行"防护 —— **两边不对称**。
                        //   后果（用户实测："左边不贴、右边贴"）：
                        //     · 上边：被防护挡住，边界停在人体内部
                        //     · 下边：任何一个【孤立】的合格行都被采纳，
                        //             于是一个孤立噪声行就能把下边推到很下面
                        //   ⇒ 框看起来"下面贴、上面不贴"（列方向同理：
                        //      "右边贴、左边不贴"）。
                        //
                        //   加上 prev_rok 保护后，只有"本行和前一行都合格"
                        //   才更新下边 —— 真人占据连续多行，不受影响；
                        //   孤立噪声行则被排除。两边行为对称。
                        if (prev_rok) sy1n <= sidx[7:0];
                        prev_rok  <= 1'b1;
                    end
                    else begin
                        // ★ 向外扩 1 行：本行不够"强"，但只要有前景就包进来
                        //   （prev_rok=1 说明上一行是合格行，即这里是一个 run
                        //     刚刚结束的位置）
                        if (prev_rok && (row_proj[sidx[7:0]] != 8'd0))
                            sy1n <= sidx[7:0];
                        prev_rok  <= 1'b0;
                    end
                    row_proj[sidx[7:0]] <= 8'd0;

                    // ★ 轮廓：本拍把本帧该行的左右边界流式输出。
                    //   ⚠⚠ 这里【绝对不能】对 row_bbox 清零！
                    //     清零会造成"同一拍读同一地址又写同一地址"，
                    //     TD 推断不出 RAM，退化成 1440 个 FF + 90:1 mux 树
                    //     （实测 logic +4,243 / seq +2,957，slice 21,567 直接爆）。
                    //     不清零是安全的：rmw 用 (rmw_rv==0) 判断本行首格并直接赋值；
                    //     本行无前景时输出端用 row_proj==0 屏蔽，与数组旧值无关。
                    O_row_valid <= 1'b1;
                    O_row_idx   <= sidx[6:0];
                    O_row_min   <= (row_proj[sidx[7:0]] == 8'd0) ? 8'hFF : row_bbox[sidx[7:0]][15:8];
                    O_row_max   <= (row_proj[sidx[7:0]] == 8'd0) ? 8'd0   : row_bbox[sidx[7:0]][ 7:0];

                    if (sidx == H-1) begin
                        sidx      <= 9'd0;
                        scan_ph   <= 1'b0;      // ★ 2026-10-30：进入扫列前复位子相位
                        scan_tail <= 1'b0;
                        st        <= S_SCANC;
                    end
                    else sidx <= sidx + 1'b1;
                end

                //--------------------------------------------------------------
                // 扫列
                //--------------------------------------------------------------
                S_SCANC: begin
                    O_row_valid <= 1'b0;      // 轮廓行输出结束（90 拍扫完）

                    // ★ 2026-10-30：col_proj 改 ERAM 后每列 2 拍
                    //   子相位 0：addra 已经给了 sidx（W_cp_raddr），等数据
                    //   子相位 1：用 cp_dout 做比较/记录边界
                    if (!scan_ph) begin
                        scan_ph <= 1'b1;
                    end
                    else begin
                        scan_ph <= 1'b0;

                        // 两级延迟：本拍 cp_d1 = 上一列、cp_d2 = 上上一列
                        cp_d1 <= cp_dout;
                        cp_d2 <= cp_d1;

                        if (cp_dout >= I_proj_th) begin
                            // ★ 要求【连续两列】才确定左边（防孤立读错把框拉到最左）
                            if (!fc && prev_cok) begin
                                sx0n <= (sidx >= 9'd2 && cp_d2 != 8'd0)
                                        ? (sidx - 9'd2) : (sidx - 9'd1);
                                fc   <= 1'b1;
                            end
                            // 右边也要求连续两列（左右对称，见下方原注释）
                            if (prev_cok) sx1n <= sidx;
                            prev_cok <= 1'b1;
                        end
                        else begin
                            // 向外扩 1 列：本列不够"强"，但只要有前景就包进来
                            if (prev_cok && (cp_dout != 8'd0))
                                sx1n <= sidx;
                            prev_cok <= 1'b0;
                        end
                        // 清零由 ERAM 的 web 完成（写 sidx_d 地址）

                        if (sidx == W-1) begin
                            if (!scan_tail) begin
                                scan_tail <= 1'b1;   // 多等一拍，把最后一列的 0 写进去
                            end else begin
                                scan_tail <= 1'b0;
                                sidx      <= 9'd0;
                                st        <= S_LATCH;
                            end
                        end
                        else sidx <= sidx + 1'b1;
                    end
                end

                S_LATCH: st <= S_VALID;
                default: st <= S_ACC;
            endcase
        end
    end

    //-------------------------------------------------------------------------
    // 增量累加
    //-------------------------------------------------------------------------
    reg [16:0] acc_area;
    reg [24:0] acc_sy;
    reg [24:0] acc_sx;
    reg [29:0] acc_sx2;
    reg [29:0] acc_sy2;
    // 连续「没有前景」的帧数（用于迟一点才把框收掉，见 MISS_HOLD）
    reg [3:0]  miss_cnt;

    // 二阶矩的即时值（组合乘法，下一拍累加）
    //   sx_r 最大 159 -> 平方 25281，16 位够；sy_r 最大 89 -> 7921，14 位够
    //   取 [7:0] 是为了让 TD 推断 8x8 乘法器（sx_r 本身只有 0..159）
    wire [15:0] sx2_now = sx_r[7:0] * sx_r[7:0];
    wire [15:0] sy2_now = {2'b0, sy_r} * {2'b0, sy_r};

    always @(posedge I_clk) begin
        if (!I_rst_n) begin
            O_valid  <= 1'b0;
            O_area   <= 17'd0;
            O_sy     <= 25'd0;
            O_sx     <= 25'd0;
            O_sx2    <= 30'd0;
            O_sy2    <= 30'd0;
            O_x0     <= 9'd0;
            O_x1     <= 9'd0;
            O_y0     <= 8'd0;
            O_y1     <= 8'd0;
            acc_area <= 17'd0;
            acc_sy   <= 25'd0;
            acc_sx   <= 25'd0;
            acc_sx2  <= 30'd0;
            acc_sy2  <= 30'd0;
            miss_cnt <= 4'd0;
        end
        else begin
            O_valid <= 1'b0;

            // 累加前景像素
            //   ⚠ 这里【不再】做 min/max 包围框 —— 框改由行列投影扫描得到
            //     （见上方的「行列投影 + 扫描裁剪」）。area/Σ 的累加完全没变。
            if (fg) begin
                acc_area <= acc_area + 1'b1;
                acc_sy   <= acc_sy + {17'b0, sy_r};
                acc_sx   <= acc_sx + {16'b0, sx_r};
                acc_sx2  <= acc_sx2 + {14'b0, sx2_now};
                acc_sy2  <= acc_sy2 + {14'b0, sy2_now};
            end

            // 帧末尾：锁存统计量 + 清零（框不在这里更新，见下面 scn_latch）
            if (frame_done) begin
                O_area   <= acc_area;
                O_sy     <= acc_sy;
                O_sx     <= acc_sx;
                O_sx2    <= acc_sx2;
                O_sy2    <= acc_sy2;

                acc_area <= 17'd0;
                acc_sy   <= 25'd0;
                acc_sx   <= 25'd0;
                acc_sx2  <= 30'd0;
                acc_sy2  <= 30'd0;
            end

            //-----------------------------------------------------------------
            // 扫描完成：更新包围框
            //
            //   找到前景   -> 直接用扫描出来的紧贴框（不滞后，人一动框就跟着动）
            //   没找到前景 -> 先按住 MISS_HOLD 帧（避免偶发 area=0 把框抖小），
            //                 超过之后每帧向内收 2 格，收成「空框」
            //                 （x0 > x1），OSD 的命中判断自然就不画了。
            //-----------------------------------------------------------------
            if (scn_latch) begin
                if (fr && fc) begin
                    O_x0 <= sx0n;
                    O_x1 <= sx1n;
                    O_y0 <= sy0n;
                    O_y1 <= sy1n;
                    miss_cnt <= 4'd0;
                end
                // ★ 2026-10-17：只有一个方向找到边界时，只更新那个方向。
                //
                //   症状（用户实测）：人贴到画面【下沿】时框消失，质心十字还在；
                //                     贴【上沿】却正常。
                //
                //   根因：行扫描要求「连续两行都合格」、列扫描要求「连续两列都合格」
                //         （2026-10-16 为了抗孤立噪声加的）。人贴底时可见前景可能
                //         只剩 1 行 —— 于是 fr=0 且 fc=0，框 12 帧后收缩成空框。
                //
                //   ⚠ 这不是"上/下代码不对称"：贴顶且只剩 1 行同样会失败。
                //     只是人站在画面上方时身体在下方、可见行数够多，实际很少触发；
                //     而人贴底时被下边缘裁切，很容易只剩极少的行。
                //
                //   处理：一个方向成立就更新那个方向，另一个方向保持旧值。
                //         人贴底时纵向仍能跟上，横向不会乱跳。
                else if (fr || fc) begin
                    if (fc) begin
                        O_x0 <= sx0n;
                        O_x1 <= sx1n;
                    end
                    if (fr) begin
                        O_y0 <= sy0n;
                        O_y1 <= sy1n;
                    end
                    miss_cnt <= 4'd0;
                end
                // ★ 两个方向都没找到边界，但画面里确实有人（area 够大）
                //   -> 保持上一次的有效框，【不要】收缩。
                //      否则人贴边时框会凭空消失，而质心十字（走 area/Σy 通路）
                //      还在 —— 现象就是"有十字、没框"。
                //
                //   门槛取 16（与顶层的 Y0_AREA_MIN 一致）：
                //     · 人贴底只剩 1 行时 area 通常几十，能过门槛 -> 框保住
                //     · 人真的离开后只剩零星噪声（area < 16）-> 仍然正常收缩消失
                //   若取 |O_area（任何非零），纯噪声就能把框永久钉住，不可接受。
                else if (O_area >= 17'd16) begin
                    miss_cnt <= 4'd0;
                end
                else begin
                    if (miss_cnt != MISS_HOLD) miss_cnt <= miss_cnt + 1'b1;
                    else begin
                        // x 轴：还收得动就收 2 格，收不动了直接置空框
                        if (O_x0 + 9'd2 <= O_x1) begin
                            O_x0 <= O_x0 + 9'd2;
                            O_x1 <= O_x1 - 9'd2;
                        end
                        else begin
                            O_x0 <= 9'h1FF;
                            O_x1 <= 9'd0;
                        end
                        // y 轴
                        if (O_y0 + 8'd2 <= O_y1) begin
                            O_y0 <= O_y0 + 8'd2;
                            O_y1 <= O_y1 - 8'd2;
                        end
                        else begin
                            O_y0 <= 8'hFF;
                            O_y1 <= 8'd0;
                        end
                    end
                end
            end

            // 再等一拍才报 valid，保证 motion_report / OSD 取到的是刚更新的框
            if (scn_valid) begin
                O_valid <= frame_ok;
            end
        end
    end

endmodule
