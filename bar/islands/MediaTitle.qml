import QtQuick
import QtQuick.Effects
import qs
import qs.components

// The playing track's title. A new one waits for its cover (`cover`, a Cover) so the two
// change together, leaving upwards as the new one rises in (Swap). One that doesn't fit
// scrolls to its end and back while playing, its clipped edges fading. With `lyrics`, the line
// being sung (Lyrics.singing) takes the title's place while it's sung, tinted with the
// accent, arriving quickly; a long one scrolls with the singing (Lyrics.singingFrac),
// keeping the word being sung a little past the middle. The width then holds at `maxWidth`, so
// the island doesn't change size line by line.
Item {
    id: m
    property Item cover
    property real maxWidth: 160
    property bool lyrics: false
    property alias font: probe.font
    property real scroll: 0          // the title marquee's offset
    // how far through the line on screen the singing is: it follows Lyrics only while that line
    // is the one being sung, so a line on its way out stays where it was instead of snapping back,
    // and only forwards
    property real frac: 0
    readonly property real liveFrac: swap.shown?.sung && swap.shown.text === Lyrics.singing ? Lyrics.singingFrac : -1
    onLiveFracChanged: if (liveFrac > frac) frac = liveFrac   // forward only: a position correction mustn't jerk it back
    property color color: Look.text

    readonly property string title: Player.player?.trackTitle || Player.player?.identity || ""
    property string held
    Component.onCompleted: held = title
    readonly property string sung: lyrics ? Lyrics.singing : ""
    implicitWidth: lyrics && Lyrics.bar ? maxWidth : Math.min(probe.implicitWidth, maxWidth)
    implicitHeight: probe.implicitHeight
    clip: true

    // MPRIS may send the art in a later update than the title: give it a moment, then wait
    // for the cover to fade in (at most 1.5 s, for art that never comes)
    property bool waiting: false
    onTitleChanged: { waiting = true; settle.restart(); cap.restart() }
    readonly property bool artReady: !Player.artPending && (cover?.settled ?? true)
    onArtReadyChanged: tryShow()
    Timer { id: settle; interval: 200; onTriggered: m.tryShow() }
    Timer { id: cap; interval: 1500; onTriggered: m.show() }
    function tryShow() { if (waiting && !settle.running && artReady) show() }
    function show() { waiting = false; cap.stop(); held = title }

    Text { id: probe; visible: false; text: swap.shown?.text ?? "" }

    layer.enabled: line.overflow > 0
    layer.effect: MultiEffect {
        autoPaddingEnabled: false
        maskEnabled: true
        maskSource: fade
        maskThresholdMin: 0
        maskSpreadAtMin: 1
    }
    Rectangle {
        id: fade
        visible: false
        width: m.width
        height: m.height
        layer.enabled: true
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: line.x < -1 ? "transparent" : "white" }
            GradientStop { position: 0.14; color: "white" }
            GradientStop { position: 0.86; color: "white" }
            GradientStop { position: 1; color: line.x > -line.overflow + 1 ? "transparent" : "white" }
        }
    }

    Swap {
        id: swap
        width: parent.width
        height: parent.height
        value: ({ text: m.sung || m.held, sung: !!m.sung })
        // a lyric line can't spend half a second arriving
        outMs: m.sung ? 50 : 140
        inMs: m.sung ? 110 : 320
        onSwapped: {
            m.scroll = 0
            m.frac = 0
            if (!shown.sung && marquee.running) marquee.restart()
        }
        Text {
            id: line
            readonly property bool sung: !!swap.shown?.sung
            readonly property real overflow: Math.max(0, implicitWidth - m.width)
            // a lyric follows the singing; a title is the marquee's
            x: sung ? Math.max(-overflow, Math.min(0, m.width * 0.6 - m.frac * implicitWidth)) : m.scroll
            anchors.verticalCenter: parent.verticalCenter
            text: swap.shown?.text ?? ""
            color: sung ? Qt.tint(m.color, Qt.alpha(Look.accent, 0.55)) : m.color
            font: probe.font
        }
    }
    // a loop while playing, against CRAFT rule 17: a long title would otherwise stay cut off
    SequentialAnimation {
        id: marquee
        running: line.overflow > 0 && Player.playing && !line.sung
        loops: Animation.Infinite
        onRunningChanged: if (!running) m.scroll = 0
        PauseAnimation { duration: 3000 }
        NumberAnimation { target: m; property: "scroll"; to: -line.overflow; duration: line.overflow * 35; easing.type: Easing.InOutSine }
        PauseAnimation { duration: 2000 }
        NumberAnimation { target: m; property: "scroll"; to: 0; duration: line.overflow * 35; easing.type: Easing.InOutSine }
    }
}
