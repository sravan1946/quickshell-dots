import QtQuick
import Quickshell
import qs

// Light in the glass of the island the music is in (shaders/isle.frag): an aurora under the
// media item, rising with the spectrum. Lives in the island's deco layer (between its surface
// and its contents). Each kick's wave is Wave.qml's, drawn over the whole bar.
ShaderEffect {
    id: s
    required property Item island
    property vector2d eq: Qt.vector2d(0, 0)

    anchors.fill: parent
    readonly property vector2d res: Qt.vector2d(width, height)
    readonly property vector4d radii: Qt.vector4d(island.br, island.radius, island.bl, island.radius)
    readonly property real dpr: QsWindow.window?.devicePixelRatio ?? 1
    property real glow: Player.playing && Visualizer.active ? 1 : 0
    Behavior on glow { Anim { type: "effects"; duration: 600 * Look.speed } }
    readonly property color c1: Qt.lighter(Player.c1, 1.1)
    readonly property color c2: Player.c2
    readonly property color c3: Player.c3
    readonly property real t: Visualizer.t
    readonly property vector4d l0: Visualizer.l0
    readonly property vector4d l1: Visualizer.l1
    readonly property vector4d l2: Visualizer.l2
    readonly property vector4d l3: Visualizer.l3
    readonly property vector4d l4: Visualizer.l4
    readonly property vector4d l5: Visualizer.l5
    readonly property vector4d l6: Visualizer.l6
    readonly property vector4d l7: Visualizer.l7
    readonly property vector4d p0: Visualizer.p0
    readonly property vector4d p1: Visualizer.p1
    readonly property vector4d p2: Visualizer.p2
    readonly property vector4d p3: Visualizer.p3
    readonly property vector4d p4: Visualizer.p4
    readonly property vector4d p5: Visualizer.p5
    readonly property vector4d p6: Visualizer.p6
    readonly property vector4d p7: Visualizer.p7
    Component.onCompleted: Visualizer.peakUsers++
    Component.onDestruction: Visualizer.peakUsers--

    fragmentShader: Qt.resolvedUrl("../shaders/isle.frag.qsb?v=a59488d8")
}
