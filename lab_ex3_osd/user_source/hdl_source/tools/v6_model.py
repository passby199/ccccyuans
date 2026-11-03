#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
v6_model.py -- v6 检测算法的【唯一权威行为模型】（RTL 必须与它逐位一致）

===========================================================================
为什么是 v6：v5 的三个硬伤（全部由现场照片取证发现）
===========================================================================
  ① 橙色判据漏了 "g>b" 约束
     魔方【红色面】display med RGB=(195,64,74)  -> R-B=121, G-B=-10
     改锥【橙色柄】display med RGB=(157,86,58)   -> R-B=99,  G-B=+28
     v5 的 o_h 只要 (r>=g)&(r>=b)&(R-B>=60)&(R-G>=45)&(R>=140) 就判橙，
     于是魔方红面（同样 R 主导、R-B 很大）被误判成"改锥"。
     → 加 g>b 且 G-B 有下限，把红面挡在外面。

  ② "魔方"判据把显示器的蓝色标题栏认成了魔方
     win_显示器.png 实拍：绿框套在笔记本屏幕的蓝色标题栏上。
     原因：v5 的 y_h 要求 (g>=r)&(g>=b)，蓝色不满足 g>=b，
     但 v4 的 is_vivid 是 (g>=r&&g>=b)||(b>=r&&b>=g) —— 后半段把蓝色放进来了。
     → v6 的魔方判据必须是"绿主导"（g>=r 且 g>=b），绝不能有 b 主导分支。

  ③ 黑色判据把整个暗背景当成一个连通块
     win_黑色物体.png：黑色掩码占 71.8% 画面，连通块 35 个、
     面积 659716 的巨块覆盖 (0,0)-(1279,719) 全屏。
     原因：v4/v5 的 dark 判据只有 max<BLK_TH && sat<BLK_SAT，
     暗桌面/暗墙全中；而且用的是"全局 min/max 外接框"，一旦有噪声点
     框就被撑爆。
     → v6 用 halo/core 双阈值 + band 合并 + core_solid 密实度。

===========================================================================
v6 算法：halo（宽松圈形）+ core（严格确认）+ 流式 band
===========================================================================
    halo（宽松层）：负责"圈形" —— 行内 1D 聚类 + band 合并
    core（严格层）：负责"确认" —— band 内统计 core 像素数与其自身包围盒

    真目标 = 致密实心块 -> core 在自己包围盒里密实度高 (core_solid 大)
    干扰源 = 零散暗点 / 细长暗线 / 大面积稀疏阴影 -> core_solid 小

    输出框 = halo_box（band 的 halo 包围盒）

流式算法（逐行，无整帧缓存，RTL 1:1 可实现）
===========================================================================
    行内 1D 聚类（gap <= GAPX 合并）-> 本行像素数最多的簇（主簇）
    主簇与当前 band 横向有交叠/邻接 -> 并入 band；否则收尾旧 band、开新 band
    空行容忍 VGAP 行不断 band
    band 内同时维护 core 像素计数与 core 自身包围盒
    帧结束：每类取 core_solid 达标且 core 数最多的 band
"""

import numpy as np
from PIL import Image

DS = 8
W, H = 160, 90

#==========================================================================
# 参数（与 RTL 中的 parameter / 串口参数一一对应）
#==========================================================================
GAPX  = 4      # 行内聚类 gap 容差（格）
VGAP  = 3      # band 空行容忍（行）
PROJ_TH = 2    # 行主簇最小像素数

# --- 颜色门限（全部在【原始像素域 raw】，即 RTL 取样点 S_video_rd_data）---
ORANGE_RB   = 60    # P23 改锥 R-B
ORANGE_RG   = 45    # P28 改锥 R-G
ORANGE_GB   = 6     # P29 改锥 G-B（★排除魔方红面）
ORANGE_RMIN = 140   # P27 改锥 R 亮度下限
#   实测（win_改锥.png raw 域网格中位数）：
#     橙柄  (164,91,81)  R-B=83  R-G=73  G-B=10  chroma=83
#     灰手套(104,101,116) G-B=-15  -> 被 g>b + G-B 排除
#     白屏幕(255,255,255) chroma=0  -> 被 R-B 排除
#     人手(78,47,27)      R-B=51   -> 被 R-B>=60 排除
#   故 G-B 门限取 6（只挡红面），core 取 8
ORANGE_CRB  = 70    # core: 改锥 R-B
ORANGE_CRG  = 60    # core: 改锥 R-G
ORANGE_CGB  = 8     # core: 改锥 G-B
ORANGE_CMIN = 150   # core: 改锥 R 亮度下限

YG_SAT   = 60       # P26 魔方饱和度下限（halo）
YG_CSAT  = 80       # P32 core: 魔方饱和度
YG_GB    = 60       # P30 魔方 G-B（绿主导强度）
#   实测：绿面 (7,90,0)/(78,89,0)/(88,103,0)  G-B=90~103 chroma=89~103
#         显示器屏幕 (147,197,171) G-B=21 蓝标题栏 (170,220,197) G-B=23 -> 天然排除
#         机身外壳 (96,108,89)   G-B=19 -> 排除

BLK_TH   = 30       # P25 黑色亮度上限（halo）
BLK_SAT  = 12       # P31 黑色色度上限（halo）
BLK_CTH  = 26       # P33 core: 黑色亮度上限
BLK_CSAT = 8        # P34 core: 黑色色度上限
#   ★ 实测分离度（raw 域，v6_hist.py）：
#     判据 mx<30 & chroma<12 : 真黑块 99.14% / 键盘整体 0.02% / 键帽 0.00% / 绿面 0.00%
#     判据 mx<26 & chroma< 8 : 真黑块 97.92% / 键盘整体 0.00%
#     （旧值 mx<40 & chroma<24 : 黑块 99.91% 但键盘 60.7% —— 这就是旧版把键盘整片
#      当成"黑色物体"的原因）

# --- 几何门限（按类）---
#   min_core   : band 内 core 像素数下限
#   min_csolid : core 自身包围盒的密实度下限（主判据）
#   min_w/min_h: core 包围盒最小宽/高（滤掉细线）
#   max_w/max_h: core 包围盒最大宽/高
CFG = {
    "orange": dict(min_core=25,  min_csolid=0.45, min_w=4,  min_h=4,  max_w=90,  max_h=90),
    "yg":     dict(min_core=60,  min_csolid=0.30, min_w=6,  min_h=6,  max_w=160, max_h=90),
    #  min_core=150：显示器负样本的暗带最高 band core=59（<150 被挡），
    #                 真黑块 core=1701（远超 150）
    "dark":   dict(min_core=150, min_csolid=0.45, min_w=6,  min_h=6,  max_w=120, max_h=90),
}


#==========================================================================
# 判色（raw 域）
#==========================================================================
def classify(s):
    r = s[:, :, 0].astype(np.int32)
    g = s[:, :, 1].astype(np.int32)
    b = s[:, :, 2].astype(np.int32)
    mx = np.maximum(np.maximum(r, g), b)
    mn = np.minimum(np.minimum(r, g), b)
    chroma = mx - mn

    # --- 改锥（橙色手柄）---
    #  ★ G-B 下限是关键：魔方红面 G-B≈-10，改锥橙柄 G-B≈+28
    o_h = ((r >= g) & (g > b) & ((r - b) >= ORANGE_RB) &
           ((r - g) >= ORANGE_RG) & ((g - b) >= ORANGE_GB) & (r >= ORANGE_RMIN))
    o_c = (o_h & ((r - b) >= ORANGE_CRB) & ((r - g) >= ORANGE_CRG) &
           ((g - b) >= ORANGE_CGB) & (r >= ORANGE_CMIN))

    # --- 魔方（彩色面）---
    #  ★ 只认"绿主导"（g>=r 且 g>=b），绝不认蓝主导
    y_h = ((g >= r) & (g >= b) & ((g - b) >= YG_GB) & (chroma >= YG_SAT))
    y_c = (y_h & (chroma >= YG_CSAT))

    # --- 黑色物体 ---
    d_h = ((mx < BLK_TH) & (chroma < BLK_SAT))
    d_c = ((mx < BLK_CTH) & (chroma < BLK_CSAT))

    return {"orange": (o_h, o_c), "yg": (y_h, y_c), "dark": (d_h, d_c)}


#==========================================================================
# 行内 1D 聚类
#==========================================================================
def row_clusters(row):
    """返回本行所有簇 [(lo, hi, cnt), ...]，gap <= GAPX 合并"""
    out = []
    x = 0
    n = len(row)
    while x < n:
        if row[x]:
            s = x
            while x < n and row[x]:
                x += 1
            e = x - 1
            if out and s <= out[-1][1] + GAPX:
                out[-1] = (out[-1][0], e, out[-1][2] + e - s + 1)
            else:
                out.append((s, e, e - s + 1))
        else:
            x += 1
    return out


#==========================================================================
# 流式 band 检测
#==========================================================================
def detect_class(halo, core, cfg):
    bands = []
    active = False
    bx0 = bx1 = by0 = by1 = 0
    cx0 = cx1 = cy0 = cy1 = 0
    bcore = 0
    c_any = False
    last = -99

    for y in range(H):
        cl = row_clusters(halo[y])
        crow = core[y]

        if cl:
            bc = max(cl, key=lambda t: t[2])
            blo, bhi, bcnt = bc
            sub = crow[blo:bhi + 1]
            cidx = np.nonzero(sub)[0]
            if len(cidx):
                c_lo = int(cidx.min()) + blo
                c_hi = int(cidx.max()) + blo
                c_cnt = int(len(cidx))
            else:
                c_lo = c_hi = blo
                c_cnt = 0
        else:
            blo = bhi = bcnt = 0
            c_lo = c_hi = 0
            c_cnt = 0

        if bcnt >= PROJ_TH:
            if not active:
                active = True
                bx0, bx1, by0, by1 = blo, bhi, y, y
                bcore = c_cnt
                c_any = c_cnt > 0
                if c_any:
                    cx0, cx1, cy0, cy1 = c_lo, c_hi, y, y
            elif blo <= bx1 + GAPX and bhi + GAPX >= bx0:
                bx0 = min(bx0, blo); bx1 = max(bx1, bhi); by1 = y
                bcore += c_cnt
                if c_cnt:
                    if not c_any:
                        cx0, cx1, cy0, cy1 = c_lo, c_hi, y, y
                        c_any = True
                    else:
                        cx0 = min(cx0, c_lo); cx1 = max(cx1, c_hi)
                        cy0 = min(cy0, y); cy1 = max(cy1, y)
            else:
                bands.append(_pack(bx0, bx1, by0, by1, cx0, cx1, cy0, cy1,
                                   bcore, c_any))
                active = True
                bx0, bx1, by0, by1 = blo, bhi, y, y
                bcore = c_cnt
                c_any = c_cnt > 0
                if c_any:
                    cx0, cx1, cy0, cy1 = c_lo, c_hi, y, y
            last = y
        else:
            if active and (y - last) > VGAP:
                bands.append(_pack(bx0, bx1, by0, by1, cx0, cx1, cy0, cy1,
                                   bcore, c_any))
                active = False

    if active:
        bands.append(_pack(bx0, bx1, by0, by1, cx0, cx1, cy0, cy1, bcore, c_any))

    best = None
    for b in bands:
        if not b["ok"]:
            continue
        if best is None or b["core"] > best["core"]:
            best = b
    return best


def _pack(bx0, bx1, by0, by1, cx0, cx1, cy0, cy1, bcore, c_any):
    b = {"halo_box": (bx0, bx1, by0, by1), "core": bcore,
         "core_box": None, "core_solid": 0.0, "ok": False}
    if not c_any or bcore <= 0:
        return b
    cw = cx1 - cx0 + 1
    ch = cy1 - cy0 + 1
    b["core_box"] = (cx0, cx1, cy0, cy1)
    b["core_w"] = cw
    b["core_h"] = ch
    b["core_solid"] = bcore / float(cw * ch)
    b["ok"] = True
    return b


def gate(b, cfg):
    """几何门限"""
    if b is None or not b["ok"]:
        return False
    if b["core"] < cfg["min_core"]:
        return False
    if b["core_solid"] < cfg["min_csolid"]:
        return False
    if b["core_w"] < cfg["min_w"] or b["core_h"] < cfg["min_h"]:
        return False
    if b["core_w"] > cfg["max_w"] or b["core_h"] > cfg["max_h"]:
        return False
    return True


def detect(px):
    """输入 1280x720 RGB -> 每类检测结果"""
    s = px.astype(np.int32)[::DS, ::DS, :]
    m = classify(s)
    out = {}
    for k in ("orange", "yg", "dark"):
        b = detect_class(m[k][0], m[k][1], CFG[k])
        out[k] = b if gate(b, CFG[k]) else None
    return out


def detect_all_bands(px):
    s = px.astype(np.int32)[::DS, ::DS, :]
    m = classify(s)
    return {k: detect_class(m[k][0], m[k][1], CFG[k])
            for k in ("orange", "yg", "dark")}


#==========================================================================
# 域换算（显示域 <-> raw 域）
#   正向链（design_top_wrapper.v）：
#     raw --dehaze(BL=16, x17/16)--> d --gamma(CHROMA_KEEP=1, SAT_BOOST=16)--> disp
#   dehaze : d = (raw-16) + (raw-16)/16
#   gamma  : Y_in=mean(d), Y_out=F_gamma(Y_in), delta=Y_out-Y_in, out=d+delta
#            ⇒ 色差（通道间差值）在 gamma 中严格不变
#==========================================================================
GAMMA_BP_IN = [0, 16, 32, 48, 64, 96, 128, 192, 255]
GAMMA_BP_OUT = [0, 73, 100, 120, 137, 164, 187, 224, 255]

FWD_SEG = [
    (0, 16, 0, 73, 146, 32, 16),
    (16, 32, 73, 100, 54, 32, 16),
    (32, 48, 100, 120, 40, 32, 16),
    (48, 64, 120, 137, 34, 32, 16),
    (64, 96, 137, 164, 27, 32, 16),
    (96, 128, 164, 187, 23, 32, 16),
    (128, 192, 187, 224, 37, 64, 32),
    (192, 256, 224, 255, 126, 256, 128),
]


def f_gamma(x):
    x = np.asarray(x)
    out = np.zeros_like(x, dtype=np.int32)
    for (lo, hi, olo, ohi, num, den, rnd) in FWD_SEG:
        m = (x >= lo) & (x < hi)
        if not m.any():
            continue
        xb = (x[m] - lo).astype(np.int32)
        out[m] = np.minimum(olo + ((xb * num + rnd) >> int(np.log2(den))), ohi)
    return out


def _build_gamma_inv_lut():
    tbl = f_gamma(np.arange(256, dtype=np.int32))
    inv = np.zeros(256, dtype=np.int32)
    for y in range(256):
        seg = None
        for (lo, hi, olo, ohi, num, den, rnd) in FWD_SEG:
            if olo <= y <= ohi:
                seg = (lo, hi, olo, ohi, num, den, rnd)
                break
        if seg is None:
            inv[y] = 0 if y < GAMMA_BP_OUT[0] else 255
            continue
        lo, hi, olo, ohi, num, den, rnd = seg
        if ohi == olo:
            inv[y] = lo
            continue
        xb = int(round(((y - olo) * den - rnd) / float(num)))
        xb = max(0, min(hi - 1 - lo, xb))
        inv[y] = lo + xb
    return np.maximum.accumulate(inv)


GAMMA_INV = _build_gamma_inv_lut()


def disp_to_raw(disp):
    """显示域 -> raw 域"""
    disp = np.asarray(disp, dtype=np.float64)
    shape = disp.shape
    flat = disp.reshape(-1, 3)
    y_out = np.clip(np.round(flat.mean(axis=1)), 0, 255).astype(np.int32)
    y_in = GAMMA_INV[y_out].astype(np.float64)
    delta = y_out.astype(np.float64) - y_in
    d = flat - delta[:, None]
    raw = d * (16.0 / 17.0) + 16.0
    return np.clip(raw, 0, 255).reshape(shape)


def raw_to_disp(raw):
    """raw 域 -> 显示域（正向链）"""
    raw = np.asarray(raw, dtype=np.float64)
    sub = np.clip(raw - 16.0, 0, 255)
    d = sub + np.floor(sub / 16.0)
    d = np.clip(d, 0, 255)
    y_in = np.clip(np.round(d.reshape(-1, 3).mean(axis=1)), 0, 255).astype(np.int32)
    y_out = f_gamma(y_in).astype(np.float64)
    delta = (y_out - y_in)[..., None]
    return np.clip(d + delta, 0, 255)


#==========================================================================
# 图像工具
#==========================================================================
def crop169_at(path, top):
    im = Image.open(path).convert("RGB")
    w, h = im.size
    th = int(w * 9 / 16)
    top = max(0, min(top, h - th))
    return np.asarray(im.crop((0, top, w, top + th)).resize((1280, 720), Image.BILINEAR))


def load_default(path):
    im = Image.open(path).convert("RGB")
    w, h = im.size
    th = int(w * 9 / 16)
    top = int((h - th) * 0.30)
    return np.asarray(im.crop((0, top, w, top + th)).resize((1280, 720), Image.BILINEAR))


def load_raw_scene(path):
    """把【显示域】图片（FPGA 直出/手机照片）转成 raw 域 1280x720"""
    px = load_default(path)
    return disp_to_raw(px)


#==========================================================================
# OSD 区域（hdmi_mixer.v 常量）—— 统计与评估时要剔除
#==========================================================================
LOGO_X, LOGO_Y, LOGO_W, LOGO_H = 0, 0, 160, 160
DYN_X, DYN_Y, DYN_W, DYN_H = 375, 120, 200, 160


def osd_mask(shape):
    h, w = shape[:2]
    m = np.zeros((h, w), bool)
    m[LOGO_Y:LOGO_Y + LOGO_H, LOGO_X:LOGO_X + LOGO_W] = True
    m[DYN_Y:DYN_Y + DYN_H, DYN_X:DYN_X + DYN_W] = True
    return m
