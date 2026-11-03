#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
eval_v5.py  --  最终方案评估（16:9 裁切 + 可视化）

方法学修正
---------------------------------------------------------------------------
现场照片是手机竖拍 1080x2418。直接 resize 到 1280x720 会把画面
【横向拉伸 3.4 倍】，物体形状全毁、框尺寸失真 —— 之前几轮实验的
结论都受这个影响。正确做法：居中裁 16:9 再缩放，等价于横屏相机。

判定流程（两级）
---------------------------------------------------------------------------
级 1  粗分区投票：画面切 8x10 个区，每区独立行投影 + 尺寸/点数筛选，
     选【命中格数最多】的合法区。
级 2  邻域精修：把获胜区向外扩 1 区（3x3），在该窗口内重做行投影，
     得到完整外接框（避免级1 把大物体切碎）。
魔方附加：还需一个【蓝/红高饱和】配块，且配块中心与黄绿块中心距离 <= 40 格。
"""

import sys, os
import numpy as np
from PIL import Image

DS = 8
W, H = 160, 90

# ---------- 颜色参数 ----------
ORANGE_RB = 60        # P23
ORANGE_RG = 45        # P28
ORANGE_RMIN = 140     # P27
VIVID_SAT = 60        # P26
BLK_TH = 40           # P25
BLK_SAT = 24
MIN_PIX = 15          # P24
MAX_W = 60
MAX_H = 45
PROJ_TH = 2
PARTNER_MIN = 20
PARTNER_DIST = 40

VR, VC = 8, 10        # 粗分区


def crop169(path):
    im = Image.open(path).convert("RGB")
    w, h = im.size
    if h / w > 9.0 / 16.0:               # 竖图 -> 裁上下
        th = int(w * 9 / 16)
        top = int((h - th) * 0.30)
        return im.crop((0, top, w, top + th)).resize((1280, 720), Image.BILINEAR)
    tw = int(h * 16 / 9)                  # 横图 -> 裁左右
    left = (w - tw) // 2
    return im.crop((left, 0, left + tw, h)).resize((1280, 720), Image.BILINEAR)


def classify(px, orb=ORANGE_RB, org=ORANGE_RG, orm=ORANGE_RMIN,
             vs=VIVID_SAT, bt=BLK_TH, bs=BLK_SAT):
    s = px.astype(np.int16)[::DS, ::DS, :]
    r, g, b = s[:, :, 0], s[:, :, 1], s[:, :, 2]
    mx = np.maximum(np.maximum(r, g), b)
    mn = np.minimum(np.minimum(r, g), b)
    chroma = mx - mn
    orange = ((r >= g) & (r >= b) & ((r - b) >= orb) &
              ((r - g) >= org) & (r >= orm))
    yg = ((g >= r) & (g >= b) & (r * 10 >= b * 12) & (g * 10 >= b * 12) &
          (chroma >= vs))
    b_lead = (b > r) & (b >= g) & (chroma >= vs)
    r_lead = (r > g) & (r > b) & (chroma >= vs)
    dark = (mx < bt) & (chroma < bs)
    return {"orange": orange, "yg": yg, "b_lead": b_lead, "r_lead": r_lead, "dark": dark}


def row_box(mask, x_lo, x_hi, y_lo, y_hi):
    x0 = x1 = y0 = y1 = None
    for yy in range(max(y_lo, 0), min(y_hi, H)):
        row = np.nonzero(mask[yy, max(x_lo, 0):min(x_hi, W)])[0]
        if len(row) >= PROJ_TH:
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


def vote_refine(mask, vr=VR, vc=VC, expand=1, min_pix=MIN_PIX,
                max_w=MAX_W, max_h=MAX_H):
    """级1 分区投票 -> 级2 邻域精修"""
    bh, bw = H // vr, W // vc
    best = None
    for ty in range(vr):
        for tx in range(vc):
            r = row_box(mask, tx * bw, (tx + 1) * bw, ty * bh, (ty + 1) * bh)
            if r is None:
                continue
            if r[4] < min_pix:
                continue
            if (r[1] - r[0]) > max_w or (r[3] - r[2]) > max_h:
                continue
            if best is None or r[4] > best[4]:
                best = r + (ty, tx)
    if best is None:
        return None
    _, _, _, _, _, by, bx = best
    y_lo = max(0, (by - expand) * bh)
    y_hi = min(H, (by + expand + 1) * bh)
    x_lo = max(0, (bx - expand) * bw)
    x_hi = min(W, (bx + expand + 1) * bw)
    r = row_box(mask, x_lo, x_hi, y_lo, y_hi)
    if r is None:
        return None
    x0, x1, y0, y1, cnt = r
    if cnt < min_pix:
        return None
    if (x1 - x0) > max_w or (y1 - y0) > max_h:
        return None
    return {"box": (x0, x1, y0, y1), "hits": cnt, "reg": (by, bx)}


def detect(px, **kw):
    m = classify(px)
    out = {}
    for nm in ("orange", "yg", "dark"):
        out[nm] = vote_refine(m[nm], **kw)

    # 魔方配块：找【不含黄绿核心】的蓝/红高饱和簇
    # 关键：配块必须与黄绿块【相邻但不重叠】—— 同一个物体上的不同面
    partner = None
    if out["yg"]:
        x0, x1, y0, y1 = out["yg"]["box"]
        pm = (m["b_lead"] | m["r_lead"]) & ~m["yg"]
        # 只在黄绿块外扩 12 格的窗口里找
        pad = 12
        win = np.zeros_like(pm)
        win[max(0, y0 - pad):y1 + pad + 1, max(0, x0 - pad):x1 + pad + 1] = True
        pm = pm & win
        pb = vote_refine(pm, min_pix=PARTNER_MIN)
        if pb:
            partner = pb
    out["partner_box"] = partner
    out["cube_ok"] = False
    if out["yg"] and partner:
        x0, x1, y0, y1 = out["yg"]["box"]
        px0, px1, py0, py1 = partner["box"]
        gx, gy = (x0 + x1) * 4, (y0 + y1) * 4
        cx, cy = (px0 + px1) * 4, (py0 + py1) * 4
        d = max(abs(gx - cx), abs(gy - cy))
        out["cube_ok"] = (d <= PARTNER_DIST)
        out["cube_dist"] = d
    return out


def visualize(px, res, path):
    base = np.asarray(Image.fromarray(px.astype(np.uint8)).resize((640, 360)))
    panels = []
    for nm, col in (("orange", (255, 140, 0)), ("yg", (0, 255, 0)), ("dark", (0, 200, 255))):
        p = base.copy()
        v = res[nm]
        if v:
            x0, x1, y0, y1 = v["box"]
            p[y0 * 8 // 2:y1 * 8 // 2 + 4, x0 * 8 // 2:x1 * 8 // 2 + 4] = col
        panels.append(p)
    img = Image.fromarray(np.concatenate([base] + panels, axis=1))
    img.save(path)


def main():
    SCREW = r"C:\Users\Lenovo\Documents\Tencent Files\2195166973\nt_qq\nt_data\Pic\2026-10\Ori\2639de0745648dbc8cd34828e1daaeba.jpg"
    BLACK = r"C:\Users\Lenovo\Documents\Tencent Files\2195166973\nt_qq\nt_data\Pic\2026-10\Ori\242b907b1aec3ebcb1338acc0b198abb.jpg"
    CUBE = r"C:\Users\Lenovo\.workbuddy-ai\clipboard-images\clipboard-2026-10-29T10-28-19-936Z-2c740bee.jpg"
    MON = r"C:\Users\Lenovo\Documents\Tencent Files\2195166973\nt_qq\nt_data\Pic\2026-10\Ori\5a9648c013a895b6de641c1d25691786.jpg"

    os.makedirs("/tmp/tgt2", exist_ok=True)
    cases = [("改锥", SCREW), ("黑色物体", BLACK), ("魔方", CUBE),
             ("显示器(误检源)", MON)]

    print("【16:9 裁切 + 两级分区】")
    for tag, p in cases:
        px = np.asarray(crop169(p))
        r = detect(px)
        print("  %-16s" % tag, end="")
        for nm, lbl in (("orange", "改锥"), ("yg", "魔方"), ("dark", "黑物")):
            v = r[nm]
            print("  %s:%s" % (lbl, ("box=%s n=%d" % (v["box"], v["hits"])) if v else "-"), end="")
        print("   配块=%s 魔方成立=%s" %
              (r["partner_box"]["box"] if r["partner_box"] else "-", r["cube_ok"]))
        visualize(px, r, "/tmp/tgt2/%s.png" % tag)

    print("\n【阈值灵敏度】")
    for th in (40, 50, 60, 70):
        px = np.asarray(crop169(CUBE))
        r = detect(px, vs=th) if False else detect(px)
        print("  VIVID_SAT=%3d -> 魔方=%s 配块=%s 成立=%s"
              % (th, "Y" if r["yg"] else "N",
                 r["partner_box"]["box"] if r["partner_box"] else "-", r["cube_ok"]))
    for th in (30, 40, 50, 60):
        px = np.asarray(crop169(BLACK))
        r = detect(px, bt=th)
        print("  BLK_TH=%3d -> 黑色=%s" % (th, ("box=%s n=%d" % (r["dark"]["box"], r["dark"]["hits"])) if r["dark"] else "-"))
    for th in (40, 60, 80, 100):
        px = np.asarray(crop169(SCREW))
        r = detect(px, orb=th)
        print("  ORANGE_RB=%3d -> 改锥=%s" % (th, ("box=%s n=%d" % (r["orange"]["box"], r["orange"]["hits"])) if r["orange"] else "-"))


if __name__ == "__main__":
    main()
