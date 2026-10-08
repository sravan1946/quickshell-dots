import QtQuick
import qs

// A one-line text box with a hint (WifiMenu, WifiList); `secret` hides what is typed.
Rectangle {
    property string hint
    property bool secret: false
    property alias text: input.text
    signal accepted()
    function grab() { input.forceActiveFocus() }
    implicitHeight: 26
    radius: 8
    color: Qt.alpha(Theme.mainFg, 0.08)
    border.color: input.activeFocus ? Theme.mainFg : Qt.alpha(Theme.mainFg, 0.25)
    TextInput {
        id: input
        anchors { fill: parent; leftMargin: 9; rightMargin: 9 }
        verticalAlignment: TextInput.AlignVCenter
        echoMode: parent.secret ? TextInput.Password : TextInput.Normal
        color: Theme.mainFg
        font { family: Theme.font; pixelSize: 12 }
        clip: true
        onAccepted: parent.accepted()
        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: input.text === ""
            text: parent.parent.hint
            color: Theme.mainFg
            opacity: 0.4
            font: input.font
        }
    }
}
