import QtQuick
import qs

// Small clickable pill used inside dropdown panels.
Rectangle {
    id: b
    property alias text: label.text
    property bool checked: false
    signal clicked()

    implicitWidth: label.implicitWidth + 16
    implicitHeight: 20
    radius: height / 2
    color: mouse.containsMouse ? Theme.hvrBg : checked ? Theme.actBg : Qt.alpha(Theme.mainFg, 0.15)
    Behavior on color { ColorAnimation { duration: 150 } }
    scale: mouse.pressed ? 0.92 : 1
    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

    Label {
        id: label
        anchors.centerIn: parent
        color: mouse.containsMouse ? Theme.hvrFg : b.checked ? Theme.actFg : Theme.mainFg
        Behavior on color { ColorAnimation { duration: 150 } }
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: b.clicked()
    }
}
