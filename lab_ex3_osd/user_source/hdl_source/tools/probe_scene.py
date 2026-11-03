#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
probe_scene.py -- 【现场照片】颜色取证

目的
    v5 模型的阈值是用 Ori 目录里 3 张照片标定的，但用户实际会拿
    4 张【现场照片】去测。这 4 张里有两个 v5 没考虑到的干扰源：

      ① 魔方有【红色面】 —— 现有橙色判据 (r>=g && r>=b && r-b>=60)
         对红面同样成立 ⇒ 红面会被框成"改锥"。
      ② 画面里有【人手】 —— 肤色同样是 r>=g>=b 且 r-b 较大
         ⇒ 人手会被框成"改锥"。

    所以必须先量清楚：这 5 类东西在【照片域】和【反 gamma 后的 raw 域】
    里分别长什么样，才能设计出既不误检又能命中的判据。

输出
    每个 ROI 的 R/G/B/chroma 分位数（照片域 & raw 域）
"""

import numpy as np
from PIL import Image

#==========================================================================
# 反 gamma：把照片（显示域）还原成 raw 域（RTL 检测取样点就是 raw 域）
#
#   工程里的 gamma_correction：out = 255*(in/255)^0.45
#   反函数：                  in  = 255*(out/255)^(1/0.45)
#   注意 AWB 之后还有别的处理，这里只做 gamma 这一项的近似。
#==========================================================================
GAMMA = 0.45


def to_raw(a):
    a = np.clip(a.astype(np.float64), 0, 255) / 255.0
    return 255.0 * np.power(a, 1.0 / GAMMA)


#==========================================================================
# 现场照片 + ROI（归一化坐标 x0,y0,x1,y1）
#==========================================================================
CLIP = r"C:\Users\Lenovo\.workbuddy-ai\clipboard-images"

SCENES = [
    dict(
        name="P1 魔方(青面)",
        path=CLIP + r"\clipboard-2026-10-29T08-22-13-939Z-656e9830.jpg",
        rois=[
            ("魔方青面",   0.20, 0.30, 0.42, 0.50),
            ("魔方红面",   0.30, 0.46, 0.62, 0.58),
            ("魔方绿面",   0.03, 0.37, 0.18, 0.47),
            ("键盘深灰",   0.62, 0.58, 0.92, 0.72),
            ("显示器白底", 0.05, 0.02, 0.60, 0.18),
        ],
    ),
    dict(
        name="P2 改锥(橙柄)",
        path=CLIP + r"\clipboard-2026-10-29T08-22-13-944Z-f82440c0.jpg",
        rois=[
            ("橙柄主面",   0.05, 0.26, 0.26, 0.60),
            ("橙柄小面",   0.03, 0.56, 0.13, 0.66),
            ("银色面板",   0.36, 0.16, 0.74, 0.80),
            ("黑色鼠标垫", 0.86, 0.30, 0.99, 0.72),
        ],
    ),
    dict(
        name="P3 魔方(黄绿面)",
        path=CLIP + r"\clipboard-2026-10-29T08-22-13-942Z-f4e5bda1.jpg",
        rois=[
            ("黄绿面",     0.06, 0.22, 0.45, 0.52),
            ("红色面",     0.50, 0.39, 0.64, 0.57),
            ("青面",       0.06, 0.52, 0.30, 0.60),
            ("显示器画面", 0.02, 0.02, 0.60, 0.22),
            ("键盘",       0.56, 0.26, 0.92, 0.42),
            ("手背",       0.02, 0.30, 0.14, 0.44),
            ("手指",       0.06, 0.74, 0.26, 0.92),
        ],
    ),
    dict(
        name="P4 黑色块",
        path=CLIP + r"\clipboard-2026-10-29T08-25-53-241Z-9cc98923.jpg",
        rois=[
            ("黑色块",     0.20, 0.26, 0.66, 0.49),
            ("手指皮肤",   0.16, 0.56, 0.80, 0.80),
            ("红色数据线", 0.56, 0.05, 0.94, 0.14),
            ("键盘暗区",   0.02, 0.02, 0.45, 0.16),
            ("背景灰面",   0.55, 0.80, 0.95, 0.95),
        ],
    ),
]


def stats(px, tag):
    r = px[:, :, 0].astype(np.float64)
    g = px[:, :, 1].astype(np.float64)
    b = px[:, :, 2].astype(np.float64)
    mx = np.maximum(np.maximum(r, g), b)
    mn = np.minimum(np.minimum(r, g), b)
    ch = mx - mn
    print("    %-12s %-4s R=%3d/%3d  G=%3d/%3d  B=%3d/%3d  "
          "chroma=%3d/%3d  G-B=%3d" % (
              tag,
              "p10/med" if False else "med",
              np.median(r), np.percentile(r, 90),
              np.median(g), np.percentile(g, 90),
              np.median(b), np.percentile(b, 90),
              np.median(ch), np.percentile(ch, 90),
              np.median(g - b)))
    return dict(r=np.median(r), g=np.median(g), b=np.median(b),
                ch=np.median(ch), gb=np.median(g - b),
                mx=np.median(mx))


def main():
    for sc in SCENES:
        im = Image.open(sc["path"]).convert("RGB")
        W, H = im.size
        px = np.asarray(im)
        print("=" * 96)
        print("%s   %dx%d" % (sc["name"], W, H))
        print("=" * 96)
        for (rn, x0, y0, x1, y1) in sc["rois"]:
            a = px[int(y0 * H):int(y1 * H), int(x0 * W):int(x1 * W)]
            if a.size == 0:
                continue
            print("  [%s]" % rn)
            s_disp = stats(a, "disp")
            s_raw = stats(to_raw(a), "raw ")
            print("    -> 判据量  dRB=%3d  dRG=%3d  chroma=%3d  G-B=%3d  (raw域)" % (
                s_raw["r"] - s_raw["b"], s_raw["r"] - s_raw["g"],
                s_raw["ch"], s_raw["gb"]))
            print()


if __name__ == "__main__":
    main()
