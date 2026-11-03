#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""v7_render.py -- 把 v7 检测框画到场景图上"""
import os, sys
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__))))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import v7_model as M
import v6_model as V6

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "out_eval")
RDIR = os.path.join(OUT, "render_v7")
COL = {"boat": (255, 144, 16), "blue": (32, 255, 32), "dark": (0, 224, 255)}


def main():
    os.makedirs(RDIR, exist_ok=True)
    for name in ["改锥", "魔方", "黑色物体", "显示器"]:
        p = os.path.join(OUT, "win_%s.png" % name)
        px = V6.load_default(p)
        res = M.detect(px)
        im = Image.fromarray(px.astype("uint8")).convert("RGB")
        d = ImageDraw.Draw(im)
        for k in ("boat", "blue", "dark"):
            b = res[k]
            if b is None:
                continue
            bx0, bx1, by0, by1, bc = b
            x0, y0 = bx0 * 8, by0 * 8
            x1, y1 = bx1 * 8 + 7, by1 * 8 + 7
            d.rectangle([x0, y0, x1, y1], outline=COL[k], width=3)
            d.text((x0 + 4, max(0, y0 - 14)), "%s %d" % ({"boat": "GAI", "blue": "MO", "dark": "HEI"}[k], bc),
                   fill=COL[k])
        o = os.path.join(RDIR, "v7_%s.png" % name)
        im.save(o)
        print("已输出", o)


if __name__ == "__main__":
    main()
