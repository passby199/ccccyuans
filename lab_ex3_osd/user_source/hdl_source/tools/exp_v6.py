#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
v6 判据实验台 —— 在真实照片上验证三类判据

设计原则
===========================================================================
手机照片经过手机 ISP（白平衡/gamma/HDR），SC500 raw 域又是另一套曲线。
所以判据必须尽量用【比值】而不是【绝对差】，才能跨设备迁移。

v6 三类判据（全部归一化）
---------------------------------------------------------------------------
改锥 orange : R 是最大通道 且  R/G 和 R/B 都够大（"暖橙"）
              (r>=g) & (r>=b) & (r*2>=g*2+th_rg) & (r*2>=b*2+th_rb)
              等价：R 主导 + R-G >= ORANGE_RG + R-B >= ORANGE_RB + R >= ORANGE_RMIN

魔方 cube   : "黄绿"核心 —— G 是最大通道，且 R、G 都远高于 B
              (g>=r) & (g>=b) & (r*10>=b*12) & (g*10>=b*12) & chroma>=VIVID_SAT
              这是魔方最有辨识度的特征（黄面/绿面都是 R≈G>>B），
              而屏幕上白色文档区是 R≈G≈B（接近中性），天然不满足。

黑色 dark   : max(R,G,B) < BLK_TH 且 chroma < BLK_SAT
"""

import sys
import numpy as np

DS = 8

# 参数（和 RTL 对齐）
ORANGE_RB   = 60     # P23  R-B 差下限
ORANGE_RG   = 45     # P28  R-G 差下限
ORANGE_RMIN = 140    # P27  R 亮度下限
VIVID_SAT   = 60     # P26  饱和度下限
BLK_TH      = 40     # P25  亮度上限
BLK_SAT     = 24     # 黑色色度上限
MIN_PIX     = 15     # P24
YGMIN       = 30     # 魔方黄绿核心最小格数
MAX_W       = 90
MAX_H       = 60
PROJ_TH     = 2


def masks(px, orb=ORANGE_RB, org=ORANGE_RG, orm=ORANGE_RMIN,
          vs=VIVID_SAT, bt=BLK_TH, bs=BLK_SAT):
    s = px.astype(np.int16)[::DS, ::DS, :]
    r, g, b = s[:, :, 0], s[:, :, 1], s[:, :, 2]
    mx = np.maximum(np.maximum(r, g), b)
    mn = np.minimum(np.minimum(r, g), b)
    chroma = mx - mn

    orange = ((r >= g) & (r >= b) & ((r - g) >= org) &
              ((r - b) >= orb) & (r >= orm))

    # 黄绿核心：G 最大 + R/G 都远高于 B
    yg = ((g >= r) & (g >= b) & (r * 10 >= b * 12) & (g * 10 >= b * 12) &
          (chroma >= vs))

    # 深色
    dark = (mx < bt) & (chroma < bs)
    return orange, yg, dark


def bbox(mask, min_pix=MIN_PIX, max_w=MAX_W, max_h=MAX_H, proj_th=PROJ_TH):
    ys, xs = np.nonzero(mask)
    if len(xs) < min_pix:
        return None
    x0 = x1 = y0 = y1 = None
    for yy in range(mask.shape[0]):
        row = np.nonzero(mask[yy])[0]
        if len(row) >= proj_th:
            if y0 is None:
                y0 = yy
            y1 = yy
            x0 = int(row.min()) if x0 is None else min(x0, int(row.min()))
            x1 = int(row.max()) if x1 is None else max(x1, int(row.max()))
    if y0 is None or (x1 - x0) < 1 or (y1 - y0) < 1:
        return None
    if (x1 - x0) > max_w or (y1 - y0) > max_h:
        return None
    return x0, x1, y0, y1, int(mask.sum())


def detect(px, **kw):
    om, ym, dm = masks(px, **kw)
    out = []
    for m, mp, nm in ((om, MIN_PIX, "改锥"), (ym, YGMIN, "魔方"), (dm, MIN_PIX, "黑物体")):
        bb = bbox(m, mp)
        if bb:
            out.append((nm, bb))
        else:
            out.append((nm, None))
    return out


def show(tag, px, **kw):
    r = detect(px, **kw)
    parts = []
    for nm, bb in r:
        if bb is None:
            parts.append("%s:-" % nm)
        else:
            parts.append("%s: box=%s cnt=%d" % (nm, bb[:4], bb[4]))
    print("  %-24s %s" % (tag, "  |  ".join(parts)))


if __name__ == "__main__":
    from PIL import Image

    def L(p, size=(1280, 720)):
        return np.asarray(Image.open(p).convert("RGB").resize(size, Image.BILINEAR))

    SCREW = r"C:\Users\Lenovo\Documents\Tencent Files\2195166973\nt_qq\nt_data\Pic\2026-10\Ori\2639de0745648dbc8cd34828e1daaeba.jpg"
    BLACK = r"C:\Users\Lenovo\Documents\Tencent Files\2195166973\nt_qq\nt_data\Pic\2026-10\Ori\242b907b1aec3ebcb1338acc0b198abb.jpg"
    CUBE  = r"C:\Users\Lenovo\.workbuddy-ai\clipboard-images\clipboard-2026-10-29T10-28-19-936Z-2c740bee.jpg"
    MON   = r"C:\Users\Lenovo\Documents\Tencent Files\2195166973\nt_qq\nt_data\Pic\2026-10\Ori\5a9648c013a895b6de641c1d25691786.jpg"

    print("【真实照片】")
    show("改锥照片", L(SCREW))
    show("黑色物体照片", L(BLACK))
    show("魔方照片", L(CUBE))

    # 显示器照片里的笔记本屏幕（误检源）—— 单独裁出来
    mo = Image.open(MON).convert("RGB")
    show("笔记本屏幕(误检源)", np.asarray(mo.crop((230, 60, 470, 390)).resize((1280, 720), Image.BILINEAR)))
    show("显示器全图", L(MON))

    print("\n【灵敏度扫描】")
    for th in (40, 50, 60, 70, 80):
        r = detect(L(CUBE), vs=th)
        print("  VIVID_SAT=%3d -> 魔方 %s" % (th, "检出" if r[1][1] else "未检出"))
    for th in (30, 40, 50, 60):
        r = detect(L(BLACK), bt=th)
        print("  BLK_TH=%3d -> 黑色 %s" % (th, "检出" if r[2][1] else "未检出"))
    for th in (40, 60, 80, 100):
        r = detect(L(SCREW), orb=th)
        print("  ORANGE_RB=%3d -> 改锥 %s" % (th, "检出" if r[0][1] else "未检出"))
    for th in (100, 140, 180):
        r = detect(L(SCREW), orm=th)
        print("  ORANGE_RMIN=%3d -> 改锥 %s" % (th, "检出" if r[0][1] else "未检出"))
