import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import qs

// Toggle tile (quick settings, the Wi-Fi panel). Turning on floods it with the accent from
// where you clicked, like liquid filling it; turning off drains back into that point.
ClippingRectangle {
    id: t
    property int icon
    property string label
    property string sub: ""
    property bool on: false
    property bool more: false      // has a list to pull out: the right end is a chevron
    property bool expanded: false
    property point origin: Qt.point(width / 2, height / 2)
    readonly property real reach: Math.hypot(Math.max(origin.x, width - origin.x), Math.max(origin.y, height - origin.y))
    property color ink: on ? Theme.mainBg : Theme.mainFg
    signal clicked()
    signal expand()

    Layout.fillWidth: true
    implicitHeight: 54
    radius: 14
    color: th.hovered ? Qt.alpha(Theme.mainFg, 0.16) : Qt.alpha(Theme.mainFg, 0.08)
    Behavior on color { ColorAnimation { duration: 150 } }
    // press only: a resting hover scale left the tile's text resampled (soft) the whole time
    scale: tap.pressed ? 0.95 : 1
    Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
    Behavior on ink { ColorAnimation { duration: 260 } }

    Rectangle {
        property real r: t.on ? t.reach : 0
        Behavior on r { NumberAnimation { duration: 460; easing.type: Easing.OutCubic } }
        x: t.origin.x - r
        y: t.origin.y - r
        width: 2 * r
        height: 2 * r
        radius: r
        color: th.hovered ? Qt.lighter(Theme.actBg, 1.08) : Theme.actBg
        Behavior on color { ColorAnimation { duration: 150 } }
    }

    HoverHandler { id: th; cursorShape: Qt.PointingHandCursor }
    TapHandler {
        id: tap
        onTapped: {
            if (t.more && tap.point.position.x > t.width - 34) return t.expand()
            t.origin = tap.point.position
            t.clicked()
        }
    }
    Text {
        visible: t.more
        anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
        text: Theme.g(0xF0140)   // chevron-down
        color: t.ink
        opacity: t.expanded ? 1 : 0.6
        rotation: t.expanded ? 180 : 0
        Behavior on rotation { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
        font { family: Theme.font; pixelSize: 16 }
    }

    Row {
        anchors.verticalCenter: parent.verticalCenter
        x: 12
        spacing: 10
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: Theme.g(t.icon)
            color: t.ink
            font { family: Theme.font; pixelSize: 18 }
        }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            Text {
                text: t.label
                color: t.ink
                font { family: Theme.font; pixelSize: 12; bold: true }
            }
            Text {
                width: t.width - 52 - (t.more ? 24 : 0)
                text: t.sub
                color: t.ink
                opacity: 0.75
                elide: Text.ElideRight
                font { family: Theme.font; pixelSize: 10 }
            }
        }
    }
}
