#!/usr/bin/env python3
"""Synced lyrics for Lyrics.qml: lyrics.py ARTIST TITLE ALBUM DURATION_S [--no-musixmatch]
Prints [{"t": seconds, "text": line, "sub": backing vocals}, ...], or [] when nothing synced
was found. Backing vocals are the line's (parenthesised) parts, shown smaller under it.

Musixmatch's word-timed "richsync" first (lines then also carry `words`/`subWords`: [{t, c}]),
then lrclib.net (exact match, then search), then Musixmatch's line-timed subtitles. Musixmatch
is called the way Spicetify's lyrics-plus does it. Musixmatch needs an anonymous user token and hands out
roughly one per IP before answering "captcha", so it is cached and only renewed on a 401.
"""
import json
import os
import re
import sys
import urllib.parse
import urllib.request

UA = "quickshell-dots (https://github.com/sravan1946/quickshell-dots)"
MXM = "https://apic-appmobile.musixmatch.com/ws/1.1/"
MXM_HEADERS = {
    "X-Cookie": "x-mxm-token-guid=",
    "x-mxm-app-version": "10.1.1",
    "X-User-Agent": "Musixmatch/2025120901 CFNetwork/3860.300.31 Darwin/25.2.0",
    "Accept": "application/json",
}
TOKEN_FILE = os.path.expanduser("~/.cache/quickshell-mxm-token")


def get(url, params, headers):
    q = urllib.parse.urlencode({k: v for k, v in params.items() if v})
    req = urllib.request.Request(f"{url}?{q}", headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=8) as r:
            return json.load(r)
    except Exception:
        return None


def parse_lrc(lrc):
    out = []
    for row in lrc.splitlines():
        text = re.sub(r"\[[^\]]*\]", "", row).strip() or "♪"
        for m, s in re.findall(r"\[(\d+):(\d+(?:\.\d+)?)\]", row):
            out.append({"t": int(m) * 60 + float(s), "text": text})
    return sorted(out, key=lambda x: x["t"])


def split(line):
    """'Stacking up (Purr)' -> {'text': 'Stacking up', 'sub': 'Purr'}; an all-backing line stays the line."""
    backing = [b.strip() for b in re.findall(r"\(([^)]*)\)", line["text"]) if b.strip()]
    main = re.sub(r"\s*\([^)]*\)", "", line["text"]).strip(" ,")
    if not main:
        return {**line, "text": ", ".join(backing) or line["text"], "sub": ""}
    return {**line, "text": main, "sub": ", ".join(backing)}


def lrclib(artist, title, album, dur):
    a = {"artist_name": artist, "track_name": title}
    r = get("https://lrclib.net/api/get", {**a, "album_name": album, "duration": dur}, {"User-Agent": UA})
    if not (r and r.get("syncedLyrics")):
        hits = get("https://lrclib.net/api/search", a, {"User-Agent": UA}) or []
        r = next((h for h in hits if h.get("syncedLyrics")), None)
    return parse_lrc(r["syncedLyrics"]) if r else []


def mxm_token(renew=False):
    if not renew and os.path.exists(TOKEN_FILE):
        return open(TOKEN_FILE).read().strip()
    r = get(MXM + "token.get", {"app_id": "mac-ios-v2.0"}, MXM_HEADERS)
    tok = ((r or {}).get("message", {}).get("body") or {}).get("user_token")
    if tok:   # a captcha answer leaves the old (dead) one in place rather than nothing
        os.makedirs(os.path.dirname(TOKEN_FILE), exist_ok=True)
        with open(TOKEN_FILE, "w") as f:
            f.write(tok)
    return tok


def musixmatch(artist, title, album, dur):
    """(word-timed lines from richsync, line-timed lines from subtitles): one request, either may be []."""
    params = {"format": "json", "namespace": "lyrics_richsynched", "subtitle_format": "mxm",
              "app_id": "mac-ios-v2.0", "q_artist": artist, "q_artists": artist, "q_track": title,
              "q_album": album, "q_duration": dur, "optional_calls": "track.richsync",
              "richsync_compact_type": "words"}
    for renew in (False, True):
        tok = mxm_token(renew)
        if not tok:
            return [], []
        r = (get(MXM + "macro.subtitles.get", {**params, "usertoken": tok}, MXM_HEADERS) or {}).get("message", {})
        if r.get("header", {}).get("status_code") != 401:
            break
    calls = (r.get("body") or {}).get("macro_calls") or {}
    body = lambda call: (calls.get(call) or {}).get("message", {}).get("body") or {}
    rich = body("track.richsync.get").get("richsync")
    words = [split_words(l) for l in json.loads(rich["richsync_body"])] if rich else []
    subs = body("track.subtitles.get").get("subtitle_list") or []
    lines = [split({"t": l["time"]["total"], "text": l.get("text") or "♪"})
             for l in json.loads(subs[0]["subtitle"]["subtitle_body"])] if subs else []
    return words, lines


def split_words(line):
    """A richsync line ({ts, l: [{c, o}]}) as split() does it, plus `words`/`subWords`:
    [{t, c}] pieces of `text`/`sub` with their absolute start times."""
    main, sub, depth = [], [], 0
    for tok in line["l"]:
        t = round(line["ts"] + tok["o"], 3)
        for ch in tok["c"]:
            if ch == "(":
                if depth == 0:
                    while main and main[-1][1] == " ":
                        main.pop()
                    if sub:
                        sub += [(t, ","), (t, " ")]
                depth += 1
            elif ch == ")":
                depth = max(0, depth - 1)
            elif not (depth == 0 and ch == "," and main and main[-1][1] == ","):   # "Stack, (Purr), st"
                (sub if depth else main).append((t, ch))

    def pieces(chars):
        while chars and chars[0][1] in " ,":
            chars = chars[1:]
        while chars and chars[-1][1] in " ,":
            chars = chars[:-1]
        out = []
        for t, ch in chars:
            if out and out[-1]["t"] == t:
                out[-1]["c"] += ch
            else:
                out.append({"t": t, "c": ch})
        return out

    main, sub = pieces(main), pieces(sub)
    if not main:
        main, sub = sub, []
    if not main:
        return {"t": line["ts"], "text": "♪", "sub": ""}
    text = lambda ws: "".join(w["c"] for w in ws)
    return {"t": line["ts"], "text": text(main), "sub": text(sub), "words": main, "subWords": sub}


def demo():
    lines = parse_lrc("[00:01.50] a\n[01:02.00][00:00.20]\nnoise")
    assert lines == [{"t": 0.2, "text": "♪"}, {"t": 1.5, "text": "a"}, {"t": 62.0, "text": "♪"}], lines
    assert split({"t": 0, "text": "Stack, stack (Purr), stack (Meow)"}) == {"t": 0, "text": "Stack, stack, stack", "sub": "Purr, Meow"}
    assert split({"t": 0, "text": "(No pressure)"}) == {"t": 0, "text": "No pressure", "sub": ""}
    assert split({"t": 0, "text": "♪"}) == {"t": 0, "text": "♪", "sub": ""}
    w = split_words({"ts": 1, "l": [{"c": "Stack,", "o": 0}, {"c": " ", "o": 0.5}, {"c": "(Purr),", "o": 1},
                                    {"c": " ", "o": 1.5}, {"c": "stack", "o": 2}, {"c": " ", "o": 2.5}, {"c": "(meow)", "o": 3}]})
    assert (w["text"], w["sub"]) == ("Stack, stack", "Purr, meow"), w
    assert [x["t"] for x in w["words"]] == [1, 2.5, 3], w["words"]
    assert split_words({"ts": 0, "l": [{"c": "(No", "o": 0}, {"c": " ", "o": 0.1}, {"c": "pressure)", "o": 0.2}]})["text"] == "No pressure"


if __name__ == "__main__":
    if sys.argv[1:] == ["--test"]:
        demo()
        sys.exit(0)
    artist, title, album, dur = (sys.argv[1:] + [""] * 4)[:4]
    try:
        words, lines = ([], []) if "--no-musixmatch" in sys.argv[5:] else musixmatch(artist, title, album, dur)
    except Exception as e:   # Musixmatch is the flaky one: never let it take lrclib down too
        print(f"lyrics: musixmatch failed: {e!r}", file=sys.stderr)
        words, lines = [], []
    print(json.dumps(words or [split(l) for l in lrclib(artist, title, album, dur)] or lines))
