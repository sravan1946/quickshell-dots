import QtQuick
import QtQuick.Layouts
import qs

// A row in a list (WifiList, BtList): accent-tinted while `selected`, hover-tinted while
// `clickable`. What goes inside is laid out left to right with the standard margins.
Rectangle {
    id: row

    property bool selected: false
    property bool clickable: true
    default property alias content: layout.data
    signal clicked()
    signal rightClicked()

    height: 30
    radius: 9
    color: selected ? Qt.alpha(Theme.actBg, 0.25) : hover.hovered && clickable ? Qt.alpha(Theme.mainFg, 0.12) : "transparent"
    Behavior on color { ColorAnimation { duration: 120 } }
    HoverHandler { id: hover; cursorShape: row.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor }
    TapHandler { onTapped: row.clicked() }
    TapHandler { acceptedButtons: Qt.RightButton; onTapped: row.rightClicked() }

    RowLayout {
        id: layout
        anchors { fill: parent; leftMargin: 9; rightMargin: 9 }
        spacing: 9
    }
}
