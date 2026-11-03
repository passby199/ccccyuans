`timescale 1ns / 1ps

/*
 * SC500CS原厂HD模式：1280x720@60，24MHz MCLK，2-Lane RAW10，
 * Lane速率约480Mbps。Sensor内部启用VBIN和HSUB，直接输出720p，
 * FPGA端不再做1024x600固定裁剪。
 *
 * ⚠️ 关于视场（2026-10-09 修正，含一次失败尝试的记录）
 *   HD 模式是「Binning and Crop」：2x2 binning 后是 1296x972，
 *   再裁到 1280x720 —— 垂直方向确实只用了传感器约 74% 的视场。
 *
 *   我曾据此把窗口行起始从 2 改到 126（想居中、让脚进画面），
 *   结果画面撕裂（下半卡住 + 上半比例错乱），已回退到厂商值 2。
 *   根因：曝光时间被设成了满格（995 行 = 2*VTS-10 的上限），
 *   整帧时序没有余量，行起始一挪就挤爆帧边界。
 *   **这两行不要再动**，想看到全身请走光学路线（俯拍 / 换广角镜头）。
 *
 * 后续若切换Sensor模式，还应同步检查MIPI约束、图像宽高、ISP、
 * DDR帧缓存、HDMI时序、HDMI TX参数及PLL，避免各级尺寸不一致。
 */
module uics500reg_720p60(
    input      [8:0]  REG_INDEX,
    output reg [31:0] REG_DATA,
    output     [8:0]  REG_SIZE
);
assign REG_SIZE = 9'd116;
always @(*) begin
    case (REG_INDEX)
        0: REG_DATA={16'h0103,8'h01}; 1: REG_DATA={16'h0100,8'h00};
        2: REG_DATA={16'h36e9,8'h80}; 3: REG_DATA={16'h36f9,8'h80};
        4: REG_DATA={16'h36ea,8'h3c}; 5: REG_DATA={16'h36ec,8'h1b};
        6: REG_DATA={16'h36fd,8'h14}; 7: REG_DATA={16'h36e9,8'h04};
        8: REG_DATA={16'h36f9,8'h04}; 9: REG_DATA={16'h3016,8'h10};
        10: REG_DATA={16'h3017,8'h0e}; 11: REG_DATA={16'h301f,8'h04};
        12: REG_DATA={16'h302d,8'h20}; 13: REG_DATA={16'h3106,8'h01};
        14: REG_DATA={16'h3200,8'h00}; 15: REG_DATA={16'h3201,8'h14};
        16: REG_DATA={16'h3202,8'h01}; 17: REG_DATA={16'h3203,8'h00};
        18: REG_DATA={16'h3204,8'h0a}; 19: REG_DATA={16'h3205,8'h1b};
        20: REG_DATA={16'h3206,8'h06}; 21: REG_DATA={16'h3207,8'ha7};
        22: REG_DATA={16'h3208,8'h05}; 23: REG_DATA={16'h3209,8'h00}; // 1280
        24: REG_DATA={16'h320a,8'h02}; 25: REG_DATA={16'h320b,8'hd0}; // 720
        26: REG_DATA={16'h320c,8'h06}; 27: REG_DATA={16'h320d,8'h40}; // HTS 1600
        28: REG_DATA={16'h320e,8'h03}; 29: REG_DATA={16'h320f,8'he8}; // VTS 1000
        //--------------------------------------------------------------------
        // 裁剪窗口起点（0x3210/11 = 列起始，0x3212/13 = 行起始）
        //
        //   ⚠️⚠️ 这两行【必须】保持厂商值 2，不要改成"居中"！ ⚠️⚠️
        //
        //   2026-10-09 我试着把行起始改成 126（想让画面下移、脚进画面），
        //   结果上电后画面撕裂：下半部分卡住不动、上半部分比例错乱。
        //   已回退。原因分析见下。
        //
        //   为什么改不动：
        //     ① 曝光时间被设成了【满格】。0x3e00/01/02 = 0x00_7c_60，
        //        按"1/2 行为单位"折算 = 1990/2 = 995 行；而手册表 2-2 给的
        //        上限就是 2*VTS-10 = 1990。也就是说曝光顶到了 VTS 的天花板，
        //        整帧时序没有任何余量，行起始一挪就把帧边界挤爆。
        //     ② 手册（V1.8 Preliminary）的"2.4.2 输出窗口"一节只列了寄存器，
        //        没有任何约束说明；而厂商自己的两份配置（720p HD binning、
        //        1080p FHD crop）用的都是**左上角小偏移**（2 / 4），
        //        从不居中。说明这颗 sensor 的读出时序就是按"接近 0 起点"设计的。
        //
        //   想"看到全身"请走光学路线，别改这两行：
        //     · 把摄像头往下俯一点（免费，立刻见效）
        //     · 换一颗 M12 广角镜头（原装 6504 是 4mm/垂直48°，可拆换）
        //--------------------------------------------------------------------
        30: REG_DATA={16'h3210,8'h00}; 31: REG_DATA={16'h3211,8'h02}; // 列起始 = 2（厂商值）
        32: REG_DATA={16'h3212,8'h00}; 33: REG_DATA={16'h3213,8'h02}; // 行起始 = 2（厂商值）
        34: REG_DATA={16'h3215,8'h31}; 35: REG_DATA={16'h3220,8'h01}; // VBIN+HSUB
        36: REG_DATA={16'h3249,8'h0f}; 37: REG_DATA={16'h3253,8'h06};
        38: REG_DATA={16'h3271,8'h13}; 39: REG_DATA={16'h3273,8'h13};
        40: REG_DATA={16'h3301,8'h0a}; 41: REG_DATA={16'h3309,8'h60};
        42: REG_DATA={16'h330a,8'h00}; 43: REG_DATA={16'h330b,8'he8};
        44: REG_DATA={16'h331e,8'h41}; 45: REG_DATA={16'h331f,8'h51};
        46: REG_DATA={16'h3320,8'h04}; 47: REG_DATA={16'h3333,8'h10};
        48: REG_DATA={16'h335d,8'h60}; 49: REG_DATA={16'h3364,8'h56};
        50: REG_DATA={16'h336b,8'h08}; 51: REG_DATA={16'h3390,8'h08};
        52: REG_DATA={16'h3391,8'h18}; 53: REG_DATA={16'h3392,8'h38};
        54: REG_DATA={16'h3393,8'h0a}; 55: REG_DATA={16'h3394,8'h24};
        56: REG_DATA={16'h3395,8'h40}; 57: REG_DATA={16'h33ad,8'h29};
        58: REG_DATA={16'h341c,8'h04}; 59: REG_DATA={16'h341d,8'h04};
        60: REG_DATA={16'h341e,8'h03}; 61: REG_DATA={16'h3425,8'h00};
        62: REG_DATA={16'h3426,8'h00}; 63: REG_DATA={16'h3622,8'hc7};
        64: REG_DATA={16'h3632,8'h44}; 65: REG_DATA={16'h3636,8'h6e};
        66: REG_DATA={16'h3637,8'h08}; 67: REG_DATA={16'h3638,8'h0a};
        68: REG_DATA={16'h3651,8'h9d}; 69: REG_DATA={16'h3670,8'h4b};
        70: REG_DATA={16'h3674,8'hc0}; 71: REG_DATA={16'h3675,8'h58};
        72: REG_DATA={16'h3676,8'h5a}; 73: REG_DATA={16'h367c,8'h18};
        74: REG_DATA={16'h367d,8'h38}; 75: REG_DATA={16'h3690,8'h43};
        76: REG_DATA={16'h3691,8'h53}; 77: REG_DATA={16'h3692,8'h53};
        78: REG_DATA={16'h3699,8'h08}; 79: REG_DATA={16'h369a,8'h10};
        80: REG_DATA={16'h369b,8'h1f}; 81: REG_DATA={16'h369c,8'h18};
        82: REG_DATA={16'h369d,8'h38}; 83: REG_DATA={16'h36a2,8'h08};
        84: REG_DATA={16'h36a3,8'h18}; 85: REG_DATA={16'h36a6,8'h08};
        86: REG_DATA={16'h36a7,8'h18}; 87: REG_DATA={16'h36ab,8'h40};
        88: REG_DATA={16'h36ac,8'h40}; 89: REG_DATA={16'h36ad,8'h40};
        90: REG_DATA={16'h3901,8'h00}; 91: REG_DATA={16'h3904,8'h0c};
        92: REG_DATA={16'h3906,8'h3a}; 93: REG_DATA={16'h391d,8'h14};
        94: REG_DATA={16'h3e00,8'h00}; 95: REG_DATA={16'h3e01,8'h7c};
        96: REG_DATA={16'h3e02,8'h60}; 97: REG_DATA={16'h4000,8'h00};
        98: REG_DATA={16'h4001,8'h04}; 99: REG_DATA={16'h4002,8'haa};
        100: REG_DATA={16'h4003,8'haa}; 101: REG_DATA={16'h4004,8'haa};
        102: REG_DATA={16'h4005,8'h00}; 103: REG_DATA={16'h4006,8'h07};
        104: REG_DATA={16'h4007,8'ha5}; 105: REG_DATA={16'h4008,8'h00};
        106: REG_DATA={16'h4009,8'hc8}; 107: REG_DATA={16'h440e,8'h02};
        108: REG_DATA={16'h4509,8'h28}; 109: REG_DATA={16'h4837,8'h42}; // 480Mbps/lane
        110: REG_DATA={16'h5000,8'h4e}; 111: REG_DATA={16'h5901,8'h04};
        // 720p60曝光时间较短，按已验证工程设置约4倍模拟增益。
        112: REG_DATA={16'h3e08,8'h0f}; 113: REG_DATA={16'h3e09,8'h20};
        114: REG_DATA={16'h0100,8'h01}; // stream on
        115: REG_DATA={16'h302d,8'h00}; // stream on后延时10ms
        default: REG_DATA={16'h0000,8'h00};
    endcase
end
endmodule
