pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs

// Synced lyrics for Player's track: fetched once per track by scripts/lyrics.py (lrclib.net,
// then Musixmatch) as `lines` ({t, text, sub, and word timings when there are any}), `index` the line at Player.pos. Tracks with only
// plain (unsynced) lyrics, or none, leave `lines` empty.
Singleton {
    id: ly

    readonly property var player: Player.player
    // (the sources setting is part of it, so flipping it refetches)
    readonly property string key: Settings.lyrics && player?.trackTitle ? `${player.trackArtist}\n${player.trackTitle}\n${Settings.lyricsMusixmatch}` : ""
    property var lines: []
    // what the fetch came to, for when there are no lines: "searching", "none" (nothing synced
    // anywhere), "error" (nothing found and a source failed: `error` says which), or "" (have
    // lines, or lyrics off / nothing playing)
    property string error: ""
    readonly property string status: !key || lines.length ? "" : fetchTimer.running || req.running ? "searching" : error ? "error" : "none"
    // only while the music panel is open (or the bar shows the line) does pos follow the
    // player, so nothing here re-runs per frame for lyrics nobody sees
    readonly property bool live: Player.open || bar
    // Settings.lyricsOffset: + shows lines earlier. The player's position runs ahead of what's
    // heard by the output's latency (Bluetooth: ~0.2-0.3 s), so there it wants to go negative.
    readonly property real pos: live ? Player.pos + Settings.lyricsOffset : -1
    readonly property int index: {
        let i = -1
        while (i + 1 < lines.length && lines[i + 1].t <= pos) i++
        return i
    }

    // the bar's title shows the line being sung (Settings.lyricsInBar): then pos runs every frame
    readonly property bool bar: Settings.lyricsInBar && lines.length > 0 && Player.playing
    Binding { target: Player; property: "fine"; value: ly.bar }
    // how long line i takes to sing, s: to its last word when there are word timings; else
    // about three quarters of the gap before the next line, at least ~70 ms a letter, at most 6 s
    function singFor(i) {
        const l = lines[i], w = l?.words
        if (!l) return 0
        if (w?.length) return w[w.length - 1].t + 0.6 - l.t
        const est = 0.4 + 0.07 * l.text.replace(/\s/g, "").length
        const gap = (lines[i + 1]?.t ?? l.t + 6) - l.t
        return Math.min(Math.max(est, 0.75 * gap), 6, gap)
    }
    // that line, while it's being sung (and a moment more), never past the next line; one that
    // starts less than 1.6 s after stays up until it does, instead of the title flashing between
    readonly property string singNow: {
        if (!bar || index < 0) return ""
        const l = lines[index]
        const next = lines[index + 1]?.t ?? l.t + 6
        let end = l.t + singFor(index) + 0.8
        if (next - end < 1.6) end = next
        return pos < end ? l.text.replace(/^[♪♫\s]+$/, "").trim() : ""
    }
    // what the bar shows: a new line at once, back to the title only after 300 ms of nothing
    property string singing: ""
    onSingNowChanged: { if (singNow) { dropT.stop(); singing = singNow } else dropT.restart() }
    Timer { id: dropT; interval: 300; onTriggered: ly.singing = ly.singNow }
    // how far through singing it is, 0..1 by letters: from the word timings when there are any
    // (the current word filling over its time, at most 1.5 s), else evenly over singFor()
    readonly property real singingFrac: {
        if (!singNow) return 1   // finished (or held on through a short gap): stays at its end
        const l = lines[index], w = l.words
        if (!w?.length) return Math.max(0, Math.min(1, (pos - l.t) / singFor(index)))
        let done = 0, total = 0
        for (let i = 0; i < w.length; i++) {
            const n = w[i].c.length
            total += n
            const end = Math.min(w[i + 1]?.t ?? w[i].t + 0.6, w[i].t + 1.5)
            done += n * Math.max(0, Math.min(1, (pos - w[i].t) / Math.max(0.05, end - w[i].t)))
        }
        return total ? done / total : 0
    }

    onKeyChanged: fetchTimer.restart()   // MPRIS fills title/artist/length in separate updates
    Timer { id: fetchTimer; interval: 400; onTriggered: ly.fetch() }
    Component.onCompleted: fetchTimer.start()   // a reload mid-track: key starts set, no change fires

    function fetch() {
        lines = []
        error = ""
        if (!key || req.running) return   // a running request refetches on exit if stale
        req.forKey = key
        req.command = ["python3", Qt.resolvedUrl("scripts/lyrics.py").toString().replace("file://", ""),
                       player.trackArtist ?? "", player.trackTitle, player.trackAlbum ?? "", String(Math.round(Player.length) || ""),
                       Settings.lyricsMusixmatch ? "" : "--no-musixmatch"]
        req.running = true
    }

    Process {
        id: req
        property string forKey
        onExited: if (forKey !== ly.key) ly.fetch()
        stdout: StdioCollector {
            onStreamFinished: {
                if (req.forKey !== ly.key) return   // the track changed mid-request
                try { ly.lines = JSON.parse(text) } catch (e) { ly.lines = []; ly.error = "bad reply from lyrics.py" }
            }
        }
        stderr: StdioCollector {
            onStreamFinished: if (req.forKey === ly.key && text.trim()) ly.error = text.trim().split("\n").pop()
        }
    }
}
