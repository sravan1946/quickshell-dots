import QtQuick
import QtQuick.Effects
import qs

// Synced lyrics (Lyrics.qml) as a short list that glides to keep the line being sung in the
// middle; the lines around it shrink and fade with distance, and the list's edges fade out.
// The current line fills in word by word as it's sung: from Musixmatch's word timings when
// there are any, else spread over the line by its letters. An instrumental break shows three
// dots filling towards the next line. Click a line to jump there.
ListView {
    id: list
    visible: Lyrics.lines.length > 0
    implicitHeight: 118
    clip: true
    interactive: false
    model: Lyrics.lines
    // the panel opens (or the track changes) mid-song: snap to the line instead of gliding down
    property bool snap: true
    onCountChanged: { snap = true; unsnap.restart() }
    Timer { id: unsnap; running: true; interval: 250; onTriggered: list.snap = false }
    currentIndex: Math.max(0, Lyrics.index)
    highlightRangeMode: ListView.StrictlyEnforceRange
    preferredHighlightBegin: height / 2 - 14
    preferredHighlightEnd: height / 2 + 14
    highlightMoveDuration: snap ? 0 : 420 * Look.speed
    highlightMoveVelocity: -1
    spacing: 7

    layer.enabled: true
    layer.effect: MultiEffect {
        maskEnabled: true
        maskSource: mask
        maskThresholdMin: 0.01
        maskSpreadAtMin: 1
    }
    Rectangle {
        id: mask
        anchors.fill: parent
        visible: false
        layer.enabled: true
        gradient: Gradient {
            GradientStop { position: 0; color: "transparent" }
            GradientStop { position: 0.28; color: "white" }
            GradientStop { position: 0.72; color: "white" }
            GradientStop { position: 1; color: "transparent" }
        }
    }

    delegate: Column {
        id: line
        required property var modelData
        required property int index
        readonly property int away: Math.abs(index - Lyrics.index)
        readonly property bool now: index === Lyrics.index
        readonly property real next: Lyrics.lines[index + 1]?.t ?? modelData.t + 5
        readonly property bool rest: !modelData.text.replace(/[♪♫\s]/g, "")
        width: ListView.view.width
        spacing: 1
        opacity: now ? 1 : away === 1 ? 0.5 : 0.25
        Behavior on opacity { Anim { type: "effects"; duration: 300 * Look.speed } }
        scale: now ? 1 : 0.9
        Behavior on scale { Anim { type: "fast" } }

        Sung {
            visible: !line.rest
            width: parent.width
            px: 14
            words: line.modelData.words ?? line.spread(line.modelData.text)
            live: line.now
        }
        Sung {
            visible: !line.rest && !!line.modelData.sub
            width: parent.width
            px: 11
            words: line.modelData.subWords ?? line.spread(line.modelData.sub ?? "")
            live: line.now
        }
        // a break: three dots that light up in turn on the way to the next line
        Row {
            visible: line.rest
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 6
            height: 18
            Repeater {
                model: 3
                Rectangle {
                    required property int index
                    readonly property real p: line.now ? Math.max(0, Math.min(1, ((Lyrics.pos - line.modelData.t) / Math.max(0.5, line.next - line.modelData.t - 0.3)) * 3 - index)) : 0
                    anchors.verticalCenter: parent.verticalCenter
                    width: 6; height: 6; radius: 3
                    color: Qt.tint(Look.faint, Qt.alpha(Look.accent, p))
                    scale: 1 + 0.35 * p
                }
            }
        }

        // no word timings: lay the line's time over its words by their letters, sung at a
        // natural pace (~70 ms a letter) rather than stretched over a long gap
        // ponytail: an estimate; real timings come from Musixmatch when it has them
        function spread(s) {
            const parts = s.match(/\s*\S+/g) ?? []
            const n = parts.reduce((a, w) => a + w.trim().length, 0)
            const dur = Math.min(next - modelData.t - 0.2, 0.4 + 0.07 * n)
            let t = modelData.t
            return parts.map(c => { const w = { t: t, c: c }; t += dur * c.trim().length / Math.max(1, n); return w })
        }

        TapHandler {
            enabled: !!Player.player?.canSeek
            onTapped: { Player.player.position = line.modelData.t; Player.refreshPos() }
        }
        HoverHandler { cursorShape: Player.player?.canSeek ? Qt.PointingHandCursor : Qt.ArrowCursor }
    }

    // A line ([{t, c}]) centred and wrapped by hand (Flow can't centre its rows). Each word is
    // drawn dim with a lit copy over it, revealed left to right while it's sung (until the next
    // word starts, at most 1.5 s). Off the current line it's one even colour.
    component Sung: Column {
        id: sg
        property var words: []
        property int px: 14
        property bool live
        readonly property color lit: Qt.lighter(Look.accent, 1.2)
        FontMetrics { id: fm; font { family: Look.sans; pixelSize: sg.px; weight: Font.DemiBold } }
        readonly property real sp: fm.advanceWidth(" ")
        // timed pieces join where the lyric has no space ("black-" + "fisted" stay one word)
        readonly property var rows: {
            const out = [[]]
            let x = 0, gap = false
            words.forEach((w, i) => {
                const c = w.c.trim()
                if (!c) { gap = true; return }
                if (/^\s/.test(w.c)) gap = true
                const wd = fm.advanceWidth(c)
                const next = words.slice(i + 1).find(n => n.c.trim())
                const e = Math.min(next?.t ?? w.t + 0.6, w.t + 1.5)
                if (x > 0 && gap && x + sp + wd > width) { out.push([]); x = 0 }
                const g = x > 0 && gap
                x += (g ? sp : 0) + wd
                out[out.length - 1].push({ c: c, t: w.t, e: e, gap: g })
                gap = /\s$/.test(w.c)
            })
            return out
        }
        Repeater {
            model: sg.rows
            Row {
                id: row
                required property var modelData
                anchors.horizontalCenter: parent.horizontalCenter
                Repeater {
                    model: row.modelData
                    Item {
                        id: word
                        required property var modelData
                        readonly property real p: sg.live ? Math.max(0, Math.min(1, (Lyrics.pos - modelData.t) / Math.max(0.05, modelData.e - modelData.t))) : 0
                        readonly property real lead: modelData.gap ? sg.sp : 0
                        width: lead + base.implicitWidth
                        height: base.implicitHeight
                        transform: Translate { y: -1.5 * Math.sin(Math.PI * word.p) }
                        Text {
                            id: base
                            x: word.lead
                            text: word.modelData.c
                            color: sg.live ? Look.faint : Look.text
                            font: fm.font
                        }
                        Item {
                            x: word.lead
                            width: base.implicitWidth * word.p
                            height: word.height
                            clip: true
                            Text { text: word.modelData.c; color: sg.lit; font: fm.font }
                        }
                    }
                }
            }
        }
    }
}
