import QtQuick

// Text that changes (a new track) leaves before the next arrives instead of snapping:
// holds `value` back as `shown` while the item fades out upwards, then fades the new one
// in from below. Children bind to `shown`; `swapped` fires as it changes.
Item {
    id: s
    property var value
    property var shown
    property real dy: 6
    property real lift: 0
    signal swapped()
    transform: Translate { y: s.lift }

    Component.onCompleted: shown = value
    onValueChanged: if (JSON.stringify(value) !== JSON.stringify(shown)) swap.restart()

    SequentialAnimation {
        id: swap
        ParallelAnimation {
            NumberAnimation { target: s; property: "opacity"; to: 0; duration: 140; easing.type: Easing.InCubic }
            NumberAnimation { target: s; property: "lift"; to: -s.dy; duration: 140; easing.type: Easing.InCubic }
        }
        ScriptAction { script: { s.shown = s.value; s.lift = s.dy; s.swapped() } }
        ParallelAnimation {
            NumberAnimation { target: s; property: "opacity"; to: 1; duration: 320; easing.type: Easing.OutCubic }
            NumberAnimation { target: s; property: "lift"; to: 0; duration: 320; easing.type: Easing.OutCubic }
        }
    }
}
