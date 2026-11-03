//=============================================================================
//  motion_report.v  --  运动统计量的「上报 + 显示」适配层
//
//  做两件事
//  ---------------------------------------------------------------------------
//  1) 上报：每帧把 motion_stats 的统计量格式化成一行 ASCII，经 UART 发到 PC。
//     用来采集训练时序 MLP 的数据。
//
//     行格式（5 个字段，每个 8 位十六进制，逗号分隔，\n 结尾，共 45 字节）：
//         ssssssss,aaaaaaaa,xxxxxxxx,0000000y,0000001z
//          sy        area      sx        y0        y1
//     PC 端解析：line.split(',') 然后 int(x, 16)
//     30fps 下约 1350 字节/秒，115200 波特率（约 11500 字节/秒）绰绰有余。
//
//  2) 显示：把 3 个诊断量转成 6 位 BCD，给 OSD 的多行文字区用。
//     （跳绳计数 CNT 的 BCD 由 jump_counter 直接给出，这里不用再转）
//
//         O_bcd_amp  <- I_val_amp   Σy 峰峰值
//         O_bcd_pix  <- I_area      前景像素数
//         O_bcd_raw  <- I_val_raw   原始事件数（未过节律门）
//
//  二进制转 BCD：double-dabble（移位加 3）
//  ---------------------------------------------------------------------------
//  每次左移前，把每个 BCD 位里 >=5 的加 3。17 位输入需要 17 次迭代，
//  串行做只要 17 拍，每帧一次，开销可忽略。比串行除法器简单，也不需要乘法器。
//  3 个转换器用 generate 并行展开（约 450 LUT）—— 比复用一个 FSM 更不容易出错。
//
//  UART 发送的握手时序（重要）
//  ---------------------------------------------------------------------------
//  uart_tx 的 O_tx_busy 要滞后一拍才拉高，所以不能在「!busy 就发下一个字节」
//  的循环里直接推进 —— 那样同一个字节会被触发两次。这里用 4 个状态严格握手：
//     ST_SEND  等空闲 -> 给数据 + 脉冲 start -> 立刻走
//     ST_BUSY  等 busy 拉高（确认 uart 已开始）
//     ST_WAIT  等 busy 落回（本字节发完）-> 推进计数器 -> 回 ST_SEND
//=============================================================================

module motion_report (
    input  wire        I_clk,
    input  wire        I_rst_n,

    //---- 来自 motion_stats ----
    input  wire        I_valid,       // 每帧一个脉冲
    input  wire [16:0] I_area,        // 前景像素数（160x90 域，最大 14400）
    input  wire [24:0] I_sy,          // Σy
    input  wire [24:0] I_sx,          // Σx
    input  wire [29:0] I_sx2,         // Σx²（二阶矩）
    input  wire [29:0] I_sy2,         // Σy²（二阶矩）
    input  wire [ 7:0] I_y0,          // 包围框上沿
    input  wire [ 7:0] I_y1,          // 包围框下沿
    input  wire [ 8:0] I_x0,          // 包围框左（2026-10-20 新增，给往返跑算框中心）
    input  wire [ 8:0] I_x1,          // 包围框右

    //---- 来自 jump_counter（用于 OSD 显示）----
    input  wire [24:0] I_val_amp,     // Σy 峰峰值
    input  wire [23:0] I_val_raw,     // 原始事件数

    //---- UART ----
    output wire        O_uart_tx,

    //---- 给 OSD 多行文字区的 BCD（[23:20] 最高位，[3:0] 最低位）----
    output wire [23:0] O_bcd_amp,
    output wire [23:0] O_bcd_pix,
    output wire [23:0] O_bcd_raw,
    // ★ 2026-10-30：坐标 BCD（云台模式 OSD 显示 POS X Y 用）
    output wire [23:0] O_bcd_cx,       // 质心列 0..159 → 3 位 BCD
    output wire [23:0] O_bcd_cy,       // 质心行 0..89  → 3 位 BCD

    //---- 给 OSD 画标记用的质心坐标（160x90 网格坐标）----
    output reg  [7:0]  O_cx,          // 质心列 0..159
    output reg  [6:0]  O_cy           // 质心行 0..89
);

    //=========================================================================
    // 1) 三个诊断量 -> 6 位 BCD（double-dabble）
    //=========================================================================
    // 每个 BCD 位 >=5 就加 3
    function [23:0] F_bcd_adj;
        input [23:0] b;
        begin
            F_bcd_adj[ 3: 0] = (b[ 3: 0] >= 4'd5) ? (b[ 3: 0] + 4'd3) : b[ 3: 0];
            F_bcd_adj[ 7: 4] = (b[ 7: 4] >= 4'd5) ? (b[ 7: 4] + 4'd3) : b[ 7: 4];
            F_bcd_adj[11: 8] = (b[11: 8] >= 4'd5) ? (b[11: 8] + 4'd3) : b[11: 8];
            F_bcd_adj[15:12] = (b[15:12] >= 4'd5) ? (b[15:12] + 4'd3) : b[15:12];
            F_bcd_adj[19:16] = (b[19:16] >= 4'd5) ? (b[19:16] + 4'd3) : b[19:16];
            F_bcd_adj[23:20] = (b[23:20] >= 4'd5) ? (b[23:20] + 4'd3) : b[23:20];
        end
    endfunction

    // 三个输入饱和到 17 位（转换器是 17 位输入，最大 131071）
    wire [16:0] v_amp = (|I_val_amp[24:17]) ? 17'd131071 : I_val_amp[16:0];
    wire [16:0] v_pix = I_area;                                 // 最大 14400，本来就够
    wire [16:0] v_raw = (|I_val_raw[23:17]) ? 17'd131071 : I_val_raw[16:0];

    reg [23:0] bcd_out [0:4];        // 0=amp 1=pix 2=raw 3=cx 4=cy

    assign O_bcd_amp = bcd_out[0];
    assign O_bcd_pix = bcd_out[1];
    assign O_bcd_raw = bcd_out[2];
    assign O_bcd_cx  = bcd_out[3];   // ★ 2026-10-30
    assign O_bcd_cy  = bcd_out[4];

    // ★ 2026-10-30：坐标 BCD 的启动信号
    //   cx/cy 的除法在 I_valid 后 7~8 拍才完成（it_y==6 / it_x==7），
    //   而 BCD 在 I_valid 那一拍就采样 → 会读到旧值。
    //   所以 cx/cy 的 BCD 延后 10 拍启动（留足除法时间）。
    reg [3:0] S_cx_dly;
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n)          S_cx_dly <= 4'd0;
        else if (I_valid)      S_cx_dly <= 4'd0;
        else if (S_cx_dly < 4'd12) S_cx_dly <= S_cx_dly + 4'd1;
    end
    wire W_cx_start = (S_cx_dly == 4'd10);    // I_valid 后第 10 拍

    genvar gi;
    generate
        for (gi = 0; gi < 5; gi = gi + 1) begin : g_bcd
            reg [16:0] dd_bin;
            reg [23:0] dd_bcd;
            reg [ 4:0] dd_iter;
            reg        dd_busy;

            // ★ 2026-10-30：加 cx(3) / cy(4) 两路，供云台模式 OSD 显示 POS X Y
            wire [16:0] v_in   = (gi == 0) ? v_amp :
                                 (gi == 1) ? v_pix :
                                 (gi == 2) ? v_raw :
                                 (gi == 3) ? { 9'd0, O_cx } :
                                             { 10'd0, O_cy };
            // amp/pix/raw 在 I_valid 拍启动；cx/cy 要等除法完成（延后 10 拍）
            wire        v_start = (gi < 3) ? I_valid : W_cx_start;
            wire [23:0] dd_adj = F_bcd_adj(dd_bcd);
            wire [23:0] dd_nxt = {dd_adj[22:0], dd_bin[16]};

            always @(posedge I_clk or negedge I_rst_n) begin
                if (!I_rst_n) begin
                    dd_bin      <= 17'd0;
                    dd_bcd      <= 24'd0;
                    dd_iter     <= 5'd0;
                    dd_busy     <= 1'b0;
                    bcd_out[gi] <= 24'd0;
                end
                else if (v_start) begin          // 每帧重新开始一次转换
                    dd_bin  <= v_in;
                    dd_bcd  <= 24'd0;
                    dd_iter <= 5'd0;
                    dd_busy <= 1'b1;
                end
                else if (dd_busy) begin
                    dd_bcd  <= dd_nxt;
                    dd_bin  <= {dd_bin[15:0], 1'b0};
                    dd_iter <= dd_iter + 1'b1;
                    if (dd_iter == 5'd16) begin  // 17 次迭代（0..16）做完
                        dd_busy     <= 1'b0;
                        bcd_out[gi] <= dd_nxt;
                    end
                end
            end
        end
    endgenerate

    //=========================================================================
    // 1b) 质心 = Σ / 面积（迭代式除法，每帧一次，各 7~8 拍）
    //
    //   只为在 OSD 上画标记用，**不参与计数判据**
    //   （计数判据用的是 Σy 的振荡，见 jump_counter.v）。
    //
    //   算法：从最高位开始逐位试减
    //     sh 从 area<<(N-1) 开始，每次右移 1 位
    //     若 rem >= sh 则减掉并置该位为 1
    //   N=7 给行质心（0..89），N=8 给列质心（0..159）。
    //   面积 = 0（画面里没前景）时直接输出 0，不发除法。
    //=========================================================================
    wire [24:0] area25 = {8'b0, I_area};

    reg [24:0] rem_y, sh_y;
    reg [ 6:0] q_y;
    reg [ 3:0] it_y;
    reg        busy_y;

    reg [24:0] rem_x, sh_x;
    reg [ 7:0] q_x;
    reg [ 3:0] it_x;
    reg        busy_x;

    //---- 行质心：Σy / area -> 7 位 ----
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            rem_y  <= 25'd0;
            sh_y   <= 25'd0;
            q_y    <= 7'd0;
            it_y   <= 4'd0;
            busy_y <= 1'b0;
            O_cy   <= 7'd0;
        end
        else if (I_valid) begin
            if (I_area == 17'd0) begin
                busy_y <= 1'b0;
                O_cy   <= 7'd0;
            end
            else begin
                rem_y  <= I_sy;
                sh_y   <= area25 << 6;      // area × 64
                q_y    <= 7'd0;
                it_y   <= 4'd0;
                busy_y <= 1'b1;
            end
        end
        else if (busy_y) begin
            if (rem_y >= sh_y) begin
                rem_y <= rem_y - sh_y;
                q_y   <= {q_y[5:0], 1'b1};
            end
            else begin
                q_y   <= {q_y[5:0], 1'b0};
            end
            sh_y <= sh_y >> 1;
            if (it_y == 4'd6) begin
                busy_y <= 1'b0;
                O_cy   <= (rem_y >= sh_y) ? {q_y[5:0], 1'b1} : {q_y[5:0], 1'b0};
            end
            else begin
                it_y <= it_y + 1'b1;
            end
        end
    end

    //---- 列质心：Σx / area -> 8 位 ----
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            rem_x  <= 25'd0;
            sh_x   <= 25'd0;
            q_x    <= 8'd0;
            it_x   <= 4'd0;
            busy_x <= 1'b0;
            O_cx   <= 8'd0;
        end
        else if (I_valid) begin
            if (I_area == 17'd0) begin
                busy_x <= 1'b0;
                O_cx   <= 8'd0;
            end
            else begin
                rem_x  <= I_sx;
                sh_x   <= area25 << 7;      // area × 128
                q_x    <= 8'd0;
                it_x   <= 4'd0;
                busy_x <= 1'b1;
            end
        end
        else if (busy_x) begin
            if (rem_x >= sh_x) begin
                rem_x <= rem_x - sh_x;
                q_x   <= {q_x[6:0], 1'b1};
            end
            else begin
                q_x   <= {q_x[6:0], 1'b0};
            end
            sh_x <= sh_x >> 1;
            if (it_x == 4'd7) begin
                busy_x <= 1'b0;
                O_cx   <= (rem_x >= sh_x) ? {q_x[6:0], 1'b1} : {q_x[6:0], 1'b0};
            end
            else begin
                it_x <= it_x + 1'b1;
            end
        end
    end

    //=========================================================================
    // 2) UART 行格式化
    //=========================================================================
    localparam [1:0] ST_IDLE = 2'd0,
                     ST_SEND = 2'd1,
                     ST_BUSY = 2'd2,
                     ST_WAIT = 2'd3;

    reg [ 1:0] st;
    reg [ 3:0] fidx;          // 字段号 0..8（共 9 个字段）
    reg [ 3:0] nidx;          // 字段内第几个十六进制字符 0..8（8 = 分隔符）

    reg [24:0] sy_r, sx_r;
    reg [16:0] area_r;
    reg [29:0] sx2_r, sy2_r;
    reg [ 7:0] y0_r, y1_r;
    reg [ 7:0] x0_r, x1_r;

    reg        tx_start;
    reg [ 7:0] tx_data;

    wire tx_busy;

    // 零扩展到 32 位，方便按 nibble 取
    wire [31:0] sy32   = {7'b0,  sy_r};
    wire [31:0] sx32   = {7'b0,  sx_r};
    wire [31:0] area32 = {15'b0, area_r};
    wire [31:0] sx232  = {2'b0,  sx2_r};
    wire [31:0] sy232  = {2'b0,  sy2_r};
    wire [31:0] y032   = {24'b0, y0_r};
    wire [31:0] y132   = {24'b0, y1_r};
    wire [31:0] x032   = {24'b0, x0_r};
    wire [31:0] x132   = {24'b0, x1_r};

    // 字段顺序：sy, area, sx, sx2, sy2, y0, y1
    //
    // ⚠️ 字段数只在这里定义一次！加/减字段时改 N_FIELD，
    //    行结束符（f_byte）和帧结束判据（ST_WAIT）都跟着走，
    //    避免两处各写一个魔数而改漏一处（曾经踩过，见 f_byte 处的注释）。
    // 2026-10-20：7 -> 9 个字段，末尾加 x0 / x1（往返跑要用框中心）
    localparam integer N_FIELD   = 9;
    localparam [3:0]   LAST_FIDX = N_FIELD[3:0] - 4'd1;      // 最后一个字段的编号 = 8

    wire [31:0] cur32 = (fidx == 4'd0) ? sy32   :
                        (fidx == 4'd1) ? area32 :
                        (fidx == 4'd2) ? sx32   :
                        (fidx == 4'd3) ? sx232  :
                        (fidx == 4'd4) ? sy232  :
                        (fidx == 4'd5) ? y032   :
                        (fidx == 4'd6) ? y132   :
                        (fidx == 4'd7) ? x032   : x132;

    // 取第 (7-nidx) 个 nibble（nidx=0 取最高位）
    //   nidx 会走到 8（分隔符位置），这里先夹到 0，避免 part-select 越界
    wire [ 3:0] nib_sel  = (nidx >= 4'd8) ? 4'd0 : (4'd7 - nidx);
    wire [ 4:0] nib_base = {1'b0, nib_sel} << 2;      // 5 位，最大 28
    wire [ 3:0] nib      = cur32[nib_base +: 4];

    wire [ 7:0] hexc = (nib < 4'd10) ? (8'h30 + {4'b0, nib})
                                     : (8'h41 + {4'b0, nib} - 8'd10);

    // nidx==8 时发分隔符：最后一个字段后发 '\n'，其余发 ','
    //
    // ⚠️⚠️ 这里必须用 LAST_FIDX（=6），不是 3'd4！
    //   字段数从 5 扩到 7 时，本行的魔数漏改了（还留着 3'd4），
    //   于是每帧在【第 5 个字段 sy2 之后】就换行，帧尾的 y1 后面反而发逗号。
    //   结果：串口流变成 "sy,area,sx,sx2,sy2\n y0,y1,sy,area,sx,sx2,sy2\n ..."，
    //   PC 端按行切出来就是「第一行 5 个字段 + 后面全是错位 2 位的 7 字段行」，
    //   解析出来全是 0，看起来像"检测层没工作"。2026-10-11 现场用串口抓包发现。
    wire [ 7:0] f_byte = (nidx == 4'd8) ? ((fidx == LAST_FIDX) ? 8'h0A : 8'h2C) : hexc;

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            st       <= ST_IDLE;
            fidx     <= 3'd0;
            nidx     <= 4'd0;
            sy_r     <= 25'd0;
            sx_r     <= 25'd0;
            area_r   <= 17'd0;
            sx2_r    <= 30'd0;
            sy2_r    <= 30'd0;
            y0_r     <= 8'd0;
            y1_r     <= 8'd0;
            x0_r     <= 8'd0;
            x1_r     <= 8'd0;
            tx_start <= 1'b0;
            tx_data  <= 8'd0;
        end
        else begin
            tx_start <= 1'b0;      // 默认不触发；只有 ST_SEND 会覆盖成 1

            case (st)
                //-------------------------------------------------------------
                ST_IDLE: begin
                    if (I_valid) begin
                        sy_r   <= I_sy;
                        sx_r   <= I_sx;
                        area_r <= I_area;
                        sx2_r  <= I_sx2;
                        sy2_r  <= I_sy2;
                        y0_r   <= I_y0;
                        y1_r   <= I_y1;
                        x0_r   <= I_x0[7:0];
                        x1_r   <= I_x1[7:0];
                        fidx   <= 4'd0;
                        nidx   <= 4'd0;
                        st     <= ST_SEND;
                    end
                end

                //-------------------------------------------------------------
                // 空闲 -> 给数据 + 脉冲 start，立刻离开（避免重复触发）
                ST_SEND: begin
                    if (!tx_busy) begin
                        tx_data  <= f_byte;
                        tx_start <= 1'b1;
                        st       <= ST_BUSY;
                    end
                end

                //-------------------------------------------------------------
                // 等 uart 确认开始（busy 拉高）
                ST_BUSY: begin
                    if (tx_busy) st <= ST_WAIT;
                end

                //-------------------------------------------------------------
                // 等本字节发完（busy 落回），推进字段/字符计数器
                ST_WAIT: begin
                    if (!tx_busy) begin
                        if (nidx == 4'd8) begin
                            nidx <= 4'd0;
                            if (fidx == LAST_FIDX)
                                st   <= ST_IDLE;        // 换行已发完，整帧结束
                            else begin
                                fidx <= fidx + 1'b1;
                                st   <= ST_SEND;
                            end
                        end
                        else begin
                            nidx <= nidx + 1'b1;
                            st   <= ST_SEND;
                        end
                    end
                end

                default: st <= ST_IDLE;
            endcase
        end
    end

    //=========================================================================
    // UART 发送器
    //=========================================================================
    uart_tx #(
        .CLK_FREQ ( 74250000 ),
        .BAUD     ( 115200   )
    ) u_uart_tx (
        .I_clk      ( I_clk      ),
        .I_rst_n    ( I_rst_n    ),
        .I_tx_start ( tx_start   ),
        .I_tx_data  ( tx_data    ),
        .O_tx_busy  ( tx_busy    ),
        .O_uart_tx  ( O_uart_tx  )
    );

endmodule
