import QtQuick

// A one-line text box (calendar quick add, Wi-Fi password). The window only takes the
// keyboard while a card is open, and the box waits for a click before taking focus.
Rectangle {
    id: f
    property alias text: input.text
    property string hint: ""
    property int glyph: 0
    property bool secret: false
    signal accepted()
    function grab() { input.forceActiveFocus() }
    width: parent?.width ?? 240
    implicitHeight: 30
    radius: 10
    color: Look.raise
    border.width: 1
    border.color: input.activeFocus ? Qt.alpha(Look.accent, 0.6) : "transparent"
    Behavior on border.color { Fade {} }
    G {
        id: ic
        visible: f.glyph !== 0
        glyph: f.glyph
        x: 10
        anchors.verticalCenter: parent.verticalCenter
        color: Look.faint
        font.pixelSize: 13
    }
    TextInput {
        id: input
        anchors { fill: parent; leftMargin: f.glyph ? 30 : 10; rightMargin: 10 }
        verticalAlignment: TextInput.AlignVCenter
        color: Look.text
        selectionColor: Qt.alpha(Look.accent, 0.4)
        clip: true
        echoMode: f.secret ? TextInput.Password : TextInput.Normal
        font.family: Look.sans
        font.pixelSize: Look.size
        onAccepted: f.accepted()
        T {
            anchors.verticalCenter: parent.verticalCenter
            visible: input.text === "" && !input.activeFocus
            text: f.hint
            color: Look.faint
            font.pixelSize: Look.size
        }
    }
}
