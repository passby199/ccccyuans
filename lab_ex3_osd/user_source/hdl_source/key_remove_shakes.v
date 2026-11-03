/*
creat time: 2020/12/3 15:50

engineer:   xiong guo qiang

description:
对按键操作进行消抖操作，每次按下产生一个时钟周期的高脉冲

*/


module key_remove_shakes( 
	input wire      I_clk,    
	input wire      I_rst_n,
	
	input wire      I_key_in,        
	
	output reg      O_key_trig_out   
);

	///同步到处理时钟域，打三拍
	reg       S_key_in_sync_1d;      
	reg       S_key_in_sync_2d;      
	reg       S_key_in_sync_3d;      
	reg	      S_key_in_sync_4d;
	wire      S_key_in_n_edge;       
			  
	reg       S_delay_en;            
	reg       S_delay_en_1d;         
	wire      S_delay_en_n_edge;     
	// ★ 2026-10-28：消抖时间 1.35ms → 20ms → 50ms，位宽 17 → 22
	//   原因：原来阈值 'd100000 @ 74.25MHz 只有 1.35ms，
	//   而机械按键抖动典型 5~20ms，滤不干净 → 一次按下触发多次
	//   → KEY3 切滤镜会跳档（比如 9 直接跳到 11，错过 10）。
	//   20ms 实测仍偶发跳档，加到 50ms（3,712,500 拍，需 22 位，2^22=4,194,304）。
	reg[21:0] S_delay_cnt;           
	localparam [21:0] DEBOUNCE_CNT = 22'd3712500;   // 50ms @ 74.25MHz
	
	
	always @ (posedge I_clk) begin
		S_key_in_sync_1d <= I_key_in;
		S_key_in_sync_2d <= S_key_in_sync_1d;
		S_key_in_sync_3d <= S_key_in_sync_2d;
		S_key_in_sync_4d <= S_key_in_sync_3d;
	end
	

	assign S_key_in_n_edge = ~S_key_in_sync_3d & S_key_in_sync_4d;
	
	
	always @ (posedge I_clk or negedge I_rst_n) begin
		if(!I_rst_n)
			S_delay_en <= 1'b0;
		else
			if(S_key_in_n_edge)
				S_delay_en <= 1'b1;
			else if(S_delay_cnt == DEBOUNCE_CNT)
				S_delay_en <= 1'b0;
			else
				S_delay_en <= S_delay_en;
	end
	
	
	always @ (posedge I_clk or negedge I_rst_n) begin
		if(!I_rst_n)
			S_delay_cnt <= 'd0;
		else
			if(S_delay_en)
				S_delay_cnt <= S_delay_cnt + 1'b1;
			else
				S_delay_cnt <= 'd0;
	end
	
	
	always @ (posedge I_clk) begin
		S_delay_en_1d <= S_delay_en;
	end
	
	
	assign S_delay_en_n_edge = ~S_delay_en & S_delay_en_1d;
	
	
	always @ (posedge I_clk) begin
		if(S_delay_en_n_edge && !S_key_in_sync_4d)
			O_key_trig_out <= 1'b1;
		else
			O_key_trig_out <= 1'b0;
	end
	

endmodule

//=============================================================================
// ★ 2026-10-29 新增：带长按检测的按键处理（只给 KEY4 用）
//
//   为什么新增而不是改 key_remove_shakes：
//     key_remove_shakes 是"按下瞬间"出脉冲，另外 3 个按键依赖这个行为。
//     长按需要"按住 1 秒才触发、且短按要延到释放时才判定"，行为不同，
//     所以单独做一个模块，不影响原有的 3 个按键。
//
//   语义：
//     O_short = 短按（按住 < 1 秒后松开）→ KEY4 切曝光档 3000/9000
//     O_long  = 长按（按住 >= 1 秒）      → KEY4 开自动曝光
//
//   ⚠ 放在本文件内（已登记在 .al 清单），避免新增文件导致 TD 报 black box。
//=============================================================================
module key_long_press (
	input  wire I_clk,
	input  wire I_rst_n,
	input  wire I_key_in,      // 低有效（按下 = 0）
	output reg  O_short,       // 短按脉冲（1 拍）
	output reg  O_long         // 长按脉冲（1 拍，按住满 1 秒时触发）
);

	// 1 秒 @ 74.25MHz = 74,250,000
	localparam [26:0] LONG_CNT   = 27'd74_250_000;
	// 50ms 消抖门限：按住超过这个时间才算"有效按下"
	localparam [26:0] DEBOUNCE   = 27'd3_712_500;

	// 4 级同步（防亚稳态）
	reg [3:0] S_sync;
	always @(posedge I_clk or negedge I_rst_n) begin
		if (!I_rst_n) S_sync <= 4'b1111;
		else          S_sync <= { S_sync[2:0], I_key_in };
	end
	wire S_pressed = ~S_sync[3];        // 低有效：按下为 1

	reg [26:0] S_cnt;
	reg        S_long_fired;

	always @(posedge I_clk or negedge I_rst_n) begin
		if (!I_rst_n) begin
			S_cnt        <= 27'd0;
			S_long_fired <= 1'b0;
			O_short      <= 1'b0;
			O_long       <= 1'b0;
		end else begin
			O_short <= 1'b0;
			O_long  <= 1'b0;

			if (S_pressed) begin
				if (S_cnt < LONG_CNT)
					S_cnt <= S_cnt + 27'd1;
				else if (!S_long_fired) begin
					O_long       <= 1'b1;     // 按住满 1 秒 → 长按
					S_long_fired <= 1'b1;     // 标记已长按，松开时不再出短按
				end
			end else begin
				// 松开：如果按住超过消抖门限、且没触发长按 → 短按
				if ((S_cnt > DEBOUNCE) && !S_long_fired)
					O_short <= 1'b1;
				S_cnt        <= 27'd0;
				S_long_fired <= 1'b0;
			end
		end
	end

endmodule
