import QtQuick
import QtQuick.Effects
import Quickshell.Widgets
import qs

// The liquid card every bar panel shares (Now Playing, quick settings, hover cards).
// pour(p) pours it out of p like liquid (components/Dissolve); drain(p) eats it away with a
// hole spreading from p once it has fully formed, or drains it back the way it came while it
// is still forming. Points are in the card's parent coordinates, and may sit outside it.
// The effect only runs mid-transition: settled, the card renders directly (crisp text).
ClippingRectangle {
    id: card

    property real progress: 0
    property color glow: Theme.actBg
    signal closed()                  // fully drained

    property real seed: 0
    property vector2d spawn: Qt.vector2d(0.5, 0)   // Dissolve origin, frozen per transition
    property bool closing: false

    function at(p) { return Qt.vector2d((p.x - x) / width, (p.y - y) / height) }
    function pour(p) {
        seed = Math.random() * 100
        spawn = at(p)
        closing = false
        burn.stop()
        form.restart()
    }
    function drain(p) {
        if (progress >= 1) { spawn = at(p); closing = true }
        form.stop()
        burn.restart()
    }

    visible: progress > 0
    layer.enabled: progress < 1
    layer.effect: Dissolve {
        progress: card.progress
        seed: card.seed
        glow: card.glow
        origin: card.spawn
        hole: card.closing ? 1 : 0
    }

    NumberAnimation { id: form; target: card; property: "progress"; to: 1; duration: 700 / Settings.liquidSpeed; easing.type: Easing.OutQuart }
    // closing: fast, then settling
    NumberAnimation { id: burn; target: card; property: "progress"; to: 0; duration: 420 / Settings.liquidSpeed; easing.type: Easing.OutCubic; onFinished: card.closed() }

    // behind the card (a child would be clipped), only once the blob has filled it; analytic,
    // so there's no offscreen blur to redo on every frame of a list sliding open
    RectangularShadow {
        parent: card.parent
        z: card.z - 1
        // geometry, not anchors: those resolve before the reparent, against the old parent
        x: card.x
        y: card.y
        width: card.width
        height: card.height
        radius: card.radius
        opacity: Math.max(0, (card.progress - 0.8) / 0.2)
        color: Qt.alpha("black", 0.5)
        blur: 32
        offset.y: 5
    }
}
