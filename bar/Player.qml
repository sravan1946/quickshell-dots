pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs

// The MPRIS player the media module and the Now Playing panel follow (one picked in the
// panel's header, else the playing one, else the first), a colour palette pulled from its
// cover art, and the panel's state.
Singleton {
    id: pl

    // the players worth showing: a browser keeps its MPRIS entry after a tab's media ends
    // (stopped, no title), and that empty one mustn't stand in for a real player
    readonly property var players: Mpris.players.values.filter(p => p.playbackState !== MprisPlaybackState.Stopped || p.trackTitle !== "")
    readonly property var auto: players.find(p => p.isPlaying) ?? players[0] ?? null
    // a pick holds until that player goes away or another one becomes the playing one
    // ponytail: only sees a start that changes `auto` (first playing in list order); track per-player starts if that bites
    property var picked: null
    onAutoChanged: if (auto?.isPlaying && auto !== picked) picked = null
    readonly property var player: (picked && players.includes(picked) ? picked : null) ?? auto
    readonly property bool playing: !!player?.isPlaying
    // paused for 10 minutes: the pill folds away until it plays again
    property bool idle: false
    Timer { interval: 600000; running: !!pl.player && !pl.playing; onTriggered: pl.idle = true }
    readonly property string artUrl: player?.trackArtUrl ?? ""

    // Track position, s. Quickshell already advances player.position in real time; it
    // just doesn't notify, so the binding re-reads it on Visualizer's frame clock (no timer
    // or animation of its own), with a slow poll as a fallback when no frames arrive.
    readonly property real length: player?.lengthSupported ? player.length : 0
    readonly property real pos: {
        Visualizer.t   // re-read every frame
        return player?.positionSupported ? Math.min(length || Infinity, player.position) : 0
    }
    readonly property real frac: length > 0 ? Math.min(1, pos / length) : 0
    function refreshPos() { player?.positionChanged() }
    Connections {
        target: pl.player
        function onTrackTitleChanged() { pl.refreshPos() }
    }
    onPlayingChanged: { if (playing) idle = false; refreshPos() }
    onPlayerChanged: { idle = false; refreshPos() }
    Timer { interval: 3000; repeat: true; running: pl.playing && !Visualizer.active; onTriggered: pl.refreshPos() }

    // Now Playing panel (NowPlaying.qml): which screen, centred under which x.
    // The bar pill opens it on hover (show) and it closes once the pointer is on neither.
    property bool open: false
    property bool pillHovered: false
    property bool pinned: false   // held open regardless of the pointer (Settings' Media page preview)
    property string screen: ""
    property real anchorX: 0
    // origin: the screen point (screen-local, logical px) the panel pours out of when it
    // opens (where the pointer rested on the pill) and drains into when it closes (where
    // the pointer last left the pill or the card)
    property point origin: Qt.point(0, 0)
    function show(screenName, x, from) {
        screen = screenName
        anchorX = x
        origin = from
        open = true
    }
    // each screen's media pill registers itself, so the panel can open under it (IPC, the
    // settings preview) wherever the bar layout has put it
    property var pills: ({})   // screen name -> pill item
    function pillX(screenName) {
        const p = pills[screenName]
        return p && p.width > 0 ? p.mapToItem(null, p.width / 2, 0).x : -1
    }
    function showAtPill(s) {
        const x = pillX(s.name) >= 0 ? pillX(s.name) : s.width / 2
        show(s.name, x, Qt.point(x, 0))
    }
    function toggle(screenName, x) {
        if (open && screen === screenName) { open = false; return }
        show(screenName, x, Qt.point(x, 0))
    }

    // palette: c1 vivid (spoke tips, accents), c2 glow and ghost line, c3 spoke roots
    property color c1: Theme.actFg
    property color c2: Theme.actBg
    property color c3: Theme.mainFg
    Behavior on c1 { ColorAnimation { duration: 900 } }
    Behavior on c2 { ColorAnimation { duration: 900 } }
    Behavior on c3 { ColorAnimation { duration: 900 } }
    function themed() { c1 = Theme.actFg; c2 = Theme.actBg; c3 = Theme.mainFg }

    // The cover as a local file, for ColorQuantizer (local files only) and every Image that
    // shows it: http(s) art is downloaded once here instead of by each Image. A fresh name per
    // download, since Qt's pixmap cache keys on the URL (a reused name shows an older cover);
    // the previous downloads are removed first.
    readonly property string cache: Quickshell.env("HOME") + "/.cache"
    property string artFile: ""
    onArtUrlChanged: fetchArt()
    Component.onCompleted: fetchArt()
    function fetchArt() {
        if (!artUrl) { artFile = ""; themed(); return }
        if (artUrl.startsWith("file://")) { artFile = artUrl; return }
        if (fetch.running) return   // onExited picks up the newer URL
        fetch.url = artUrl
        fetch.target = `${cache}/quickshell-np-art-${Date.now()}`
        fetch.command = ["sh", "-c", 'rm -f "$1"/quickshell-np-art-*; curl -sfL --max-time 10 -o "$2" "$3"',
                         "sh", cache, fetch.target, artUrl]
        fetch.running = true
    }
    Process {
        id: fetch
        property string url
        property string target
        onExited: code => {
            if (fetch.url !== pl.artUrl) pl.fetchArt()
            else if (code === 0) pl.artFile = "file://" + fetch.target
            else pl.themed()
        }
    }

    ColorQuantizer {
        id: quant
        source: pl.artFile
        depth: 3            // 8 buckets
        rescaleSize: 64
        onColorsChanged: {
            const cs = Array.prototype.slice.call(quant.colors)
            const viv = c => c.hsvSaturation * c.hsvValue
            cs.sort((a, b) => viv(b) - viv(a))
            if (!cs.length || viv(cs[0]) < 0.12) { pl.themed(); return }   // greyscale art: keep the theme
            // lift each towards a readable, glowing tone on the dark panel
            const lift = (c, l) => Qt.hsla(Math.max(0, c.hslHue), Math.max(c.hslSaturation, 0.45), Math.max(c.hslLightness, l), 1)
            pl.c1 = lift(cs[0], 0.7)
            pl.c2 = lift(cs[1] ?? cs[0], 0.6)
            pl.c3 = lift(cs[2] ?? cs[0], 0.45)
        }
    }
}
