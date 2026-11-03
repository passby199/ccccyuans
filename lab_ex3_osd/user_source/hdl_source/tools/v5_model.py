#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
v5_model.py -- v5 检测算法的【唯一权威行为模型】（RTL 必须与它逐位一致）

---------------------------------------------------------------------------
设计目标
    三个实物：改锥(橙色手柄) / 魔方(黄绿+彩色面) / 黑色物体
    要求：框要落在实物上，不能乱飘到背景（显示器画面、键盘暗缝、桌面阴影）。

核心机制：halo + core 双阈值 + 流式连通域
---------------------------------------------------------------------------
    halo（宽松层）：负责"圈形" —— 行内聚类 + band 合并
    core（严格层）：负责"确认" —— 在 band 内统计 core 像素数与其自身包围盒

    真目标   = 一个致密实心块
             -> core 像素在自己的包围盒里密实度高（core_solid 大）
    干扰源   = 零散暗点 / 细长暗线 / 大面积稀疏阴影
             -> core_solid 小

    因此【不用尺寸上限做主判据】（否则"魔方占满画面"会被误杀），
    改用 core_solid 做主判据。

流式算法（逐行，无整帧缓存，RTL 1:1 可实现）
---------------------------------------------------------------------------
    行内 1D 聚类（gap <= GAPX 合并）-> 本行主簇（像素数最多的簇）
    主簇与当前 band 横向有交叠/邻接 -> 并入 band；否则收尾旧 band、开新 band
    空行容忍 VGAP 行不断 band
    band 内同时维护 core 像素计数与 core 自身包围盒
    帧结束：每类取 core_solid 达标且 core 数最多��� band
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

# --- 颜色门限 ---
ORANGE_RB   = 60    # P23 改锥 R-B
ORANGE_RG   = 45    # P28 改锥 R-G
ORANGE_RMIN = 140   # P27 改锥 R 亮度下限
ORANGE_CRB  = 80    # core: 改锥 R-B
ORANGE_CRG  = 55    # core: 改锥 R-G
ORANGE_CMIN = 170   # core: 改锥 R 亮度下限

YG_SAT   = 60       # P26 魔方饱和度下限（halo）
YG_CSAT  = 80       # core: 魔方饱和度

BLK_TH   = 40       # P25 黑色亮度上限（halo）
BLK_SAT  = 24       # 黑色色度上限（halo）
BLK_CTH  = 28       # core: 黑色亮度上限
BLK_CSAT = 16       # core: 黑色色度上限

# --- 几何门限（按类） ---
#   min_core   : band 内 core 像素数下限
#   min_csolid : core 自身包围盒的密实度下限（主判据）
#   min_wh     : core 包围盒最小宽/高（滤掉细线）
CFG = {
    "orange": dict(min_core=25,  min_csolid=0.45, min_w=4,  min_h=4,  max_w=90, max_h=90),
    "yg":     dict(min_core=60,  min_csolid=0.30, min_w=6,  min_h=6,  max_w=160, max_h=90),
    "dark":   dict(min_core=60,  min_csolid=0.45, min_w=6,  min_h=6,  max_w=120, max_h=90),
}


#==========================================================================
# 判色
#==========================================================================
def classify(s):
    r = s[:, :, 0].astype(np.int32)
    g = s[:, :, 1].astype(np.int32)
    b = s[:, :, 2].astype(np.int32)
    mx = np.maximum(np.maximum(r, g), b)
    mn = np.minimum(np.minimum(r, g), b)
    chroma = mx - mn

    o_h = ((r >= g) & (r >= b) & ((r - b) >= ORANGE_RB) &
           ((r - g) >= ORANGE_RG) & (r >= ORANGE_RMIN))
    o_c = (o_h & ((r - b) >= ORANGE_CRB) & ((r - g) >= ORANGE_CRG) &
           (r >= ORANGE_CMIN))

    y_h = ((g >= r) & (g >= b) & (r * 10 >= b * 12) & (g * 10 >= b * 12) &
           (chroma >= YG_SAT))
    y_c = (y_h & (chroma >= YG_CSAT))

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
    """
    halo 圈 band，core 确认。返回最佳 band 或 None。
    band 内维护：halo 包围盒 + core 包围盒 + core 计数
    """
    bands = []          # 已收尾的 band 特征
    active = False
    bx0 = bx1 = by0 = by1 = 0
    cx0 = cx1 = cy0 = cy1 = 0
    bcore = 0
    c_any = False      # band 内是否已有 core 像素
    last = -99

    for y in range(H):
        cl = row_clusters(halo[y])
        crow = core[y]

        if cl:
            bc = max(cl, key=lambda t: t[2])
            blo, bhi, bcnt = bc
            # 该簇内的 core 像素
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
    """调试：返回每类全部 band"""
    s = px.astype(np.int32)[::DS, ::DS, :]
    m = classify(s)
    out = {}
    for k in ("orange", "yg", "dark"):
        b = detect_class(m[k][0], m[k][1], CFG[k])
        out[k] = b
    return out


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
    """无 top 参数时用 30% 偏移（等价横屏取景）"""
    im = Image.open(path).convert("RGB")
    w, h = im.size
    th = int(w * 9 / 16)
    top = int((h - th) * 0.30)
    crop = im.crop((0, top, w, top + th))
    return np.asarray(crop.resize((1280, 720), Image.BILINEAR))
