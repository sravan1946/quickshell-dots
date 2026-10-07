import QtQuick
import Quickshell
import Quickshell.Hyprland
import qs
import qs.components

// hyprland/workspaces: click to switch, scroll for prev/next existing workspace.
// Hyprland's Lua config only takes hl.dsp.* dispatches (the legacy
// `workspace N` syntax waybar sends is rejected).
Item {
    id: root
    readonly property var monitor: Hyprland.monitorFor(QsWindow.window?.screen ?? null)
    implicitWidth: row.implicitWidth

    // Neighbouring existing workspace, no wraparound (Hyprland's e+1/e-1 loops).
    function step(dir) {
        const cur = monitor?.activeWorkspace?.id ?? 0
        const ids = Hyprland.workspaces.values.map(w => w.id).filter(i => i > 0).sort((a, b) => a - b)
        const next = dir > 0 ? ids.filter(i => i > cur)[0] : ids.filter(i => i < cur).pop()
        if (next !== undefined) goto(next)
    }

    function goto(ws) { Hyprland.dispatch(`hl.dsp.focus({workspace="${ws}"})`) }

    // past startup: buttons that show up after this grow in
    property bool settled: false
    Timer { running: true; interval: 1000; onTriggered: root.settled = true }

    ActiveSlide { id: slide }

    Row {
        id: row
        height: parent.height
        Repeater {
            model: Hyprland.workspaces
            Mod {
                id: ws
                required property HyprlandWorkspace modelData
                visible: modelData.id > 0          // hide special workspaces
                button: true
                growIn: root.settled
                extraPad: 4.5
                active: modelData.active && modelData.monitor === root.monitor
                activeBg: "transparent"
                onActiveChanged: if (active) slide.take(ws)
                Component.onCompleted: if (active) slide.take(ws)
                text: modelData.name
                onClicked: root.goto(modelData.id)
                onScrolled: s => root.step(s > 0 ? -1 : 1)
            }
        }
    }
}
