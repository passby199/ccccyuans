//=============================================================================
//  uart_tx.v  --  UART 发送器（8N1，115200）
//
//  ★★★ 2026-10-27 22:20：换成【验证可用的例程实现】★★★
//
//  【新实现来自】D:/ANLU/anlogic_example/chuankou/lab_ex1_mipi_hdmi/
//                user_source/hdl_source/uart_8n1.v
//    用户实测可用的版本，比旧实现更规范：
//      · CLK_FREQ 单位 Hz（74250000），DIV = 644 精确
//      · 用 11 位移位寄存器一次装载整帧，发送过程零判断
//      · 支持 PARITY / STOP 参数（默认 8N1）
//
//  【端口和参数名与旧版完全一致】顶层例化不用改
//=============================================================================
module uart_tx #(
    parameter integer CLK_FREQ = 74250000,   // 系统时钟 Hz
    parameter integer BAUD     = 115200,     // 波特率
    parameter integer PARITY   = 0,          // 0=None 1=Even 2=Odd
    parameter integer STOP     = 1           // 1 或 2 个停止位
)(
    input  wire       I_clk,
    input  wire       I_rst_n,
    input  wire [7:0] I_tx_data,     // 待发送字节
    input  wire       I_tx_start,    // 单拍脉冲启动一次发送
    output reg        O_tx_busy,     // 1 = 正在发送，此时忽略 I_tx_start
    output reg        O_uart_tx      // 串行输出，空闲为高
);
    localparam integer DIV = CLK_FREQ / BAUD;                          // 每 bit 时钟数
    localparam integer NB  = 1 + 8 + ((PARITY == 0) ? 0 : 1) + STOP;   // 总位数

    reg [10:0] r_sr;        // 移位寄存器：{stop..., parity, data[7:0], start}
    reg [3:0]  r_bit;       // 当前发送到第几位
    reg [15:0] r_cnt;       // 位内分频计数

    // 偶校验：数据里 1 的个数为奇数时补 1，使总数为偶数
    wire w_par = (PARITY == 1) ? ^I_tx_data : ~(^I_tx_data);

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            r_sr      <= 11'h7FF;      // 全 1 = 空闲
            r_bit     <= 4'd0;
            r_cnt     <= 16'd0;
            O_tx_busy <= 1'b0;
            O_uart_tx <= 1'b1;
        end else if (!O_tx_busy) begin
            O_uart_tx <= 1'b1;
            r_cnt     <= 16'd0;
            r_bit     <= 4'd0;
            if (I_tx_start) begin
                // 低位先发：start(0) -> data[0..7] -> parity -> stop(1...)
                r_sr <= (PARITY == 0)
                        ? { {(STOP){1'b1}}, I_tx_data, 1'b0 }
                        : { {(STOP){1'b1}}, w_par, I_tx_data, 1'b0 };
                O_tx_busy <= 1'b1;
                O_uart_tx <= 1'b0;      // 起始位立即拉低
            end
        end else begin
            if (r_cnt == DIV - 1) begin
                r_cnt <= 16'd0;
                if (r_bit == NB - 1) begin
                    O_tx_busy <= 1'b0;
                    O_uart_tx <= 1'b1;
                    r_bit     <= 4'd0;
                end else begin
                    r_bit     <= r_bit + 4'd1;
                    O_uart_tx <= r_sr[r_bit + 4'd1];
                end
            end else begin
                r_cnt <= r_cnt + 16'd1;
            end
        end
    end
endmodule
