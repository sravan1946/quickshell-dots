import QtQuick
import qs

// Themed horizontal slider. `value` (0..1) is owned by the caller; drag/click/scroll emit moved(v).
// The knob chases the value on a spring and stretches with how far behind it is, so
// drags and jumps feel liquid; the fill follows the knob.
Item {
    id: s

    property real value: 0
    property bool dim: false
    readonly property bool pressed: mouse.pressed
    readonly property real v: Math.max(0, Math.min(1, value))
    signal moved(real v)

    readonly property real rest: (width - 14) * v     // knob's left edge at the value
    property real kx: rest
    Behavior on kx { SpringAnimation { spring: 5; damping: 0.4; epsilon: 0.1 } }
    readonly property real lag: Math.min(12, Math.abs(kx - rest) * 0.4)

    implicitWidth: 200
    implicitHeight: 18

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 6
        radius: 3
        color: Qt.alpha(Theme.mainFg, 0.18)
        Rectangle {
            width: s.kx + 7
            height: parent.height
            radius: parent.radius
            color: s.dim ? Qt.alpha(Theme.mainFg, 0.4) : Theme.mainFg
        }
    }
    Rectangle {
        id: knob
        anchors.verticalCenter: parent.verticalCenter
        x: s.kx - s.lag / 2
        width: 14 + s.lag
        height: 14 - s.lag * 0.3          // squashes as it stretches
        radius: height / 2
        color: s.dim ? Theme.mainBg : Theme.actFg
        border.color: Theme.mainFg
        border.width: 2
        scale: mouse.pressed ? 1.25 : mouse.containsMouse ? 1.12 : 1
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        preventStealing: true
        function set(x) { s.moved(Math.max(0, Math.min(1, (x - 7) / (width - 14)))) }
        onPressed: e => set(e.x)
        onPositionChanged: e => { if (pressed) set(e.x) }
        // 5% per wheel notch; touchpads send fractions of a notch
        onWheel: e => s.moved(Math.max(0, Math.min(1, s.value + e.angleDelta.y / 120 * 0.05)))
    }
}
