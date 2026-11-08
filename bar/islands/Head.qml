import QtQuick

// A panel's small header line: what it is on the left, a note or a control on the right.
Item {
    id: h
    property string text
    property string note: ""
    default property alias side: side.data
    width: parent?.width ?? 200
    implicitHeight: 18
    T {
        anchors.verticalCenter: parent.verticalCenter
        text: h.text
        color: Look.faint
        font.pixelSize: Look.small
        font.weight: Font.DemiBold
    }
    Row {
        id: side
        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
        spacing: 8
        T {
            visible: h.note !== ""
            text: h.note
            color: Look.faint
            font.pixelSize: Look.small
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
