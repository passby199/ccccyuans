#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
full_view.py -- 输出原始照片完整缩略图 + 若干水平切片的缩略图
用于确认目标物在画面中的真实位置（16:9 居中裁切可能把目标裁掉）
"""
import os
import numpy as np
from PIL import Image

SCREW = r"C:\Users\Lenovo\Documents\Tencent Files\2195166973\nt_qq\nt_data\Pic\2026-10\Ori\2639de0745648dbc8cd34828e1daaeba.jpg"
BLACK = r"C:\Users\Lenovo\Documents\Tencent Files\2195166973\nt_qq\nt_data\Pic\2026-10\Ori\242b907b1aec3ebcb1338acc0b198abb.jpg"
CUBE  = r"C:\Users\Lenovo\.workbuddy-ai\clipboard-images\clipboard-2026-10-29T10-28-19-936Z-2c740bee.jpg"
MON   = r"C:\Users\Lenovo\Documents\Tencent Files\2195166973\nt_qq\nt_data\Pic\2026-10\Ori\5a9648c013a895b6de641c1d25691786.jpg"

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "out_eval")
os.makedirs(OUT, exist_ok=True)


def main():
    for tag, p in (("screw", SCREW), ("black", BLACK), ("cube", CUBE), ("mon", MON)):
        im = Image.open(p).convert("RGB")
        w, h = im.size
        print("%-6s orig=%dx%d" % (tag, w, h))
        # 全图缩略（保持比例）
        full = im.resize((360, int(360 * h / w)), Image.BILINEAR)
        # 竖向分 3 段，每段压扁成 360 宽
        segs = []
        for i in range(3):
            y0 = int(h * i / 3)
            y1 = int(h * (i + 1) / 3)
            seg = im.crop((0, y0, w, y1)).resize((360, 120), Image.BILINEAR)
            segs.append(seg)
        canvas = Image.new("RGB", (360 * 4, 260), (20, 20, 20))
        canvas.paste(full.crop((0, 0, 360, 120)), (0, 0))
        for i, s in enumerate(segs):
            canvas.paste(s, (360 * (i + 1), 0))
        canvas.save(os.path.join(OUT, "full_%s.png" % tag))
        print("   -> out_eval/full_%s.png  (左=全图缩略, 右3格=上/中/下 1/3 切片)" % tag)


if __name__ == "__main__":
    main()
