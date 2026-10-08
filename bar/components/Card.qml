import QtQuick
import qs

// A rounded, faintly tinted box for the thing a panel is about (the current network, the
// hotspot, a connected device). `accent` tints and rims it in the accent colour.
Rectangle {
    property bool accent: false

    radius: 12
    color: accent ? Qt.alpha(Theme.actBg, 0.12) : Qt.alpha(Theme.mainFg, 0.06)
    border.color: Qt.alpha(Theme.actBg, accent ? 0.45 : 0)
    Behavior on border.color { ColorAnimation { duration: 150 } }
}
