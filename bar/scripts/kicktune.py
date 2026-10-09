#!/usr/bin/env python3
"""Tune the bar's kick detector (Visualizer.detect) on your own music.

  kicktune.py record [--minutes 30]    # play music meanwhile; Ctrl-C stops early
  kicktune.py tune [DIR ...] [--apply] # all recordings by default; --apply sets the winners
  kicktune.py --test

record saves, side by side under ~/.cache/quickshell-kicktune/<time>/:
  audio.raw   what the default sink plays (pw-cat, mono s16 at 2 kHz: plenty for a kick)
  cava.txt    a second cava on the bar's own cava.conf, each frame stamped with its arrival time
  meta.txt    play state + track, polled every second

tune takes the kicks heard in the audio as the truth: onsets of the 40-130 Hz band
(bandpass, 30 ms energy, rise over 30 ms, adaptive threshold). cava trails the audio by its own
buffering (~150 ms), so each track's lag is measured and taken off. Then a Python copy of
detect() is replayed on the cava frames and searched one parameter at a time, scored by F1
(a detection within 70 ms of a kick), averaged per track so a long one doesn't dominate.
beatSens/beatFloor/beatGap are Settings (--apply sets them on the running bar); the rise span,
EMA window and bass bands are code in Visualizer.qml, so for those it says what to change.
Pure stdlib: no numpy on the box.
"""
import array
import bisect
import glob
import json
import math
import os
import signal
import subprocess
import sys
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.expanduser("~/.cache/quickshell-kicktune")
RATE = 2000          # audio sample rate
HOP = 20             # 10 ms
TOL = 0.07           # s: a detection this close to a kick counts
CURRENT = {"sens": 0, "floor": 0.02, "gap": 0.23, "span": 2, "ema": 270, "bands": 6}   # code + Settings defaults
GRID = {
    "sens": [0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 1.0, 1.2, 1.5, 2.0],
    "floor": [0, 0.005, 0.01, 0.015, 0.02, 0.03, 0.04, 0.06],
    "gap": [0.1, 0.13, 0.16, 0.2, 0.23, 0.26, 0.3, 0.35],
    "span": [1, 2, 3],
    "ema": [30, 45, 60, 90, 135, 180, 270],
    "bands": [2, 4, 6, 8],
}
SETTING = {"sens": "beatSens", "floor": "beatFloor", "gap": "beatGap"}
try:   # what the bar runs now, not just its defaults
    _saved = json.load(open(os.path.expanduser("~/.config/quickshell-bar/settings.json")))
    CURRENT.update({k: _saved[name] for k, name in SETTING.items() if name in _saved})
except (OSError, ValueError):
    pass


# ---------------- record ----------------

def record(minutes):
    out = os.path.join(ROOT, time.strftime("%Y%m%d-%H%M%S"))
    os.makedirs(out)
    stop = threading.Event()
    procs = []

    def audio():
        # parec hears nothing from a Bluetooth sink here; pw-cat on the sink's monitor does
        p = subprocess.Popen(["pw-cat", "--record", "-P", "stream.capture.sink=true", "--rate", str(RATE),
                              "--channels", "1", "--format", "s16", "--raw", "--latency", "20ms", "-"],
                             stdout=subprocess.PIPE)
        procs.append(p)
        n = 0
        with open(os.path.join(out, "audio.raw"), "wb") as f, open(os.path.join(out, "audio.t"), "w", buffering=1) as ft:
            while not stop.is_set():
                b = p.stdout.read1(RATE // 10 * 2)   # up to 100 ms, as it arrives
                if not b:
                    break
                f.write(b)
                n += len(b) // 2
                ft.write(f"{time.time():.4f} {n}\n")   # wall time when sample n arrived

    def cava():
        p = subprocess.Popen(["cava", "-p", os.path.join(HERE, "cava.conf")], stdout=subprocess.PIPE, text=True)
        procs.append(p)
        with open(os.path.join(out, "cava.txt"), "w", buffering=1) as f:
            for line in p.stdout:
                if stop.is_set():
                    break
                f.write(f"{time.time():.4f};{line}")

    def meta():
        with open(os.path.join(out, "meta.txt"), "w") as f:
            last = None
            while not stop.is_set():
                r = subprocess.run(["playerctl", "metadata", "--format", "{{status}}\t{{artist}} - {{title}}"],
                                   capture_output=True, text=True).stdout.strip()
                if r != last:
                    f.write(f"{time.time():.4f}\t{r}\n")
                    f.flush()
                    last = r
                stop.wait(1)

    threads = [threading.Thread(target=fn, daemon=True) for fn in (audio, cava, meta)]
    for th in threads:
        th.start()
    signal.signal(signal.SIGINT, lambda *_: stop.set())
    print(f"recording to {out} for {minutes:g} min (Ctrl-C to stop early)")
    stop.wait(minutes * 60)
    stop.set()
    for p in procs:
        p.terminate()
    for th in threads:
        th.join(timeout=3)
    print("done:", out)


# ---------------- load ----------------

def load(d):
    a = array.array("h")
    with open(os.path.join(d, "audio.raw"), "rb") as f:
        a.frombytes(f.read())
    marks = [tuple(map(float, l.split())) for l in open(os.path.join(d, "audio.t"))]
    frames = []
    for l in open(os.path.join(d, "cava.txt")):
        parts = l.rstrip("\n").split(";")
        vals = [int(x) / 100 for x in parts[1:] if x]
        if len(vals) == 32:
            frames.append((float(parts[0]), vals))
    meta = []
    for l in open(os.path.join(d, "meta.txt")):
        t, _, rest = l.rstrip("\n").partition("\t")
        status, _, track = rest.partition("\t")
        meta.append((float(t), status, track))
    return a, clock(marks), frames, meta


def clock(marks):
    """sample index -> wall time. The audio clock runs a little off the wall clock (~2003 Hz
    measured, a quarter second over a 3 min track), so no fixed rate: in each 10 s stretch the
    earliest-arriving chunk (least delivery delay) is a point, joined piecewise-linearly."""
    pts = {}
    for t, n in marks:
        k = int(n // (RATE * 10))
        if k not in pts or t - n / RATE < pts[k][0] - pts[k][1] / RATE:
            pts[k] = (t, n)
    pts = [pts[k] for k in sorted(pts)]
    ns = [n for _, n in pts]

    def at(n):
        if len(pts) < 2:
            return pts[0][0] + (n - pts[0][1]) / RATE
        j = min(max(bisect.bisect_right(ns, n), 1), len(pts) - 1)
        (ta, na), (tb, nb) = pts[j - 1], pts[j]
        return ta + (n - na) * (tb - ta) / (nb - na)
    return at


def index(at, t, n):
    """Inverse of clock(): the sample playing at wall time t."""
    lo, hi = 0, n
    while lo < hi:
        m = (lo + hi) // 2
        if at(m) < t:
            lo = m + 1
        else:
            hi = m
    return lo


def segments(meta, end):
    """(start, stop, track) stretches of one track playing, at least 20 s long."""
    out = []
    for i, (t, status, track) in enumerate(meta):
        stop = meta[i + 1][0] if i + 1 < len(meta) else end
        if status == "Playing" and stop - t >= 20:
            out.append((t + 1, stop - 1, track))   # a second of slack at both ends
    return out


# ---------------- kicks heard in the audio ----------------

def biquad(x, b0, b1, b2, a1, a2):
    y = [0.0] * len(x)
    x1 = x2 = y1 = y2 = 0.0
    for i, v in enumerate(x):
        o = b0 * v + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1, y2, y1 = x1, v, y1, o
        y[i] = o
    return y


def butter(kind, f, rate=RATE, q=0.7071):
    w = 2 * math.pi * f / rate
    al, c = math.sin(w) / (2 * q), math.cos(w)
    if kind == "low":
        b = [(1 - c) / 2, 1 - c, (1 - c) / 2]
    else:
        b = [(1 + c) / 2, -(1 + c), (1 + c) / 2]
    a0 = 1 + al
    return [b[0] / a0, b[1] / a0, b[2] / a0, -2 * c / a0, (1 - al) / a0]


def kicks(samples, t0):
    """Times of low-band onsets, t0 + seconds into `samples`."""
    x = biquad(biquad([v / 32768 for v in samples], *butter("high", 40)), *butter("low", 130))
    win = 60   # 30 ms
    db = []
    for i in range(0, len(x) - win, HOP):
        e = sum(v * v for v in x[i:i + win]) / win
        db.append(10 * math.log10(e + 1e-10))
    if not db:
        return []
    flux = [0.0] * len(db)
    for i in range(3, len(db)):
        flux[i] = max(0.0, db[i] - db[i - 3])
    loud = sorted(db)[int(len(db) * 0.95)]
    out, last, base = [], -1e9, 0.0
    for i in range(5, len(flux) - 5):
        if i % 10 == 0:   # local median of the flux over ±1 s, every 100 ms
            w = sorted(flux[max(0, i - 100):i + 100])
            med = w[len(w) // 2]
            mad = sorted(abs(v - med) for v in w)[len(w) // 2]
            base = max(4.0, med + 3 * mad)
        f = flux[i]
        if f > base and f == max(flux[i - 5:i + 6]) and db[i] > loud - 25 and i - last >= 12:
            out.append(t0 + (i * HOP + win / 2) / RATE)
            last = i
    return out


# ---------------- the bar's detector ----------------

def bass(frames, n):
    lo = 16 - n // 2
    return [sum(v[lo:lo + n]) / n for _, v in frames]


def detect(times, b, p):
    """Visualizer.detect(), parameterised: beat times."""
    span, a = p["span"], 1 / p["ema"]
    mean = var = 0.0
    last, out = -1e9, []
    for i in range(len(b)):
        d = max(0.0, b[i] - b[i - span]) if i >= span else 0.0
        thr = mean + p["sens"] * math.sqrt(var) + p["floor"]
        if d > thr and times[i] - last >= p["gap"]:
            last = times[i]
            out.append(last)
        mean += (d - mean) * a
        var += ((d - mean) * (d - mean) - var) * a
    return out


def score(det, truth, tol=TOL):
    """(precision, recall, F1): each kick matched by at most one detection."""
    used, hit = set(), 0
    for t in det:
        j = bisect.bisect_left(truth, t - tol)
        while j < len(truth) and truth[j] <= t + tol:
            if j not in used:
                used.add(j)
                hit += 1
                break
            j += 1
    p = hit / len(det) if det else 0.0
    r = hit / len(truth) if truth else 0.0
    return p, r, (2 * p * r / (p + r) if p + r else 0.0)


def lag(truth, times, b):
    """How far cava's rises trail the audio's kicks: the shift (0-400 ms) under which the most
    kicks have a rise starting within 40 ms."""
    d = [max(0.0, b[i] - b[i - 2]) if i >= 2 else 0.0 for i in range(len(b))]
    m = sum(d) / len(d)
    sd = math.sqrt(sum((v - m) ** 2 for v in d) / len(d))
    starts = [times[i] for i in range(1, len(d)) if d[i] > m + 0.5 * sd >= d[i - 1]]
    best = max(range(0, 401, 10), key=lambda ms: score(starts, [k + ms / 1000 for k in truth], 0.04)[1])
    return best / 1000


# ---------------- tune ----------------

def prepare(dirs):
    tracks = []
    for d in dirs:
        a, at, frames, meta = load(d)
        if not frames:
            continue
        print(f"{d}: {len(a) / RATE / 60:.1f} min audio, {len(frames)} cava frames")
        for start, stop, name in segments(meta, frames[-1][0]):
            fr = [f for f in frames if start <= f[0] <= stop]
            i0, i1 = index(at, start, len(a)), index(at, stop, len(a))
            if len(fr) < 300 or i1 - i0 < RATE * 10:
                continue
            truth = [at(i0 + k * RATE) for k in kicks(a[i0:i1], 0.0)]
            if len(truth) < 10:
                print(f"  skip {name!r}: {len(truth)} kicks heard")
                continue
            times = [t for t, _ in fr]
            L = lag(truth, times, bass(fr, 6))
            truth = [k + L for k in truth]
            bpm = 60 * len(truth) / (stop - start)
            print(f"  {name[:60]!r}: {stop - start:.0f} s, {len(truth)} kicks (~{bpm:.0f}/min), cava lag {L * 1000:.0f} ms")
            tracks.append({"name": name, "times": times, "frames": fr, "truth": truth,
                           "bass": {n: bass(fr, n) for n in GRID["bands"]}})
    return tracks


def evaluate(tracks, p):
    rows = [score(detect(t["times"], t["bass"][p["bands"]], p), t["truth"]) for t in tracks]
    return tuple(sum(r[k] for r in rows) / len(rows) for k in range(3)), rows


def search(tracks, start):
    p = dict(start)
    best = evaluate(tracks, p)[0][2]
    for _ in range(4):   # coordinate descent: one parameter at a time until nothing moves
        moved = False
        for k, vals in GRID.items():
            for v in vals:
                q = {**p, k: v}
                f = evaluate(tracks, q)[0][2]
                if f > best + 1e-4:
                    p, best, moved = q, f, True
        if not moved:
            break
    return p


def tune(dirs, apply):
    dirs = dirs or sorted(glob.glob(os.path.join(ROOT, "*", "")))
    tracks = prepare(dirs)
    if not tracks:
        sys.exit("nothing usable: record some music with a beat first")
    (p0, r0, f0), rows0 = evaluate(tracks, CURRENT)
    best = search(tracks, CURRENT)
    (p1, r1, f1), rows1 = evaluate(tracks, best)
    print(f"\n{len(tracks)} tracks, {sum(len(t['truth']) for t in tracks)} kicks")
    print(f"current: F1 {f0:.3f} (precision {p0:.2f}, recall {r0:.2f})")
    print(f"tuned:   F1 {f1:.3f} (precision {p1:.2f}, recall {r1:.2f})\n")
    for k in GRID:
        mark = "" if best[k] == CURRENT[k] else "   <- " + (f"Settings.{SETTING[k]}" if k in SETTING else "code")
        print(f"  {k:6} {CURRENT[k]!s:>6} -> {best[k]!s:<6}{mark}")
    print("\nper track (current -> tuned F1):")
    for t, a, b in sorted(zip(tracks, rows0, rows1), key=lambda x: x[2][2]):
        print(f"  {a[2]:.2f} -> {b[2]:.2f}  {t['name'][:70]}")
    code = {k: best[k] for k in GRID if k not in SETTING and best[k] != CURRENT[k]}
    if code:
        print("\nVisualizer.qml changes for the rest:"
              + (f"\n  rise span {best['span']} frames: prevBass{'2' if CURRENT['span'] == 2 else ''} chain in detect()" if "span" in code else "")
              + (f"\n  EMA window: the two `/ 90` in detect() -> / {best['ema']}" if "ema" in code else "")
              + (f"\n  bands: detect() gets the middle {best['bands']} of lv[] (now lv[13..18])" if "bands" in code else ""))
    json.dump({"current": CURRENT, "tuned": best, "f1": [f0, f1], "tracks": len(tracks)},
              open(os.path.join(ROOT, "last-tune.json"), "w"), indent=2)
    if apply:
        for k, name in SETTING.items():
            subprocess.run(["qs", "-c", "bar", "ipc", "call", "settings", "set", name, json.dumps(best[k])])
        print("\napplied", {SETTING[k]: best[k] for k in SETTING})


# ---------------- self-check ----------------

def demo():
    import random
    random.seed(1)
    n, at = RATE * 20, [0.5 + 0.47 * i + random.uniform(-0.03, 0.03) for i in range(40)]
    x = [0.02 * math.sin(2 * math.pi * 300 * i / RATE) + random.gauss(0, 0.003) for i in range(n)]
    for k in at:   # kick: a decaying 60 Hz thump
        amp = random.uniform(0.3, 0.8)
        for j in range(int(0.15 * RATE)):
            i = int(k * RATE) + j
            if i < n:
                x[i] += amp * math.exp(-j / RATE / 0.05) * math.sin(2 * math.pi * 60 * j / RATE)
    found = kicks([int(v * 32767) for v in x], 0.0)
    p, r, f = score(found, at, 0.03)
    assert f > 0.95, (p, r, found[:5], at[:5])

    times = [i / 30 for i in range(600)]   # cava-ish: bass jumps on each kick, decays between
    b, v, ks = [], 0.1, [int(k * 30) + 4 for k in at]
    for i in range(600):
        v = 0.8 if i in ks else max(0.1, v * 0.85)
        b.append(v)
    det = detect(times, b, CURRENT)
    assert score(det, [i / 30 for i in ks], 0.04)[2] > 0.95, det[:5]
    assert 0.1 <= lag(at, times, b) <= 0.17, lag(at, times, b)


if __name__ == "__main__":
    args = sys.argv[1:]
    if args == ["--test"]:
        demo()
        print("ok")
    elif args[:1] == ["record"]:
        record(float(args[args.index("--minutes") + 1]) if "--minutes" in args else 30)
    elif args[:1] == ["tune"]:
        tune([a for a in args[1:] if not a.startswith("--")], "--apply" in args)
    else:
        sys.exit(__doc__)
