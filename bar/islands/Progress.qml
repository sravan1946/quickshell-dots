import QtQuick
import qs

// The track's progress under the bar's media item (shaders/progress.frag): a lit filament with
// a spark at the head that swells with the bass and flares on each kick. Its line runs `len` px
// from x + pad; the item is wider and taller than the line for the spark's glow.
ShaderEffect {
    property real len: 60
    readonly property real pad: 6
    width: len + 2 * pad
    height: 10
    readonly property vector2d res: Qt.vector2d(width, height)
    property real frac: Player.frac
    Behavior on frac { Anim { type: "effects" } }
    readonly property real t: Visualizer.t
    readonly property real bass: Visualizer.bass
    readonly property real kick: Visualizer.beatPows.x * Math.exp(-Math.max(0, Visualizer.t - Visualizer.beatAts.x) / 0.18)
    property real glow: Player.playing && Visualizer.active ? 1 : 0
    Behavior on glow { Anim { type: "effects"; duration: 600 * Look.speed } }
    readonly property color c1: Qt.lighter(Player.c1, 1.2)
    readonly property color c3: Player.c3

    fragmentShader: Qt.resolvedUrl("../shaders/progress.frag.qsb?v=7ae9a888")
}
