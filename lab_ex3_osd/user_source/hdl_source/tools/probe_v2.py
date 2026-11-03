#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
probe_v2.py -- 自动分割 + 域一致性验证

两件事：
  ① 自动分割：不再手挑 ROI（上一版手挑 ROI 取偏了），改用颜色规则自动
     找出每张照片里的目标像素，输出中位色 + 连通块面积 + 外接框。
     同时把每个分割结果存成 PNG 供肉眼复核。

  ② 域一致性：验证「照片(显示域) --反gamma--> raw --正gamma--> 显示域」
     能否回到原图。若成立，则说明【显示域阈值】可以直接搬到
     【raw 域 RTL】上用（前提是 RTL 内部也做同样的 gamma 变换）。
"""

import os
import numpy as np
from PIL import Image

GAMMA = 0.45
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "out_eval")
CLIP = r"C:\Users\Lenovo\.workbuddy-ai\clipboard-images"
ORI = r"C:\Users\Lenovo\Documents\Tencent Files\2195166973\nt_qq\nt_data\Pic\2026-10\Ori"


def to_raw(a):
    a = np.clip(a.astype(np.float64), 0, 255) / 255.0
    return 255.0 * np.power(a, 1.0 / GAMMA)


def to_disp(a):
    """工程 gamma_correction 的 CHROMA_KEEP=1 路径（含 dehaze 黑电平 16 的反算）"""
    a = np.clip(a.astype(np.float64) - 16, 0, 255) / 255.0
    return 255.0 * np.power(a, GAMMA)


def rgb_arr(px):
    return (px[:, :, 0].astype(np.float64),
            px[:, :, 1].astype(np.float64),
            px[:, :, 2].astype(np.float64))


def classes(r, g, b):
    """返回各类掩码（显示域口径）"""
    mx = np.maximum(np.maximum(r, g), b)
    mn = np.minimum(np.minimum(r, g), b)
    ch = mx - mn
    out = {}
    # 橙色：R 最高，G 明显高于 B
    out["orange"] = (r > g) & (g > b + 25) & ((g - b) > 45) & (r > 120) & (ch > 45)
    # 红色：R 最高，G≈B（G-B 小）
    out["red"] = (r > g + 40) & (g <= b + 30) & (r > 100) & (ch > 70)
    # 黄绿/黄
    out["yellowgreen"] = (g >= r) & (g > b + 60) & (ch > 70)
    # 青
    out["cyan"] = (b > r + 40) & (g > r + 20) & (ch > 60)
    # 绿
    out["green"] = (g > r + 20) & (g > b + 40) & (ch > 50)
    # 黑：低亮度低彩度
    out["black"] = (mx < 90) & (ch < 35)
    # 肤色：R,G 都高且接近，B 接近 G
    out["skin"] = (r > 120) & (abs(r - g) < 45) & (b > g - 25) & (ch < 60)
    return out


def comp_info(mask):
    """简单连通块：用 4 邻域膨胀做粗略估计（无 scipy）"""
    n = int(mask.sum())
    if n == 0:
        return 0, None
    ys, xs = np.nonzero(mask)
    return n, (int(xs.min()), int(xs.max()), int(ys.min()), int(ys.max()))


def describe(tag, px, mask, save=None):
    r, g, b = rgb_arr(px)
    n, bb = comp_info(mask)
    if n < 30:
        print("    %-12s  像素 %6d  -- 太少，跳过" % (tag, n))
        return
    sel = mask
    rm = float(np.median(r[sel])); gm = float(np.median(g[sel])); bm = float(np.median(b[sel]))
    mx = max(rm, gm, bm); mn = min(rm, gm, bm)
    print("    %-12s 像素 %7d (%5.2f%%)  med RGB=(%3.0f,%3.0f,%3.0f)  "
          "chroma=%3.0f  G-B=%4.0f  R-B=%4.0f  bb=%s" % (
              tag, n, 100.0 * n / mask.size, rm, gm, bm, mx - mn, gm - bm, rm - bm, bb))
    if save is not None:
        sub = px.copy()
        sub[~mask] = (sub[~mask] * 0.25).astype(np.uint8)
        Image.fromarray(sub).resize((px.shape[1] // 2, px.shape[0] // 2)).save(save)


def main():
    if not os.path.isdir(OUT):
        os.makedirs(OUT)
    scenes = [
        ("P1_cube_cyan", CLIP + r"\clipboard-2026-10-29T08-22-13-939Z-656e9830.jpg"),
        ("P2_screw", CLIP + r"\clipboard-2026-10-29T08-22-13-944Z-f82440c0.jpg"),
        ("P3_cube_yellow", CLIP + r"\clipboard-2026-10-29T08-22-13-942Z-f4e5bda1.jpg"),
        ("P4_black", CLIP + r"\clipboard-2026-10-29T08-25-53-241Z-9cc98923.jpg"),
        ("O_screw", ORI + r"\2639de0745648dbc8cd34828e1daaeba.jpg"),
        ("O_black", ORI + r"\242b907b1aec3ebcb1338acc0b198abb.jpg"),
        ("O_monitor", ORI + r"\5a9648c013a895b6de641c1d25691786.jpg"),
    ]
    for name, path in scenes:
        if not os.path.exists(path):
            print("!! 缺文件", path); continue
        im = Image.open(path).convert("RGB")
        W, H = im.size
        # 统一到 16:9 取景窗口（模拟 FPGA 取景）；竖拍图从中间取
        th = int(W * 9 / 16)
        if H >= th:
            im2 = im.crop((0, (H - th) // 2, W, (H - th) // 2 + th))
        else:
            im2 = im.crop((0, 0, W, H)).resize((1280, 720), Image.BILINEAR)
        px = np.asarray(im2.resize((1280, 720), Image.BILINEAR))
        print("=" * 110)
        print("%s   原图 %dx%d -> 取景 1280x720" % (name, W, H))
        print("=" * 110)
        r, g, b = rgb_arr(px)
        cs = classes(r, g, b)
        for k in ("orange", "red", "yellowgreen", "cyan", "green", "black", "skin"):
            describe(k, px, cs[k], os.path.join(OUT, "seg_%s_%s.png" % (name, k)))
        print()

    #------------------------------------------------------------------
    # 域一致性检查
    #------------------------------------------------------------------
    print("#" * 110)
    print("域一致性：照片(显示域) --反gamma--> raw --(+16 黑电平, 正gamma)--> 显示域'")
    print("#" * 110)
    for name, path in scenes:
        if not os.path.exists(path):
            continue
        im = Image.open(path).convert("RGB")
        px = np.asarray(im)
        back = to_disp(to_raw(px))
        err = np.abs(back - px.astype(np.float64))
        r0, g0, b0 = rgb_arr(px)
        r1, g1, b1 = rgb_arr(back)
        m0 = (r0 > g0) & (g0 > b0 + 25) & ((g0 - b0) > 45) & (r0 > 120)
        m1 = (r1 > g1) & (g1 > b1 + 25) & ((g1 - b1) > 45) & (r1 > 120)
        agree = 100.0 * (m0 == m1).mean()
        print("  %-16s 往返平均误差 %5.1f LSB   橙色掩码一致率 %5.1f%%" % (
            name, err.mean(), agree))


if __name__ == "__main__":
    main()
