import QtQuick

// The root of every card panel (panels/*.qml). `arg` is what the item passed (a workspace, a
// tray item, ...), `ctl` the bar's controller (ctl.hide() closes the card). A panel sets its
// implicitWidth; the card measures that and the column's height.
Item {
    property var arg
    property var ctl
    property var hit
    default property alias content: col.data
    property alias spacing: col.spacing
    implicitHeight: col.implicitHeight
    Column {
        id: col
        width: parent.width
        spacing: 8
    }
}
