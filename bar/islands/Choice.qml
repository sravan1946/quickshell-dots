import QtQuick
import QtQuick.Layouts

// A row in a panel list: something on the left, a title (and a line under it), a note on
// the right. Washes on hover; `selected` tints it in the accent.
Rectangle {
    id: c
    property string title
    property string sub: ""
    property string note: ""
    property color noteColor: Look.faint
    property bool selected: false
    property bool clickable: true
    property bool icon: true          // false: no room kept for something on the left
    default property alias leading: lead.data
    signal clicked(int button)

    width: parent?.width ?? 260
    implicitHeight: sub ? 40 : 30
    radius: 9
    color: selected ? Qt.alpha(Look.accent, 0.16) : clickable && hov.hovered ? Look.hover : "transparent"
    Behavior on color { Fade {} }

    RowLayout {
        anchors { fill: parent; leftMargin: 7; rightMargin: 8 }
        spacing: 10
        Item {
            id: lead
            Layout.preferredWidth: 20
            Layout.preferredHeight: 20
            visible: c.icon && children.length > 0
        }
        Column {
            Layout.fillWidth: true
            T { width: parent.width; text: c.title; elide: Text.ElideRight; font.weight: c.selected || c.sub ? Font.DemiBold : Font.Normal }
            T { visible: c.sub !== ""; width: parent.width; text: c.sub; color: Look.dim; font.pixelSize: Look.small; elide: Text.ElideRight }
        }
        T { visible: c.note !== ""; text: c.note; color: c.noteColor; font.pixelSize: Look.small }
    }
    HoverHandler { id: hov; cursorShape: c.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor }
    TapHandler {
        enabled: c.clickable
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onTapped: (p, b) => c.clicked(b)
    }
}
