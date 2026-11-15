import QtQuick
import Quickshell
import qs

// Each kick's wave over the whole bar (shaders/wave.frag): along the islands' outline and
// round the card's, drawn above their contents so nothing covers it. Place it over the part of
// the bar it should draw (it works in the bar's coordinates); it draws nothing while no wave is out.
ShaderEffect {
    required property var islands   // [left, centre, right]
    required property Item card
    property real originX: 0         // where the waves start, in the bar's coordinates
    property bool on: true

    visible: on && Settings.beatEffects && Visualizer.active && Visualizer.t - Visualizer.beatAt < Visualizer.waveLife

    readonly property vector2d res: Qt.vector2d(width, height)
    readonly property vector2d org: Qt.vector2d(x, y)
    readonly property real dpr: QsWindow.window?.devicePixelRatio ?? 1
    readonly property real yb: Look.top + Look.h
    function rect(i) { return Qt.vector4d(i.x, i.y, i.width, i.height) }
    function radii(i) { return Qt.vector4d(i.topLeftRadius, i.topRightRadius, i.bottomRightRadius, i.bottomLeftRadius) }
    readonly property vector4d i0: rect(islands[0])
    readonly property vector4d i1: rect(islands[1])
    readonly property vector4d i2: rect(islands[2])
    readonly property vector4d r0: radii(islands[0])
    readonly property vector4d r1: radii(islands[1])
    readonly property vector4d r2: radii(islands[2])
    // the card as goo.frag draws it
    readonly property real attach: card.shown && card.isl ? islands.indexOf(card.isl) : -1
    readonly property vector4d body: Qt.vector4d(card.x, card.y, card.width, card.height)
    readonly property vector4d bodyR: card.bodyR
    readonly property real goo: card.goo
    readonly property real fL: card.fL
    readonly property real fR: card.fR

    readonly property real ox: originX
    // the pulse (Visualizer.arrive)
    readonly property real v0: Visualizer.waveSpeed
    readonly property real v1: Visualizer.waveCruise
    readonly property real bend: Visualizer.waveBend
    readonly property real fade: Visualizer.waveFade
    readonly property real head: Visualizer.waveHead
    readonly property real tail: Visualizer.waveTail
    function agesOf(a) { const t = Visualizer.t; return Qt.vector4d(t - a.x, t - a.y, t - a.z, t - a.w) }
    readonly property vector4d ages: agesOf(Visualizer.beatAts)
    readonly property vector4d ages2: agesOf(Visualizer.beatAts2)
    readonly property vector4d punches: Visualizer.beatPows
    readonly property vector4d punches2: Visualizer.beatPows2
    readonly property vector4d kr: Visualizer.beatR
    readonly property vector4d kg: Visualizer.beatG
    readonly property vector4d kb: Visualizer.beatB
    readonly property vector4d kr2: Visualizer.beatR2
    readonly property vector4d kg2: Visualizer.beatG2
    readonly property vector4d kb2: Visualizer.beatB2
    readonly property color c2: Player.c2

    fragmentShader: Qt.resolvedUrl("../shaders/wave.frag.qsb?v=cf397e7c")
}
