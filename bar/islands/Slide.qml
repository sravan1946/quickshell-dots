import QtQuick

// A level slider: drag, click or scroll. Reports 0..1 through moved().
Item {
    id: s
    property real value: 0
    property color fill: Look.accent
    readonly property real v: Math.max(0, Math.min(1, value))
    signal moved(real v)
    implicitWidth: 200
    implicitHeight: 18
    anchors.verticalCenter: parent?.verticalCenter

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 6
        radius: 3
        color: Qt.alpha("white", 0.12)
        Rectangle {
            width: Math.max(height, 7 + (parent.width - 14) * s.v)
            height: parent.height
            radius: 3
            color: s.fill
        }
    }
    Rectangle {
        x: (s.width - 14) * s.v
        anchors.verticalCenter: parent.verticalCenter
        width: 14
        height: 14
        radius: 7
        color: "white"
        scale: mouse.pressed ? 1.2 : 1
        Behavior on scale { Anim { type: "fast" } }
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        preventStealing: true
        function set(x) { s.moved(Math.max(0, Math.min(1, (x - 7) / (width - 14)))) }
        onPressed: e => set(e.x)
        onPositionChanged: e => { if (pressed) set(e.x) }
        onWheel: e => s.moved(Math.max(0, Math.min(1, s.v + Math.sign(e.angleDelta.y) * 0.05)))
    }
}
