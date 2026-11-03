#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
v5_variants.py -- 变体对比 + 可视化核对

变体：
  A) 行内聚类 on/off    —— 决定 RTL 复杂度
  B) 输出框用 core 包围盒 / halo 包围盒 —— 决定框精度

同时输出叠加图，人工核对每个检出的框是否落在实物上。
"""
import os
import sys
import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import v5_model as M

SCREW = r"C:\Users\Lenovo\Documents\Tencent Files\2195166973\nt_qq\nt_data\Pic\2026-10\Ori\2639de0745648dbc8cd34828e1daaeba.jpg"
BLACK = r"C:\Users\Lenovo\Documents\Tencent Files\2195166973\nt_qq\nt_data\Pic\2026-10\Ori\242b907b1aec3ebcb1338acc0b198abb.jpg"
CUBE  = r"C:\Users\Lenovo\.workbuddy-ai\clipboard-images\clipboard-2026-10-29T10-28-19-936Z-2c740bee.jpg"
MON   = r"C:\Users\Lenovo\Documents\Tencent Files\2195166973\nt_qq\nt_data\Pic\2026-10\Ori\5a9648c013a895b6de641c1d25691786.jpg"

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "out_eval")

CASES = [
    ("screw", SCREW, "orange", (62, 82, 8, 82), (255, 140, 0)),
    ("black", BLACK, "dark",   (36, 97, 0, 60), (0, 200, 255)),
    ("cube",  CUBE,  "yg",     ( 6, 124, 0, 90), (0, 255, 0)),
]


def iou(a, b):
    ax0, ax1, ay0, ay1 = a
    bx0, bx1, by0, by1 = b
    ix0, iy0 = max(ax0, bx0), max(ay0, by0)
    ix1, iy1 = min(ax1, bx1), min(ay1, by1)
    iw, ih = ix1 - ix0 + 1, iy1 - iy0 + 1
    if iw <= 0 or ih <= 0:
        return 0.0
    inter = iw * ih
    ua = (ax1 - ax0 + 1) * (ay1 - ay0 + 1)
    ub = (bx1 - bx0 + 1) * (by1 - by0 + 1)
    return inter / float(ua + ub - inter)


def detect_nocluster(halo, core, cfg, gapx):
    """变体：关闭行内聚类（整行取 min/max），其余不变"""
    bands = []
    active = False
    bx0 = bx1 = by0 = by1 = 0
    cx0 = cx1 = cy0 = cy1 = 0
    bcore = 0
    c_any = False
    last = -99
    for y in range(M.H):
        idx = np.nonzero(halo[y])[0]
        if len(idx):
            blo, bhi = int(idx.min()), int(idx.max())
            bcnt = len(idx)
            sub = core[y][blo:bhi + 1]
            cidx = np.nonzero(sub)[0]
            if len(cidx):
                c_lo = int(cidx.min()) + blo
                c_hi = int(cidx.max()) + blo
                c_cnt = len(cidx)
            else:
                c_lo = c_hi = blo; c_cnt = 0
        else:
            blo = bhi = bcnt = 0; c_lo = c_hi = 0; c_cnt = 0
        if bcnt >= M.PROJ_TH:
            if not active:
                active = True; bx0, bx1, by0, by1 = blo, bhi, y, y
                bcore = c_cnt; c_any = c_cnt > 0
                if c_any: cx0, cx1, cy0, cy1 = c_lo, c_hi, y, y
            elif blo <= bx1 + gapx and bhi + gapx >= bx0:
                bx0 = min(bx0, blo); bx1 = max(bx1, bhi); by1 = y
                bcore += c_cnt
                if c_cnt:
                    if not c_any:
                        cx0, cx1, cy0, cy1 = c_lo, c_hi, y, y; c_any = True
                    else:
                        cx0 = min(cx0, c_lo); cx1 = max(cx1, c_hi)
                        cy0 = min(cy0, y); cy1 = max(cy1, y)
            else:
                bands.append(M._pack(bx0, bx1, by0, by1, cx0, cx1, cy0, cy1, bcore, c_any))
                active = True; bx0, bx1, by0, by1 = blo, bhi, y, y
                bcore = c_cnt; c_any = c_cnt > 0
                if c_any: cx0, cx1, cy0, cy1 = c_lo, c_hi, y, y
            last = y
        else:
            if active and (y - last) > M.VGAP:
                bands.append(M._pack(bx0, bx1, by0, by1, cx0, cx1, cy0, cy1, bcore, c_any))
                active = False
    if active:
        bands.append(M._pack(bx0, bx1, by0, by1, cx0, cx1, cy0, cy1, bcore, c_any))
    best = None
    for b in bands:
        if not b["ok"]: continue
        if best is None or b["core"] > best["core"]: best = b
    return best if M.gate(best, cfg) else None


def main():
    print("=" * 92)
    print("变体对比：行内聚类 on/off  ×  输出框 core/halo")
    print("=" * 92)
    for tag, path, cls, gt, col in CASES:
        im = Image.open(path).convert("RGB")
        w, h = im.size
        th = int(w * 9 / 16)
        span = max(1, h - th)
        print("\n----- %s (%s) -----" % (tag, cls))
        for mode in ("cluster", "nocluster"):
            for boxsrc in ("halo", "core"):
                ious = []
                ndet = 0
                for i in range(21):
                    px = M.crop169_at(path, int(span * i / 20.0))
                    s = px.astype(np.int32)[::M.DS, ::M.DS, :]
                    m = M.classify(s)
                    halo, core = m[cls]
                    if mode == "cluster":
                        b = M.detect_class(halo, core, M.CFG[cls])
                        b = b if M.gate(b, M.CFG[cls]) else None
                    else:
                        b = detect_nocluster(halo, core, M.CFG[cls], M.GAPX)
                    if b:
                        ndet += 1
                        bx = b["halo_box"] if boxsrc == "halo" else b["core_box"]
                        ious.append(iou(bx, gt))
                good = sum(1 for v in ious if v >= 0.2)
                print("   %-10s box=%-5s  检出=%2d/21  IoU>=0.2=%2d  平均IoU=%.3f  最大=%.3f"
                      % (mode, boxsrc, ndet, good,
                         np.mean(ious) if ious else 0, max(ious) if ious else 0))

    # -------- 可视化核对：标出每个窗口的检出框 --------
    print("\n生成叠加核对图 ...")
    for tag, path, cls, gt, col in CASES:
        im = Image.open(path).convert("RGB")
        w, h = im.size
        th = int(w * 9 / 16)
        span = max(1, h - th)
        panels = []
        for i in range(21):
            top = int(span * i / 20.0)
            px = M.crop169_at(path, top)
            r = M.detect(px)
            b = r[cls]
            img = Image.fromarray(px.astype(np.uint8)).resize((320, 180), Image.BILINEAR)
            d = ImageDraw.Draw(img)
            # GT 框（换算到 320x180：网格 160x90 -> 像素 2 倍）
            gx0, gx1, gy0, gy1 = gt
            d.rectangle([gx0 * 2, gy0 * 2, gx1 * 2 + 1, gy1 * 2 + 1], outline=(0, 0, 255))
            if b:
                bx0, bx1, by0, by1 = b["halo_box"]
                d.rectangle([bx0 * 2, by0 * 2, bx1 * 2 + 1, by1 * 2 + 1], outline=col, width=2)
            panels.append(np.asarray(img))
        rows = []
        for r0 in range(0, 21, 7):
            rows.append(np.concatenate(panels[r0:r0 + 7], axis=1))
        Image.fromarray(np.concatenate(rows, axis=0)).save(
            os.path.join(OUT, "chk_%s.png" % tag))
        print("   -> out_eval/chk_%s.png （蓝=真值框，彩色=检出框，每格一个窗口）" % tag)


if __name__ == "__main__":
    main()
