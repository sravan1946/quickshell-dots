import QtQuick

// An on/off switch. The knob moves on the fast spatial curve, the colour on effects.
Rectangle {
    id: sw
    property bool on: false
    signal toggled()
    width: 30
    height: 18
    radius: 9
    color: on ? Look.accent : Qt.alpha("white", hov.hovered ? 0.22 : 0.16)
    Behavior on color { Fade {} }
    anchors.verticalCenter: parent?.verticalCenter
    Rectangle {
        x: sw.on ? 14 : 2
        y: 2
        width: 14
        height: 14
        radius: 7
        color: "white"
        Behavior on x { Anim { type: "fast" } }
    }
    HoverHandler { id: hov; cursorShape: Qt.PointingHandCursor }
    TapHandler { onTapped: sw.toggled() }
}
