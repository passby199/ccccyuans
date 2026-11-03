#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
v6_calib.py -- v5/v6 判据的【定量标定】

为什么需要这个脚本
    RTL 的取样点是 S_video_rd_data（raw 域，OSD 之前）。
    而我们手上的照片/截图有三种域：
        · 手机照片      —— 拍摄现场的显示域（带手机 ISP）
        · FPGA 屏截图   —— 显示域（raw → dehaze → gamma 之后）
        · win_*.png     —— 1280x720，FPGA 直出画面（带 OSD 叠加）
    三者不能直接混用，必须换算到 raw 域才能定阈值。

本脚本做三件事
    ① 精确逆变换：display -> raw
       正向链（design_top_wrapper.v）：
         raw --dehaze(BL=16, ×17/16)--> d --gamma(CHROMA_KEEP=1, SAT_BOOST=16)--> disp
       dehaze : d = (raw-16) + (raw-16)/16          （逐通道，同一映射）
       gamma  : Y_in=mean(d)，Y_out=F_gamma(Y_in)，delta=Y_out-Y_in（三通道同加）
                ⇒ 颜色【差值】在 gamma 中严格不变
       所以逆变换唯一：
         Y_out = round(mean(disp))（无钳位时）
         Y_in  = F_gamma^-1(Y_out)，delta = Y_out - Y_in
         d     = disp - delta
         raw   = d * 16/17 + 16
    ② OSD 区域剔除：logo 矩形 + 动态文字矩形 + 三色检测框（否则统计被 OSD 污染）
    ③ scipy 连通块分析：在 raw 域上跑判据，列出每类候选连通块的
       面积 / 包围盒 / 中位 RGB / 关键色差

用法：
    python tools/v6_calib.py
"""

import os
import sys
import numpy as np
from PIL import Image

try:
    from scipy import ndimage
except Exception:
    ndimage = None

HERE = os.path.dirname(os.path.abspath(__file__))
HDLDIR = os.path.dirname(HERE)
OUT = os.path.join(HDLDIR, "out_eval")
WIN = os.path.join(OUT, "")

# ---------------------------------------------------------------------------
# gamma 8 段折线（与 gamma_correction.v 的 F_gamma 逐位一致）
#   断点 in : 0  16  32  48  64  96  128 192 255
#   断点 out: 0  73 100 120 137 164  187 224 255
# ---------------------------------------------------------------------------
GAMMA_BP_IN = [0, 16, 32, 48, 64, 96, 128, 192, 255]
GAMMA_BP_OUT = [0, 73, 100, 120, 137, 164, 187, 224, 255]

FWD_SEG = [  # (lo, hi, out_lo, out_hi, 分子, 分母, 舍入加数)  —— 与 RTL 折线对应
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
    """RTL F_gamma 的 numpy 版（逐位一致）"""
    x = np.asarray(x)
    out = np.zeros_like(x, dtype=np.int32)
    for (lo, hi, olo, ohi, num, den, rnd) in FWD_SEG:
        m = (x >= lo) & (x < hi)
        if not m.any():
            continue
        xb = (x[m] - lo).astype(np.int32)
        v = olo + ((xb * num + rnd) >> int(np.log2(den)))
        out[m] = np.minimum(v, ohi)
    return out


def build_gamma_inv_lut():
    """F_gamma 的逆（单调上升，做 LUT 反查）"""
    tbl = f_gamma(np.arange(256, dtype=np.int32))
    inv = np.zeros(256, dtype=np.int32)
    # 折线段内线性插值反查更准
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
        # y = olo + ((xb*num + rnd) >> log2den)  -> 反解 xb
        span = ohi - olo
        xb = int(round(((y - olo) * den - rnd) / float(num)))
        xb = max(0, min(hi - 1 - lo, xb))
        inv[y] = lo + xb
    # 单调修正
    inv = np.maximum.accumulate(inv)
    return inv


GAMMA_INV = build_gamma_inv_lut()


def disp_to_raw(disp):
    """
    显示域 -> raw 域（标量/数组皆可，uint8 三通道）
    逆链： Y_out=mean(disp) -> Y_in=GAMMA_INV[Y_out] -> d=disp-delta -> raw=d*16/17+16
    """
    disp = np.asarray(disp, dtype=np.float64)
    shape = disp.shape
    flat = disp.reshape(-1, 3)
    mean = flat.mean(axis=1)
    y_out = np.clip(np.round(mean), 0, 255).astype(np.int32)
    y_in = GAMMA_INV[y_out].astype(np.float64)
    delta = y_out.astype(np.float64) - y_in
    d = flat - delta[:, None]
    raw = d * (16.0 / 17.0) + 16.0
    return np.clip(raw, 0, 255).reshape(shape)


# ---------------------------------------------------------------------------
# OSD 区域（hdmi_mixer.v 常量 + target_osd 三色框）
# ---------------------------------------------------------------------------
LOGO_X, LOGO_Y, LOGO_W, LOGO_H = 0, 0, 160, 160
DYN_X, DYN_Y, DYN_W, DYN_H = 375, 120, 200, 160
OSD_BOX_COLORS = {
    "orange_box": (0xFF, 0x90, 0x10),
    "vivid_box": (0x20, 0xFF, 0x20),
    "dark_box": (0x00, 0xE0, 0xFF),
    "logo_red": (0xEC, 0x1C, 0x2D),
    "logo_blue": (0x1F, 0x31, 0x5C),
    "dyn_yellow": (0xFF, 0xF2, 0x00),
    "dyn_cyan": (0x00, 0xE6, 0xFF),
    "card_black": (0x00, 0x00, 0x00),
    "text_white": (0xFF, 0xFF, 0xFF),
}


def osd_mask(shape):
    """True = 该像素属于 OSD 叠加（统计时应剔除）"""
    h, w = shape[:2]
    m = np.zeros((h, w), bool)
    m[LOGO_Y:LOGO_Y + LOGO_H, LOGO_X:LOGO_X + LOGO_W] = True
    m[DYN_Y:DYN_Y + DYN_H, DYN_X:DYN_X + DYN_W] = True
    return m


def exact_color_mask(rgb, c, tol=2):
    return (np.abs(rgb[:, :, 0].astype(np.int32) - c[0]) <= tol) & \
           (np.abs(rgb[:, :, 1].astype(np.int32) - c[1]) <= tol) & \
           (np.abs(rgb[:, :, 2].astype(np.int32) - c[2]) <= tol)


def describe(px, mask, tag, top=8):
    """列出连通块"""
    if ndimage is None:
        print("  (无 scipy，跳过连通块)")
        return []
    lab, n = ndimage.label(mask)
    if n == 0:
        print("    %-10s  无连通块" % tag)
        return []
    objs = ndimage.find_objects(lab)
    info = []
    for i, sl in enumerate(objs):
        m = (lab[sl] == i + 1)
        cnt = int(m.sum())
        if cnt < 8:
            continue
        ys, xs = sl
        sub = px[sl][m]
        med = np.median(sub, axis=0)
        info.append(dict(cnt=cnt, x0=xs.start, x1=xs.stop - 1,
                         y0=ys.start, y1=ys.stop - 1,
                         rgb=tuple(float(v) for v in med)))
    info.sort(key=lambda t: -t["cnt"])
    print("    %-10s  连通块 %d 个" % (tag, len(info)))
    for t in info[:top]:
        r, g, b = t["rgb"]
        print("        面积 %6d  框(%3d,%3d)-(%3d,%3d)  med RGB=(%3.0f,%3.0f,%3.0f)"
              "  R-G=%4.0f R-B=%4.0f G-B=%4.0f" %
              (t["cnt"], t["x0"], t["y0"], t["x1"], t["y1"], r, g, b,
               r - g, r - b, g - b))
    return info


# ---------------------------------------------------------------------------
def load(path):
    im = Image.open(path).convert("RGB")
    if im.size != (1280, 720):
        im = im.resize((1280, 720), Image.BILINEAR)
    return np.asarray(im)


def analyze_scene(name, path, raw_tap=True):
    print("=" * 100)
    print("%s   %s" % (name, os.path.basename(path)))
    print("=" * 100)
    disp = load(path)
    om = osd_mask(disp.shape)

    # OSD 颜色检出（判断是不是 FPGA 直出）
    hits = {}
    for k, c in OSD_BOX_COLORS.items():
        n = int(exact_color_mask(disp, c).sum())
        if n > 20:
            hits[k] = n
    print("  OSD 颜色命中: %s" % (hits if hits else "无 -> 不是 FPGA 直出/已裁剪"))

    # 剔除 OSD 矩形 + OSD 颜色像素
    clean = disp.copy()
    clean[om] = 0

    if raw_tap:
        px = disp_to_raw(disp.astype(np.float64))
        print("  域: 显示域 -> raw 域（逆变换）")
    else:
        px = disp.astype(np.float64)
        print("  域: 显示域")

    r = px[:, :, 0]
    g = px[:, :, 1]
    b = px[:, :, 2]
    mx = np.maximum(np.maximum(r, g), b)
    mn = np.minimum(np.minimum(r, g), b)
    chroma = mx - mn
    rg = r - g
    rb = r - b
    gb = g - b

    keep = ~om
    # 剔除 OSD 纯色像素（框/字）—— 只剔饱和的框色，白色/黑色是场景内容，不能剔
    for k, c in OSD_BOX_COLORS.items():
        if k in ("card_black", "text_white"):
            continue
        keep &= ~exact_color_mask(disp, c, tol=3)

    def show(tag, m):
        m = m & keep
        if m.sum() < 30:
            print("    %-12s 像素 %6d  太少" % (tag, int(m.sum())))
            return None
        sel = m
        rm = float(np.median(r[sel])); gm = float(np.median(g[sel])); bm = float(np.median(b[sel]))
        print("    %-12s 像素 %7d (%5.2f%%)  med RGB=(%3.0f,%3.0f,%3.0f)  chroma=%3.0f "
              "R-G=%4.0f R-B=%4.0f G-B=%4.0f" %
              (tag, int(m.sum()), 100.0 * m.sum() / m.size, rm, gm, bm,
               float(np.median(chroma[sel])), float(np.median(rg[sel])),
               float(np.median(rb[sel])), float(np.median(gb[sel]))))
        return m

    print("  --- 颜色分割统计（raw 域）---")
    m_or = show("orange(候选)", (r >= g) & (r >= b) & (rb >= 60) & (rg >= 45) & (r >= 140))
    show("orange+g>b", (r >= g) & (g > b) & (rb >= 60) & (rg >= 45) & (r >= 140))
    show("red(魔方红面)", (r > g + 40) & (g <= b + 30) & (r > 100) & (chroma > 70))
    show("yellowgreen", (g >= r) & (g > b + 60) & (chroma > 70))
    show("cyan", (b > r + 40) & (g > r + 20) & (chroma > 60))
    show("black", (mx < 70) & (chroma < 35))
    show("skin", (r > 120) & (np.abs(r - g) < 45) & (b > g - 25) & (chroma < 60))

    print("  --- 连通块 ---")
    if m_or is not None:
        describe(px, m_or, "orange")
    mo = (r >= g) & (g > b) & (rb >= 60) & (rg >= 45) & (r >= 140) & keep
    describe(px, mo, "orange+g>b")
    myg = (g >= r) & (g > b + 60) & (chroma > 70) & keep
    describe(px, myg, "yellowgreen")
    mbl = (mx < 70) & (chroma < 35) & keep
    describe(px, mbl, "black")
    print()


def main():
    scenes = [
        ("win_改锥", os.path.join(WIN, "win_改锥.png")),
        ("win_魔方", os.path.join(WIN, "win_魔方.png")),
        ("win_黑色物体", os.path.join(WIN, "win_黑色物体.png")),
        ("win_显示器", os.path.join(WIN, "win_显示器.png")),
    ]
    for name, p in scenes:
        if os.path.exists(p):
            analyze_scene(name, p)
        else:
            print("!! 缺", p)

    # 显示域对照（不逆变换），看同一像素两种域下的色差
    print("#" * 100)
    print("域对照：同一场景 显示域 vs raw 域 的颜色差值")
    print("#" * 100)
    for name, p in scenes:
        if not os.path.exists(p):
            continue
        disp = load(p).astype(np.float64)
        raw = disp_to_raw(disp)
        om = osd_mask(disp.shape)
        for dom, px in (("disp", disp), ("raw ", raw)):
            r, g, b = px[:, :, 0], px[:, :, 1], px[:, :, 2]
            rgb = r - g
            rb = r - b
            gb = g - b
            sel = ~om
            print("  %-14s %s  med R-G=%4.0f R-B=%4.0f G-B=%4.0f  med R=%3.0f G=%3.0f B=%3.0f"
                  % (name, dom, float(np.median(rgb[sel])), float(np.median(rb[sel])),
                     float(np.median(gb[sel])), float(np.median(r[sel])),
                     float(np.median(g[sel])), float(np.median(b[sel]))))


if __name__ == "__main__":
    main()
