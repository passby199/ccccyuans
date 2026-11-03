#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
locate_black.py -- 在网格上标出坐标，人工/程序化定位真黑方块

做法：把 160x90 检测网格的粗坐标（每 20 格一条线，每 10 格标注）
画在缩略图上，并给暗连通块编号上色，便于精确圈定 ROI。
"""
import os
import numpy as np
from PIL import Image, ImageDraw

DS = 8
W, H = 160, 90
BLACK = r"C:\Users\Lenovo\Documents\Tencent Files\2195166973\nt_qq\nt_data\Pic\2026-10\Ori\242b907b1aec3ebcb1338acc0b198abb.jpg"
SCREW = r"C:\Users\Lenovo\Documents\Tencent Files\2195166973\nt_qq\nt_data\Pic\2026-10\Ori\2639de0745648dbc8cd34828e1daaeba.jpg"
CUBE  = r"C:\Users\Lenovo\.workbuddy-ai\clipboard-images\clipboard-2026-10-29T10-28-19-936Z-2c740bee.jpg"
OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "out_eval")

CASES = [("black", BLACK, 1050), ("screw", SCREW, 150), ("cube", CUBE, 714)]


def load(path, top):
    im = Image.open(path).convert("RGB")
    w, h = im.size
    th = int(w * 9 / 16)
    top = max(0, min(top, h - th))
    return np.asarray(im.crop((0, top, w, top + th)).resize((1280, 720), Image.BILINEAR))


def comps(mask, min_px=25):
    lab = np.zeros(mask.shape, np.int32)
    cur = 0
    out = []
    ys, xs = np.nonzero(mask)
    for y0, x0 in zip(ys, xs):
        if lab[y0, x0]:
            continue
        cur += 1
        stack = [(y0, x0)]
        lab[y0, x0] = cur
        pix = []
        while stack:
            y, x = stack.pop()
            pix.append((y, x))
            for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                ny, nx = y + dy, x + dx
                if 0 <= ny < H and 0 <= nx < W and mask[ny, nx] and not lab[ny, nx]:
                    lab[ny, nx] = cur
                    stack.append((ny, nx))
        if len(pix) >= min_px:
            a = np.array(pix)
            out.append((len(pix), int(a[:, 1].min()), int(a[:, 1].max()),
                        int(a[:, 0].min()), int(a[:, 0].max())))
    out.sort(key=lambda c: -c[0])
    return out, lab


COLORS = [(255, 0, 0), (0, 255, 0), (0, 128, 255), (255, 255, 0),
          (255, 0, 255), (0, 255, 255), (255, 128, 0), (255, 255, 255)]


def main():
    for tag, path, top in CASES:
        px = load(path, top)
        s = px.astype(np.int16)[::DS, ::DS, :]
        r, g, b = s[:, :, 0], s[:, :, 1], s[:, :, 2]
        mx = np.maximum(np.maximum(r, g), b)
        mn = np.minimum(np.minimum(r, g), b)
        chroma = mx - mn
        if tag == "black":
            m = (mx < 40) & (chroma < 24)
        elif tag == "screw":
            m = (r >= g) & (r >= b) & ((r - b) >= 60) & ((r - g) >= 45) & (r >= 140)
        else:
            m = (g >= r) & (g >= b) & (r * 10 >= b * 12) & (g * 10 >= b * 12) & (chroma >= 60)

        cs, lab = comps(m, 25)
        print("\n=== %s ===" % tag)
        for i, c in enumerate(cs[:8]):
            print("  #%d n=%-5d x %d..%d  y %d..%d  (%dx%d)" %
                  (i + 1, c[0], c[1], c[2], c[3], c[4], c[2] - c[1] + 1, c[4] - c[3] + 1))

        # 上色图 + 坐标网格
        big = Image.fromarray(px.astype(np.uint8)).resize((1280, 720), Image.BILINEAR)
        ov = np.asarray(big).copy()
        lut = np.zeros((H, W, 3), np.uint8)
        order = {c[0]: i for i, c in enumerate(cs[:8])}
        for y in range(H):
            for x in range(W):
                if lab[y, x] and lab[y, x] in order:
                    lut[y, x] = COLORS[order[lab[y, x]] % len(COLORS)]
        lut = np.asarray(Image.fromarray(lut).resize((1280, 720), Image.NEAREST))
        sel = lut.sum(axis=2) > 0
        ov[sel] = (0.5 * ov[sel] + 0.5 * lut[sel]).astype(np.uint8)
        im2 = Image.fromarray(ov)
        d = ImageDraw.Draw(im2)
        for gx in range(0, W + 1, 20):
            d.line([(gx * 8, 0), (gx * 8, 720)], fill=(255, 255, 255), width=1)
            d.text((gx * 8 + 2, 4), str(gx), fill=(255, 255, 255))
        for gy in range(0, H + 1, 10):
            d.line([(0, gy * 8), (1280, gy * 8)], fill=(255, 255, 255), width=1)
            d.text((4, gy * 8 + 2), str(gy), fill=(255, 255, 255))
        im2.save(os.path.join(OUT, "loc_%s.png" % tag))
        print("  -> out_eval/loc_%s.png" % tag)


if __name__ == "__main__":
    main()
