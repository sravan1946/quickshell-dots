#!/usr/bin/env python3
"""Build scripts/emoji.tsv for the emoji picker (islands/panels/Emoji.qml) from Unicode's data.

    python3 scripts/emoji-data.py      # rerun when a new Emoji version ships

One line per emoji, in Unicode's order:  group <TAB> emoji <TAB> name <TAB> search keywords
Fully-qualified emoji only, no skin-tone variants and no bare components.
Keywords are CLDR's English annotations plus emojilib's (the everyday words: 🥀 "rose", "dead"),
minus words already in the name.
"""
import json
import os
import re
import urllib.request

TEST = "https://unicode.org/Public/emoji/latest/emoji-test.txt"
CLDR = "https://raw.githubusercontent.com/unicode-org/cldr-json/main/cldr-json/"
ANN = [CLDR + "cldr-annotations-full/annotations/en/annotations.json",
       CLDR + "cldr-annotations-derived-full/annotationsDerived/en/annotations.json"]
EMOJILIB = "https://cdn.jsdelivr.net/npm/emojilib@4/dist/emoji-en-US.json"
TONES = set(range(0x1F3FB, 0x1F400))


def get(url):
    with urllib.request.urlopen(url, timeout=30) as r:
        return r.read().decode()


keywords = {}
for url in ANN:
    data = json.loads(get(url))
    for ch, a in next(iter(data.values()))["annotations"].items():
        keywords.setdefault(ch.replace("\ufe0f", ""), a.get("default", []))

for ch, words in json.loads(get(EMOJILIB)).items():
    keywords.setdefault(ch.replace("\ufe0f", ""), []).extend(w.replace("_", " ") for w in words)

rows, group = [], ""
for line in get(TEST).splitlines():
    if line.startswith("# group:"):
        group = line.split(":", 1)[1].strip()
    m = re.match(r"^([0-9A-F ]+?)\s*; fully-qualified\s*# (\S+) E[\d.]+ (.+)$", line)
    if not m or group == "Component":
        continue
    cps = [int(c, 16) for c in m.group(1).split()]
    if TONES & set(cps):
        continue
    ch, name = m.group(2), m.group(3)
    words = set(re.findall(r"\w+", name.lower()))
    kw = []
    for k in keywords.get(ch.replace("\ufe0f", ""), []):
        k = k.lower()
        if k != name.lower() and not set(re.findall(r"\w+", k)) <= words and k not in kw:
            kw.append(k)
    rows.append(f"{group}\t{ch}\t{name}\t{' '.join(kw)}")

out = os.path.join(os.path.dirname(os.path.abspath(__file__)), "emoji.tsv")
with open(out, "w") as f:
    f.write("\n".join(rows) + "\n")
print(f"{len(rows)} emoji -> {out}")
