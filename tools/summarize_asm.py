#!/usr/bin/env python3
"""把 blutter 生成的 .dart 汇编压缩成「函数 -> 引用的字符串/常量/调用」摘要，便于人读。

用法: python tools/summarize_asm.py <asm_file.dart> [out.txt]
"""
import re
import sys

src = sys.argv[1]
out = open(sys.argv[2], "w", encoding="utf-8") if len(sys.argv) > 2 else sys.stdout

func_re = re.compile(r"^\s{2}(?:static )?(?:_ |[\w<>?, ]+ )?([\w:@$<>]+)\(.*\) (?:async\*? |sync\*? )?\{\s*$")
cls_re = re.compile(r"^(?:abstract )?(?:class|enum|mixin) ([\w$<>]+)")
addr_re = re.compile(r"// \*\* addr: (0x[0-9a-f]+), size: (0x[0-9a-f]+)")
str_re = re.compile(r'; \[pp\+0x[0-9a-f]+\] (".*")\s*$')
call_re = re.compile(r"bl\s+#0x[0-9a-f]+\s+; (?:\[(package:[^\]]+|dart:[^\]]+)\] )?(.+)$")
imm_re = re.compile(r"(?:movz|mov)\s+x\d+, #(0x[0-9a-f]+)\s*$")
pp_re = re.compile(r"; \[pp\+0x[0-9a-f]+\] (?!\")(.+)$")

cur_cls = ""
cur_fn = None
items = []  # (cls, fn, addr, strings, calls, imms)
state = None
for line in open(src, encoding="utf-8", errors="replace"):
    m = cls_re.match(line)
    if m:
        cur_cls = m.group(1)
        continue
    m = func_re.match(line)
    if m and not line.lstrip().startswith("//"):
        state = {"cls": cur_cls, "fn": m.group(1), "addr": "", "str": [], "calls": [], "imm": [], "pp": []}
        items.append(state)
        continue
    if state is None:
        continue
    m = addr_re.search(line)
    if m and not state["addr"]:
        state["addr"] = m.group(1) + "/" + m.group(2)
        continue
    m = str_re.search(line)
    if m:
        s = m.group(1)
        if s not in state["str"]:
            state["str"].append(s)
        continue
    m = call_re.search(line)
    if m:
        c = (m.group(1) or "") + " " + m.group(2).strip()
        c = c.strip()
        if c and not c.endswith("Stub") and "Stub" not in c and c not in state["calls"]:
            state["calls"].append(c)
        continue
    m = pp_re.search(line)
    if m:
        v = m.group(1).strip()
        if v not in state["pp"]:
            state["pp"].append(v)

for it in items:
    if not (it["str"] or it["calls"]):
        continue
    out.write(f"## {it['cls']}.{it['fn']}  {it['addr']}\n")
    if it["str"]:
        out.write("  str : " + " | ".join(it["str"]) + "\n")
    if it["pp"]:
        out.write("  pool: " + " | ".join(it["pp"][:12]) + "\n")
    if it["calls"]:
        out.write("  call: " + " ; ".join(it["calls"][:40]) + "\n")
