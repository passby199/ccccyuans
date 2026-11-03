#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
check_verilog.py  --  轻量 Verilog 结构自检（无 TD 环境时用）

只查三件事（都是本工程踩过的坑）：
  1) begin/end、case/endcase、module/endmodule、function/endfunction 是否配对
     —— 配对错时 TD 报的错往往指在别的行，很难查
  2) 例化端口名是否都在模块声明里存在
     —— 端口名拼错时 TD 只警告、静默悬空，上板才发现"没反应"
  3) 例化端口数量是否和模块端口数一致（漏接）
  4) 同一个 reg 是否被多个 always 块赋值（TD 报 multiple places / non-net）
     —— 2026-10-29 踩过：v7_class 里 best_x 在 A+B 块结算、又在 C/D/E 块清零，
        TD 报 "net 'best_x[7]' is constantly driven from multiple places"，
        而且要到综合阶段才报，白白浪费一次 20 分钟编译。

用法：
  python tools/check_verilog.py a.v b.v ...
  python tools/check_verilog.py --inst top.v sub1.v sub2.v
"""

import re
import sys

KW_OPEN = {"begin": "end", "case": "endcase", "casex": "endcase", "casez": "endcase",
           "module": "endmodule", "function": "endfunction", "task": "endtask",
           "fork": "join"}
KW_CLOSE = set(KW_OPEN.values())


def strip_comments(s):
    s = re.sub(r"/\*.*?\*/", " ", s, flags=re.S)
    s = re.sub(r"//[^\n]*", " ", s)
    s = re.sub(r'"(\\.|[^"\\])*"', '""', s)
    return s


def tokens(s):
    return re.findall(r"[A-Za-z_][A-Za-z_0-9$]*|[0-9]+'[a-zA-Z0-9_]+|[0-9]+", s)


def check_balance(path):
    src = strip_comments(open(path, encoding="utf-8", errors="ignore").read())
    tk = tokens(src)
    stack = []
    ok = True
    for i, t in enumerate(tk):
        if t in KW_OPEN:
            stack.append((t, i))
        elif t in KW_CLOSE:
            if not stack:
                print("  [ERR] %s: 多余的 %s (token %d)" % (path, t, i))
                ok = False
            elif KW_OPEN[stack[-1][0]] != t:
                print("  [ERR] %s: %s 期望 %s，却遇到 %s"
                      % (path, stack[-1][0], KW_OPEN[stack[-1][0]], t))
                ok = False
                stack.pop()
            else:
                stack.pop()
    for k, i in stack:
        print("  [ERR] %s: %s 没有闭合 (token %d)" % (path, k, i))
        ok = False
    return ok


def parse_modules(path):
    """返回 {模块名: [端口名...]}"""
    src = strip_comments(open(path, encoding="utf-8", errors="ignore").read())
    mods = {}
    for m in re.finditer(r"\bmodule\s+([A-Za-z_]\w*)(.*?)\bendmodule\b", src, re.S):
        name, body = m.group(1), m.group(2)
        # 端口列表：module 名之后第一个 (...) 且其后紧跟 ;  或 #(params)(ports)
        ports = []
        pm = re.search(r"\)\s*\((.*?)\)\s*;", body, re.S)      # #(参数) (端口)
        if pm is None:
            pm = re.match(r"\s*\((.*?)\)\s*;", body, re.S)     # 无参数，直接 (端口)
        if pm is not None:
            seg = pm.group(1)
            for part in seg.split(","):
                ids = re.findall(r"[A-Za-z_]\w*", part)
                if not ids:
                    continue
                # 最后一个标识符是端口名（跳过 wire/reg/input 等关键字）
                for cand in reversed(ids):
                    if cand not in ("wire", "reg", "input", "output", "inout",
                                    "signed", "integer", "logic"):
                        ports.append(cand)
                        break
        mods[name] = ports
    return mods


def check_instances(top, subpaths):
    allmods = {}
    for p in [top] + subpaths:
        allmods.update(parse_modules(p))
    src = strip_comments(open(top, encoding="utf-8", errors="ignore").read())
    ok = True
    for m in re.finditer(r"\b([A-Za-z_]\w*)\s*(?:#\s*\(.*?\)\s*)?([A-Za-z_]\w*)\s*\((.*?)\)\s*;",
                         src, re.S):
        mtype, minst, body = m.group(1), m.group(2), m.group(3)
        if mtype not in allmods:
            continue
        declared = set(allmods[mtype])
        used = re.findall(r"\.\s*([A-Za-z_]\w*)\s*\(", body)
        if not used:
            continue
        bad = [u for u in used if u not in declared]
        if bad:
            print("  [ERR] %s: 例化 %s(%s) 用了模块里没有的端口: %s"
                  % (top, minst, mtype, ", ".join(bad)))
            ok = False
        miss = [d for d in allmods[mtype] if d not in used]
        if miss:
            print("  [WARN] %s: 例化 %s(%s) 漏接端口: %s"
                  % (top, minst, mtype, ", ".join(miss)))
    return ok


def _split_always_blocks(body):
    """按 begin/end 配平切出每个 always 块的内容"""
    blocks = []
    for am in re.finditer(r"always\s*@\s*\(([^)]*)\)", body):
        i = am.end()
        j = body.find("begin", i)
        if j < 0 or j - i > 200:
            k = body.find(";", i)
            blocks.append(body[i:k + 1])
            continue
        depth = 0
        k = j
        while k < len(body):
            if body.startswith("begin", k):
                depth += 1; k += 5
            elif body.startswith("end", k) and not body.startswith("endmodule", k):
                depth -= 1; k += 3
                if depth == 0:
                    break
            else:
                k += 1
        blocks.append(body[i:k])
    return blocks


def check_multidriver(path):
    """同一个 reg 被多个 always 块赋值 -> TD 会报多驱动"""
    src = strip_comments(open(path, encoding="utf-8", errors="ignore").read())
    ok = True
    for m in re.finditer(r"\bmodule\s+(\w+)(.*?)\bendmodule\b", src, re.S):
        name, body = m.group(1), m.group(2)
        blocks = _split_always_blocks(body)
        if len(blocks) < 2:
            continue
        from collections import defaultdict
        cnt = defaultdict(list)
        for bi, b in enumerate(blocks):
            lhs = set()
            for lm in re.finditer(r"(?:^|[\s;])(\w+)\s*(?:\[[^\]]*\])?\s*<=", b):
                lhs.add(lm.group(1))
            for lm in re.finditer(r"(?:^|[\s;])(\w+)\s*(?:\[[^\]]*\])?\s*=(?!=)", b):
                lhs.add(lm.group(1))
            for sig in lhs:
                cnt[sig].append(bi)
        for sig, bl in sorted(cnt.items()):
            if len(bl) > 1:
                print("    [%s] %s 被 always 块 %s 同时驱动" % (name, sig, bl))
                ok = False
        # assign 与 always 冲突
        for am in re.finditer(r"\bassign\s+(\w+)", body):
            if am.group(1) in cnt:
                print("    [%s] %s 同时被 assign 和 always 驱动" % (name, am.group(1)))
                ok = False
    return ok


def main():
    args = sys.argv[1:]
    inst_mode = False
    if args and args[0] == "--inst":
        inst_mode = True
        args = args[1:]
    if not args:
        print(__doc__)
        return 1
    ok = True
    print("[1] 结构配对检查")
    for p in args:
        if not check_balance(p):
            ok = False
    if ok:
        print("    全部通过")
    if inst_mode:
        print("[2] 例化端口检查")
        if check_instances(args[0], args[1:]):
            print("    全部通过")
        else:
            ok = False
    print("[3] 多驱动检查（同一 reg 被多个 always 块赋值）")
    if all(check_multidriver(p) for p in args):
        print("    全部通过")
    else:
        ok = False
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
