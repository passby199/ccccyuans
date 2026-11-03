#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
v6_render.py -- 把检测框画到场景图上，直观看框落在哪

用法：
    python tools/v6_render.py            # 全部场景
    python tools/v6_render.py 魔方        # 只看一个
"""

import os
import sys
import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import v6_model as M
import v6_diag

OUT = os.path.join(os.path.dirname(HERE), "out_eval")
RENDER = os.path.join(OUT, "render")
SCENES = [
    ("改锥", "win_改锥.png"),
    ("魔方", "win_魔方.png"),
    ("黑色物体", "win_黑色物体.png"),
    ("显示器", "win_显示器.png"),
]
COLS = {"orange": (255, 144, 16), "yg": (32, 255, 32), "dark": (0, 224, 255)}


def draw_box(d, box, col, w=3):
    x0, y0, x1, y1 = box
    for i in range(w):
        d.rectangle([x0 + i, y0 + i, x1 - i, y1 - i], outline=col)


def main():
    only = sys.argv[1] if len(sys.argv) > 1 else None
    if not os.path.isdir(RENDER):
        os.makedirs(RENDER)
    for name, fn in SCENES:
        if only and only not in name:
            continue
        path = os.path.join(OUT, fn)
        if not os.path.exists(path):
            continue
        disp = np.asarray(Image.open(path).convert("RGB").resize((1280, 720), Image.BILINEAR))
        raw = M.disp_to_raw(disp)
        im = Image.fromarray(disp.copy())
        d = ImageDraw.Draw(im)

        bl = v6_diag.band_list(raw)
        for k in ("orange", "yg", "dark"):
            for bi, b in enumerate(bl[k][:3]):
                hb = b["halo_box"]
                pb = (hb[0] * 8, hb[2] * 8, hb[1] * 8 + 7, hb[3] * 8 + 7)
                col = COLS[k]
                draw_box(d, pb, col, 3 if bi == 0 else 1)
                if bi == 0:
                    d.text((pb[0] + 4, max(0, pb[1] - 14)), "%s #%d core=%d" % (k, bi, b["core"]),
                           fill=col)
        dst = os.path.join(RENDER, "v6_%s.png" % name)
        im.save(dst)
        print("已输出", dst)


if __name__ == "__main__":
    main()
