import QtQuick
import Quickshell
import Quickshell.Hyprland

// Workspace numbers, each followed by the icons of the apps open on it (one per app), with
// the accent "worm" behind the active one. Its two edges move
// separately: the one in the direction of travel leads, the other follows, so it stretches
// and settles (CRAFT.md rule 20). Click a number to go there, scroll to step; a workspace
// holding a window that wants attention gets an amber ring that breathes once a second.
Item {
    id: ws
    property var ctl
    property var monitor
    readonly property var list: Hyprland.workspaces.values.filter(w => w.id > 0 && w.monitor === monitor).sort((a, b) => a.id - b.id)
    readonly property int active: monitor?.activeWorkspace?.id ?? 0

    implicitWidth: row.implicitWidth
    implicitHeight: Look.item
    anchors.verticalCenter: parent?.verticalCenter

    // Hyprland's Lua config only takes hl.dsp.* dispatches
    function goto(id) { Hyprland.dispatch(`hl.dsp.focus({workspace="${id}"})`) }
    function step(dir) {
        const ids = list.map(w => w.id)
        const next = dir > 0 ? ids.find(i => i > active) : ids.filter(i => i < active).pop()
        if (next !== undefined) goto(next)
    }

    // ---- the worm ----
    property real l: 0
    property real r: 0
    property int was: 0
    function place(animate) {
        const it = row.children.find(c => c.wsId === active)
        if (!it) return
        const a = it.x, b = it.x + it.width
        if (!animate) { lead.stop(); trail.stop(); l = a; r = b; was = active; return }
        const fwd = active > was
        lead.property = fwd ? "r" : "l"; lead.to = fwd ? b : a
        trail.property = fwd ? "l" : "r"; trail.to = fwd ? a : b
        lead.restart(); trail.restart()
        was = active
    }
    onActiveChanged: Qt.callLater(place, true)
    Connections { target: row; function onImplicitWidthChanged() { Qt.callLater(ws.place, ws.was !== 0) } }
    Component.onCompleted: Qt.callLater(place, false)
    NumberAnimation {
        id: lead
        target: ws
        duration: 220 * Look.speed
        easing.type: Easing.BezierSpline
        easing.bezierCurve: [0.34, 1.3, 0.64, 1, 1, 1]
    }
    NumberAnimation {
        id: trail
        target: ws
        duration: 480 * Look.speed
        easing.type: Easing.BezierSpline
        easing.bezierCurve: [0.22, 1, 0.36, 1, 1, 1]
    }
    Rectangle {
        x: ws.l
        width: Math.max(0, ws.r - ws.l)
        height: Look.item
        radius: Look.item / 2
        color: Look.accent
    }

    // a slow breath for urgent rings: a stepped timer, not a looping animation (rule 17)
    property bool breath: true
    Timer {
        interval: 700
        repeat: true
        running: ws.list.some(w => w.urgent && w.id !== ws.active)
        onTriggered: ws.breath = !ws.breath
        onRunningChanged: if (!running) ws.breath = true
    }

    Row {
        id: row
        height: Look.item
        Repeater {
            model: ws.list
            Hit {
                id: w
                required property HyprlandWorkspace modelData
                readonly property int wsId: modelData.id
                readonly property bool on: modelData.id === ws.active
                readonly property bool urgent: modelData.urgent && !on
                readonly property bool occupied: modelData.toplevels.values.length > 0
                readonly property var apps: [...new Set(modelData.toplevels.values.map(t => Apps.id(t)).filter(a => a))].slice(0, 4)
                key: "ws:" + modelData.id
                property var arg: modelData
                wash: false
                padX: apps.length ? 7 : 0
                spacing: 4
                minWidth: 24
                Component.onCompleted: ws.ctl?.register(this)
                onClicked: b => { if (b === Qt.LeftButton) ws.goto(modelData.id) }
                onScrolled: s => ws.step(-s)

                Rectangle {
                    parent: w
                    anchors { fill: parent; margins: 3 }
                    radius: height / 2
                    color: "transparent"
                    border.color: Look.urgent
                    border.width: 1.5
                    opacity: w.urgent ? (ws.breath ? 1 : 0.3) : 0
                    visible: opacity > 0
                    Behavior on opacity { Anim { type: "effects"; duration: 600 * Look.speed } }
                }
                T {
                    height: Look.item
                    text: w.modelData.name
                    font.pixelSize: Look.barText
                    font.weight: Font.Bold
                    color: w.on ? Look.accentInk : w.urgent ? Look.urgent
                        : w.hovered || w.hot ? Look.text : w.occupied ? Look.dim : Look.faint
                    Behavior on color { Fade {} }
                }
                Repeater {
                    model: w.apps
                    AppIcon {
                        required property string modelData
                        appId: modelData
                        size: 13
                        opacity: w.on ? 1 : 0.8
                    }
                }
            }
        }
    }
}
