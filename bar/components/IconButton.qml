import QtQuick
import qs

// Round glyph button.
Rectangle {
    id: ib
    property int icon
    property int size: 16
    property bool dim: false
    signal clicked()

    implicitWidth: 30
    implicitHeight: 30
    radius: 15
    opacity: enabled ? 1 : 0.35
    color: ih.hovered && enabled ? Qt.alpha(Theme.mainFg, 0.18) : "transparent"
    Behavior on color { ColorAnimation { duration: 120 } }
    scale: ibTap.pressed ? 0.86 : 1
    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
    HoverHandler { id: ih; cursorShape: Qt.PointingHandCursor }
    TapHandler { id: ibTap; onTapped: ib.clicked() }
    Text {
        anchors.centerIn: parent
        text: Theme.g(ib.icon)
        color: ib.dim ? Qt.alpha(Theme.mainFg, 0.5) : Theme.mainFg
        font { family: Theme.font; pixelSize: ib.size }
    }
}
