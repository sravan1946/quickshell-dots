import QtQuick
import qs

// Label + sliding switch. `checked` is owned by the caller; clicking only emits toggled().
Item {
    id: t
    property alias text: label.text
    property bool checked: false
    signal toggled()

    implicitWidth: row.implicitWidth
    implicitHeight: 20

    Row {
        id: row
        spacing: 6
        anchors.verticalCenter: parent.verticalCenter
        Text {
            id: label
            anchors.verticalCenter: parent.verticalCenter
            color: Theme.mainFg
            opacity: t.checked || mouse.containsMouse ? 1 : 0.6
            Behavior on opacity { NumberAnimation { duration: 150 } }
            font { family: Theme.font; pixelSize: 12 }
        }
        Rectangle {
            width: 30; height: 16; radius: 8
            anchors.verticalCenter: parent.verticalCenter
            color: t.checked ? Theme.actBg : Qt.alpha(Theme.mainFg, mouse.containsMouse ? 0.35 : 0.25)
            Behavior on color { ColorAnimation { duration: 150 } }
            Rectangle {
                width: 12; height: 12; radius: 6
                y: 2
                x: t.checked ? 16 : 2
                color: t.checked ? Theme.mainBg : Theme.mainFg
                Behavior on x { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: 150 } }
            }
        }
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: t.toggled()
    }
}
