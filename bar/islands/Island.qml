import QtQuick
import QtQuick.Effects
import Quickshell

// One floating piece of the bar. It sizes itself for where its slots are heading (not where
// they are mid-spring), so the island and its contents arrive together, and keeps one width
// while nothing in it changes. `align` says which way it grows: from the left edge, the right
// edge, or both ways about the centre.
Rectangle {
    id: isl

    property string align: "left"
    property real bl: radius                 // bottom corners square off where the card joins
    property real br: radius
    property real join: 0                    // 0..1: how much the card hangs from it
    default property alias content: row.data
    readonly property alias row: row
    readonly property real pad: 3

    // the width it is heading for: the row as it will be once every slot has finished springing
    readonly property real targetW: {
        let w = row.implicitWidth
        for (const c of row.children) if (c.target !== undefined) w += c.target - c.implicitWidth
        return snap(w + 2 * pad)
    }
    // where it is heading for, in the bar's coordinates (the card is placed against this)
    readonly property real targetX: align === "left" ? Look.edge
        : align === "right" ? snap(parent.width - Look.edge - targetW)
        : snap((parent.width - targetW) / 2)
    // whole device pixels: at 1.5x a half-pixel edge blurs (rule 4)
    readonly property real dpr: QsWindow.window?.devicePixelRatio ?? 1
    function snap(v) { return Math.round(v * dpr) / dpr }

    property bool ready: false
    Component.onCompleted: Qt.callLater(() => ready = true)

    y: Look.top
    height: Look.h
    width: targetW
    Behavior on width { enabled: isl.ready; Anim {} }
    x: align === "left" ? Look.edge
        : align === "right" ? snap(parent.width - Look.edge - width)
        : snap((parent.width - width) / 2)

    radius: Look.h / 2
    topLeftRadius: radius
    topRightRadius: radius
    bottomLeftRadius: bl
    bottomRightRadius: br
    color: Look.surface
    border.width: 0

    // a 1px rim of light, dropped while the card hangs from it (the card's own edge takes over)
    Rectangle {
        anchors.fill: parent
        topLeftRadius: parent.topLeftRadius; topRightRadius: parent.topRightRadius
        bottomLeftRadius: parent.bottomLeftRadius; bottomRightRadius: parent.bottomRightRadius
        color: "transparent"
        border.color: Look.rim
        border.width: 1
        opacity: 1 - isl.join
    }
    RectangularShadow {
        z: -1
        anchors.fill: parent
        offset.y: 8
        blur: 24
        radius: isl.radius
        color: Qt.rgba(0, 0, 0, 0.28)
        cached: true
        opacity: 1 - isl.join
    }

    // light in the glass (Isle), under the contents
    readonly property alias deco: deco
    Item { id: deco; anchors.fill: parent }

    Row {
        id: row
        height: parent.height
        spacing: 1
        x: isl.align === "left" ? isl.pad
            : isl.align === "right" ? isl.snap(parent.width - isl.pad - width)
            : isl.snap((parent.width - width) / 2)
    }

    // what the window's input mask follows: the island and the strip above it to the screen edge
    readonly property Item hitBox: hb
    Item { id: hb; y: -Look.top; width: parent.width; height: parent.height + Look.top }
}
