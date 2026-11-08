#!/usr/bin/env python3
"""Kicks in what the default sink plays, live, for Visualizer.qml: kicks.py FLOOR_DB GAP_S [MARGIN_DB]
Prints one line per kick: its strength 0..1 (a typical one 0.8) and how long ago it started
(s), ~10-60 ms after the sink got it.

The sink's audio (pw-cat on its monitor, mono at 2 kHz: plenty for a kick) through a
40-130 Hz band. A kick is that band's energy (30 ms window) rising by more than FLOOR_DB over
30 ms and the recent rises' median + 3 MAD (past 2 s), at least GAP_S after the last, once per
rise, whose peak (watched for up to 50 ms) comes within MARGIN dB of the band's loud level over
the past minute (its 95th percentile). That last test is what tells a kick from the other
things that swell the low end: a bass or 808 note starting, a piano or a voice in a drumless
intro, all quieter there than the kicks of the same song.
Measured 2026-10-27 against kicks in the drums stem (Demucs) of 9 min of hip-hop: without the
loudness test precision was 0.52; with it 0.92 at a 4 dB margin, 0.84 at 6, recall ~0.56 either
way (the rest are kicks buried under a held 808). On 19 older EDM/pop tracks a wider margin
keeps more of what may be kicks (recall 0.65 at 4 dB, 0.82 at 10), so it's a setting. cava's bass rise, before this, scored F1 0.62 against kicks in the audio.
"""
import math
import os
import subprocess
import sys

RATE = 2000
HOP = 20     # 10 ms
WIN = 60     # 30 ms
RISE = 3     # hops the rise is taken over
QUIET = -50  # dBFS in the band: below it, a rise is noise (a quiet intro, a fade), not a kick
MARGIN = 5   # dB: a kick's peak is this close to the past minute's loud level, or it isn't one
PEAK = 5     # hops (50 ms) a rise is watched for its peak before it's judged


def butter(kind, f, q=0.7071):
    w = 2 * math.pi * f / RATE
    al, c = math.sin(w) / (2 * q), math.cos(w)
    b = [(1 - c) / 2, 1 - c, (1 - c) / 2] if kind == "low" else [(1 + c) / 2, -(1 + c), (1 + c) / 2]
    a0 = 1 + al
    return [b[0] / a0, b[1] / a0, b[2] / a0, -2 * c / a0, (1 - al) / a0]


class Detector:
    """Feed samples (floats, -1..1) with push(); it returns (strength, s since it started) of
    the kicks it has made out in them."""

    def __init__(self, floor=4.0, gap=0.18, margin=MARGIN):
        self.floor, self.gap, self.margin = floor, gap, margin
        self.filters = [[*butter("high", 40), 0, 0, 0, 0], [*butter("low", 130), 0, 0, 0, 0]]
        self.x = []          # filtered samples not yet hopped past
        self.db, self.flux = [], []
        self.base = floor
        self.recent = []     # the last 16 kicks' rises: strength is against their median
        self.loud = 0.0      # dBFS: nothing passes the gate until there's a level to go by
        self.n = 0           # hops so far
        self.last = -1e9     # hop of the last kick
        self.armed = False   # the rise has been under the threshold since the last kick
        self.cand = None     # (hop, rise) of a rise whose peak is being watched

    def push(self, samples):
        out = []
        for v in samples:
            for f in self.filters:
                b0, b1, b2, a1, a2, x1, x2, y1, y2 = f
                o = b0 * v + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
                f[5:] = [v, x1, o, y1]
                v = o
            self.x.append(v)
            if len(self.x) == WIN:
                s = self.step(10 * math.log10(sum(v * v for v in self.x) / WIN + 1e-10))
                if s is not None:
                    out.append(s)
                del self.x[:HOP]
        return out

    def step(self, level):
        """One hop: the band's level (dB) over the last 30 ms -> (strength, s since it started) of
        a kick made out now, or None. (kicktune.py replays recorded levels through this.)"""
        db, flux = self.db, self.flux
        db.append(level)
        flux.append(max(0.0, db[-1] - db[-1 - RISE]) if len(db) > RISE else 0.0)
        del db[:-6000], flux[:-200]
        self.n += 1
        if self.n % 10 == 0 and self.n > 20:   # every 100 ms
            w = sorted(flux)
            med = w[len(w) // 2]
            mad = sorted(abs(v - med) for v in w)[len(w) // 2]
            self.base = max(self.floor, med + 3 * mad)
            self.loud = sorted(db)[int(len(db) * 0.95)]
        out = None
        if self.cand:   # judge a rise once it has peaked (the level falls), or after 50 ms
            n0, f0 = self.cand
            k = self.n - n0
            if k >= PEAK or db[-1] < db[-2]:
                self.cand = None
                if max(db[-k - 1:]) > max(self.loud - self.margin, QUIET):
                    self.last = n0
                    self.recent = self.recent[-15:] + [f0]
                    out = (min(1.0, 0.8 * f0 / sorted(self.recent)[len(self.recent) // 2]), k * HOP / RATE)   # a typical kick: 0.8
        f = flux[-1]
        if f <= self.base:
            self.armed = True
        elif self.armed and not self.cand and (self.n - self.last) * HOP / RATE >= self.gap:
            self.armed = False
            self.cand = (self.n, f)
        return out


def demo():
    # a 60 Hz thump every 0.5 s over quiet noise: each one found, nothing between
    import random
    random.seed(1)
    d, hits, t = Detector(), [], 0
    for i in range(RATE * 6):
        k = (i % (RATE // 2)) / RATE
        v = 0.01 * random.uniform(-1, 1) + (0.8 * math.exp(-k / 0.08) * math.sin(2 * math.pi * 60 * k) if i > RATE else 0)
        for s, age in d.push([v]):
            hits.append(i / RATE - age)
    assert len(hits) == 10, hits
    assert all(min((h - 1) % 0.5, 0.5 - (h - 1) % 0.5) < 0.05 for h in hits), hits


if __name__ == "__main__":
    if sys.argv[1:] == ["--test"]:
        demo()
        sys.exit(0)
    det = Detector(*map(float, sys.argv[1:4]))
    # stdbuf: into a pipe pw-cat's stdout is block-buffered, 4 KiB = a second of audio at a time
    p = subprocess.Popen(["stdbuf", "-o0", "pw-cat", "--record", "-P", "stream.capture.sink=true", "--rate", str(RATE), "--channels", "1",
                          "--format", "s16", "--raw", "--latency", "10ms", "-"], stdout=subprocess.PIPE)
    fd, rest = p.stdout.fileno(), b""
    while chunk := os.read(fd, 4096):
        chunk, rest = rest + chunk, b""
        if len(chunk) % 2:
            chunk, rest = chunk[:-1], chunk[-1:]
        for s in det.push([int.from_bytes(chunk[i:i + 2], "little", signed=True) / 32768 for i in range(0, len(chunk), 2)]):
            print(f"{s[0]:.3f} {s[1]:.3f}", flush=True)
