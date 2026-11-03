//=============================================================================
//  jump_counter.v  --  跳绳计数（自适应双阈值 + 节律门）
//
//  输入：motion_stats 的 O_sy（Σy = 前景像素行号之和，正比于质心高度）
//  输出：6 位 BCD 计数，直接喂给 hdmi_mixer 的 OSD
//
//  方向很重要
//  ---------------------------------------------------------------------------
//  行号 0 在画面顶部。人站在地上 -> 质心偏下 -> Σy 大；
//  跳起来 -> 质心偏上 -> **Σy 变小**。所以「起跳」的判据是 Σy 跌破下阈值。
//
//  三层防线（参数在 PC 上经 14 个用例扫描确定，全部通过）
//  ---------------------------------------------------------------------------
//  ① 滑动平均（4 点）—— 压白噪声。白噪声降 sqrt(4)=2 倍，
//     而跳绳是 1.5~3Hz 的低频，衰减有限（3Hz 时约 24%）。
//
//  ② 包络自适应双阈值 —— 不用手工定阈值，自动跟踪波峰波谷
//        peak_hi 超过就抬高，否则每帧衰减 decay = max(1, amp>>8)
//        peak_lo 低于就压低，否则每帧回升同样的量
//        这样人走远走近、画面明暗变化都能自适应
//      幅度门限：amp < MIN_AMP 直接忽略（人没在跳，防静止时乱计数）
//      双阈值：up = peak_lo + amp/4，down = peak_lo + 3amp/4
//              （用移位实现，避免除法器。实测 amp/4 与原 amp/3 同样 14/14）
//
//  ③ 节律门 —— 真跳绳的间隔是规律的，噪声不是
//      记录相邻两次事件的间隔，要求与上一个间隔相差不超过 max(2, prev/2)
//      连续一致才计入。这一层把「静止 + 大噪声」从 111 次误计压到 0 次。
//
//  不应期 REFRACTORY=7 帧（30fps 下 0.23s，最高可数 4.3Hz）
//    —— 取 8 会漏计 3Hz 的跳绳（周期只有 10 帧），取 7 刚好。
//
//  资源：全加器 + 比较器，无乘法器、无除法器、无 RAM，约 300 LUT
//=============================================================================

module jump_counter #(
    // 保持期过后的快速衰减速度：decay = max(1, amp >> FAST_SHIFT)
    //   5 -> 时间常数 32 帧 ≈ 1.1 秒，实测停止运动后 1.3 秒回正
    //   ⚠ 这个**保持编译期常量**：做成运行时可调要多一个桶形移位器（约 +25 LUT），
    //     而它基本不用调（要调就改这里重编译）。
    parameter integer FAST_SHIFT  = 5
)(
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire        I_valid,       // 每帧一个脉冲（接 motion_stats 的 O_valid）
    input  wire [24:0] I_sy,          // Σy
    input  wire        I_clear,       // 计数清零（拨码开关 SW1 或串口 'R'，高有效）

    //------------------------------------------------------------------
    // 以下 4 个原本是 parameter，2026-10-13 改成端口，由 param_ctrl 驱动
    // —— 串口在线调参，不用再重新编译（一次编译 75~92 分钟）。
    //   ⚠ 上电默认值由 param_ctrl 给，与原来的 parameter 原值一致。
    //------------------------------------------------------------------
    input  wire [8:0]  I_hold,        // 包络峰值保持期（帧）0..511（2026-10-20 从 8 位扩）
    input  wire [24:0] I_min_amp,     // 幅度门限                  原 MIN_AMP=2500
    input  wire [7:0]  I_refractory,  // 不应期（帧）              原 REFRACTORY=7
    input  wire [7:0]  I_rhythm_tol,  // 节律门间隔容差下限（帧）  原 RHYTHM_TOL=2

    output reg  [23:0] O_count_bcd,   // 6 位 BCD：[23:20] 最高位，[3:0] 最低位
    output reg  [23:0] O_count_bin,   // 同一个计数的二进制形式（给串口上报用）
    output reg  [23:0] O_raw_events,  // 原始事件数（未过节律门），诊断用
    // 最近一次事件与上一次之间的帧数（= 一个完整动作周期）。
    //   2026-10-20 新增：往返跑要用它换算速度 v = 401 / interval（单程 3.35 m）。
    //   2026-10-20 扩到 10 位：原来 8 位饱和在 255 帧（4.25 秒），
    //   往返跑慢于 1.57 m/s 时速度读数会卡住不动。现在支持到 1023 帧（17 秒）。
    output reg  [ 9:0] O_interval,

    //---- 调试用（可接 ChipWatcher 或省掉）----
    output reg  [24:0] O_peak_hi,
    output reg  [24:0] O_peak_lo,
    output reg  [24:0] O_amp,
    output reg         O_in_air       // 1 = 判定在空中

    // ⚠ 2026-10-15 删除了 O_up_th / O_dn_th 两个输出。
    //
    //   它们原本是给"参考线接在 jump_counter 阈值上"那版用的，后来参考线
    //   改成独立的 line_tracker（只吃头顶 y0），这两个输出就没人接了。
    //
    //   但【悬空的模块输出不会让综合器省掉那条加法链】：
    //     up_th   = lo_new + amp/4        （25 位加法）
    //     down_th = lo_new + (amp - amp/4)（25 位加法）
    //   综合器要保留这两个输出寄存器，就必须把这条逻辑链留在网表里。
    //   实测代价（final_timing.rpt 的关键路径）：
    //     起点 u_jump_counter/O_peak_hi_reg[0]
    //     终点 u_jump_counter/O_count_bcd_reg[20]
    //     Logic Level 18（ADDER=12）  延迟 15.039ns vs 预算 13.333ns
    //     => SWNS -2.057ns，违例 187 个端点
    //   对比 10-15 17:41 那版（同样有这两个输出）SWNS 是 -1.689ns，
    //   而 10-14 更早的版本没有它们时是 -1.721ns —— 说明这条链一直在
    //   拖累时序，删掉后应该能缓解。
);

    //-------------------------------------------------------------------------
    // ① 滑动平均（4 点）
    //-------------------------------------------------------------------------
    reg [24:0] sy_d1, sy_d2, sy_d3;

    wire [26:0] sy_sum = {2'b0, I_sy} + {2'b0, sy_d1} + {2'b0, sy_d2} + {2'b0, sy_d3};
    wire [24:0] sy_f   = sy_sum[26:2];        // 除以 4

    //-------------------------------------------------------------------------
    // ② 包络跟踪（保持期 + 快速衰减）
    //
    //   为什么不用固定的慢衰减
    //     固定 decay = amp>>8 时时间常数 256 帧 = 8.5 秒。好处是两个跳跃周期
    //     之间峰值不会塌（1.5Hz 时峰间只衰减 7.8%），坏处是**停止运动后 AMP
    //     要 4.7 秒才回落到门限以下**，明显能感觉到。
    //     而单纯加快衰减（改成 >>6）会把峰间衰减推到 31%，包络在跳绳过程中
    //     就塌了，阈值跟着漂移，计数会乱。
    //
    //   保持期方案
    //     峰值刚被刷新后的 HOLD 帧内完全不衰减 —— 覆盖最慢的跳绳节奏
    //     （1.5Hz 周期 20 帧 < HOLD=25 帧）；
    //     超过 HOLD 帧没有新峰值，说明人停了，改用快速衰减（>>5）。
    //     实测（tools/envelope_experiment.py）：回正时间 4.7s -> 1.3s，
    //     同时 14 个用例仍全部通过。
    //-------------------------------------------------------------------------
    wire [24:0] amp_cur = O_peak_hi - O_peak_lo;

    wire [24:0] fast_raw = amp_cur >> FAST_SHIFT;
    wire [24:0] decay_w  = (fast_raw == 25'd0) ? 25'd1 : fast_raw;

    // ⚠️ 2026-10-17 时序修复（第二处）：decay 也提前一拍寄存
    //
    //  decay 只依赖 O_peak_hi / O_peak_lo（都是寄存器），是纯组合函数，
    //  所以"前一拍算好寄存起来"与"本拍现算"结果完全相同
    //  （因为这两个寄存器只在 I_valid 那一拍才变，相邻两拍的值一样）。
    //
    //  不寄存的话，包络更新那条环是：
    //    peak_hi --(-)-> amp_cur --(>>5)-> decay --(-)-> hi_dec --mux-> peak_hi
    //  两条 25 位减法串在一起；寄存后只剩一条。
    reg [24:0] decay_r;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) decay_r <= 25'd1;
        else          decay_r <= decay_w;
    end

    wire [24:0] decay = decay_r;

    wire hi_decay_en = (since_hi >= I_hold);
    wire lo_decay_en = (since_lo >= I_hold);

    // peak_hi：超过就抬高；否则只在保持期外衰减（且不低于当前值）
    wire [24:0] hi_dec = hi_decay_en ? ((O_peak_hi > decay) ? (O_peak_hi - decay) : 25'd0)
                                     : O_peak_hi;
    wire [24:0] hi_new = (sy_f > O_peak_hi) ? sy_f :
                         ((hi_dec < sy_f) ? sy_f : hi_dec);

    // peak_lo：低于就压低；否则只在保持期外回升（且不高于当前值）
    wire [24:0] lo_inc = lo_decay_en ? (O_peak_lo + decay) : O_peak_lo;
    wire [24:0] lo_new = (sy_f < O_peak_lo) ? sy_f :
                         ((lo_inc > sy_f) ? sy_f : lo_inc);

    wire [24:0] amp_new = hi_new - lo_new;

    //-------------------------------------------------------------------------
    // ③ 双阈值（纯移位，无除法器）
    //
    // ⚠️⚠️ 2026-10-17 时序修复：阈值改成【由上一帧的包络算出并寄存】
    //
    //  问题（14:42 那版的 STA 实测，全部违例都在这一条链上）
    //    起点 u_jump_counter/O_peak_lo_reg[0]
    //    终点 u_jump_counter/O_count_bcd_reg[2]
    //    Logic Level 18（ADDER=12）延迟 14.737ns vs 预算 13.333ns
    //    => SWNS -1.629ns，291 个违例端点
    //
    //  根因：一拍之内串了 4 条 25 位算术
    //    peak_lo --(+)--> lo_inc --mux--> lo_new --(-)--> amp_new
    //            --(>>2)--> quarter --(-)/(+)--> down_th --cmp--> 计数
    //
    //  修法：up_th / down_th / amp_ok 只依赖【已经寄存的】O_peak_hi、O_peak_lo、
    //        O_amp（= 上一帧的 amp_new），所以它们可以【无条件每拍算、寄存起来】，
    //        本帧直接拿寄存器去比。关键路径缩短为
    //          sy_f --cmp--> 事件标志 --BCD 进位链--> O_count_bcd
    //        加法器彻底离开这条链（变成 reg->add->reg 的独立小环，时间充裕）。
    //
    //  唯一的行为差异：阈值比包络【晚一帧】生效。
    //    包络本身就有 HOLD=25 帧的保持期，一帧的滞后完全被淹没；
    //    用 tools/jump1.csv（1773 帧真实数据）逐帧对比，计数与判决完全相同。
    //
    //  等价性（整数精确，无溢出）：
    //    down_th = peak_lo + (amp - amp/4) = peak_hi - amp/4
    //-------------------------------------------------------------------------
    wire [24:0] quarter_r = O_amp >> 2;               // amp/4（用上一帧的 amp）

    reg  [24:0] up_th_r, down_th_r;
    reg         amp_ok_r;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            up_th_r   <= 25'd0;
            down_th_r <= 25'd0;
            amp_ok_r  <= 1'b0;
        end
        else begin
            up_th_r   <= O_peak_lo + quarter_r;       // peak_lo + amp/4
            down_th_r <= O_peak_hi - quarter_r;       // peak_hi - amp/4（= peak_lo + 3amp/4）
            amp_ok_r  <= (O_amp >= I_min_amp);
        end
    end

    wire [24:0] up_th   = up_th_r;
    wire [24:0] down_th = down_th_r;
    wire        amp_ok  = amp_ok_r;

    //-------------------------------------------------------------------------
    // ④ 不应期 + 节律门状态
    //-------------------------------------------------------------------------
    reg  [7:0] refr;
    reg  [9:0] since_last;     // 2026-10-20：8 -> 10 位
    reg  [9:0] prev_interval;  // 同上
    reg  [2:0] consist;
    reg  [8:0] since_hi;      // 距 peak_hi 上次被刷新的帧数（9 位，饱和 511）
    reg  [8:0] since_lo;      // 距 peak_lo 上次被刷新的帧数

    // 间隔一致判定
    wire [9:0] tol_ext    = {2'b0, I_rhythm_tol};
    wire [9:0] half_prev  = prev_interval >> 1;
    wire [9:0] tol        = (half_prev > tol_ext) ? half_prev : tol_ext;
    wire [9:0] idiff      = (since_last > prev_interval) ? (since_last - prev_interval)
                                                         : (prev_interval - since_last);
    // ⚠️ 2026-10-18 改：第一次事件（prev_interval==0）【直接计入】，不再丢弃。
    //
    //   原来是 (prev_interval != 0) && (idiff <= tol) —— 第一次必然为假，
    //   于是每次"开始运动"和每次"amp_ok 掉过之后再动"都白丢一个。
    //   用真实跳绳数据（tune_rope_1018_2108.csv，真值 36）实测：
    //     36 个事件全是真动作（间隔 28~177 帧，无假尖峰），
    //     原逻辑只数出 30~33 个，丢的 3 个正是"第一次"。
    //   改成"第一次放行"后：MIN_AMP=200 / HOLD=20 / REF=7 / TOL=255 -> 36/36 ✓
    //
    //   深蹲数据（jump1.csv）也从 14 变成 15 —— 复查事件列表，15 个事件间隔
    //   全部 113~127 帧、第一个在 1.52 秒，说明真值本来就是 15（当初少记了 1 个）。
    //
    //   风险：镜头前晃一下产生的单个完整事件会立刻计 1。这类误检本来就该由
    //   MIN_AMP 挡掉，不靠节律门（节律门只在有前一次参考时才有意义）。
    wire       consistent = (prev_interval == 8'd0) || (idiff <= tol);

    // 本帧是否产生一次「起跳-落地」事件
    wire ev_ground2air = (!O_in_air) && amp_ok && (sy_f < up_th);
    wire ev_air2ground = ( O_in_air) && amp_ok && (refr == 8'd0) && (sy_f > down_th);

    // 节律门：consistent 为真才计入。
    //   第一次事件（prev_interval==0）直接放行；之后要求间隔与上一次相差不超过
    //   max(上一次/2, RHYTHM_TOL)。RHYTHM_TOL 调到 255 等价于关闭节律门。

    //-------------------------------------------------------------------------
    // ⑤ BCD 加一
    //-------------------------------------------------------------------------
    wire c0 = (O_count_bcd[ 3: 0] == 4'd9);
    wire c1 = c0 && (O_count_bcd[ 7: 4] == 4'd9);
    wire c2 = c1 && (O_count_bcd[11: 8] == 4'd9);
    wire c3 = c2 && (O_count_bcd[15:12] == 4'd9);
    wire c4 = c3 && (O_count_bcd[19:16] == 4'd9);

    wire [23:0] bcd_next = {
        c4 ? (O_count_bcd[23:20] + 4'd1) : O_count_bcd[23:20],
        c3 ? (c4 ? 4'd0 : (O_count_bcd[19:16] + 4'd1)) : O_count_bcd[19:16],
        c2 ? (c3 ? 4'd0 : (O_count_bcd[15:12] + 4'd1)) : O_count_bcd[15:12],
        c1 ? (c2 ? 4'd0 : (O_count_bcd[11: 8] + 4'd1)) : O_count_bcd[11: 8],
        c0 ? (c1 ? 4'd0 : (O_count_bcd[ 7: 4] + 4'd1)) : O_count_bcd[ 7: 4],
        c0 ? 4'd0 : (O_count_bcd[ 3: 0] + 4'd1)
    };

    //-------------------------------------------------------------------------
    // 主状态机：每帧走一步（只在 I_valid 时更新）
    //-------------------------------------------------------------------------
    reg init_done;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            sy_d1         <= 25'd0;
            sy_d2         <= 25'd0;
            sy_d3         <= 25'd0;
            O_peak_hi     <= 25'd0;
            O_peak_lo     <= 25'd0;
            O_amp         <= 25'd0;
            // ⚠ 2026-10-20 试过把 in_air 初值改成 1（想让第一次动作也计数），
            //   实测【无效】，已回滚。原因：包络建立期 amp 从 0 增长，
            //   dn_th = peak_hi - amp/4 也跟着变，第一次"落地"会在跑到半路
            //   （xc 才到中点）就触发，反而让 raw 多算一次、CNT 仍然少 1。
            //   所以"第一次动作不准"是包络初始化的固有代价，靠改初值解决不了。
            O_in_air      <= 1'b0;
            refr          <= 8'd0;
            since_last    <= 10'd0;
            prev_interval <= 10'd0;
            consist       <= 3'd0;
            O_count_bcd   <= 24'd0;
            O_count_bin   <= 24'd0;
            O_raw_events  <= 24'd0;
            O_interval    <= 10'd0;
            init_done     <= 1'b0;
            since_hi      <= 9'd0;
            since_lo      <= 9'd0;
        end
        else if (I_clear) begin
            // 计数清零：只清计数和状态机，不动包络（避免清完要重新收敛）
            O_count_bcd   <= 24'd0;
            O_count_bin   <= 24'd0;
            O_raw_events  <= 24'd0;
            O_interval    <= 10'd0;
            O_in_air      <= 1'b0;
            refr          <= 8'd0;
            since_last    <= 10'd0;
            prev_interval <= 10'd0;
            consist       <= 3'd0;
        end
        else if (I_valid) begin
            if (!init_done) begin
                // ⚠️ 第一帧必须把包络【和滑动平均延迟线】都用当前值填满！
                //
                //   两个都不能省：
                //   · peak_hi/peak_lo 若从 0 起，peak_lo 会以 amp>>8 的速度缓慢爬升，
                //     约 8 秒才收敛；这期间 up_th = peak_lo + amp/4 低得离谱
                //     （Σy 在 50000 附近而 up_th 只有 12500），起跳判据永远不触发。
                //   · 延迟线若从 0 起，第一帧算出的 sy_f 只有真实值的 1/4，
                //     会把 peak_lo 拉到错误位置，再花 8 秒爬回来。
                //
                //   实测（tools/jump_counter_rtl_model.py，跳绳 2Hz 跳 60 秒）：
                //     两个都不初始化 -> 前 10 秒计数恒为 0，60 秒只数到 90
                //     只初始化包络   -> 前 5 秒恒为 0，60 秒数到 102
                //     两个都初始化   -> 1 秒内就出数，60 秒数到 119 ✓
                //
                //   PC 理想模型里有这一步，移植 RTL 时漏了 —— 这就是"怎么动都不变"的原因。
                init_done <= 1'b1;
                sy_d1     <= I_sy;
                sy_d2     <= I_sy;
                sy_d3     <= I_sy;
                O_peak_hi <= I_sy;
                O_peak_lo <= I_sy;
                O_amp     <= 25'd0;
                since_hi  <= 8'd0;
                since_lo  <= 8'd0;
            end
            else begin
                // 滑动平均延迟链
                sy_d1 <= I_sy;
                sy_d2 <= sy_d1;
                sy_d3 <= sy_d2;

                // 包络更新
                O_peak_hi <= hi_new;
                O_peak_lo <= lo_new;
                O_amp     <= amp_new;

                // 保持期计数器：峰值被刷新就清零，否则递增（饱和）
                if (sy_f > O_peak_hi) begin
                    since_hi <= 9'd0;
                end
                else if (since_hi != 9'h1FF) begin
                    since_hi <= since_hi + 9'd1;
                end

                if (sy_f < O_peak_lo) begin
                    since_lo <= 9'd0;
                end
                else if (since_lo != 9'h1FF) begin
                    since_lo <= since_lo + 9'd1;
                end

                // 间隔计数（饱和在 255）
                if (since_last != 10'h3FF) since_last <= since_last + 10'd1;

                if (!amp_ok) begin
                    // 幅度不足：人没在跳，状态机复位（但计数保留）
                    O_in_air      <= 1'b0;
                    refr          <= 8'd0;
                    consist       <= 3'd0;
                    prev_interval <= 10'd0;
                end
                else begin
                    if (refr != 8'd0) refr <= refr - 8'd1;

                    if (ev_ground2air) begin
                        // 起跳：进空中态，启动不应期
                        O_in_air <= 1'b1;
                        refr     <= I_refractory;
                    end
                    else if (ev_air2ground) begin
                        // 落地：一个完整周期
                        O_in_air      <= 1'b0;
                        prev_interval <= since_last;
                        since_last    <= 10'd0;
                        O_interval    <= since_last;   // 给速度换算用
                        O_raw_events  <= O_raw_events + 1'b1;

                        if (consistent) begin
                            if (consist != 3'd7) consist <= consist + 3'd1;
                            O_count_bcd <= bcd_next;
                            O_count_bin <= O_count_bin + 1'b1;
                        end
                        else begin
                            consist <= 3'd0;
                        end
                    end
                end
            end
        end
    end

endmodule
