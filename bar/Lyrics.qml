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
    // Settings.lyricsOffset: + shows lines earlier. The player's position runs ahead of what's
    // heard by the output's latency (Bluetooth: ~0.2-0.3 s), so there it wants to go negative.
    // only while the Now Playing panel is open does pos follow the player, so nothing here
    // re-runs per frame for a panel nobody sees
    readonly property bool live: Player.open
    readonly property real pos: live ? Player.pos + Settings.lyricsOffset : -1
    readonly property int index: {
        let i = -1
        while (i + 1 < lines.length && lines[i + 1].t <= pos) i++
        return i
    }

    onKeyChanged: fetchTimer.restart()   // MPRIS fills title/artist/length in separate updates
    Timer { id: fetchTimer; interval: 400; onTriggered: ly.fetch() }
    Component.onCompleted: fetchTimer.start()   // a reload mid-track: key starts set, no change fires

    function fetch() {
        lines = []
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
                try { ly.lines = JSON.parse(text) } catch (e) { ly.lines = [] }
            }
        }
    }
}
