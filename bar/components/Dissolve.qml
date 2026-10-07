import QtQuick
import qs

// Liquid-spread layer effect (shaders/dissolve.frag): set as an item's layer.effect
// and animate `progress` 0 -> 1 to pour it out of `origin`, 1 -> 0 to drain it back
// (or, with hole: 1, to eat it away from `origin` outwards).
ShaderEffect {
    property real progress: 1
    property real edge: 0.07      // meniscus width
    property real bias: 0.82      // roundness of the pool (1 = circle, lower = wobblier)
    property vector2d origin: Qt.vector2d(1, 0)   // spawn point, 0..1 of the item
    property real seed: 0         // new pattern each time
    property real hole: 0         // 1: eat the content away from origin instead (progress 1 -> 0)
    property color glow: Theme.actBg
    readonly property vector2d res: Qt.vector2d(width, height)
    // Qt caches shaders by URL across reloads: bump ?v= after shaders/build.sh
    fragmentShader: Qt.resolvedUrl("../shaders/dissolve.frag.qsb?v=2")
}
