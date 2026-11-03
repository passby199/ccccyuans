#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
exp_v9.py  --  最终方案：连通簇聚类 + 形状先验

为什么必须上"连通簇"
---------------------------------------------------------------------------
黑色物体和键盘阴影在【颜色上完全一样】（实测都是 max≈42, chroma≈10）。
唯一的区别是【形状】：
    黑色方块：一个小而方正的紧凑块（实测 15x15 格）
    键盘阴影：横贯整幅画面的长条（56x34 格，纵横比 1.6）
任何基于颜色/位置的规则都区分不了，只有"连通域的紧致度"能区分。

所以最终架构：
    降采样 8x8 -> 160x90 网格
    颜色分类 -> 每类一张二值图
    连通域标记(4邻域) -> 取【形状最像目标】的簇：
        面积够大 + 紧致度高(面积/外接框面积) + 纵横比在合理区间 + 尺寸在范围内
    三类各取最优簇 -> 画框

RTL 实现要点
---------------------------------------------------------------------------
不做完整 CCL（太贵）。改用【超级块 + 4 邻域扩张】的近似：
    1. 把 160x90 网格再分块成 20x12 个 8x8 超级块（64x64 像素）
    2. 每块统计该类命中数 cnt
    3. cnt >= K 的块算"种子"
    4. 从种子出发做 4 邻域连通扩张，得到若干"候选簇"
    5. 选形状最优的簇
8x8 超级块只有 240 个，扩张逻辑很便宜。
"""

import sys
import numpy as np
from PIL import Image
from collections import deque

DS = 8
W, H = 160, 90
TS = 8
TW, TH = W // TS, H // TS      # 20 x 12 = 240 块

# ---------- 颜色判据 ----------
ORANGE_RB = 60      # P23  R-B 差
ORANGE_RG = 45      # P28  R-G 差
ORANGE_RMIN = 140   # P27  R 亮度下限
VIVID_SAT = 60      # P26  饱和度下限
BLK_TH = 40         # P25  亮度上限
BLK_SAT = 24        # 黑色色度上限

# ---------- 形状判据 ----------
SEED_MIN = 4        # 超级块最少命中格数
MIN_PIX = 15        # P24 簇内最少命中格数
MAX_W = 60          # 簇宽上限（格）480 像素
MAX_H = 45          # 簇高上限（格）360 像素
MIN_W = 3           # 簇宽下限
MIN_H = 3           # 簇高下限
FILL_MIN = 0.45     # 紧致度下限：命中格 / 外接框面积
AR_MIN = 0.30       # 宽高比下限（w/h）
AR_MAX = 3.5        # 宽高比上限


def classify(px, orb=ORANGE_RB, org=ORANGE_RG, orm=ORANGE_RMIN,
             vs=VIVID_SAT, bt=BLK_TH, bs=BLK_SAT):
    s = px.astype(np.int16)[::DS, ::DS, :]
    r, g, b = s[:, :, 0], s[:, :, 1], s[:, :, 2]
    mx = np.maximum(np.maximum(r, g), b)
    mn = np.minimum(np.minimum(r, g), b)
    chroma = mx - mn
    orange = (r >= g) & (r >= b) & ((r - g) >= org) & ((r - b) >= orb) & (r >= orm)
    yg = (g >= r) & (g >= b) & (r * 10 >= b * 12) & (g * 10 >= b * 12) & (chroma >= vs)
    b_lead = (b > r) & (b >= g) & (chroma >= vs)
    r_lead = (r > g) & (r > b) & (chroma >= vs)
    dark = (mx < bt) & (chroma < bs)
    return {"orange": orange, "yg": yg, "b_lead": b_lead, "r_lead": r_lead, "dark": dark}


def super_tiles(mask, seed_min=SEED_MIN):
    """返回 (块命中数矩阵, 块外接框, 块内精确像素包围)"""
    tiles = np.zeros((TH, TW), int)
    for ty in range(TH):
        for tx in range(TW):
            tiles[ty, tx] = mask[ty * TS:(ty + 1) * TS, tx * TS:(tx + 1) * TS].sum()
    return tiles


def clusters(tiles, seed_min=SEED_MIN):
    """4 邻域连通簇，返回每簇的 (块列表, 命中格数)"""
    ok = tiles >= seed_min
    seen = np.zeros_like(ok)
    out = []
    for y in range(TH):
        for x in range(TW):
            if ok[y, x] and not seen[y, x]:
                q = deque([(y, x)])
                seen[y, x] = True
                cells = []
                while q:
                    cy, cx = q.popleft()
                    cells.append((cy, cx))
                    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        ny, nx = cy + dy, cx + dx
                        if 0 <= ny < TH and 0 <= nx < TW and ok[ny, nx] and not seen[ny, nx]:
                            seen[ny, nx] = True
                            q.append((ny, nx))
                hits = int(sum(tiles[p] for p in cells))
                out.append((cells, hits))
    return out


def best_cluster(mask, seed_min=SEED_MIN, min_pix=MIN_PIX, max_w=MAX_W, max_h=MAX_H,
                 min_w=MIN_W, min_h=MIN_H, fill_min=FILL_MIN,
                 ar_min=AR_MIN, ar_max=AR_MAX):
    tiles = super_tiles(mask, seed_min)
    best = None
    for cells, hits in clusters(tiles, seed_min):
        ys = [p[0] for p in cells]
        xs = [p[1] for p in cells]
        # 块范围 -> 格范围
        gx0, gx1 = min(xs) * TS, max(xs) * TS + TS - 1
        gy0, gy1 = min(ys) * TS, max(ys) * TS + TS - 1
        w = gx1 - gx0 + 1
        h = gy1 - gy0 + 1
        if hits < min_pix:
            continue
        if w > max_w or h > max_h or w < min_w or h < min_h:
            continue
        fill = hits / float(w * h)
        if fill < fill_min:
            continue
        ar = w / float(h)
        if ar < ar_min or ar > ar_max:
            continue
        # 打分：命中数多 + 紧致度高 优先
        score = hits * fill
        if best is None or score > best[0]:
            best = (score, (gx0, gx1, gy0, gy1), hits, fill, ar, len(cells))
    if best is None:
        return None
    return {"box": best[1], "hits": best[2], "fill": best[3], "ar": best[4],
            "nblk": best[5]}


def detect(px, **kw):
    m = classify(px)
    out = {}
    for nm in ("orange", "yg", "dark"):
        out[nm] = best_cluster(m[nm], **kw)
    # 魔方：yg 簇 + 邻域内蓝/红配块
    if out["yg"]:
        x0, x1, y0, y1 = out["yg"]["box"]
        pad = 5
        win = np.zeros_like(m["yg"])
        win[max(0, y0 - pad):y1 + pad + 1, max(0, x0 - pad):x1 + pad + 1] = True
        out["partner"] = int(((m["b_lead"] | m["r_lead"]) & win).sum())
    else:
        out["partner"] = 0
    return out


def show(tag, px, **kw):
    r = detect(px, **kw)
    parts = []
    for nm in ("orange", "yg", "dark"):
        v = r[nm]
        if v:
            b = v["box"]
            parts.append("%s: %s n=%d fill=%.2f ar=%.2f" % (nm, b, v["hits"], v["fill"], v["ar"]))
        else:
            parts.append("%s: -" % nm)
    parts.append("partner=%d" % r["partner"])
    print("  %-20s %s" % (tag, " | ".join(parts)))


if __name__ == "__main__":
    SCREW = r"C:\Users\Lenovo\Documents\Tencent Files\2195166973\nt_qq\nt_data\Pic\2026-10\Ori\2639de0745648dbc8cd34828e1daaeba.jpg"
    BLACK = r"C:\Users\Lenovo\Documents\Tencent Files\2195166973\nt_qq\nt_data\Pic\2026-10\Ori\242b907b1aec3ebcb1338acc0b198abb.jpg"
    CUBE = r"C:\Users\Lenovo\.workbuddy-ai\clipboard-images\clipboard-2026-10-29T10-28-19-936Z-2c740bee.jpg"
    MON = r"C:\Users\Lenovo\Documents\Tencent Files\2195166973\nt_qq\nt_data\Pic\2026-10\Ori\5a9648c013a895b6de641c1d25691786.jpg"

    def L(p):
        return np.asarray(Image.open(p).convert("RGB").resize((1280, 720), Image.BILINEAR))

    mo = Image.open(MON).convert("RGB")
    scr = np.asarray(mo.crop((230, 60, 470, 390)).resize((1280, 720), Image.BILINEAR))

    print("【v9 连通簇 + 形状先验】")
    show("改锥照片", L(SCREW))
    show("黑色物体照片", L(BLACK))
    show("魔方照片", L(CUBE))
    show("笔记本屏幕(误检源)", scr)
    show("显示器全图", L(MON))
