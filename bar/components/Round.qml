import QtQuick
import qs

// round toggle with its name under it (WifiMenu, BtMenu)
Column {
    id: rd
    property int icon
    property string label
    property bool on: false
    signal clicked()
    signal rightClicked()
    spacing: 5
    opacity: enabled ? 1 : 0.4
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        width: 48
        height: 48
        radius: 24
        color: rd.on ? (rdHover.hovered ? Qt.lighter(Theme.actBg, 1.08) : Theme.actBg)
                     : Qt.alpha(Theme.mainFg, rdHover.hovered && rd.enabled ? 0.16 : 0.08)
        Behavior on color { ColorAnimation { duration: 200 } }
        scale: rdTap.pressed ? 0.9 : 1
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        HoverHandler { id: rdHover; cursorShape: Qt.PointingHandCursor }
        TapHandler {
            id: rdTap
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onTapped: (p, button) => button === Qt.RightButton ? rd.rightClicked() : rd.clicked()
        }
        Text {
            anchors.centerIn: parent
            text: Theme.g(rd.icon)
            color: rd.on ? Theme.mainBg : Theme.mainFg
            Behavior on color { ColorAnimation { duration: 200 } }
            font { family: Theme.font; pixelSize: 20 }
        }
    }
    Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: rd.label
        color: Theme.mainFg
        opacity: rd.on ? 0.9 : 0.55
        font { family: Theme.font; pixelSize: 10 }
    }
}
