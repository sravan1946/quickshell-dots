import QtQuick
import qs

// Radial spectrum around a circle (shaders/ring.frag), live from Visualizer and coloured
// from the cover art (Player palette). Size it at least 2 * (inner + amp) + a few px.
ShaderEffect {
    property real inner: 40     // px: spokes grow out from this radius
    property real amp: 20       // px: spoke length at full level
    property real spokes: 64
    property real thick: 0.5    // spoke width as a fraction of its slot
    property real halo: 1       // glow / ghost line / bass halo strength
    property real spin: 0       // turns

    readonly property vector2d res: Qt.vector2d(width, height)
    readonly property color c1: Player.c1
    readonly property color c2: Player.c2
    readonly property color c3: Player.c3
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

    // Qt caches shaders by URL across reloads: bump ?v= after shaders/build.sh
    fragmentShader: Qt.resolvedUrl("../shaders/ring.frag.qsb?v=1")
}
