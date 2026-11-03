#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
probe_black.py -- 黑色物体 vs 键盘暗区 的精细取证

目标
---------------------------------------------------------------------------
在【正确的 16:9 窗口】下，定位真实的黑色方块，逐像素统计它与
干扰源（键盘暗缝 / 键帽阴影 / 手指暗部 / 显示器暗条）的颜色差异，
找出可分层的判据。

同时输出掩膜叠加图，便于目视确认落点。
"""
import os
import numpy as np
from PIL import Image

DS = 8
W, H = 160, 90
BLACK = r"C:\Users\Lenovo\Documents\Tencent Files\2195166973\nt_qq\nt_data\Pic\2026-10\Ori\242b907b1aec3ebcb1338acc0b198abb.jpg"
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "out_eval")

TOP = 1050


def load(path, top):
    im = Image.open(path).convert("RGB")
    w, h = im.size
    th = int(w * 9 / 16)
    top = max(0, min(top, h - th))
    return np.asarray(im.crop((0, top, w, top + th)).resize((1280, 720), Image.BILINEAR))


def main():
    px = load(BLACK, TOP)
    s = px.astype(np.int16)[::DS, ::DS, :]
    r, g, b = s[:, :, 0], s[:, :, 1], s[:, :, 2]
    mx = np.maximum(np.maximum(r, g), b)
    mn = np.minimum(np.minimum(r, g), b)
    chroma = mx - mn

    print("=== 窗口内 mx 分位数（亮度）===")
    for p in (1, 3, 5, 10, 20, 30, 50, 70, 90):
        print("  p%-3d  mx=%3d  chroma=%3d" % (p, int(np.percentile(mx, p)),
                                              int(np.percentile(chroma, p))))

    # ---- 手工圈定 ROI：网格坐标 (x0,x1,y0,y1) ----
    # 真黑方块：从图上看在 1280 坐标 x≈230..470, y≈0..250  -> 网格 x≈29..58, y≈0..31
    rois = {
        "真黑方块(手捏黑物)": (28, 58, 0, 30),
        "手指暗部(左下)": (0, 25, 45, 88),
        "键帽区(右上)": (95, 155, 5, 45),
        "键帽文字暗": (100, 120, 55, 70),
        "键缝暗线": (60, 95, 40, 60),
    }
    print("\n=== 各 ROI 的颜色统计 ===")
    print("  %-20s %6s %6s %6s %6s %6s %6s %6s" %
          ("ROI", "mx_med", "mx_p90", "chr_med", "chr_p90", "r_med", "g_med", "b_med"))
    for name, (x0, x1, y0, y1) in rois.items():
        sub_mx = mx[y0:y1, x0:x1]
        sub_ch = chroma[y0:y1, x0:x1]
        sub_r = r[y0:y1, x0:x1]
        sub_g = g[y0:y1, x0:x1]
        sub_b = b[y0:y1, x0:x1]
        print("  %-20s %6d %6d %6d %6d %6d %6d %6d" % (
            name,
            int(np.median(sub_mx)), int(np.percentile(sub_mx, 90)),
            int(np.median(sub_ch)), int(np.percentile(sub_ch, 90)),
            int(np.median(sub_r)), int(np.median(sub_g)), int(np.median(sub_b))))

    # ---- 分层判据的命中率对比 ----
    print("\n=== 候选判据在 ROI 上的命中率 ===")
    crits = {
        "mx<40 & chr<24": (mx < 40) & (chroma < 24),
        "mx<32 & chr<16": (mx < 32) & (chroma < 16),
        "mx<28 & chr<12": (mx < 28) & (chroma < 12),
        "mx<30 & chr<20": (mx < 30) & (chroma < 20),
        "mx<36 & chr<14": (mx < 36) & (chroma < 14),
    }
    hdr = "  %-18s" % "判据"
    for name in rois:
        hdr += "%14s" % name[:12]
    print(hdr)
    for cn, m in crits.items():
        line = "  %-18s" % cn
        for name, (x0, x1, y0, y1) in rois.items():
            sub = m[y0:y1, x0:x1]
            line += "%13.0f%%" % (100.0 * sub.sum() / max(1, sub.size))
        print(line)

    # ---- 掩膜叠加图 ----
    base = np.asarray(Image.fromarray(px.astype(np.uint8)).resize((640, 360)))
    panels = [base]
    for cn, m in (("mx<40&c<24", (mx < 40) & (chroma < 24)),
                  ("mx<32&c<16", (mx < 32) & (chroma < 16)),
                  ("mx<28&c<12", (mx < 28) & (chroma < 12))):
        p = base.copy()
        mm = np.asarray(Image.fromarray((m * 255).astype(np.uint8)).resize((640, 360), Image.NEAREST))
        p[mm > 0] = (0, 220, 255)
        panels.append(p)
    # ROI 参考线（画在第 2 张上）
    p = panels[1].copy()
    for name, (x0, x1, y0, y1) in rois.items():
        col = {"真黑方块(手捏黑物)": (255, 0, 0), "手指暗部(左下)": (255, 255, 0),
               "键帽区(右上)": (0, 255, 0), "键帽文字暗": (255, 0, 255),
               "键缝暗线": (255, 128, 0)}[name]
        for k in range(4):
            p[y0 * 4, x0 * 4 + k] = col
            p[y1 * 4 + 3, x0 * 4 + k] = col
            p[y0 * 4 + k, x0 * 4] = col
            p[y0 * 4 + k, x1 * 4 + 3] = col
    panels[1] = p
    Image.fromarray(np.concatenate(panels, axis=1)).save(os.path.join(OUT, "probe_black.png"))
    print("\n  -> out_eval/probe_black.png  (原图 | mx<40&c<24+ROI框 | mx<32&c<16 | mx<28&c<12)")


if __name__ == "__main__":
    main()
