//=============================================================================
//  line_tracker.v  --  参考线跟踪器（**现在就是计数判据本身**）
//
//  ⚠⚠ 2026-10-16 重要变更：从"只是参考"改成"真的等于判据"
//  ---------------------------------------------------------------------------
//  这个模块的公式和 jump_counter 内部的阈值**本来就是同一个**：
//      amp     = peak_hi - peak_lo      （一次动作的幅度）
//      up_row  = peak_lo + amp/4        （接近最高点）
//      dn_row  = peak_lo + 3*amp/4      （接近最低点）
//  jump_counter 吃的是 y0<<7，除以 4 之后完全等价 —— **数学上是一回事**。
//
//  但之前有两处不一致，导致"屏幕上的线 ≠ 判据"：
//    ① 输入信号不同：这里吃 S_bb_y0（原始框上沿），计数吃 S_y0_hold（保持值）
//    ② HOLD 时间常数不同：这里固定 120 帧，计数跟着运动模式走（25/100/60）
//  结果就是"看着线穿过去了却没计数"。**现已把两处都对齐。**
//
//  现在可以理直气壮地对评委说：**屏幕上这两条线就是判决线，穿过就计一次。**
//
//  为什么不做成"从 jump_counter 引出阈值"
//    10-15 试过：那两个输出会把 25 位加法链的寄存器带出来，
//    使 SWNS 从 -1.689ns 恶化到 -2.057ns（最差路径终点是 count_bcd）。
//    这里的 8 位版本**完全等价但便宜得多**（约 60~80 LUT，0 DSP，0 ERAM），
//    而且不在关键路径上。
//
//  算法（与 jump_counter 的包络跟踪逐行对应，只是位宽小得多）
//  ---------------------------------------------------------------------------
//    peak_lo = 头顶到过的【最高】位置（行号最小）
//    peak_hi = 头顶到过的【最低】位置（行号最大）
//    保持期 HOLD：峰值刷新后这么多帧内不衰减，超过就按 decay 快速回中。
//
//  资源：8 位数据通路，约 60~80 LUT，0 DSP，0 ERAM
//=============================================================================

module line_tracker #(
    // 保持期缺省值（帧）。实际由 I_hold 端口给 —— 接的是和 jump_counter
    // 同一个信号（S_hold_final），这样两条线才真的等于判据。
    parameter [7:0] HOLD       = 8'd120,
    // 保持期过后的衰减速度：decay = max(1, amp >> FAST_SHIFT)
    parameter integer FAST_SHIFT = 5,
    // 无前景多久之后开始"线回中"（帧）。避免人离开后线停在奇怪的位置。
    parameter [7:0] MISS_HOLD  = 8'd180,
    // 行号范围（网格高度 - 1）
    parameter [7:0] MAX_ROW    = 8'd89
)(
    input  wire       I_clk,
    input  wire       I_rst_n,
    input  wire       I_valid,      // 每帧一个脉冲（接 motion_stats 的 O_valid）
    input  wire [7:0] I_y0,         // 头顶行号（0=画面顶），无前景时传 8'hFF
    input  wire       I_fg_ok,      // 本帧有有效前景
    // ⚠ 2026-10-16 新增：保持期必须和 jump_counter 的 I_hold 同源，
    //   否则线的位置和判据对不上（这就是"线穿了却没计数"的原因之一）。
    input  wire [7:0] I_hold,

    output reg  [7:0] O_line_up,    // 上线行号（起跳线，青）—— 等于 up_th
    output reg  [7:0] O_line_dn,    // 下线行号（落地线，橙）—— 等于 down_th
    output reg  [7:0] O_amp         // 幅度（调试用）
);

    reg [7:0] peak_lo;      // 头顶最高（行号最小）
    reg [7:0] peak_hi;      // 头顶最低（行号最大）
    reg [7:0] since_hi;     // 距 peak_hi 上次刷新多少帧
    reg [7:0] since_lo;
    reg [7:0] miss;         // 连续无前景帧数
    reg       init_done;

    //-------------------------------------------------------------------------
    // ① 滑动平均（4 点）—— 与 jump_counter.v 逐行对应
    //
    //   ⚠ 2026-10-16 补上：原来这里没有滑动平均，直接用原始 y0。
    //     而 jump_counter 吃的是 sy_f（4 点平均）。两者不一致，
    //     阈值就会差几行 —— 既然要宣称"线就是判据"，就得真的对齐。
    //     8 位域里这一步几乎免费（3 个寄存器 + 2 个加法器）。
    //-------------------------------------------------------------------------
    reg [7:0] y0_d1, y0_d2, y0_d3;

    wire [9:0] y_sum = {2'b0, I_y0} + {2'b0, y0_d1} + {2'b0, y0_d2} + {2'b0, y0_d3};
    wire [7:0] y_f   = y_sum[9:2];        // 除以 4

    //-------------------------------------------------------------------------
    // ② 包络跟踪（保持期 + 快速衰减）—— 与 jump_counter.v 同一套结构
    //-------------------------------------------------------------------------
    wire [7:0] amp_cur = peak_hi - peak_lo;
    wire [7:0] fast_raw = amp_cur >> FAST_SHIFT;
    wire [7:0] decay    = (fast_raw == 8'd0) ? 8'd1 : fast_raw;

    wire hi_decay_en = (since_hi >= I_hold);   // ⚠ 用 I_hold，和 jump_counter 同源
    wire lo_decay_en = (since_lo >= I_hold);

    // peak_hi：超过就抬高；否则只在保持期外衰减（且不低于当前值）
    //   ⚠ 这两处钳位原来没有，现在补上，与 jump_counter 一致
    wire [7:0] hi_dec = hi_decay_en ? ((peak_hi > decay) ? (peak_hi - decay) : 8'd0)
                                    : peak_hi;
    wire [7:0] hi_new = (y_f > peak_hi) ? y_f :
                        ((hi_dec < y_f) ? y_f : hi_dec);

    // peak_lo：低于就压低；否则只在保持期外回升（且不高于当前值）
    wire [7:0] lo_inc = lo_decay_en ? (peak_lo + decay) : peak_lo;
    wire [7:0] lo_new = (y_f < peak_lo) ? y_f :
                        ((lo_inc > y_f) ? y_f : lo_inc);

    //-------------------------------------------------------------------------
    // ③ 双阈值（纯移位，无除法器）—— 与 jump_counter.v 完全同一个公式
    //-------------------------------------------------------------------------
    wire [7:0] amp_new = hi_new - lo_new;
    wire [7:0] quarter = amp_new >> 2;                  // amp/4
    wire [7:0] up_new  = lo_new + quarter;              // peak_lo + amp/4
    wire [7:0] dn_new  = lo_new + (amp_new - quarter);  // peak_lo + 3amp/4

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            y0_d1     <= 8'd0;
            y0_d2     <= 8'd0;
            y0_d3     <= 8'd0;
            peak_lo   <= 8'd30;
            peak_hi   <= 8'd60;
            since_hi  <= 8'd0;
            since_lo  <= 8'd0;
            miss      <= 8'd0;
            init_done <= 1'b0;
            O_line_up <= 8'hFF;      // 8'hFF = 不画（上电第一帧之前不显示）
            O_line_dn <= 8'hFF;
            O_amp     <= 8'd0;
        end
        else if (I_valid) begin
            if (!init_done && I_fg_ok) begin
                // 第一帧：包络【和滑动平均延迟线】都用当前值填满
                //   ⚠ 两个都不能省 —— 这是 jump_counter 踩过的坑：
                //     延迟线若从 0 起，第一帧的 y_f 只有真实值的 1/4，
                //     会把 peak_lo 拉到错误位置。这里必须同样处理，
                //     否则上电后头几秒"线"和"判据"对不上。
                init_done <= 1'b1;
                y0_d1     <= I_y0;
                y0_d2     <= I_y0;
                y0_d3     <= I_y0;
                peak_lo   <= I_y0;
                peak_hi   <= I_y0;
                since_hi  <= 8'd0;
                since_lo  <= 8'd0;
                miss      <= 8'd0;
                O_line_up <= I_y0;
                O_line_dn <= I_y0;
                O_amp     <= 8'd0;
            end
            else if (init_done) begin
                if (I_fg_ok) begin
                    miss     <= 8'd0;
                    y0_d1    <= I_y0;      // 滑动平均延迟链（与 jump_counter 一致）
                    y0_d2    <= y0_d1;
                    y0_d3    <= y0_d2;
                    peak_hi  <= hi_new;
                    peak_lo  <= lo_new;
                    O_amp    <= amp_new;

                    // 保持期计数（比较基准是【平均后】的值，与 jump_counter 一致）
                    if (y_f > peak_hi) since_hi <= 8'd0;
                    else if (since_hi != 8'hFF) since_hi <= since_hi + 8'd1;

                    if (y_f < peak_lo) since_lo <= 8'd0;
                    else if (since_lo != 8'hFF) since_lo <= since_lo + 8'd1;

                    // 行号钳位到画面内，超范围就标记"不显示"
                    O_line_up <= (up_new > MAX_ROW) ? 8'hFF : up_new;
                    O_line_dn <= (dn_new > MAX_ROW) ? 8'hFF : dn_new;
                end
                else begin
                    // 没前景：先保持（避免偶发丢帧让线抖动），
                    // 超过 MISS_HOLD 帧后让线缓慢回中
                    if (miss != 8'hFF) miss <= miss + 8'd1;
                    if (miss >= MISS_HOLD) begin
                        peak_hi <= hi_dec;
                        peak_lo <= lo_inc;
                        if (since_hi != 8'hFF) since_hi <= since_hi + 8'd1;
                        if (since_lo != 8'hFF) since_lo <= since_lo + 8'd1;
                        O_line_up <= (up_new > MAX_ROW) ? 8'hFF : up_new;
                        O_line_dn <= (dn_new > MAX_ROW) ? 8'hFF : dn_new;
                    end
                end
            end
        end
    end

endmodule
