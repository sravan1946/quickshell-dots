import QtQuick

// A small pill button. `strong` fills it (Join, Copy), otherwise it's a quiet raise.
Rectangle {
    id: b
    property string text
    property bool strong: false
    property color tone: Look.accent
    signal clicked()
    implicitWidth: t.implicitWidth + 20
    implicitHeight: 24
    radius: 12
    color: strong ? (hov.hovered ? Qt.lighter(tone, 1.08) : tone) : hov.hovered ? Look.hover : Look.raise
    Behavior on color { Fade {} }
    T {
        id: t
        anchors.centerIn: parent
        text: b.text
        color: b.strong ? Look.accentInk : Look.text
        font.pixelSize: Look.small
        font.weight: Font.DemiBold
    }
    HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: b.clicked() }
}
