#!/usr/bin/env python3
"""从 decode.py 的文本 trace 还原 HT PHY 表的写入。

PHY 表访问：0x072 写地址（表号 << 10 | 偏移），32 位值先写 0x074（高 16 位）再写
0x073（低 16 位），8/16 位值只写 0x073；每次写 0x073 后偏移自增。

  tabdump.py wl-5g.txt [--phase linked] [--table 26]   列出到某阶段末为止各表项的最终值
  tabdump.py --diff wl-5g.txt b43-5g.txt [--table 26]   对比两个 trace 的最终表内容
"""
import argparse
import re

LINE = re.compile(r"^PHY W 0x([0-9a-f]+) = 0x([0-9a-f]+)")


def load(path, upto=None):
    tab = {}  # (表号, 偏移) -> 值
    addr = None
    hi = None
    with open(path) as f:
        for line in f:
            if line.startswith("== PHASE"):
                if upto and line.split()[2] == upto:
                    break
                continue
            m = LINE.match(line)
            if not m:
                continue
            reg, val = int(m.group(1), 16), int(m.group(2), 16)
            if reg == 0x72:
                addr, hi = val, None
            elif reg == 0x74:
                hi = val
            elif reg == 0x73 and addr is not None:
                v = (hi << 16 | val) if hi is not None else val
                tab[(addr >> 10, addr & 0x3FF)] = v
                addr, hi = addr + 1, None
    return tab


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="+")
    ap.add_argument("--diff", action="store_true")
    ap.add_argument("--phase", help="在这个阶段开始前停止（默认读完整个 trace）")
    ap.add_argument("--table", type=lambda s: int(s, 0), action="append")
    a = ap.parse_args()
    want = lambda k: not a.table or k[0] in a.table
    if a.diff:
        x, y = (load(p, a.phase) for p in a.files[:2])
        for k in sorted(set(x) | set(y)):
            if want(k) and x.get(k) != y.get(k):
                fmt = lambda v: "-" if v is None else f"0x{v:x}"
                print(f"tab {k[0]:2d} off 0x{k[1]:03x}  {fmt(x.get(k))} / {fmt(y.get(k))}")
    else:
        t = load(a.files[0], a.phase)
        for k in sorted(t):
            if want(k):
                print(f"tab {k[0]:2d} off 0x{k[1]:03x}  0x{t[k]:x}")


if __name__ == "__main__":
    main()
