import QtQuick
import Quickshell
import qs

// HyDE group shapes: "full" = #pill, "right" = #pill-right (flat left edge),
// "left" = #pill-left (flat right edge), "down" = #pill-down (flat top edge).
// Pills sit 0.3em from the bar edges; #pill-down touches the top.
Rectangle {
    id: p

    property string shape: "full"
    property real padL: 6
    property real padR: 6
    property bool rim: true   // light up as the beat wave passes (off for the media pill: it has its own)
    default property alias content: row.data

    readonly property real r: Theme.radius
    color: Theme.mainBg
    topLeftRadius: shape === "right" || shape === "down" ? 0 : r
    bottomLeftRadius: shape === "right" ? 0 : r
    topRightRadius: shape === "left" || shape === "down" ? 0 : r
    bottomRightRadius: shape === "left" ? 0 : r

    y: shape === "down" ? 0 : Config.pillInset
    implicitWidth: row.implicitWidth + padL + padR
    implicitHeight: shape === "down" ? 27 : 24

    Row {
        id: row
        x: p.padL
        height: p.height
    }

    // the beat wave passing through (shaders/rim.frag): where the wave starts, in pill
    // coordinates, is read on each kick, since pills only move when the layout does
    property real ox: -1e4
    Connections {
        target: p.rim ? Visualizer : null
        function onBeat() {
            const w = p.QsWindow.window
            if (w && "beatX" in w) p.ox = w.beatX - p.mapToItem(null, 0, 0).x
        }
    }
    ShaderEffect {
        anchors.fill: parent
        visible: p.rim && Visualizer.active
        readonly property vector2d res: Qt.vector2d(width, height)
        readonly property vector4d radii: Qt.vector4d(p.bottomRightRadius, p.topRightRadius, p.bottomLeftRadius, p.topLeftRadius)
        readonly property real ox: p.ox
        // capped, so the uniforms stop changing (and the pill repainting) once every beat's light is out
        readonly property vector4d ages: {
            const a = Visualizer.beatAts, t = Visualizer.t
            const f = at => Math.min(3, t - at)
            return Qt.vector4d(f(a.x), f(a.y), f(a.z), f(a.w))
        }
        readonly property vector4d punches: Visualizer.beatPows
        readonly property real dur: Visualizer.waveDur
        readonly property real reach: Visualizer.waveReach
        readonly property color c1: Player.c1
        // Qt caches shaders by URL across reloads: bump ?v= after shaders/build.sh
        fragmentShader: Qt.resolvedUrl("../shaders/rim.frag.qsb?v=3")
    }
}
