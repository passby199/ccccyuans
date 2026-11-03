//=============================================================================
//  uart_rx.v  --  串口接收（8N1，115200）
//
//  ★★★ 2026-10-28：完全照抄验证可用的例程，不加任何额外逻辑 ★★★
//
//  来源（一字未改逻辑）：
//    D:/ANLU/anlogic_example/chuankou/lab_ex1_mipi_hdmi/
//    user_source/hdl_source/uart_8n1.v  的 uart_rx 模块
//
//  唯一改动：端口名适配本工程顶层（clk / rst_n / rx_pin / rx_data /
//            rx_data_valid），并保留 rx_data_ready 端口（内部不使用）。
//
//  例程的关键设计（不要改）：
//    ① 3 级同步器 s_sync，抗亚稳态
//    ② 起始位【半位回采】确认，毛刺直接丢弃回 IDLE
//    ③ 每位中心采样，低位先收：r_data <= {s_line, r_data[7:1]}
//    ④ 停止位必须为高才认合法帧，否则只置 rx_error，【不输出数据】
//
//  时钟：S_hdmi_pixel_clk = 74.25 MHz
//        DIV = 74250000 / 115200 = 644（实际波特率 115,294，偏差 +0.08%）
//=============================================================================
module uart_rx #(
    parameter integer CLK_FRE   = 74250000,  // 单位 Hz
    parameter integer BAUD_RATE = 115200
)(
    input  wire       clk,
    input  wire       rst_n,          // 低有效
    output reg  [7:0] rx_data,
    output reg        rx_data_valid,  // 收到一个合法字节时 1 拍脉冲
    input  wire       rx_data_ready,  // 保留（例程无此端口，内部不使用）
    input  wire       rx_pin
);

    localparam integer DIV  = CLK_FRE / BAUD_RATE;   // 74250000/115200 = 644
    localparam integer HALF = DIV / 2;

    //-------------------------------------------------------------------------
    // 输入同步（3 级，抗亚稳态）—— 例程原样
    //-------------------------------------------------------------------------
    reg [2:0] s_sync;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) s_sync <= 3'b111;
        else        s_sync <= { s_sync[1:0], rx_pin };
    end
    wire s_line = s_sync[2];

    localparam [1:0] RX_IDLE  = 2'd0,
                     RX_START = 2'd1,
                     RX_DATA  = 2'd2,
                     RX_STOP  = 2'd3;

    reg [1:0]  r_state;
    reg [15:0] r_cnt;
    reg [3:0]  r_bit;
    reg [7:0]  r_data;
    reg        rx_error;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            r_state       <= RX_IDLE;
            r_cnt         <= 16'd0;
            r_bit         <= 4'd0;
            r_data        <= 8'd0;
            rx_data       <= 8'd0;
            rx_data_valid <= 1'b0;
            rx_error      <= 1'b0;
        end else begin
            rx_data_valid <= 1'b0;
            rx_error      <= 1'b0;

            case (r_state)
            //---- 等起始位（下降沿）----
            RX_IDLE: begin
                if (!s_line) begin
                    r_state <= RX_START;
                    r_cnt   <= 16'd0;
                end
            end

            //---- 半位后回采，确认是真起始位而不是毛刺 ----
            RX_START: begin
                if (r_cnt == HALF - 1) begin
                    r_cnt <= 16'd0;
                    if (!s_line) begin
                        r_state <= RX_DATA;
                        r_bit   <= 4'd0;
                    end else begin
                        r_state <= RX_IDLE;      // 毛刺，丢弃
                    end
                end else begin
                    r_cnt <= r_cnt + 16'd1;
                end
            end

            //---- 每位中心采样，低位先收 ----
            RX_DATA: begin
                if (r_cnt == DIV - 1) begin
                    r_cnt  <= 16'd0;
                    r_data <= { s_line, r_data[7:1] };
                    if (r_bit == 4'd7) r_state <= RX_STOP;
                    else               r_bit   <= r_bit + 4'd1;
                end else begin
                    r_cnt <= r_cnt + 16'd1;
                end
            end

            //---- 停止位：高电平才算合法帧（例程原样，非法帧不输出）----
            RX_STOP: begin
                if (r_cnt == DIV - 1) begin
                    r_cnt   <= 16'd0;
                    r_state <= RX_IDLE;
                    if (s_line) begin
                        rx_data       <= r_data;
                        rx_data_valid <= 1'b1;
                    end else begin
                        rx_error <= 1'b1;        // 停止位错，丢弃本帧
                    end
                end else begin
                    r_cnt <= r_cnt + 16'd1;
                end
            end

            default: r_state <= RX_IDLE;
            endcase
        end
    end

endmodule
