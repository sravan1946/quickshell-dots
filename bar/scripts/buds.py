#!/usr/bin/env python3
"""Per-bud battery of Nothing / CMF earbuds: python3 buds.py AA:BB:CC:DD:EE:FF

Prints {"left": [pct, charging], "right": [...], "case": [...]} (pieces the buds don't report
are left out), or {} when they don't answer. Read-only: asks once with Nothing's own protocol
(the one the Nothing X app speaks) over its RFCOMM channel, found by an SDP lookup of the
vendor service so nothing else (the hands-free channel) is ever opened.

Frames: 0x55 | control u16 | command u16 | length u16 | seq u8 | payload | CRC-16/ARC u16, all
little-endian. Battery: ask 0xC007, the reply is 0x4007 (or an unsolicited 0xE001) with
[count, (piece, value) * count]; piece 2 left, 3 right, 4 case; value bit 7 charging, bits 0-6
percent. (johron/something-x, chukfinley/nada)
"""
import json
import socket
import struct
import sys
import time

NOTHING_UUID = bytes.fromhex("aeac4a03dff5498f843a34487cf133eb")
PIECES = {2: "left", 3: "right", 4: "case"}


def crc16(data):
    crc = 0xFFFF
    for b in data:
        crc ^= b
        for _ in range(8):
            crc = (crc >> 1) ^ 0xA001 if crc & 1 else crc >> 1
    return crc


def frame(cmd, seq, payload=b""):
    head = struct.pack("<BHHHB", 0x55, 0x0160, cmd, len(payload), seq)
    return head + payload + struct.pack("<H", crc16(head + payload))


def sdp_channel(addr):
    """The RFCOMM channel of the vendor service: one ServiceSearchAttribute request over SDP."""
    s = socket.socket(socket.AF_BLUETOOTH, socket.SOCK_SEQPACKET, socket.BTPROTO_L2CAP)
    s.settimeout(4)
    try:
        s.connect((addr, 1))
        pattern = b"\x35\x11\x1c" + NOTHING_UUID                    # seq { uuid128 }
        attrs = b"\x35\x05\x0a\x00\x00\xff\xff"                     # seq { range 0x0000-0xffff }
        params = pattern + struct.pack(">H", 0xFFFF) + attrs + b"\x00"
        s.send(struct.pack(">BHH", 0x06, 1, len(params)) + params)
        data = s.recv(4096)
    finally:
        s.close()
    # in the protocol descriptor list, RFCOMM (uuid16 0x0003) is followed by its channel (uint8)
    i = data.find(b"\x19\x00\x03\x08")
    return data[i + 4] if i >= 0 else None


def parse(buf):
    """Battery from any whole 0x55 frames in buf (the reply's CRC isn't checked: some firmware sends a different one)."""
    out = {}
    i = 0
    while (i := buf.find(b"\x55", i)) >= 0 and i + 8 <= len(buf):
        ctrl, cmd, n = struct.unpack_from("<HHH", buf, i + 1)
        end = i + 8 + n + (2 if ctrl & 0x20 else 0)
        if end > len(buf):
            break
        if cmd | 0x8000 == 0xC007 or cmd == 0xE001:
            p = buf[i + 8:i + 8 + n]
            for k in range(min(p[0], (len(p) - 1) // 2) if p else 0):
                piece, v = p[1 + 2 * k], p[2 + 2 * k]
                if piece in PIECES:
                    out[PIECES[piece]] = [v & 0x7F, bool(v & 0x80)]
        i = end
    return out


def battery(addr, ch):
    s = socket.socket(socket.AF_BLUETOOTH, socket.SOCK_STREAM, socket.BTPROTO_RFCOMM)
    s.settimeout(4)
    try:
        s.connect((addr, ch))
        s.send(frame(0xC007, 1))
        buf, out, until = b"", {}, time.time() + 2.5
        s.settimeout(0.5)
        while time.time() < until and not out:
            try:
                chunk = s.recv(1024)
            except socket.timeout:
                continue
            if not chunk:
                break
            buf += chunk
            out = parse(buf)
        return out
    finally:
        s.close()


if __name__ == "__main__":
    if sys.argv[1:] == ["--test"]:
        # a reply with left 85, right 80 charging, case 40: 3 pieces
        p = bytes([3, 2, 85, 3, 0x80 | 80, 4, 40])
        r = struct.pack("<BHHHB", 0x55, 0x0120, 0x4007, len(p), 1) + p + b"\0\0"
        assert parse(b"junk" + r) == {"left": [85, False], "right": [80, True], "case": [40, False]}, parse(r)
        assert frame(0xC007, 1)[:8] == bytes.fromhex("55600107c0000001")
        print("ok")
        sys.exit()
    try:
        ch = sdp_channel(sys.argv[1])
        print(json.dumps(battery(sys.argv[1], ch) if ch else {}))
    except OSError:
        print("{}")
