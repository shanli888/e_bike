#!/usr/bin/env python3
"""从 Flutter APK 解出的 libflutter.so / libapp.so 里找 Dart 版本与 snapshot hash。

用法: python tools/dart_version.py <apk_extract_dir>
"""
import re
import sys

root = sys.argv[1]
flu = open(root + r"\lib\arm64-v8a\libflutter.so", "rb").read()
app = open(root + r"\lib\arm64-v8a\libapp.so", "rb").read()

print("== libflutter.so Dart 版本串 ==")
seen = set()
for m in re.finditer(rb"\d+\.\d+\.\d+ \((?:stable|beta|dev|main)\)[^\x00]{0,80}", flu):
    s = m.group().decode("latin1")
    if s not in seen:
        seen.add(s)
        print(s)

print("== libflutter.so engine/flutter 版本线索 ==")
for pat in (rb"[0-9a-f]{40}", rb"Flutter/[\d.]+", rb"engine\.version[^\x00]{0,60}"):
    hits = {x.group().decode("latin1") for x in re.finditer(pat, flu)}
    print(pat.decode(), "->", sorted(hits)[:8])

print("== libapp.so snapshot 特征(32 位 hex hash) ==")
hits = {x.group().decode() for x in re.finditer(rb"(?<![0-9a-f])[0-9a-f]{32}(?![0-9a-f])", app[:0x4000])}
print(sorted(hits))
print("libapp.so 内 AOT 标志:", set(re.findall(rb"product no-code_comments no-dwarf_stack_traces[^\x00]{0,120}", app)) or "未找到")
for m in re.finditer(rb"(?:product|release|debug)[ a-z_\-]{20,200}", app[:0x4000]):
    print("flags:", m.group().decode("latin1"))
