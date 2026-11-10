#!/usr/bin/env python3
"""解析 Android btsnoop_hci.log，提取 ATT/GATT 报文（H4 / datalink 1002,1003）。

用法: python tools/parse_btsnoop.py <btsnoop.log> [--all]
默认只打印 ATT 报文；--all 额外打印非 ATT 的 ACL/HCI 包概要。
"""
import struct
import sys

ATT_OPS = {
    0x01: "ErrorRsp", 0x02: "MtuReq", 0x03: "MtuRsp",
    0x04: "FindInfoReq", 0x05: "FindInfoRsp",
    0x06: "FindByTypeReq", 0x07: "FindByTypeRsp",
    0x08: "ReadByTypeReq", 0x09: "ReadByTypeRsp",
    0x0A: "ReadReq", 0x0B: "ReadRsp",
    0x10: "ReadByGroupReq", 0x11: "ReadByGroupRsp",
    0x12: "WriteReq", 0x13: "WriteRsp",
    0x16: "PrepareWriteReq", 0x18: "ExecWriteReq",
    0x1B: "Notify", 0x1D: "Indicate", 0x1E: "Confirm",
    0x52: "WriteCmd",
}


def uuid_str(b: bytes) -> str:
    if len(b) == 2:
        return "%04X" % struct.unpack("<H", b)[0]
    return b[::-1].hex().upper()


def main():
    path = sys.argv[1]
    show_all = "--all" in sys.argv
    data = open(path, "rb").read()
    if data[:8] != b"btsnoop\0":
        sys.exit("不是 btsnoop 文件")
    ver, dl = struct.unpack(">II", data[8:16])
    print(f"# btsnoop version={ver} datalink={dl} size={len(data)}")
    off = 16
    n = 0
    # L2CAP 分片重组: handle -> bytearray
    pending = {}
    while off + 24 <= len(data):
        orig, incl, flags, drops, ts = struct.unpack(">IIIIq", data[off:off + 24])
        off += 24
        pkt = data[off:off + incl]
        off += incl
        n += 1
        direction = "RX<-" if flags & 1 else "TX->"
        if not pkt:
            continue
        ptype = pkt[0]
        if ptype != 0x02:  # ACL
            if show_all:
                print(f"#{n:04d} {direction} type=0x{ptype:02X} {pkt[1:].hex()}")
            continue
        handle_flags, dlen = struct.unpack("<HH", pkt[1:5])
        handle = handle_flags & 0x0FFF
        pb = (handle_flags >> 12) & 3
        payload = pkt[5:5 + dlen]
        if pb in (0, 2):  # 起始
            if len(payload) < 4:
                continue
            l2len, cid = struct.unpack("<HH", payload[:4])
            pending[handle] = [l2len, cid, bytearray(payload[4:])]
        else:  # 续片
            if handle not in pending:
                continue
            pending[handle][2].extend(payload)
        l2len, cid, buf = pending[handle]
        if len(buf) < l2len:
            continue
        del pending[handle]
        buf = bytes(buf[:l2len])
        if cid != 0x0004:  # 只看 ATT
            if show_all:
                print(f"#{n:04d} {direction} L2CAP cid=0x{cid:04X} {buf.hex()}")
            continue
        op = buf[0]
        name = ATT_OPS.get(op, f"op0x{op:02X}")
        info = ""
        if op in (0x12, 0x52, 0x1B, 0x1D, 0x0B, 0x16):
            if op == 0x0B:
                info = f"value={buf[1:].hex(' ').upper()}"
            else:
                h = struct.unpack("<H", buf[1:3])[0]
                info = f"handle=0x{h:04X} value={buf[3:].hex(' ').upper()}"
        elif op == 0x0A:
            info = f"handle=0x{struct.unpack('<H', buf[1:3])[0]:04X}"
        elif op in (0x09, 0x11):
            item = buf[1]
            rows = []
            for i in range(2, len(buf), item):
                rows.append(buf[i:i + item])
            parts = []
            for r in rows:
                if len(r) < item:
                    continue
                if op == 0x11:  # 服务: start end uuid
                    s, e = struct.unpack("<HH", r[:4])
                    parts.append(f"[0x{s:04X}-0x{e:04X} svc {uuid_str(r[4:])}]")
                else:  # 特征: handle props valhandle uuid
                    h = struct.unpack("<H", r[:2])[0]
                    if item in (7, 21):
                        pr = r[2]
                        vh = struct.unpack("<H", r[3:5])[0]
                        parts.append(f"[0x{h:04X} prop=0x{pr:02X} val=0x{vh:04X} chr {uuid_str(r[5:])}]")
                    else:
                        parts.append(f"[0x{h:04X} {r[2:].hex()}]")
            info = " ".join(parts)
        elif op in (0x08, 0x10):
            s, e = struct.unpack("<HH", buf[1:5])
            info = f"range=0x{s:04X}-0x{e:04X} type={uuid_str(buf[5:])}"
        elif op == 0x04:
            s, e = struct.unpack("<HH", buf[1:5])
            info = f"range=0x{s:04X}-0x{e:04X}"
        elif op == 0x05:
            fmt = buf[1]
            sz = 4 if fmt == 1 else 18
            parts = []
            for i in range(2, len(buf), sz):
                r = buf[i:i + sz]
                if len(r) < sz:
                    continue
                h = struct.unpack("<H", r[:2])[0]
                parts.append(f"[0x{h:04X} {uuid_str(r[2:])}]")
            info = " ".join(parts)
        else:
            info = buf[1:].hex(" ").upper()
        print(f"#{n:04d} {direction} conn=0x{handle:03X} {name:12s} {info}")


if __name__ == "__main__":
    main()
