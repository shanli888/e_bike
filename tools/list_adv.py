#!/usr/bin/env python3
"""列出 btsnoop 里的 LE 广播报告(设备地址/名称/服务UUID)和连接事件。

用法: python tools/list_adv.py <btsnoop.log>
"""
import struct
import sys

data = open(sys.argv[1], "rb").read()
off = 16
devs = {}
conn = []
while off + 24 <= len(data):
    orig, incl, flags, drops, ts = struct.unpack(">IIIIq", data[off:off + 24])
    off += 24
    pkt = data[off:off + incl]
    off += incl
    if not pkt or pkt[0] != 0x04 or len(pkt) < 4 or pkt[1] != 0x3E:
        continue
    sub = pkt[3]
    body = pkt[4:]
    if sub == 0x01 or sub == 0x0A:
        conn.append((sub, body.hex()))
    if sub != 0x02:  # legacy adv report
        continue
    n = body[0]
    p = 1
    for _ in range(n):
        et, at = body[p], body[p + 1]
        addr = ":".join("%02X" % x for x in body[p + 2:p + 8][::-1])
        dl = body[p + 8]
        ad = body[p + 9:p + 9 + dl]
        p += 9 + dl + 1
        name, uuids = None, []
        i = 0
        while i < len(ad) and ad[i]:
            l, t = ad[i], ad[i + 1]
            v = ad[i + 2:i + 1 + l]
            if t in (8, 9):
                name = v.decode("utf-8", "replace")
            elif t in (2, 3):
                uuids += ["%04X" % struct.unpack("<H", v[k:k + 2])[0] for k in range(0, len(v) - 1, 2)]
            elif t in (6, 7):
                uuids += [v[k:k + 16][::-1].hex() for k in range(0, len(v) - 15, 16)]
            i += l + 1
        d = devs.setdefault(addr, {"name": None, "uuids": set(), "cnt": 0})
        d["cnt"] += 1
        d["name"] = name or d["name"]
        d["uuids"].update(uuids)

for a, d in sorted(devs.items(), key=lambda x: -x[1]["cnt"]):
    print(a, d["name"], sorted(d["uuids"]), d["cnt"])
print("connection events:", conn)
