#!/usr/bin/env python3
"""Build scripts/glyphs.tsv for the glyph picker (islands/panels/Glyphs.qml) from Nerd Fonts'
glyphnames.json, keeping only glyphs the installed icon font really has.

    python3 scripts/glyph-data.py      # rerun after a Nerd Fonts update

One line per glyph:  group <TAB> glyph <TAB> name <TAB> search words <TAB> footer text
Groups are the big sets (md, fa, cod, oct, dev, seti, linux, weather); the rest is "other".
"""
import json
import os
import subprocess
import urllib.request

FONT = "JetBrainsMono Nerd Font"
URL = "https://raw.githubusercontent.com/ryanoasis/nerd-fonts/master/glyphnames.json"
SETS = ["md", "fa", "cod", "oct", "dev", "seti", "linux", "weather"]

path = subprocess.run(["fc-match", "-f", "%{file}", FONT], capture_output=True, text=True).stdout
ranges = subprocess.run(["fc-query", "-f", "%{charset}", path], capture_output=True, text=True).stdout.split()
have = set()
for r in ranges:
    a, _, b = r.partition("-")
    have.update(range(int(a, 16), int(b or a, 16) + 1))

with urllib.request.urlopen(URL, timeout=30) as r:
    names = json.load(r)

rows, seen = [], set()
for key, v in sorted(names.items(), key=lambda kv: (kv[0].split("-")[0] not in SETS, kv[0])):
    if key == "METADATA" or "code" not in v:
        continue
    cp = int(v["code"], 16)
    if cp not in have or cp in seen:
        continue
    seen.add(cp)
    prefix, _, rest = key.partition("-")
    group = prefix if prefix in SETS else "other"
    name = rest.replace("_", " ")
    rows.append(f"{group}\t{chr(cp)}\t{name}\t{prefix}\tnf-{key}   U+{cp:04X}")

rows.sort(key=lambda r: SETS.index(r.split("\t")[0]) if r.split("\t")[0] in SETS else len(SETS))
out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "glyphs.tsv")
with open(out, "w") as f:
    f.write("\n".join(rows) + "\n")
print(f"{len(rows)} glyphs from {path} -> {out}")
