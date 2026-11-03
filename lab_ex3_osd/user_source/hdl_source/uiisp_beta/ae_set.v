/*******************************MILIANKE*******************************
*Company : MiLianKe Electronic Technology Co., Ltd.
*WebSite:https://www.milianke.com
*TechWeb:https://www.uisrc.com
*tmall-shop:https://milianke.tmall.com
*jd-shop:https://milianke.jd.com
*taobao-shop1: https://milianke.taobao.com
*Create Date: 2023/03/23
*Module Name:
*File Name:
*Description: 
*The reference demo provided by Milianke is only used for learning. 
*We cannot ensure that the demo itself is free of bugs, so users 
*should be responsible for the technical problems and consequences
*caused by the use of their own products.
*Copyright: Copyright (c) MiLianKe
*All rights reserved.
*Revision: 1.0
*Signal description
*1) I_ input
*2) O_ output
*3) IO_ input output
*4) S_ system internal signal
*5) _n activ low
*6) _dg debug signal 
*7) _r delay or register
*8) _s state mechine
*********************************************************************/
/*********ae_set �ֶ��������AE ***********
--�汾��1.0
*********************************************************************/

module ae_set
(
input wire I_clk,
input wire I_rst,
input wire [3:0]I_btn,
input wire I_ae_cfg_done,
input wire I_cam_cfg_done,
    // ★★★ 2026-10-18（第三十四轮）：闭环 AE 测光输入
    //   I_y_med     = 后级 cartoonize 算出的帧亮度【中位】（gamma 之后的显示域）
    //   I_y_med_tog = 每帧翻转一次的电平标志（75MHz → 24MHz 跨时钟域用）
    input wire [7:0]  I_y_med,
    input wire        I_y_med_tog,
output wire O_ae_req,
output wire [15:0] O_ae,
output wire [15:0] O_ag,
input  wire        I_ae_en,     // rev61: 1=auto AE/AWB, 0=hold (manual)
input  wire        I_ae_kick,   // rev96: kick pulse - darken first, then AE climbs back
// ★ 2026-10-29：KEY4 曝光档位选择（仅在 AE 关闭时生效）
//   0 = AE_LOW(3000，3.1ms，运动清晰)   1 = AE_HIGH(9000，9.4ms，亮但模糊)
//   电平信号（顶层翻转），这里两级同步后使用。
input  wire        I_ae_hi
);
	

reg 	[19:0] 	rc_ae_tick = 0; 
reg 			r_ae_tick = 0; 
reg 	[4:0] 	rc_ag_tick = 0; 
reg 			r_ag_tick = 0; 
	
always @(posedge I_clk or posedge I_rst) begin
	if(I_rst) begin
		rc_ae_tick <= 0; 
		r_ae_tick <= 0; 
		rc_ag_tick <= 0; 
		r_ag_tick <= 0; 
	end else begin
	//	Trigger AE Inc / Dec per 1 ms. 
	//  ★ 2026-10-28：更新周期 100,000 → 20,000 拍
	//    原因：原来 100,000 @ 24MHz = 4.17ms 一次，每次只 ±1，
	//    曝光范围 800~13000 共 12,200 步 → 走完全程要 51 秒，太慢。
	//    改成 20,000 → 0.83ms 一次，全程约 10 秒（快 5 倍）。
	//    再快会画面抖动，5 倍是折中值。
		rc_ae_tick <= rc_ae_tick + 1; 
		r_ae_tick <= 0; 
		if(rc_ae_tick >= 19999) begin
			rc_ae_tick <= 0; 
			r_ae_tick <= 1; 
		end 
	//	Trigger AG Inc / Dec per 32 ms. 
		rc_ag_tick <= rc_ag_tick + r_ae_tick; 
		r_ag_tick <= (&rc_ag_tick) && r_ae_tick; 
	end
end
	
//	Use button to add / sub idelay values. I_button[0]:IncDatDly, [1]DecDatDly, [2]IncI_clkDly, [3]DecI_clkDly
reg 	[3:0] 	r_button_0 = 0, r_button_1 = 0; 
// ★★★ 2026-10-18（第三十六轮）：曝光初值/上限从 1990 放开到 5000。
//   【为什么】1990 只是原作者随手写的"上限"，不是传感器的上限：
//     曝光寄存器单位 = 1/16 行，VTS = 1000 行 → 合法上限 ≈ 16000。
//     而 1990 只有 124 行（约 2ms@60fps），AE 想再亮时已经"顶到假天花板"，
//     所以之前把目标从 130 一路提到 165 都【不会变亮】。
//   ★ 5000 = 312 行 ≈ 5.2ms，静态场景够用；动态场景若觉得拖影就回 3000。
// ★★★ 2026-10-18（第三十九轮·根源修正）：
//   SC500 寄存器表注释写明「720p60 曝光时间较短，按已验证工程设置约 4 倍模拟增益」——
//   即原厂是用【124 行曝光 + 4x 增益】硬撑亮度。之前把增益降到 1x 却不动曝光，
//   画面等于暗了 4 倍（这就是"越调越灰"的根源）。
//   ✅ 正解：把曝光从 124 行提到 600~800 行（单位=1/16 行），增益回到 1x。
//   ★★★ rev41 修正：「增益回到 1x」的写法有 bug——r_ag_set=1024 过 7bit
//      增益表会越界写 0（实际≈0.8x）。现改为 AG 直写寄存器值，2x 起步、上限 4x。
//     同样亮度下多收 4~6 倍光 → 噪声更低、层次更自然。
//   VTS=1000 行 → 合法曝光上限 ≈ 15800；这里留余量取 13000（812 行 ≈ 13.5ms）。
localparam [15:0] AE_MAX  = 16'd13000;   // rev69: 812 rows (unit = 1/16 row!)
// ★ 2026-10-29：AE_INIT 9600 → 3000
//   9600 = 600 行 = 约 10ms 曝光（占帧周期 60%）→ 人走动时 2.7 像素运动模糊。
//   3000 = 187 行 = 约 3.1ms 曝光 → 0.8 像素，运动清晰。
//   用户要求"上电默认清晰"，亮画面由 K4 切到 AE_HIGH(9000) 手动获得。
localparam [15:0] AE_INIT = 16'd3000;    // 上电默认 3000（清晰档）
localparam [15:0] AE_LOW  = 16'd3000;    // ★ K4 低档：187 行 = 3.1ms，运动清晰
localparam [15:0] AE_HIGH = 16'd9000;    // ★ K4 高档：562 行 = 9.4ms，亮但运动模糊
localparam [15:0] AE_MIN  = 16'd800;     // rev69: 50 rows
localparam [15:0] AE_MID  = 16'd3200;    // rev97: geometric mid of 800~13000 -> ~4x headroom each way

// [OBSOLETE-REV44] ★★★ 2026-10-18（rev41·第二处根源）：AG 增益通路修复
//   【上一个 bug】SC500GainTbl 入口是 7bit 的 (I_ag - 16)，而 r_ag_set=1024
//     减 16 截断后 = 112，越过增益表最大下标 73 → 恒输出 0 → 传感器
//     0x3e08/09 被写 0x0000 = 最低增益（≈0.8x）。rev39 把曝光提到 812 行后，
//     60fps 帧长封顶、增益又是坏的 → 暗场景无牌可打（用户 10-18 夜景实拍：
//     中位 120 远低于目标 150，AE 已饱和）。原厂在此场景用 4x 增益是对的。
//   【修法】r_ag_set 直接 = AG 寄存器值（0x3e08/09 的 16bit 值），增益 ≈ AG/968。
//     uicfgcs500.v 里已同步改为直连（不再过 SC500GainTbl）。
// ���� 2026-10-19��rev44�����������������ڶ��ˣ���AG ��Ϊ��SC500GainTbl ���±꡿
//   ��rev41 �����ġ��� 0x3e08/09 ������������ֵ��968=1x/1936=2x/3872=4x����
//     ֱд 1936 = 0x0790 ���� ���üĴ����� SmartSens �� AGAIN���ֶα��롿��
//       ���ֽ� 0x03 + ���ֽ� 0x20~0x3F = 1.0x �Σ�0x0320 = 1.0x��
//       ���ֽ� 0x07 + ���ֽ� 0x20~0x3F = 2.0x �Σ�0x0720 = 2.0x��
//       ���ֽ� 0x0F + ���ֽ� 0x20~0x29 = 4.0x �Σ�0x0F20 = 4.0x������������Ĭ�ϣ�
//     0x0790 �ĵ��ֽ� 0x90 ���ںϷ��� �� ���������ȫ�ڣ�����ģʽ���ڣ���
//   �����ڡ�r_ag_set �ǡ����±� 0~73������ uicfgcs500.v �� SC500GainTbl ӳ��ɺϷ��롣
//     �±� 0��0x0320(1.0x) / 32��0x0720(2.0x) / 64��0x0F20(4.0x) / 73��0x0F29(��4.1x)
//     ÿ�� ��1 ��8 ֡һ�Σ������ʱ��������ϴ�1.47x��2.0x������������
localparam [15:0] AG_IDX_MIN = 16'd64;   // rev73: index 64 = 0x0F20 = 4.0x = sensor default (no dark dip)
localparam [15:0] AG_IDX_FLOOR = 16'd0;  // rev75: gain floor 1.0x (bright scenes need it)
localparam [15:0] AG_IDX_MAX = 16'd73;   // rev69: 4.1x (restored)
localparam [15:0] AG_STEP    = 16'd4;    // rev75: 4 idx per update (~2s for 4x->1x)
reg 	[15:0] 	r_ae_set = 16'd9600, r_ag_set = AG_IDX_MIN;  // 600 ���ع� + 1x �����𲽣�rev44��AG �߱��±� 0��

// ---------------- 闭环 AE 的测光同步与节拍（第三十四轮）----------------
localparam [7:0] Y_MED_TGT = 8'd85;    // rev90: lower target = more headroom for AE demo
                                       //   ★ 165 = 很亮档。依据（用户 10-18 两张实拍）：屏幕上的白色耳机盒 Y=145，
                                       //     而手拿的真机是 159.5 → 屏幕偏暗 15 码；中位 154 也偏低。
                                       //     标准 130 / 略亮 150 / 当前 165 / 极亮 175
localparam [7:0] Y_MED_DB  = 8'd10;    // 死区 ±10 码（防抖动）
reg  [7:0] y_med_s0, y_med_s1;         // 中位值两级同步
reg        y_tog_s0, y_tog_s1, y_tog_d;// 帧标志两级同步 + 打一拍测边沿
reg  [7:0] y_med_d;                    // 同步后的中位（AE 用）
reg  [4:0] ae_fc;                      // rev89: 16 frames per step (~0.27s) - visible AE
reg        ae_upd;                     // 调整脉冲
always @(posedge I_clk or posedge I_rst) begin
	if (I_rst) begin
		y_med_s0 <= 8'd118; y_med_s1 <= 8'd118; y_med_d <= 8'd118;
		y_tog_s0 <= 1'b0;   y_tog_s1 <= 1'b0;   y_tog_d <= 1'b0;
		ae_fc    <= 5'd0;   ae_upd   <= 1'b0;
	end else begin
		y_med_s0 <= I_y_med;
		y_med_s1 <= y_med_s0;
		y_tog_s0 <= I_y_med_tog;
		y_tog_s1 <= y_tog_s0;
		y_tog_d  <= y_tog_s1;
		ae_upd   <= 1'b0;
		if (y_tog_s1 != y_tog_d) begin          // 一帧一次
			y_med_d <= y_med_s1;                // 锁存最新中位
if (ae_fc == 5'd7) begin           // rev89: 8->16 frames (~0.27s) so AE is visible
				ae_fc  <= 5'd0;
				ae_upd <= 1'b1;                 // 8 帧调一次
			end else begin
				ae_fc <= ae_fc + 1'b1;
			end
		end
	end
end   // ★ 2026-10-16 提亮：曝光=上限1990(VTS=1000)，模拟增益 80->0x0720(2x) 

// ★ 2026-10-29：KEY4 曝光档位选择 —— 跨时钟域两级同步
//   顶层在 74.25MHz 像素域翻转电平，本模块在 24MHz 域使用。
//   电平信号（不是单拍脉冲）→ 两级同步足够，不会漏。
reg [1:0] ae_hi_sync;
always @(posedge I_clk or posedge I_rst) begin
	if (I_rst)
		ae_hi_sync <= 2'b00;
	else
		ae_hi_sync <= { ae_hi_sync[0], I_ae_hi };
end

always @(posedge I_clk or posedge I_rst) begin
	if(I_rst) begin
		r_button_0 <= 0; 
		r_button_1 <= 0; 
		r_ae_set <= AE_INIT; 
		r_ag_set <= AG_IDX_MIN; 
	end else begin
	//	When button pressed, r_button_1 bit is 1. 
		r_button_0 <= ~I_btn; 
		r_button_1 <= r_button_0; 
	
		if(r_button_1[0]) begin
			r_ae_set <= (r_ae_set > 2) ? r_ae_set - r_ae_tick : r_ae_set; 
		end else if(r_button_1[1]) begin
			r_ae_set <= (r_ae_set < AE_MAX) ? r_ae_set + r_ae_tick : r_ae_set; 
		end 
		if(r_button_1[2]) begin
				r_ag_set <= (r_ag_set > AG_IDX_MIN) ? r_ag_set - r_ag_tick : r_ag_set; 
		end else if(r_button_1[3]) begin
				r_ag_set <= (r_ag_set < AG_IDX_MAX) ? r_ag_set + r_ag_tick : r_ag_set; 
		end 
		// ================= ★★★ 2026-10-18（第三十四轮）：闭环自动曝光 =================
		//   【为什么必须有它】原来 AE/AG 写死成 曝光=1990(上限)/增益=1824(≈1.8x)，
		//     用户三张实拍照片都是「灰白、层次挤在高光端」——根因在【传感器端】，
		//     后级再怎么调色调都救不回来（信息已经被压缩了）。
		//   【做法 = 手机 AE】测光（后级帧中位）→ 与目标比 → 调曝光，曝光到底再调增益。
		//     每 8 帧调一次（≈0.13s），死区 ±10 码，步长按误差大小分粗/细两档。
		//   【调参入口】Y_MED_TGT：目标中位（越大越亮）。118 ≈ 46% 灰（标准）。
		//     想要整体更亮 → 130；更暗/更沉稳 → 105。
		// rev97: on auto-enable edge, start from AE_MID (mid value)
		//   then AE closed-loop adjusts UP (dark scene) or DOWN (bright scene)
		if (I_ae_kick) begin
			r_ae_set <= AE_MID;
		end else if (ae_upd && I_ae_en) begin
			if (y_med_d > Y_MED_TGT + Y_MED_DB) begin
				// 太亮 → 先降曝光（噪声小），曝光到底再降增益
				if (r_ae_set > AE_MIN)
					r_ae_set <= (r_ae_set < (AE_MIN + 16'd256)) ? AE_MIN : ((r_ae_set > (AE_MIN + 16'd3000)) ? r_ae_set - 16'd400 : r_ae_set - 16'd256);
				else if (r_ag_set > AG_IDX_FLOOR)
					// rev103: CLAMP! 2-4 would wrap to 65534 -> index 126 -> table default 0 -> illegal gain -> BLACK SCREEN
					r_ag_set <= (r_ag_set < (AG_IDX_FLOOR + AG_STEP)) ? AG_IDX_FLOOR : r_ag_set - AG_STEP;
			end else if (y_med_d + Y_MED_DB < Y_MED_TGT) begin
				// 太暗 → 先升曝光，曝光到顶再升增益
				if (r_ae_set < AE_MAX)
					r_ae_set <= (r_ae_set > (AE_MAX - 16'd256)) ? AE_MAX : ((r_ae_set < (AE_MAX - 16'd3000)) ? r_ae_set + 16'd400 : r_ae_set + 16'd256);
				else if (r_ag_set < AG_IDX_MAX)
					// rev103: CLAMP! 70+4=74 is OUT of table (0..73) -> default 0 -> illegal gain -> BLACK SCREEN
					r_ag_set <= (r_ag_set > (AG_IDX_MAX - AG_STEP)) ? AG_IDX_MAX : r_ag_set + AG_STEP;
			end
		end
		// ★ 2026-10-29：AE 关闭时，曝光由 KEY4 在 3000/9000 之间切换
		//   放在 always 块最后 → 优先级最高，覆盖上面的按键调节和 AE 闭环。
		//   AE 开着（I_ae_en=1）时这段不生效，AE 闭环完全接管。
		if (!I_ae_en) begin
			r_ae_set <= ae_hi_sync[1] ? AE_HIGH : AE_LOW;
		end
		end
	end
	
//	Update AG / AE when changed. 
reg 	[15:0] 	r_ae ; 
reg        cfg_done_d;   // rev100: I_ae_cfg_done delayed 1 cycle (edge detect)
reg [19:0] req_to;       // rev100: req hold timeout counter
reg 	[15:0] 	r_ag ; 
reg 			r_ae_req = 0; //synthesis keep
assign O_ae = r_ae;
assign O_ag = r_ag;
assign O_ae_req = r_ae_req;

always @(posedge I_clk or posedge I_rst) begin
	if (I_rst) cfg_done_d <= 1'b0;
	else       cfg_done_d <= I_ae_cfg_done;
end

always @(posedge I_clk or posedge I_rst) begin
	if(I_rst) begin
		r_ae_req <= 0; 
		// ���� rev95: r_ae ��λֵ��Ϊ 0���� r_ae_set=9600��
		//   ԭ����λֵҲ�� 9600���� r_ae_set ���
		//   �� (r_ae != r_ae_set) ��Ϊ�� �� �ϵ�Ӳ�д������
		//   �� ������ͣ�������� 1984����124 �У��� �� 9600��600 �У��� 4.8 �� = ����

		req_to   <= 20'd0;
		r_ae     <= 16'd0; 
		r_ag     <= AG_IDX_MIN; 
	end else if(r_ae_req) begin
		// rev100: req must stay until cfg module really finishes (cfg_done rising edge).
		//   A 1-cycle pulse is ignored when the cfg FSM is busy -> exposure never written.
		// rev101: clear on cfg_done FALLING edge (1->0) = cfg module has ACCEPTED the request.
		//   Using the rising edge (done) would make the cfg FSM accept the same req twice
		//   -> r_ae never updates -> sensor keeps old exposure forever.
		if ((!I_ae_cfg_done && cfg_done_d) || (req_to == 20'hFFFFF)) begin
			r_ae_req <= 1'b0;
			req_to   <= 20'd0;
		end else
			req_to   <= req_to + 20'd1;
	end else if(((r_ae != r_ae_set) || (r_ag != r_ag_set))&&(I_cam_cfg_done==1'b1)&&(I_ae_cfg_done==1'b1)) begin
		r_ae     <= r_ae_set; 
		r_ag     <= r_ag_set; 
		r_ae_req <= 1'b1; 
		req_to   <= 20'd0;
	end
end


endmodule


	