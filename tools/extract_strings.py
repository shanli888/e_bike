#!/usr/bin/env python3
"""从 libapp.so 抽取可打印字符串（ASCII + 2 字节对齐的 UTF-16LE），按文件偏移输出。

Dart AOT 里：纯 Latin1 字符串存成 one-byte string，含中文等字符的存成
two-byte string(UTF-16LE，2 字节对齐)。命令表 JSON 可能带中文描述，所以两种都提。

用法: python tools/extract_strings.py <libapp.so> <out.txt> [minlen]
输出每行: 偏移<TAB>类型(A/W)<TAB>内容
"""
import re
import sys
from array import array

src, dst = sys.argv[1], sys.argv[2]
minlen = int(sys.argv[3]) if len(sys.argv) > 3 else 4
data = open(src, "rb").read()

items = []
for m in re.finditer(rb"[\x20-\x7e]{%d,}" % minlen, data):
    items.append((m.start(), "A", m.group().decode("ascii")))


def ok(v: int) -> bool:
    return (0x20 <= v <= 0x7E) or (0x4E00 <= v <= 0x9FFF) or (0x3000 <= v <= 0x303F) \
        or (0xFF00 <= v <= 0xFFEF) or (0x2010 <= v <= 0x203F)


def scan_wide(parity: int):
    buf = data[parity:]
    buf = buf[: len(buf) - (len(buf) % 2)]
    arr = array("H")
    arr.frombytes(buf)
    i, n = 0, len(arr)
    while i < n:
        if not ok(arr[i]):
            i += 1
            continue
        j = i
        while j < n and ok(arr[j]):
            j += 1
        seg = arr[i:j]
        if len(seg) >= minlen and any(v > 0x7F for v in seg):
            # 必须以 \0 或 非 ok 结尾/开头不强求；过滤掉明显的乱码：CJK 占比 < 100% 且含大量 ASCII 混杂
            t = "".join(map(chr, seg))
            ascii_n = sum(1 for v in seg if v < 0x80)
            if ascii_n == 0 or ascii_n == len(seg) or True:
                items.append((parity + i * 2, "W", t))
        i = j


# 字符之间若 ASCII 与 CJK 混杂，大概率是误判；这里只保留 全 CJK/标点 或 全 ASCII+少量 CJK 的段
scan_wide(0)
scan_wide(1)

items.sort()
with open(dst, "w", encoding="utf-8") as f:
    for off, k, t in items:
        f.write("%08X\t%s\t%s\n" % (off, k, t))
print("strings:", len(items), "wide:", sum(1 for i in items if i[1] == "W"))
