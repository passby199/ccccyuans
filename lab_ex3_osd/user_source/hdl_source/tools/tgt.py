#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
tgt.py  --  target_detect.v (v5) 的 Python 行为模型

v5 相对 v4 的三处改动（全部来自现场照片取证，2026-10-29）
===========================================================================
1. 改锥：ORANGE_TH 100→60，新增 R-G 差下限(45)、R 亮度下限(140)
   依据：实测橙色握把中位 RGB = (224,147,135) —— R-B 只有 89，
        v4 阈值 100 直接漏检。肤色 (159,144,149) 的 R-B 仅 10，
        用 R-B>=60 + R-G>=45 能把肤色挡住。

2. 魔方：单色相 → 【黄绿核心 + 蓝/红配块】
   依据：现场误检的绿框飘到了笔记本屏幕的 PPT 上 —— 蓝色标题栏
        （B 主导 + 高饱和）被单色相判据直接命中。
        魔方的本质特征是"黄面/绿面（R≈G>>B）"，
        屏幕上白色文档区是 R≈G≈B，天然不满足。
        再加"同框内还要有蓝或红高饱和块"，PPT 单色内容不会通过。

3. 黑色物体：BLK_TH 60→40、BLK_SAT 32→24
   依据：实测黑方块 mx=26,chroma=3；键盘阴影 mx=42,chroma=10。
        阈值 60 时两者都命中，阴影把框撑到 96 格宽，
        连带真方块一起被尺寸上限否决。收到 40 后阴影被挡掉。

4. 【最关键】全局外接框 → 【细分区投票 + 区内精修】
   依据：v4 用的是"全图 min/max"，背景（键盘阴影、屏幕内容）
        只要有零星命中就把框撑到全图，真目标连带被否决。
        现在把画面切成 8x10 个区，每区独立行投影，选命中最多的合法框。
        背景再大也集中在一两个区里，撑不垮真目标的框。
"""

import sys
import numpy as np

DS = 8
W, H = 160, 90

# ---- 颜色判据（与 param_ctrl.v 的 DEF_* 对应）----
ORANGE_RB = 60        # P23 改锥 R-B 差下限
ORANGE_RG = 45        # P28 改锥 R-G 差下限
ORANGE_RMIN = 140     # P27 改锥 R 亮度下限
VIVID_SAT = 60        # P26 魔方饱和度下限
BLK_TH = 40           # P25 黑色亮度上限
BLK_SAT = 24          # 黑色色度上限
MIN_PIX = 15          # P24 最小采样点数
MAX_W = 60            # 宽度上限（格）= 480 像素
MAX_H = 45            # 高度上限（格）= 360 像素
PROJ_TH = 2           # 行投影阈值
PARTNER_MIN = 20      # 魔方配块最少格数

# ---- 投票区划分 ----
VR, VC = 8, 10        # 8 行 x 10 列 = 80 区，每区 11x16 格

NAMES = ["SCREWDRIVER", "MAGIC CUBE", "BLACK OBJ"]


def classify(px, orb=ORANGE_RB, org=ORANGE_RG, orm=ORANGE_RMIN,
             vs=VIVID_SAT, bt=BLK_TH, bs=BLK_SAT):
    """px: (h,w,3) uint8 -> dict of masks（160x90 网格）"""
    s = px.astype(np.int16)[::DS, ::DS, :]
    r, g, b = s[:, :, 0], s[:, :, 1], s[:, :, 2]
    mx = np.maximum(np.maximum(r, g), b)
    mn = np.minimum(np.minimum(r, g), b)
    chroma = mx - mn

    # 改锥：R 主导 + R-B 差够 + R-G 差够 + 够亮
    orange = ((r >= g) & (r >= b) & ((r - b) >= orb) &
              ((r - g) >= org) & (r >= orm))

    # 魔方黄绿核心：G 是最大通道，且 R、G 都远高于 B（黄面/绿面）
    yg = ((g >= r) & (g >= b) & (r * 10 >= b * 12) & (g * 10 >= b * 12) &
          (chroma >= vs))

    # 魔方配块：蓝主导 / 红主导 的高饱和
    b_lead = (b > r) & (b >= g) & (chroma >= vs)
    r_lead = (r > g) & (r > b) & (chroma >= vs)

    # 黑色物体：暗 + 中性
    dark = (mx < bt) & (chroma < bs)

    return {"orange": orange, "yg": yg, "b_lead": b_lead, "r_lead": r_lead, "dark": dark}


def row_box(mask, x_lo, x_hi, y_lo, y_hi, proj_th=PROJ_TH):
    """在限定窗口内做行投影，返回 (x0,x1,y0,y1,count)"""
    x0 = x1 = y0 = y1 = None
    for yy in range(max(y_lo, 0), min(y_hi, H)):
        row = np.nonzero(mask[yy, max(x_lo, 0):min(x_hi, W)])[0]
        if len(row) >= proj_th:
            if y0 is None:
                y0 = yy
            y1 = yy
            a = int(row.min()) + max(x_lo, 0)
            b = int(row.max()) + max(x_lo, 0)
            x0 = a if x0 is None else min(x0, a)
            x1 = b if x1 is None else max(x1, b)
    if y0 is None:
        return None
    cnt = int(mask[max(y_lo, 0):min(y_hi, H), max(x_lo, 0):min(x_hi, W)].sum())
    return x0, x1, y0, y1, cnt


def best_region(mask, vr=VR, vc=VC, min_pix=MIN_PIX, max_w=MAX_W, max_h=MAX_H):
    """分区投票：每区独立精修，选命中格数最多的合法框"""
    bh = H // vr
    bw = W // vc
    best = None
    for ty in range(vr):
        for tx in range(vc):
            r = row_box(mask, tx * bw, (tx + 1) * bw, ty * bh, (ty + 1) * bh)
            if r is None:
                continue
            x0, x1, y0, y1, cnt = r
            if cnt < min_pix:
                continue
            if (x1 - x0) > max_w or (y1 - y0) > max_h:
                continue
            if best is None or cnt > best[0]:
                best = (cnt, (x0, x1, y0, y1))
    if best is None:
        return None
    return {"box": best[1], "hits": best[0]}


def detect(px, vr=VR, vc=VC, **kw):
    m = classify(px)
    out = {}
    for nm in ("orange", "yg", "dark"):
        out[nm] = best_region(m[nm], vr=vr, vc=vc, **kw)

    # 魔方：yg 框内（外扩几格）必须还有蓝/红高饱和块
    out["partner"] = 0
    if out["yg"]:
        x0, x1, y0, y1 = out["yg"]["box"]
        pad = 5
        win = np.zeros_like(m["yg"])
        win[max(0, y0 - pad):y1 + pad + 1, max(0, x0 - pad):x1 + pad + 1] = True
        out["partner"] = int(((m["b_lead"] | m["r_lead"]) & win).sum())
        if out["partner"] < PARTNER_MIN:
            out["yg"] = None
    return out


def report(tag, px, **kw):
    r = detect(px, **kw)
    found = False
    for idx, nm in enumerate(("orange", "yg", "dark")):
        v = r[nm]
        if v is None:
            print("  %-26s -> %-12s -" % (tag, NAMES[idx]))
        else:
            b = v["box"]
            print("  %-26s -> %-12s cnt=%-5d box=%s 中心=(%d,%d)"
                  % (tag, NAMES[idx], v["hits"], b,
                     (b[0] + b[1] + 1) * 4, (b[2] + b[3] + 1) * 4))
            found = True
    if not found:
        print("  %-26s -> 无目标" % tag)


def synth(bg=(200, 210, 205), color=(220, 40, 45), cx=640, cy=360, size=120):
    img = np.zeros((720, 1280, 3), np.uint8)
    img[:, :] = bg
    yy, xx = np.mgrid[0:720, 0:1280]
    img[np.abs(xx - cx) <= size // 2] = color
    img[np.abs(yy - cy) <= size // 2] = color
    return img


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("-")]

    if args:
        try:
            from PIL import Image
        except ImportError:
            print("需要 pillow:  pip install pillow")
            return 1
        print("v5 阈值：ORANGE_RB=%d ORANGE_RG=%d ORANGE_RMIN=%d VIVID_SAT=%d "
              "BLK_TH=%d BLK_SAT=%d 分区=%dx%d"
              % (ORANGE_RB, ORANGE_RG, ORANGE_RMIN, VIVID_SAT, BLK_TH, BLK_SAT, VR, VC))
        for p in args:
            im = Image.open(p).convert("RGB").resize((1280, 720))
            report(p.replace("\\", "/").split("/")[-1][-24:], np.asarray(im))
        return 0

    print("v5 阈值：ORANGE_RB=%d ORANGE_RG=%d ORANGE_RMIN=%d VIVID_SAT=%d "
          "BLK_TH=%d BLK_SAT=%d 分区=%dx%d"
          % (ORANGE_RB, ORANGE_RG, ORANGE_RMIN, VIVID_SAT, BLK_TH, BLK_SAT, VR, VC))

    print("\n[1] 改锥（实测握把 224,147,135）")
    report("握把 120px", synth(bg=(200, 205, 210), color=(224, 147, 135)))
    report("握把 60px", synth(bg=(200, 205, 210), color=(224, 147, 135), size=60))

    print("\n[2] 魔方（黄绿核心 + 蓝/红配块）")
    img = synth(bg=(200, 205, 210), color=(136, 152, 24), size=160)
    img[300:420, 560:700] = (8, 85, 111)
    report("黄+蓝", img)
    img = synth(bg=(200, 205, 210), color=(136, 152, 24), size=160)
    img[300:420, 560:700] = (103, 12, 5)
    report("黄+红", img)
    report("只有黄面(应无)", synth(bg=(200, 205, 210), color=(136, 152, 24), size=160))

    print("\n[3] 黑色物体（实测黑方块 24,26,23）")
    report("黑方块 120px", synth(bg=(200, 205, 210), color=(24, 26, 23)))
    report("黑方块 60px", synth(bg=(200, 205, 210), color=(24, 26, 23), size=60))

    print("\n[4] 不该误检")
    report("肤色手 159,144,149", synth(bg=(200, 205, 210), color=(159, 144, 149), size=80))
    report("蓝标题栏(应无魔方)", synth(bg=(230, 232, 235), color=(8, 85, 111), size=60))
    report("绿UI(应无魔方)", synth(bg=(230, 232, 235), color=(90, 200, 80), size=60))
    report("键盘阴影 42,42,38", synth(bg=(200, 205, 210), color=(42, 42, 38), size=120))
    report("白墙 200,215,205", synth(bg=(200, 215, 205), color=(200, 215, 205)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
