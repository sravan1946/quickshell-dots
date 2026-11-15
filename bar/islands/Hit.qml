import QtQuick
import Quickshell

// One thing in an island you can point at: a soft wash on hover, clicks, wheel notches, and
// (with a `key`) the panel it opens. The bar's controller (IslandBar `ctl`) does the opening:
// a short rest before the first panel, instant retargeting once one is open.
Item {
    id: hit

    property string key: ""          // panel to open on hover, "" = none
    property bool tapOpens: true     // a finger tap opens the panel; false = it clicks instead (workspaces)
    property bool lit: false         // drawn in the accent (caffeine on, a toggle that's on)
    property bool wash: true         // the hover wash (workspaces colour their number instead)
    property real padX: 6
    property real spacing: 4
    property real minWidth: 0
    default property alias content: row.data

    signal clicked(int button)
    signal scrolled(int steps)       // +1 up, -1 down, one per notch
    signal wheeled(real notches)     // every wheel event as it comes, in notches (a touchpad's are fractions)

    readonly property var ctl: QsWindow.window?.ctl ?? null
    readonly property bool hovered: hover.hovered
    readonly property bool hot: !!ctl && ctl.hot === hit && ctl.open

    implicitWidth: Math.max(minWidth, row.implicitWidth + 2 * padX)
    implicitHeight: Look.item
    anchors.verticalCenter: parent?.verticalCenter

    Rectangle {
        anchors.fill: parent
        radius: height / 2
        color: hit.lit ? Look.accent : hit.wash && (hit.hovered || hit.hot) ? Look.hover : "transparent"
        Behavior on color { Fade {} }
    }
    Row {
        id: row
        anchors.centerIn: parent
        spacing: hit.spacing
    }

    HoverHandler {
        id: hover
        // a finger doesn't hover: it would open nothing (lifted before the rest is over) and
        // its lift would close the card; taps are handled below instead
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad | PointerDevice.Stylus
        cursorShape: Qt.PointingHandCursor
        onHoveredChanged: if (hit.ctl && hit.key) hovered ? hit.ctl.enter(hit) : hit.ctl.leave(hit)
    }
    property real wheel: 0
    MouseArea {
        // reaches up to the screen edge, so a pointer pinned to the top still lands on it
        anchors { fill: parent; topMargin: -Look.top - 3; bottomMargin: -3 }
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        // a finger arrives here as a synthesized click: it opens the item's panel, which then
        // stays until tapped again (ctl.tap); an item with no panel just gets the click
        onClicked: e => {
            if (hit.key && hit.tapOpens && hit.ctl && e.source !== Qt.MouseEventNotSynthesized) hit.ctl.tap(hit)
            else hit.clicked(e.button)
        }
        onWheel: e => {
            hit.wheeled(e.angleDelta.y / 120)
            hit.wheel += e.angleDelta.y
            while (Math.abs(hit.wheel) >= 120) {
                const s = Math.sign(hit.wheel)
                hit.wheel -= s * 120
                hit.scrolled(s)
            }
        }
    }
}
