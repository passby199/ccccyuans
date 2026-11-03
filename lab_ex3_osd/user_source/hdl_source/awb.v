/*****************************************************************
Company : MiLianKe Electronic Technology Co., Ltd.
WebSite:https://www.milianke.com
TechWeb:https://www.uisrc.com
tmall-shop:https://milianke.tmall.com
jd-shop:https://milianke.jd.com
taobao-shop: https://milianke.taobao.com
Description: 
The reference demo provided by Milianke is only used for learning. 
We cannot ensure that the demo itself is free of bugs, so users 
should be responsible for the technical problems and consequences
caused by the use of their own products.
@Author      :   XiaoQingquan 
@Time        :   2024/10 
version:     :   
@Description :   在原基础上删去了一些赘余的代码，并且优化了时序，加入BRAM IP核，
                 让从除法器出来的每一个数据都可以对上相应的像素数据进行增益，使
                 得它的适用行更加广泛了。
*****************************************************************/
module awb  #(   
    parameter IMG_HEIGHT = 1080,
    parameter IMG_WIDTH  = 1920,
    //-------------------------------------------------------------------------
    // 白平衡增益模式（2026-09-19 修订版 —— 重要更正）
    //
    //   ★★★ 先看这段历史，别再重复踩坑 ★★★
    //
    //   曾经这么改过（错）：
    //     直接旁路 AWB（增益强制 1.0）→ 结果「整体偏青蓝、暖色物体变灰白」。
    //     原因：AWB 有两个作用，只看到了一半——
    //       ① 拉平色彩：把整帧 R/B 均值拉到 G 均值，对偏暖场景会压红提蓝；
    //       ② 补偿传感器通道增益差：SC500 的 RAW 输出 R 通道天然比 G/B 低，
    //          实测需要 R 增益 ≈ 1.12、B 增益 ≈ 0.97 才能校回中性。
    //     直接旁路 = 把 ② 的补偿也一起关掉 → R 严重不足 → 整体偏青蓝。
    //
    //   现在的做法（对）：
    //     保留 AWB，但给增益【限幅】，限制 ① 的过度拉平，
    //     同时保住 ② 的通道补偿能力。
    //
    //-------------------------------------------------------------------------
    //   参数含义：
    //     AWB_GAIN_LIMIT = 0 → 不限幅（原始行为，会把暖色抹得太狠）
    //     AWB_GAIN_LIMIT = 1 → 限幅（当前使用），增益夹在
    //                          [GAIN_MIN_Q16, GAIN_MAX_Q16] 之间
    //     AWB_BYPASS     = 1 → 完全旁路（仅调试用，会偏青蓝，别烧板！）
    //
    //   ★ 为什么限幅能同时解决两个问题：
    //     偏暖场景下原始 AWB 会把 R 压到 0.85、B 提到 1.3 之类，
    //     限幅后这些极端值被夹住，暖色得以保留一部分；
    //     而传感器的固定通道差（R 需 1.12、B 需 0.97）在限幅范围内，
    //     所以补偿仍然有效。
    //-------------------------------------------------------------------------
    // ★★★ 2026-09-19 第三轮修订：AWB_STRENGTH 默认值改回 256 ★★★
    //
    //   ⚠️⚠️ 重要更正：第二轮「弱化 AWB 作用强度」的思路
    //        已被上板实测【否证】，不要再走这条路。⚠️⚠️
    //
    //   第二轮的推理（错在哪）：
    //     认为"灰世界 AWB 把冷色彩度抹平（仿真实测 -96%）"是主因，
    //     于是把校正量按比例弱化（STRENGTH=0.5）。
    //
    //   上板实测结果：
    //     用户反馈「有鲜艳的但很少，整体还是灰的」→ 进一步排查发现：
    //     · 照片彩度 top 0.1% = 89.7  → 通路完全能出鲜艳色，饱和度不是瓶颈
    //     · 色相分布：90% 的彩色像素都是青/蓝系，暖色仅 2.5%
    //     · R-B = -20  → 整画面被系统性染上青蓝
    //     · 反推需要的增益 kr=1.1121 / kb=0.9018 都很小（本来就该补上）
    //
    //   ★ 真正的根因：AWB 的增益【同时】承担两件事，
    //     弱化它等于把"通道补偿"也砍了：
    //       ① 补偿传感器通道差（SC500 RAW：R 天然低、B 天然高）— 必须保留
    //       ② 灰世界拉平色彩 — 副作用
    //     S=0.5 时 kr 只补了 5.6%（需要 11.2%）→ R 严重不足 → 偏青蓝。
    //
    //   ★ 数据证伪（同一帧，只改这一个参数）：
    //       配置         暖色占比   冷色占比   R-B
    //       S=0.50         3.1%      88.7%    -8.4
    //       S=1.00        49.3%      39.9%    -0.0
    //     → 暖色占比提升 16 倍！而饱和度参数完全没动。
    //
    //   ★ 另一个反直觉点（务必记住）：
    //     S=0.5 时平均彩度反而【更高】（49.7 vs 32.9）——
    //     因为它在放大"偏蓝的色差"，等于把错误放大。
    //     → **饱和度高 ≠ 颜色对。先修色相，再谈饱和度。**
    //
    //   ★ 职责边界（两者不重叠，别混用）：
    //       色相/白平衡问题  → AWB_STRENGTH_Q8 = 256（本模块）
    //       饱和度不足问题   → SAT_BOOST_Q4（gamma_correction.v）
    //
    //   本参数现在只用于【画面整体偏暖时微调】：
    //     256 = 1.00 ★ 默认（色相最准）
    //     224 = 0.875  略偏暖时可用
    //     192 = 0.75   画面明显偏红时可用
    //     128 = 0.50   ✗ 实测导致暖色占比只剩 3%，禁止使用
    //       0 = 0      等于旁路（偏青蓝，更糟）
    //
    //   ★ 实现方式：只在【乘数】上做加权，寄存器级数不变，
    //     de/tuser 对齐、时序完全不受影响。
    //-------------------------------------------------------------------------
    parameter integer AWB_BYPASS     = 0,      // 1 = 完全旁路（危险，仅调试）
    parameter integer AWB_GAIN_LIMIT = 1,      // 1 = 启用增益限幅（推荐）
    // 增益上下限，Q16 定点（1.0 = 0x10000 = 65536）
    //   0.80 = 52429 (0x0CCCD)
    //   1.50 = 98304 (0x18000)
    //
    //   ★ 2026-09-19 第六轮：白点标定后，kb 由灰世界的 1.633 降到 1.008，
    //     kr 由 1.215 降到 1.118 —— 增益全部落在 [0.80, 1.50] 内，
    //     所以【不再需要放宽限幅】，恢复 0.80/1.50 这组保守值。
    //     （第五轮曾放宽到 0.55/2.00 是为了绕过灰世界算出的极端 kb=1.633，
    //       那是【治标】；本轮改白点标定是【治本】，限幅可以收回。）
    //
    //   ★★★ 2026-09-20 续21：GAIN_MAX 1.50 → 2.00（上限放宽）★★★
    //
    //     【为什么又放宽 —— 新的实测证据】
    //       用「实物魔方 vs 屏幕显示」配对实验（同一手机拍）：
    //         通道最大值归属   实物照 →  屏幕照
    //           R 是最大值      9.32%  →  1.14%   ★ 掉 8.2 倍
    //           G 是最大值     31.74%  → 71.93%   ★ 涨到 71.9%
    //           B 是最大值     54.65%  → 27.82%
    //         白纸 R/G        0.9310  →  0.8632   （屏幕比实物低 7%）
    //
    //       → R 通道存在【系统性偏弱】，不是场景问题。
    //         红色块在屏幕上「饱和上不去」（S>0.25 时无红像素）。
    //
    //     【本次只放宽上限，不碰算法】
    //       白点判据已收紧到 500/30，取到的像素很白（自身 R/G=0.9679），
    //       算出的 kr≈1.033 —— 看似远小于 1.50，理论上不该被限幅卡住。
    //       但【实测 R 就是偏弱】。所以先做最安全的一步：
    //       把上限放宽到 2.00，排除「AWB 想给更大 R 增益但被 1.50 夹住」。
    //       ★ 这一步不会让画面失控：白点判据 500/30 只取真白像素，
    //         且 AWB_SMOOTH_Q2 平滑 + GAIN_LIMIT 仍在，最多到 2.00。
    //
    //     【若放宽后仍无改善】→ 说明不是限幅问题，转向 BAYER_MODE 相位
    //       （相位错会同时打击 R/B、保留 G —— 与「G 占 71.93%」高度吻合）。
    parameter [19:0]  GAIN_MIN_Q16   = 20'd52429,   // 0.80
    // ★★★ 2026-09-20 第八轮：GAIN_MAX 2.00 → 1.15 ★★★
    //   配合 WHITE_POINT_MODE 改回 0（灰世界），把上限从 1.50/2.00 收到 1.15。
    //   理由：灰世界在低饱和场景算出的 kr = 1.09~1.14（实测四场景），
    //         收到 1.15 不会卡住这些场景（完全复现 V8 的不偏绿），
    //         而在全绿等鲜艳场景 kr 会冲到 1.99，此时被 1.15 卡住 → 提供保护。
    //   注意：本参数只是【模块默认值】，实际生效值由 isp_top.v 的例化覆盖。
    parameter [19:0]  GAIN_MAX_Q16   = 20'd75366,   // ★ 1.15（第八轮）
    // AWB 作用强度，Q8 定点（256 = 1.0 = 完全采用 AWB 的校正量）
    //
    //   ★★★ 2026-09-19 重要：默认值必须是 256（全强度）！★★★
    //
    //   踩坑记录：曾把默认值设成 128（0.5），以为"弱化 AWB 能保住彩度"。
    //   实测结果相反 —— AWB 的增益【同时】承担两件事：
    //       ① 补偿传感器通道差（R 天然低、B 天然高）—— 必须保留
    //       ② 灰世界拉平色彩 —— 副作用
    //   砍半等于把 ① 也砍了 → R 提不够、B 压不够 → 整画面偏青蓝
    //     → 用户反馈「只有灰色，别的颜色凑近看也是灰的」
    //
    //   数据实证（照片反推，逐级建模）：
    //      需要的  kr=1.1121 / kb=0.9018
    //      S=128   kr=1.0560 / kb=0.9509  → R-B 残留 -8.4（偏冷）
    //      S=256   kr=1.1121 / kb=0.9018  → R-B = 0.0（中性）
    //      色相分布：暖色占比  3.1%（S=128） →  49.3%（S=256）
    //
    //   → **色相/白平衡问题用 256 解决；饱和度问题用 SAT_BOOST 解决，
    //     两者职责不重叠，不要用本参数去"保彩度"。**
    //
    //   参数含义（Q8 定点，256 = 1.0）：
    //     256 = 1.00 ★ 默认/推荐（色相最准）
    //     224 = 0.875  画面偏暖时可用
    //     192 = 0.75   轻微弱化
    //     128 = 0.50   ✗ 实测导致暖色占比只剩 3%，别用
    //       0 = 0      等于旁路（偏青蓝，更糟）
    parameter [9:0]   AWB_STRENGTH_Q8 = 10'd256,    // ★ 1.00 = 全强度
    //=========================================================================
    // ★★★ 2026-09-19 第六轮：白点标定（WHITE_POINT_MODE）★★★
    //
    //   【问题 —— 魔方测试暴露的根本矛盾】
    //     用实物魔方（已知标准色）做标靶，对比"实物照片"与"屏幕输出"：
    //       实物魔方: 7 个分明色相（红/黄/绿/青），色差动态范围 R-G std=73、B-G std=60
    //       屏幕输出: 色相挤在 195-210°（青蓝），色差动态范围 R-G std=24、B-G std=17（损失 2/3）
    //       关键症状: B 通道均值 117(实物) → 170(屏幕)，+53 LSB
    //                 B-G 由 -45.45(实物) → +7.60(屏幕) ★ 符号翻转！
    //       色块跟踪: 红块 (225,99,104)Hue289° → (154,177,206)Hue213° 红变青蓝
    //                 黄块 (156,216,94)Hue94°  → (184,225,215)Hue155° 黄变青
    //
    //   【根因 —— 灰世界假设在鲜艳场景下必然犯错】
    //     原 AWB 用【全画面均值】做灰世界：kr=G_mean/R_mean、kb=G_mean/B_mean
    //     魔方场景里大量黄绿（G 高、B 低）→ 场景均值 R/G=0.82、B/G=0.61
    //     → AWB 忠实执行灰世界，算出 kr=1.215、kb=1.633
    //     → 【把 B 放大 63%】！黄绿被"洗"成青蓝
    //
    //     ★ 这不是 bug，是灰世界的固有局限：
    //       灰世界让【平均色】变灰，但鲜艳场景本来就不是灰的。
    //       → AWB 越"准确"，彩色物体越失真。
    //
    //   【数值实证 —— 四种策略在魔方场景下的色相偏差】
    //       全强度灰世界 (1.215/1.633)  色相偏差 24.73°  饱和保持 0.855x
    //       弱化灰世界 0.75             色相偏差 18.53°  饱和保持 0.854x
    //       完全旁路     (1.0/1.0)      色相偏差  0.14°  饱和保持 0.874x
    //       ★ 白点标定   (1.118/1.008)  色相偏差  3.81°  饱和保持 0.909x
    //
    //     → 旁路能保色相，但【丢掉了传感器通道补偿】（历史上 v3 旁路失败的原因）。
    //     → 白点标定兼顾两者：色相几乎不偏（3.81°）且饱和保持最好（0.909x）。
    //
    //   【原理 —— 白点标定 vs 灰世界】
    //     灰世界：假设"整幅画面的平均色是灰"    → 鲜艳场景必错
    //     白点  ：假设"画面里最亮的那些像素是白" → 只校准真正的白点
    //
    //     实现：只统计【三通道都足够亮 且 彩度足够低】的像素（即"近白像素"）。
    //     这样白色物体依然被校准成白色（传感器通道补偿保留），
    //     而彩色物体【完全不参与统计】→ 不被干扰。
    //
    //   【实测数据支撑（魔方照片）】
    //     近白像素占 22.45%（桌面/显示器边框为灰白）
    //     近白像素均值 R=166.9 G=186.5 B=185.1  → kr=1.118、kb=1.008
    //     ★ kb 由灰世界的 1.633 降到 1.008 —— 几乎不干扰 B 通道！
    //
    //   【时序零风险】
    //     只改【累加条件的判断逻辑】，不增删任何流水线寄存器级数。
    //     → 与 de/tuser 的对齐关系完全不变。
    //
    //   【参数】
    //     WHITE_POINT_MODE = 0 → 退回原灰世界（对照/回滚用）
    //     WHITE_POINT_MODE = 1 → ★ 白点标定（推荐）
    //     WP_SUM_MIN       → 近白判据：R+G+B 的最小值（越低越宽松）
    //     WP_CHROMA_MAX    → 近白判据：max(R,G,B)-min(R,G,B) 的上限
    //=========================================================================
    parameter integer WHITE_POINT_MODE = 1,      // ★ 1 = 白点标定（推荐）, 0 = 灰世界
    //-------------------------------------------------------------------------
    // ★★★ 2026-09-20 第七轮：白点判据收紧 + 帧级统计 + 增益时域平滑 ★★★
    //
    //   【上板反馈的两个现象】
    //     ① 「白桌子显不出来颜色」
    //     ② 「画面会有蓝色阴影」
    //
    //   【照片实测数据】（工作目录 _shot_1036.jpg / _shot_1123.jpg）
    //     白桌场景: 白色区(V>=0.55 & chroma<=40) 占 61.4%，R-B = −20.0（偏蓝）
    //               低饱和像素(S<0.20) 占 74.4% → 眼神所及大半是灰白
    //     暗部 V<0.15: R=13.2 G=23.3 B=24.9 → R/G=0.569（亮部 0.854，★塌陷 33%）
    //     亮部 V>0.75: R=172.7 G=202.3 B=204.0 → R/G=0.854  B/G=1.009
    //     ★ B/G 各档只差 ±6%，而 R/G 差 33% → 问题在 R，不是 B
    //
    //   【根因一：白点判据 WP_CHROMA_MAX=60 太宽松 —— 收进了"假白"】
    //     V>=0.55 的浅色像素彩度 max-min 中位只有 29、p75=36，
    //     WP_CHROMA_MAX=60 一次性通过 67.5% 的像素。
    //     被收进来的这些"浅色"，实测 R/G=0.891（明显偏蓝），
    //     于是算出的白点增益 kr=1.1219 / kb=0.9732 是按"偏蓝的假白"算的。
    //     → 收紧到 30（只取真白），kr 会回到 ~1.05 附近。
    //
    //   【根因二：累加器在 I_tuser（行开始）复位 —— 每行一个增益】
    //     I_tuser 由 zhenghe.v 的 `O_tuser = (x_cnt==...) && (y_cnt==0)` 生成，
    //     是【行开始】标记（每行一次），不是帧开始。
    //     于是 AWB 每行独立统计 + 独立算增益，行内仅 320 个采样点（1280/4）。
    //     实测行间波动：kr 1.0326~1.2425（★ 0.210）、kb 0.8750~1.0912（★ 0.216）
    //       → 同一物体跨行颜色不停变，视觉上被平均成灰（"显不出颜色"的帮凶）
    //       → 并且产生【横向色带】
    //
    //   【根因三：暗部 R 塌陷 + 全局增益不匹配】
    //     暗部 R/G=0.569 vs 亮部 0.854。AWB 是【乘法】的，乘同一个 kr
    //     不改变 R/G → 塌陷发生在 RAW 域（Bayer R 只占 1/4 像素 + 暗部 SNR 差）。
    //     而 AWB 用亮部白点算出的单一增益对暗部完全不匹配
    //     → 暗部被推成蓝青（"蓝色阴影"）。
    //     ★ 注：黑电平未扣（BLC 未例化）经数值验证【不是】蓝阴影成因，
    //       它反而会压缩通道差（R/G 往 1.0 拉）；扣掉后暗部会更蓝。
    //       → 所以本轮不动 BLC。
    //
    //   【本轮对策】
    //     A. 白点判据收紧：WP_SUM_MIN 450→500、WP_CHROMA_MAX 60→30
    //     B. 帧级统计：row_cnt 找出每帧首行，帧首锁存 hold_* 并清零 sum_*，
    //        sum_* 在整帧内持续累加（不再逐行复位）
    //        → 增益从"每行变"变成"每帧变"，行间波动归零
    //     C. 增益时域平滑：new = (old*3 + calc) / 4
    //        → 帧间残留的小抖动也被压掉（Q16 域，纯移位/加法，无除法器）
    //
    //   【★ 时序零风险保证】
    //     A 只改比较常数（组合逻辑），B/C 是对【已有 done[0] 时刻】的增益值
    //     做锁存与滤波 —— 不增删任何流水线寄存器级数，
    //     与 signal_delay(50拍) 的对齐关系完全不变。
    //
    //   【判据取值对照（照片实测，白桌场景 _shot_1036.jpg）】
    //     WP_SUM_MIN / WP_CHROMA_MAX   通过率    取样像素自身R/G   算出kr   算出kb
    //     450 / 60（旧）               49.23%    0.8913          1.1219   0.9732
    //     500 / 30（★新）              11.32%    0.9679          1.0332   0.9365
    //     560 / 60                     12.50%    0.8477          1.1800   1.0006
    //     640 / 不限                    2.30%    0.8282          1.2075   1.0157
    //
    //   ★ 判读：判据越严，取到的像素越白（R/G 越接近 1.0），算出的 kr 越小
    //     （对彩色物体破坏越小）。但取样像素自身的 B/G 反而更高
    //     （新判据 1.0678 vs 旧 1.0276）→ kb 更小（压 B 更多）。
    //     ★ 这是正确的：把偏冷的"白"校成中性本来就是 AWB 的职责。
    //       若上板后觉得画面【偏暖/发黄】→ WP_CHROMA_MAX 回到 40；
    //       若觉得【还偏蓝】        → WP_CHROMA_MAX 降到 20。
    //-------------------------------------------------------------------------
    parameter [9:0]   WP_SUM_MIN     = 10'd500,  // ★ 收紧：R+G+B >= 500（均值>=167）
    parameter [9:0]   WP_CHROMA_MAX  = 10'd30,   // ★ 收紧：彩度 <= 30（只取真白）
    // 增益时域平滑系数，Q2 定点（4 = 1.0 = 不平滑）
    //   1 = 每次只走 1/4 → 最平滑（推荐）
    //   2 = 走 1/2
    //   0 = 不平滑（退回逐帧直接生效）
    //   ★ 收敛实测（目标 1.0000→1.1500，Q2=1）：
    //       第1帧 1.0750  第3帧 1.1312  第5帧 1.1453  第10帧 1.1499
    //     → 约 10 帧（0.17 秒）收敛，够快且把帧间抖动压掉 4 倍
    parameter [2:0]   AWB_SMOOTH_Q2  = 3'd1       // ★ 1 = 新值占 1/4
)
(
    input                   I_clk  ,
    input                   I_rst_n,


    input                   I_tlast  ,
    input                   I_tuser  ,
    input [95:0]            I_tdata  ,
    input                   I_tvalid , 
    output                  I_tready ,

    output                  O_tlast  ,
    output                  O_tuser  ,
    output [95:0]           O_tdata  ,
    output                  O_tvalid ,
    input                   O_tready
);

/*****************************************************************
                          RGB565תRGB888                                        
*****************************************************************/

    // //RGB565??????888
    // wire [4:0]  rgb565_r   = I_st_data[11+:5];
    // wire [5:0]  rgb565_g   = I_st_data[5+:6];
    // wire [4:0]  rgb565_b   = I_st_data[0+:5];
    
    // wire [23:0] rgb888     = {{rgb565_r[4:0],rgb565_r[2:0]},{rgb565_g[5:0],rgb565_g[1:0]},{rgb565_b[4:0],rgb565_b[2:0]}};
    
    // wire [7:0]  rgb888_r   = rgb888[16+:8];
    // wire [7:0]  rgb888_g   = rgb888[8+:8] ;
    // wire [7:0]  rgb888_b   = rgb888[0+:8] ;
    
  /*****************************************************************
                          中间信号                                        
*****************************************************************/


  reg         I_tvalid_r0,I_tvalid_r1;
  reg  [95:0] I_tdata_d0,I_tdata_d1;


  //累加RGB通道的�??
  reg  [31:0]         sum_r[0:3];
  reg  [31:0]         sum_g[0:3];
  reg  [31:0]         sum_b[0:3];

  
  wire  [95:0]        data_d0 ;
  wire                valid_d0;
  wire                I_tuser_r0;    

  reg                 I_tuser_r1;

  reg   [95:0]        data_d1 ;
  reg                 valid_d1;
  reg   [9:0]         rgb_sum[0:3];//每个像素点RGB的和
  /*****************************************************************
                            平均值计�??                                      
*****************************************************************/

// 对输入数据和有效信号进行寄存，形成流水线
always @(posedge I_clk or negedge I_rst_n) begin
    if (!I_rst_n) begin
        I_tdata_d0  <= 0;
        I_tdata_d1  <= 0;
        {I_tvalid_r0,I_tvalid_r1} <= 0;
    end else begin
        I_tdata_d0  <= I_tdata   ;
        I_tdata_d1  <= I_tdata_d0;
        I_tvalid_r0 <= I_tvalid;
        I_tvalid_r1 <= I_tvalid_r0;
    end
end

// 将输入数据拆分为4个像素的RGB分量
wire [7:0] rgb888_r_d[0:3];
wire [7:0] rgb888_g_d[0:3];
wire [7:0] rgb888_b_d[0:3];

assign  rgb888_r_d[0] = I_tdata[16+:8];
assign  rgb888_g_d[0] = I_tdata[8+:8];
assign  rgb888_b_d[0] = I_tdata[0+:8];


// 将输入数据拆分为4个像素的RGB分量
wire [7:0] rgb888_r_d0[0:3];
wire [7:0] rgb888_g_d0[0:3];
wire [7:0] rgb888_b_d0[0:3];

assign  rgb888_r_d0[0] = I_tdata_d0[16+:8];
assign  rgb888_g_d0[0] = I_tdata_d0[8+:8];
assign  rgb888_b_d0[0] = I_tdata_d0[0+:8];


        ///削弱白色
        always @(posedge I_clk or negedge I_rst_n) begin
            if(!I_rst_n) begin
                rgb_sum[0] <= 0;
            end
            else if(I_tvalid)begin
                rgb_sum[0] <= rgb888_r_d[0] + rgb888_g_d[0] + rgb888_b_d[0];
            end
        end

        //-------------------------------------------------------------------------
        // ★★★ 白点判据（2026-09-19 第六轮新增）
        //
        //   近白像素 = 三通道都足够亮 且 彩度足够低
        //     · wp_sum    = R+G+B >= WP_SUM_MIN     （足够亮）
        //     · wp_chroma = max(R,G,B) - min(R,G,B) <= WP_CHROMA_MAX（足够灰）
        //
        //   ★ 为什么要"足够亮"：暗部噪声大，色偏无意义，统计进来会污染增益
        //   ★ 为什么要"足够灰"：彩色像素若参与统计，就等于回到灰世界的老问题
        //
        //   ★ 时序：纯组合逻辑，与 rgb_sum 同拍（都基于 rgb888_*_d0[0]），
        //     下游 sum_* 在下一拍使用它 → 不存在额外延迟。
        //-------------------------------------------------------------------------
        wire [9:0] s_wp_sum = {2'b00, rgb888_r_d0[0]} + {2'b00, rgb888_g_d0[0]}
                            + {2'b00, rgb888_b_d0[0]};
        wire [7:0] s_wp_max = (rgb888_r_d0[0] > rgb888_g_d0[0])
                            ? ((rgb888_r_d0[0] > rgb888_b_d0[0]) ? rgb888_r_d0[0] : rgb888_b_d0[0])
                            : ((rgb888_g_d0[0] > rgb888_b_d0[0]) ? rgb888_g_d0[0] : rgb888_b_d0[0]);
        wire [7:0] s_wp_min = (rgb888_r_d0[0] < rgb888_g_d0[0])
                            ? ((rgb888_r_d0[0] < rgb888_b_d0[0]) ? rgb888_r_d0[0] : rgb888_b_d0[0])
                            : ((rgb888_g_d0[0] < rgb888_b_d0[0]) ? rgb888_g_d0[0] : rgb888_b_d0[0]);
        wire [7:0] s_wp_chroma = s_wp_max - s_wp_min;

        // 综合判据：白点模式启用时用近白门限，否则恒为 1（= 原灰世界行为）
        wire s_is_whitepoint = (WHITE_POINT_MODE == 0)
                             ? 1'b1
                             : ((s_wp_sum >= WP_SUM_MIN) && (s_wp_chroma <= WP_CHROMA_MAX));

        //-------------------------------------------------------------------------
        // ★★★ 帧级统计（2026-09-20 第七轮新增）★★★
        //
        //   问题：I_tuser 是【行开始】（zhenghe.v: O_tuser = (x_cnt==..) && (y_cnt==0)），
        //         原累加器在 I_tuser 复位 → 每行独立算增益 → 行间波动 0.21
        //
        //   ★★ 正确的帧级统计做法（三段式，务必理解时序）：
        //
        //     1) sum_* 改成【整帧累加】：不再在 I_tuser 复位，
        //        而是由一个"行开始且本帧已积累足够行"的脉冲 s_frame_start 清零。
        //        这样 sum_* 就累积了【整帧所有近白像素】。
        //
        //     2) s_frame_start 出现时（= 新一帧的首行开始），
        //        先把【上一帧的整帧结果】锁存到 hold_*，供本帧使用；
        //        然后再把 sum_* 清零，开始累积本帧。
        //        ★ 顺序很重要：hold_* 必须读【清零之前】的 sum_*。
        //          由于两者都是时序逻辑、同一拍更新：
        //            hold_* <= sum_*[0]   （读到的是清零前的值 ✓）
        //            sum_*  <= 1          （同时清零）
        //          在同一 always 块里写，Verilog 语义保证 RHS 用的是旧值 ✓
        //
        //     3) hold_* 初值 = 1（不是 0），配合分母 sum 至少为 1，
        //        除法器不会除零；首帧未锁存时 kr=kb=1.0 → 直通，绝不炸。
        //
        //   ★ 为什么 row_cnt >= 2：I_tuser 是每行一个，需要区分"帧首"与"行首"。
        //     行内 tvalid 递增 row_cnt，行开始时清 0。
        //     帧首行与上一帧末行之间只隔几个周期，
        //     若某拍 row_cnt 已累积 >= 2 又来 I_tuser，说明是【新帧首行】。
        //     （单行至少 320 拍，>=2 是极宽松的判据，不会误判）
        //-------------------------------------------------------------------------
        reg [15:0] row_cnt;

        always @(posedge I_clk or negedge I_rst_n) begin
            if (!I_rst_n)
                row_cnt <= 0;
            else if (I_tuser)
                row_cnt <= 0;
            else if (I_tvalid_r0)
                row_cnt <= row_cnt + 1'b1;
        end

        // 帧首判定：I_tuser 且本帧已积累足够行 → 说明这是新一帧（非行首）
        // ★ 第八轮：阈值 2 → 100，更鲁棒。
        //   原值 2 太敏感：若某行 tvalid 不足 2 拍（行末缺数据），该帧首会被漏判
        //   → 那一帧沿用旧 hold_* → 增益不更新 → 帧间不一致 → 明暗闪烁。
        //   一行有 320 个采样点（1280/4），取 100（约 1/3 行）既不会误判行首
        //   （行首 row_cnt 刚清零为 0），也不会漏判帧首。
        wire s_frame_start = I_tuser && (row_cnt >= 16'd100);

        // 整帧统计结果保持寄存器：帧首锁存，整帧沿用
        reg [31:0] hold_r, hold_g, hold_b;

        always @(posedge I_clk or negedge I_rst_n) begin
            if (!I_rst_n) begin
                hold_r <= 1;
                hold_g <= 1;
                hold_b <= 1;
            end
            else if (s_frame_start) begin
                // 锁存上一帧的整帧统计结果（此时 sum_* 尚未清零 ✓）
                hold_r <= sum_r[0];
                hold_g <= sum_g[0];
                hold_b <= sum_b[0];
            end
        end


        // 对每个通道的值进行累加，用于计算平均值
        // ★★★ 2026-09-20 第七轮：改为【整帧累加】★★★
        //   · 旧行为：`if (!I_rst_n || I_tuser)` 每行复位 → 只统计一行
        //   · 新行为：只在【帧首】(s_frame_start) 清零 → 累积整帧
        //   ★ 复位条件里【不再有 I_tuser】！这是帧级统计的关键。
        always @(posedge I_clk or negedge I_rst_n) begin
            if (!I_rst_n) begin
                // 硬复位：清零累加器
                sum_r[0] <= 1;
                sum_g[0] <= 1;
                sum_b[0] <= 1;
            end
            // ★ 帧首：清零，开始累积新一帧
            //   （注意：hold_* 在同一拍读走的是清零前的旧值 → 先锁存后清零 ✓）
            else if (s_frame_start) begin
                sum_r[0] <= 1;
                sum_g[0] <= 1;
                sum_b[0] <= 1;
            end
            // 正常累加近白像素（整帧累计）
            else if (I_tvalid_r0 && s_is_whitepoint) begin
                // 当输入有效时，累加RGB分量的值
                sum_r[0] <= sum_r[0] + rgb888_r_d0[0];
                sum_g[0] <= sum_g[0] + rgb888_g_d0[0];
                sum_b[0] <= sum_b[0] + rgb888_b_d0[0];
            end
        end

  /*****************************************************************
                           计算增益                                       
*****************************************************************/

  wire [47:0] dout_R[3:0];
  wire [47:0] dout_B[3:0];

  wire done[3:0];

  wire [47:0] in_r_x1;
  wire [47:0] in_b_x1;
  assign in_r_x1 = dout_R[0][47:0];
  assign in_b_x1 = dout_B[0][47:0];



/*****************************************************************
                   IP 调用                                    
*****************************************************************/
    //为了保证合理的延迟，这里使用了除法器

      divider div_gen_G_R_r1 (
          .clk(I_clk),  // input wire aclk
          .rst(!I_rst_n),
          .start(I_tvalid_r1),
          // ★ 2026-09-20 第七轮：分母/分子改用帧级锁存值 hold_*，
          //   使整帧共享同一组统计 → 增益不再逐行变化。
          .denominator(hold_r),  // input wire [31 : 0] s_axis_divisor_tdata
          .numerator({hold_g,16'd0}),  // input wire [47 : 0] s_axis_dividend_tdata
          .quotient(dout_R[0]),  // output wire [79 : 0] m_axis_dout_tdata
          .done(done[0])
      );

      divider divide_G_B_r1 (
          .clk(I_clk),  // input wire aclk
          .rst(!I_rst_n),
          .start(I_tvalid_r1),
          .denominator(hold_b),  // input wire [31 : 0] s_axis_divisor_tdata
          .numerator({hold_g,16'd0}),  // input wire [47 : 0] s_axis_dividend_tdata
          .quotient(dout_B[0]),  // output wire [79 : 0] m_axis_dout_tdata
          .done()
      );

     
    signal_delay #(
        .IMG_HEIGHT   (IMG_HEIGHT),
        .IMG_WIDTH    (IMG_WIDTH ),
        .DATA_WIDTH   (96  ),
        .DELAY_CYCLE  (50)
    )signal_delay_d (
        /*input                       */ .I_clk  (I_clk  ),
        /*input                       */ .I_rst_n(I_rst_n),
        /*input                       */ .I_tuser(I_tuser),  //synthesis keep 
        /*input  wire                 */ .I_valid(I_tvalid_r1),  //synthesis keep 
        /*input  wire [DATA_WIDTH-1:0]*/ .I_data (I_tdata_d1 ),   //synthesis keep 
        /*output wire                 */ .O_valid(valid_d0   ),  //synthesis keep 
        /*output wire [DATA_WIDTH-1:0]*/ .O_data (data_d0    ),   //synthesis keep 
        /*output wire                 */ .O_tuser(I_tuser_r0 )
    );

    

/*****************************************************************
                            ��������                                      
*****************************************************************/

    reg  [19:0]   in_r_r1;
    reg  [19:0]   in_b_r1;

    //-------------------------------------------------------------------------
    // 增益限幅函数（2026-09-19 新增）
    //   把 AWB 算出的增益夹在 [GAIN_MIN_Q16, GAIN_MAX_Q16] 区间内。
    //   ★ 为什么必须限幅：
    //     原始 AWB 对偏暖场景会产生 R 增益 0.85（压红）、B 增益 1.3（提蓝）
    //     这类极端值，把暖色抹掉。限幅后极端值被夹住，暖色得以保留；
    //     而传感器固定的通道差（R 需 ~1.12、B 需 ~0.97）在限幅区间内，
    //     所以通道补偿能力不受影响。
    //   ★ 限幅只改【乘数】，不改寄存器级数 → 时序与 de/tuser 对齐零风险。
    //-------------------------------------------------------------------------
    function [19:0] limit_gain;
        input [19:0] g;
        begin
            if (g < GAIN_MIN_Q16)
                limit_gain = GAIN_MIN_Q16;
            else if (g > GAIN_MAX_Q16)
                limit_gain = GAIN_MAX_Q16;
            else
                limit_gain = g;
        end
    endfunction

    //-------------------------------------------------------------------------
    // ★ 作用强度加权（2026-09-19 第二轮新增）
    //
    //   apply_strength(g):
    //       out = 1.0 + (g - 1.0) * (AWB_STRENGTH_Q8 / 256)
    //
    //   定点推导（全部 Q16，1.0 = 65536）：
    //       g      : 20bit，Q16，量程约 [0, 16) 实际 [0.8, 1.5]
    //       S      : AWB_STRENGTH_Q8，10bit，256 = 1.0
    //       step   = g - 65536              (signed，可正可负)
    //       out    = 65536 + step * S / 256
    //
    //   实现要点（★ 关键，别写错）：
    //     1. step 必须先扩展成 signed 再乘，否则 g<1.0 时的负数会被
    //        当成大正数（Verilog 中 unsigned 参与运算的默认规则）。
    //     2. 用 signed 中间量 s_step / s_prod，且显式用 $signed() 转换。
    //     3. 结果再夹回 [GAIN_MIN_Q16, GAIN_MAX_Q16]：
    //        加权后一般更靠近 1.0，所以不会越界，
    //        但保险起见仍调用 limit_gain。
    //     4. 纯组合逻辑，不增加寄存器级数 → 时序零风险。
    //-------------------------------------------------------------------------
    function [19:0] apply_strength;
        input [19:0] g;
        reg signed [21:0] s_step;
        reg signed [31:0] s_prod;
        reg signed [31:0] s_out;
        begin
            // 1. 求偏移量（signed）
            s_step = $signed({2'b00, g}) - 32'sd65536;   // = g - 1.0(Q16)

            // 2. 乘强度系数（Q8）
            s_prod = s_step * $signed({22'b0, AWB_STRENGTH_Q8});

            // 3. 除 256 并加回 1.0
            s_out = 32'sd65536 + (s_prod >>> 8);

            // 4. 负值保护 + 限幅
            if (s_out < 32'sd0)
                apply_strength = GAIN_MIN_Q16;
            else if (s_out > 32'sd1048575)          // 超出 20bit 可表示范围
                apply_strength = GAIN_MAX_Q16;
            else
                apply_strength = limit_gain(s_out[19:0]);
        end
    endfunction

    //-------------------------------------------------------------------------
    // ★★★ 增益更新 + 时域平滑（2026-09-20 第七轮）★★★
    //
    //   ★★ 关键改动：原代码是 `if(!I_rst_n || I_tuser)` —— 把增益在【每行开始】
    //      都重置成 1.0！这就是"每行一个增益"的最后一块拼图：
    //      · 累加器在 I_tuser 复位 → 每行独立统计
    //      · 增益也在 I_tuser 复位 → 每行重新从 1.0 开始爬
    //      → 行间波动 0.21，画面产生横向色带。
    //
    //   现在改为【只在 !I_rst_n 复位】，I_tuser 不复位增益。
    //   配合上面 hold_* 的帧级统计，整帧共享同一组增益。
    //
    //   时域平滑（Q16 域，纯位移+加法，不引入除法器）：
    //       new = old + (calc - old) / SMOOTH_DIV
    //   其中 SMOOTH_DIV = 2^AWB_SMOOTH_Q2（Q2=1 → 除 4 → 新值占 1/4）
    //   → 帧间残留抖动被压掉，且仍能跟随场景缓慢变化。
    //   ★ 为兼容 g < 1.0（signed），全部用 signed 中间量。
    //-------------------------------------------------------------------------
    // 平滑函数
    function [19:0] smooth_gain;
        input [19:0] g_new;      // 本帧算出的目标增益（已限幅+已加权）
        input [19:0] g_old;      // 当前生效的增益
        reg signed [21:0] s_diff;
        reg signed [21:0] s_step;
        reg signed [21:0] s_res;
        begin
            s_diff = $signed({2'b00, g_new}) - $signed({2'b00, g_old});
            // 除以 2^AWB_SMOOTH_Q2（算术右移，保留符号）
            // AWB_SMOOTH_Q2 = 0 时除数=1 → 直接取新值（不平滑）
            if (AWB_SMOOTH_Q2 == 0)
                s_step = s_diff;
            else
                s_step = s_diff >>> AWB_SMOOTH_Q2;
            s_res = $signed({2'b00, g_old}) + s_step;
            // 负值保护
            if (s_res < 22'sd0)
                smooth_gain = 20'd0;
            else
                smooth_gain = s_res[19:0];
        end
    endfunction

    // 本帧目标增益（组合）
    wire [19:0] w_target_r = (|in_r_x1[47:20]) ? 20'hfffff :
                             ((AWB_GAIN_LIMIT != 0) ? apply_strength(limit_gain(in_r_x1[19:0]))
                                                    : apply_strength(in_r_x1[19:0]));
    wire [19:0] w_target_b = (|in_b_x1[47:20]) ? 20'hfffff :
                             ((AWB_GAIN_LIMIT != 0) ? apply_strength(limit_gain(in_b_x1[19:0]))
                                                    : apply_strength(in_b_x1[19:0]));

    //=========================================================================
    // ★★★ 2026-09-20 第八轮：增益【每帧只更新一次】★★★
    //
    //   【问题】上板反馈「有光的地方周围一直抖动 / 整块区域明暗闪烁」。
    //
    //   【根因】除法器的 start 接的是 I_tvalid_r1 —— 这是【每行】都有效的信号。
    //     于是 done[0] 每行脉冲一次，smooth_gain 每行被调用一次：
    //       720 行/帧 × 每次走 1/4 步长
    //       → 帧内几行就收敛到目标（Q2=1 只需 10 行）
    //       → 时域平滑【形同虚设】，只平滑了帧内，帧间目标一变就整块跳过去
    //     视觉表现：帧交界处【一条横线以上的区域突然变亮/变暗】= 明暗闪烁。
    //
    //   【做法】加一个「本帧已更新过」标志 s_gain_upd：
    //     · s_frame_start（帧首）清零 → 新一帧允许更新
    //     · done[0] && !s_gain_upd 时更新增益，并把 s_gain_upd 置 1
    //     → 效果：每帧只更新一次，帧内增益恒定 → 帧间平滑过渡，彻底消除跳变
    //
    //   【位宽/时序安全】
    //     · s_gain_upd 是 1bit 标志，无位宽风险
    //     · s_frame_start 与 done[0] 都在 I_clk 域，无跨时钟问题
    //     · 帧首清零与增益更新不在同一拍（除法器有 ~50 拍延迟），
    //       所以 s_frame_start 清 0 后，本帧第一次 done[0] 才会更新 ✓
    //     · 若某帧除法器从未 done（异常情况），该帧沿用上一帧增益 → 不变暗不炸
    //=========================================================================
    reg s_gain_upd;   // 本帧是否已经更新过增益

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n)
            s_gain_upd <= 1'b0;
        else if (s_frame_start)
            s_gain_upd <= 1'b0;      // 帧首清零 → 允许本帧更新一次
        else if (done[0] && !s_gain_upd)
            s_gain_upd <= 1'b1;      // 本帧已更新 → 后续 done 不再更新
    end

    always @(posedge I_clk or negedge I_rst_n)begin 
        if(!I_rst_n)begin
            // ★ 只在硬复位时归 1.0；I_tuser 不再复位！
            in_r_r1 <= 20'h10000;
            in_b_r1 <= 20'h10000;
        end
        // ★ 第八轮：从 `done[0]` 改为 `done[0] && !s_gain_upd`
        //   → 每帧只更新一次增益，帧内恒定，消除帧间明暗闪烁
        else if(done[0] && !s_gain_upd)begin
            if (AWB_BYPASS != 0) begin
                // 完全旁路（仅调试用，会导致整体偏青蓝，别烧板）
                in_r_r1 <= 20'h10000;
                in_b_r1 <= 20'h10000;
            end
            else begin
                // ★ 时域平滑：向目标增益缓慢逼近
                in_r_r1 <= smooth_gain(w_target_r, in_r_r1);
                in_b_r1 <= smooth_gain(w_target_b, in_b_r1);
            end
        end
    end


    ////信号同步
    always @(posedge I_clk or negedge I_rst_n) begin
      if (!I_rst_n) begin
          valid_d1 <= 0;
          data_d1  <= 0;
          I_tuser_r1 <= 0;
      end else begin
          valid_d1 <= valid_d0;
          data_d1  <= data_d0 ;
          I_tuser_r1 <= I_tuser_r0;
      end
    end
/*****************************************************************
                           ��������                                       
*****************************************************************/

    reg [27:0] R_new_r1;
    reg [27:0] G_new_r1;
    reg [27:0] B_new_r1;

    reg [27:0] R_new_r2;
    reg [27:0] G_new_r2;
    reg [27:0] B_new_r2;

    reg [27:0] R_new_r3;
    reg [27:0] G_new_r3;
    reg [27:0] B_new_r3;

    reg [27:0] R_new_r4;
    reg [27:0] G_new_r4;
    reg [27:0] B_new_r4;


    wire   [7:0] rgb888_r_d1[0:3];
    wire   [7:0] rgb888_g_d1[0:3];
    wire   [7:0] rgb888_b_d1[0:3];

    assign  rgb888_r_d1[0] = data_d1[16+:8];
    assign  rgb888_g_d1[0] = data_d1[8+:8];
    assign  rgb888_b_d1[0] = data_d1[0+:8];

    assign  rgb888_r_d1[1] = data_d1[40+:8];
    assign  rgb888_g_d1[1] = data_d1[32+:8];
    assign  rgb888_b_d1[1] = data_d1[24+:8];

    assign  rgb888_r_d1[2] = data_d1[64+:8];
    assign  rgb888_g_d1[2] = data_d1[56+:8];
    assign  rgb888_b_d1[2] = data_d1[48+:8];

    assign  rgb888_r_d1[3] = data_d1[88+:8];
    assign  rgb888_g_d1[3] = data_d1[80+:8];
    assign  rgb888_b_d1[3] = data_d1[72+:8];
    always @(posedge I_clk or negedge I_rst_n)begin 
        if(!I_rst_n)begin
            R_new_r1 <= 0;
            G_new_r1 <= 0;
            B_new_r1 <= 0;

            R_new_r2 <= 0;
            G_new_r2 <= 0;
            B_new_r2 <= 0;

            R_new_r3 <= 0;
            G_new_r3 <= 0;
            B_new_r3 <= 0;

            R_new_r4 <= 0;
            G_new_r4 <= 0;
            B_new_r4 <= 0;
        end
        else if(valid_d1) begin
            R_new_r1 <= in_r_r1 * rgb888_r_d1[0];
            G_new_r1 <=           rgb888_g_d1[0];
            B_new_r1 <= in_b_r1 * rgb888_b_d1[0];

            R_new_r2 <= in_r_r1 * rgb888_r_d1[1];
            G_new_r2 <=           rgb888_g_d1[1];
            B_new_r2 <= in_b_r1 * rgb888_b_d1[1];

            R_new_r3 <= in_r_r1 * rgb888_r_d1[2];
            G_new_r3 <=           rgb888_g_d1[2];
            B_new_r3 <= in_b_r1 * rgb888_b_d1[2];

            R_new_r4 <= in_r_r1 * rgb888_r_d1[3];
            G_new_r4 <=           rgb888_g_d1[3];
            B_new_r4 <= in_b_r1 * rgb888_b_d1[3];
        end
    end

/*****************************************************************
                            �������???                                      
*****************************************************************/

    wire [7:0] R_new_x1;
    wire [7:0] G_new_x1;
    wire [7:0] B_new_x1;

    wire [7:0] R_new_x2;
    wire [7:0] G_new_x2;
    wire [7:0] B_new_x2;

    wire [7:0] R_new_x3;
    wire [7:0] G_new_x3;
    wire [7:0] B_new_x3;

    wire [7:0] R_new_x4;
    wire [7:0] G_new_x4;
    wire [7:0] B_new_x4;

    assign R_new_x1 = (R_new_r1[27:24])?255:R_new_r1[23:16];
    assign G_new_x1 =  G_new_r1;
    assign B_new_x1 = (B_new_r1[27:24])?255:B_new_r1[23:16];

    assign R_new_x2 = (R_new_r2[27:24])?255:R_new_r2[23:16];
    assign G_new_x2 =  G_new_r2;
    assign B_new_x2 = (B_new_r2[27:24])?255:B_new_r2[23:16];

    assign R_new_x3 = (R_new_r3[27:24])?255:R_new_r3[23:16];
    assign G_new_x3 =  G_new_r3;
    assign B_new_x3 = (B_new_r3[27:24])?255:B_new_r3[23:16];

    assign R_new_x4 = (R_new_r4[27:24])?255:R_new_r4[23:16];
    assign G_new_x4 =  G_new_r4;
    assign B_new_x4 = (B_new_r4[27:24])?255:B_new_r4[23:16];
/*****************************************************************
                           ͬ���ź�                                       
*****************************************************************/

    reg valid_d2,I_tuser_r2;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n)begin
            valid_d2 <= 0;
            I_tuser_r2 <= 0;
        end
        else begin
            valid_d2 <= valid_d1;
            I_tuser_r2 <= I_tuser_r1;
        end
    end


    assign  O_tlast  = (valid_d1 == 0) && (valid_d2 == 1);   
    assign  O_tuser  = I_tuser ;   
    assign  O_tvalid = valid_d2;

    assign  O_tdata = O_tvalid?{R_new_x4,G_new_x4,B_new_x4,
                       R_new_x3,G_new_x3,B_new_x3,
                       R_new_x2,G_new_x2,B_new_x2,
                       R_new_x1,G_new_x1,B_new_x1}:0;
    // assign O_t_data = {R_new[7-:5],G_new[7-:6],B_new[7-:5]};
    assign  I_tready = O_tready;
 
endmodule



