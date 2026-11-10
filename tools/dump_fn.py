#!/usr/bin/env python3
"""按函数地址从 blutter 的 .dart 汇编里抽取函数体，去掉重复的指令注释行，输出精简版。

用法: python tools/dump_fn.py <asm.dart> <out.txt> <addr1> [addr2 ...]
addr 形如 0x55659c（函数 "** addr:" 的起始地址，不带 0x 前缀的小写也行）
"""
import re
import sys

src, dst = sys.argv[1], sys.argv[2]
want = {a.lower().replace("0x", "") for a in sys.argv[3:]}
lines = open(src, encoding="utf-8", errors="replace").read().split("\n")

addr_re = re.compile(r"// \*\* addr: 0x([0-9a-f]+), size: (0x[0-9a-f]+)")
# 一条指令在 blutter 里出现两次：先是 "// 0xADDR: 语义" 再是 "//     0xADDR: 汇编"；只保留语义行
sem_re = re.compile(r"^\s*// 0x[0-9a-f]+: (.*)$")

out = []
i = 0
while i < len(lines):
    m = addr_re.search(lines[i])
    if m and m.group(1) in want:
        # 回溯找到函数签名行
        j = i - 1
        while j >= 0 and not lines[j].strip().endswith("{"):
            j -= 1
        out.append("=" * 70)
        out.append(lines[j].strip() if j >= 0 else "?")
        out.append(f"addr 0x{m.group(1)} size {m.group(2)}")
        k = i + 1
        while k < len(lines) and not re.match(r"^  \}\s*$", lines[k]):
            s = sem_re.match(lines[k])
            if s:
                t = s.group(1)
                if not t.startswith(("EnterFrame", "CheckStackOverflow", "LeaveFrame")):
                    out.append("  " + t)
            k += 1
        i = k
    i += 1

open(dst, "w", encoding="utf-8").write("\n".join(out) + "\n")
print("functions found:", sum(1 for o in out if o.startswith("addr ")), "of", len(want))
