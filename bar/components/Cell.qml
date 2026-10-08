import QtQuick
import QtQuick.Layouts
import Quickshell
import qs

// A labelled value tile in a details grid (WifiMenu); click copies it.
Rectangle {
    id: cell
    property string label
    property string value
    property string copy: value   // what a click copies, when it isn't what's shown
    property bool copied: false
    Layout.fillWidth: true
    Layout.preferredWidth: 1
    implicitHeight: 36
    radius: 9
    color: Qt.alpha(Theme.mainFg, cellHover.hovered ? 0.12 : 0.05)
    Behavior on color { ColorAnimation { duration: 120 } }
    HoverHandler { id: cellHover; cursorShape: Qt.PointingHandCursor }
    TapHandler {
        onTapped: if (cell.copy) { Quickshell.execDetached(["wl-copy", cell.copy]); cell.copied = true; copiedTimer.restart() }
    }
    Timer { id: copiedTimer; interval: 1200; onTriggered: cell.copied = false }
    Column {
        anchors { fill: parent; leftMargin: 9; rightMargin: 8; topMargin: 5 }
        spacing: 1
        Text {
            text: cell.copied ? "COPIED" : cell.label.toUpperCase()
            color: cell.copied ? Theme.actFg : Theme.mainFg
            opacity: cell.copied ? 1 : 0.5
            font { family: Theme.font; pixelSize: 8; bold: true; letterSpacing: 1 }
        }
        Text {
            width: parent.width
            text: cell.value || "—"
            color: Theme.mainFg
            elide: Text.ElideRight
            font { family: Theme.font; pixelSize: 11; bold: true }
        }
    }
}
