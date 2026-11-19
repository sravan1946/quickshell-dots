import QtQuick

// A fat level track (brightness, the speaker): filled in `tint` to `value`, the glyph riding the
// edge of the fill, the number in a fixed cell on the right. Drag or click anywhere; scroll for
// `step` a notch (Shift for five times that). Tapping the glyph is its own signal (mute).
Rectangle {
    id: t
    property real value: 0
    property color tint: Look.accent
    property bool muted: false
    property int glyph
    property string text: Math.round(value * 100) + "%"
    property real step: 0.01
    property real floor: 0
    signal moved(real v)
    signal glyphTapped()
    readonly property color ink: Qt.darker(tint, 3.4)
    readonly property color face: muted ? Qt.alpha(Look.text, 0.18) : tint

    implicitHeight: 46
    radius: 15
    color: Qt.alpha(tint, muted ? 0.05 : 0.11)
    Behavior on color { Fade {} }

    Rectangle {
        id: fill
        width: Math.max(t.height, t.width * Math.min(1, t.value))
        height: parent.height
        radius: t.radius
        color: t.face
        Behavior on width { enabled: !drag.pressed; Anim { type: "effects" } }
        Behavior on color { Fade {} }
    }
    MouseArea {
        id: drag
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        preventStealing: true
        function set(x) { t.moved(Math.max(t.floor, Math.min(1, x / width))) }
        onPressed: e => set(e.x)
        onPositionChanged: e => { if (pressed) set(e.x) }
        onWheel: e => {
            const n = (e.modifiers & Qt.ShiftModifier ? 5 : 1) * Math.sign(e.angleDelta.y || e.angleDelta.x)
            t.moved(Math.max(t.floor, Math.min(1, t.value + n * t.step)))
        }
    }
    // the glyph, riding the edge of the fill; above the drag area, so a tap on it is its own
    G {
        // it stops short of the number, so a full track keeps both readable
        x: Math.max(14, Math.min(fill.width - width - 14, t.width - 42 - 14 - 10 - width))
        anchors.verticalCenter: parent.verticalCenter
        glyph: t.glyph
        font.pixelSize: 18
        color: t.muted ? Look.dim : t.ink
        MouseArea {
            anchors { fill: parent; margins: -8 }
            cursorShape: Qt.PointingHandCursor
            onClicked: t.glyphTapped()
        }
    }
    // the number, in a cell sized for "100%": dark once the fill runs under it
    T {
        anchors { right: parent.right; rightMargin: 14; verticalCenter: parent.verticalCenter }
        width: 42
        horizontalAlignment: Text.AlignRight
        text: t.text
        font.pixelSize: 14
        font.weight: Font.Bold
        color: !t.muted && fill.width > t.width - 56 ? t.ink : t.muted ? Look.faint : Look.text
        Behavior on color { Fade {} }
    }
}
