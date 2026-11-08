import QtQuick

// A quick-settings tile: glyph, name and state; filled with the accent while on.
Rectangle {
    id: t
    property int glyph
    property string label
    property string sub: ""
    property bool on: false
    signal clicked()
    implicitHeight: 52
    radius: 14
    color: on ? Look.accent : hov.hovered ? Qt.alpha("white", 0.1) : Look.raise
    Behavior on color { Fade {} }
    Row {
        anchors { left: parent.left; leftMargin: 12; verticalCenter: parent.verticalCenter }
        spacing: 10
        G { glyph: t.glyph; font.pixelSize: 17; color: t.on ? Look.accentInk : Look.text; anchors.verticalCenter: parent.verticalCenter }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            T { width: t.width - 54; text: t.label; elide: Text.ElideRight; font.weight: Font.DemiBold; color: t.on ? Look.accentInk : Look.text }
            T { width: t.width - 54; text: t.sub; elide: Text.ElideRight; font.pixelSize: Look.small; color: t.on ? Qt.alpha(Look.accentInk, 0.75) : Look.dim }
        }
    }
    HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: t.clicked() }
}
