#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
v7_model.py -- RTL 可实现的检测模型（v6 的等价简化版）

===========================================================================
为什么要有 v7：v6 的"行内 gap 合并 + band 合并"在 RTL 里每类要 ~250 个
寄存器，3 类 = 750 FF，slice 只剩 1519，风险太大。
===========================================================================

现场数据证明：三个目标的【每一行都是单一连续段】（不是被 gap 打断的多段）
  改锥     core框 (63,18)-(79,70)   宽 17 格，高度方向连续
  魔方     core框 ( 8, 0)-(122,89)  宽 115 格，高度方向连续
  黑色物体 core框 (46, 0)-(94,73)   宽 49 格，高度方向连续
→ 所以"每行取最长连续段（run）"就等价于 v6 的"行内聚类主簇"，
   但寄存器少一半以上，且没有 run 间 gap 状态机。

v7 与 v6 的差异（唯一）
---------------------------------------------------------------------------
  行内：从"gap<=4 合并的簇中取最大" 改为  "取最长连续段"
  密实度：从 core 自身包围盒面积     改为  halo 包围盒面积
  （core 包围盒要 4 个 min/max 比较器 + 4 个寄存器/类，省掉）

判据、阈值、band 合并、几何门限全部与 v6 一致（已由 v6_eval 验证 IoU=1.000）。
"""

import os
import sys
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import v6_model as V6

DS = 8
W, H = 160, 90

#==========================================================================
# 参数（与 v6_model.py 完全一致 —— 阈值已由真实 FPGA 截图定量标定）
#==========================================================================
GAPX  = 4
VGAP  = 3
PROJ_TH = 2

# ★ 2026-10-30：改成三类纯颜色 —— 小船(白) / 蓝色物体 / 黑色物体
#   删掉魔方(绿主导)和改锥(橙主导)，全部按颜色分。

# --- 小船：白色/浅色 3D 打印件，高亮度 + 低色度 ---
#   ⚠ 白墙/屏幕的 raw 域中位数实测 (149,156,130)、chroma 中位 25 —— 和白塑料
#     几乎一样，**纯颜色分不开**。所以小船这一类额外靠几何约束：
#       · mx 上下限   ：排除过暗的灰和过曝的白
#       · chroma 收紧 ：只认很中性的灰白
#       · max_w/max_h ：排除撑满画面的墙
#       · edge_margin ：排除贴边的大面积背景（屏幕/墙一定贴边）
WHITE_MX   = 85      # mx 下限 (halo)
WHITE_SAT  = 18      # chroma 上限 (halo)
WHITE_CMX  = 105     # mx 下限 (core)
WHITE_CSAT = 15      # chroma 上限 (core)
WHITE_MXMAX= 205     # mx 上限（过曝白墙/屏幕排除）

# --- 蓝色物体：b 主导，且比 r/g 都高出阈值 ---
#   ★ 2026-10-30 实测（用户照片）：
#       青色钳柄  b-r=82  b-g=**11**  chroma=82   -> b-g 门槛 30/10 都会漏检
#       深蓝支架  b-r=150 b-g=58      chroma=150  -> 随便过
#     所以 **b-g 约束整个去掉**，只要求 b 是最大通道 + b-r 够大 + chroma 够大。
#     青色/天蓝/深蓝都算「蓝色」，符合用户「这两个都是蓝色」的判定。
#   ★ 2026-10-30 放宽：BL_BR 50->35, BL_SAT 65->50, BL_CSAT 70->60
BL_BR   = 35         # b - r 下限 (halo)
BL_SAT  = 50         # chroma 下限 (halo)
BL_CSAT = 60         # chroma 下限 (core)

# --- 红色物体：r 高、g/b 都低（用 r-g 区分黄/橙）---
# ★ core 直接等于 halo（原来 core 要求 r>=130，raw 域达不到 -> 完全不检出）
# ★ 2026-10-30 放宽：RMIN 95->70, RG 50->45, RB 60->45, SAT 65->50
#   RG=45 是实测平衡点：真红色（改锥）r-g 中位 74 稳定过，
#   皮肤/暖色误检区 r-g 中位 35 被挡住
RED_RMIN = 70; RED_RG = 45; RED_RB = 45; RED_SAT = 50

# --- 黑色物体：低亮度 + 低色度 ---
#   ★ 2026-10-30：黑色太敏感（阴影 mx 30~50 被判黑）-> 上限 30 降到 22
BLK_TH   = 28        # mx 上限 (halo)  真黑块 mx=20 / 阴影 mx=30~50
BLK_SAT  = 12        # chroma 上限 (halo)
BLK_CTH  = 24        # mx 上限 (core)
BLK_CSAT = 8         # chroma 上限 (core)

# 全局最小 core 数（与各类 min_core 取大者）
# ★ 2026-10-30：从 P24 解耦出来，原来和蓝色 b-r 阈值共用一个参数
GLOBAL_MIN_CORE = 15

# ★ 2026-10-30 整体放宽（用户要求「范围广点」）：
#   蓝/红 dens_k 3->2（密度要求放宽，检测范围明显变大）
#   蓝 min_core 40->25, min_w/h 4->3
#   红 min_core 25->15, min_w/h 3->2, max_w 140->160
#   黑 min_core 150->120, min_w/h 6->5, dens_k 保持 3（防误检）
CFG = {
    "blue": dict(min_core=25,  dens_k=2, min_w=3,  min_h=3,
                 max_w=160, max_h=90),
    "dark": dict(min_core=120, dens_k=3, min_w=5,  min_h=5,
                 max_w=120, max_h=90),
    "red":  dict(min_core=15,  dens_k=2, min_w=2,  min_h=2,
                 max_w=160, max_h=90),
}

#==========================================================================
# 判色（yg 这个 key 是历史代号，现在代表「蓝色物体」）
#==========================================================================
def classify(s):
    r = s[:, :, 0].astype(np.int32)
    g = s[:, :, 1].astype(np.int32)
    b = s[:, :, 2].astype(np.int32)
    mx = np.maximum(np.maximum(r, g), b)
    mn = np.minimum(np.minimum(r, g), b)
    chroma = mx - mn

    # 蓝色物体：b 最大，且比 r/g 都高出阈值
    b_h = ((b >= r) & ((b - r) >= BL_BR) & (chroma >= BL_SAT))
    b_c = (b_h & (chroma >= BL_CSAT))

    # 红色物体：r 高、g/b 都低
    r_h = ((r >= RED_RMIN) & ((r - g) >= RED_RG) & ((r - b) >= RED_RB) &
           (chroma >= RED_SAT))
    r_c = r_h

    # 黑色物体：低亮度 + 低色度
    d_h = ((mx < BLK_TH) & (chroma < BLK_SAT))
    d_c = ((mx < BLK_CTH) & (chroma < BLK_CSAT))

    return {"blue": (b_h, b_c), "dark": (d_h, d_c), "red": (r_h, r_c)}


#==========================================================================
# 行内取段：整行密度够就用整行范围，否则退回最长连续段
#
#   ★ 2026-10-30：为什么不能只用「最长连续段」
#     红色 3D 打印框架是「回」字形镂空的，一行里会被切成左右两段。
#     只取最长段 -> 框只套住一条竖边，整个物体框不全。
#     所以：先看整行命中密度，够密就说明这些段属于同一个物体（镂空也算），
#     直接取 [最左, 最右]；密度不够（说明是分散噪声）才退回最长段。
#==========================================================================
def row_longest_run(row):
    """返回 (lo, hi, len)；无命中返回 None"""
    best = None
    x = 0
    n = len(row)
    while x < n:
        if row[x]:
            s = x
            while x < n and row[x]:
                x += 1
            e = x - 1
            if best is None or (e - s + 1) > (best[1] - best[0] + 1):
                best = (s, e, e - s + 1)
        else:
            x += 1
    return best


#==========================================================================
# 流式 band 检测
#==========================================================================
def row_segment(row):
    """本行的代表段：密度够就取整行范围，否则取最长连续段"""
    idx = np.flatnonzero(row)
    if len(idx) == 0:
        return None
    lo, hi = int(idx[0]), int(idx[-1])
    cnt = len(idx)
    if cnt * 2 >= (hi - lo + 1):      # 填充率 >= 50% -> 整行范围
        return (lo, hi, hi - lo + 1)
    return row_longest_run(row)


def detect_class(halo, core, cfg):
    bands = []
    active = False
    bx0 = bx1 = by0 = by1 = 0
    bcore = 0
    last = -99

    for y in range(H):
        run = row_segment(halo[y])
        if run is not None:
            blo, bhi, bcnt = run
            c_cnt = int(np.count_nonzero(core[y, blo:bhi + 1]))
        else:
            blo = bhi = bcnt = 0
            c_cnt = 0

        if bcnt >= PROJ_TH:
            if not active:
                active = True
                bx0, bx1, by0, by1 = blo, bhi, y, y
                bcore = c_cnt
            elif blo <= bx1 + GAPX and bhi + GAPX >= bx0:
                bx0 = min(bx0, blo); bx1 = max(bx1, bhi); by1 = y
                bcore += c_cnt
            else:
                bands.append((bx0, bx1, by0, by1, bcore))
                active = True
                bx0, bx1, by0, by1 = blo, bhi, y, y
                bcore = c_cnt
            last = y
        else:
            if active and (y - last) > VGAP:
                bands.append((bx0, bx1, by0, by1, bcore))
                active = False

    if active:
        bands.append((bx0, bx1, by0, by1, bcore))

    best = None
    for (bx0, bx1, by0, by1, bc) in bands:
        if bc <= 0:
            continue
        if best is None or bc > best[4]:
            best = (bx0, bx1, by0, by1, bc)
    return best


def gate(b, cfg):
    if b is None:
        return False
    bx0, bx1, by0, by1, bc = b
    w = bx1 - bx0 + 1
    h = by1 - by0 + 1
    if bc < cfg["min_core"]:
        return False
    # 全局最小 core 数（与 RTL 的 I_min_core 一致）
    if bc < GLOBAL_MIN_CORE:
        return False
    # 双轴密度：core 数必须同时够密（横向 core>=K*w，纵向 core>=K*h）
    k = cfg["dens_k"]
    if bc < k * w or bc < k * h:
        return False
    if w < cfg["min_w"] or h < cfg["min_h"]:
        return False
    if w > cfg["max_w"] or h > cfg["max_h"]:
        return False
    # 宽高比（形状约束）：排除细长条和扁平板
    arlo = cfg.get("ar_min", 0.0)
    arhi = cfg.get("ar_max", 99.0)
    if arlo > 0.0 and (float(w) / float(h) < arlo or float(w) / float(h) > arhi):
        return False
    # 贴边拒绝：大面积背景（屏幕/墙）一定贴边
    em = cfg.get("edge_margin", 0)
    if em > 0:
        if bx0 < em or bx1 > (W - 1 - em) or by0 < em or by1 > (H - 1 - em):
            return False
    return True


def detect(px):
    s = px.astype(np.int32)[::DS, ::DS, :]
    m = classify(s)
    out = {}
    for k in ("blue", "dark", "red"):
        b = detect_class(m[k][0], m[k][1], CFG[k])
        out[k] = b if gate(b, CFG[k]) else None
    return out


def detect_all_bands(px):
    s = px.astype(np.int32)[::DS, ::DS, :]
    m = classify(s)
    return {k: detect_class(m[k][0], m[k][1], CFG[k])
            for k in ("blue", "dark", "red")}
