import QtQuick
import Quickshell.Hyprland
import qs.islands

// The windows on one workspace. Click one to go to it.
Panel {
    id: p
    implicitWidth: 260
    readonly property var wins: arg?.toplevels.values ?? []

    Head { text: "Workspace " + (p.arg?.name ?? ""); note: p.wins.length + (p.wins.length === 1 ? " window" : " windows") }
    T {
        visible: p.wins.length === 0
        text: "Empty. Click the number to go there."
        color: Look.dim
        font.pixelSize: Look.small
        leftPadding: 4
    }
    Column {
        width: parent.width
        spacing: 2
        Repeater {
            model: p.wins
            Choice {
                required property var modelData
                title: Apps.name(modelData)
                sub: modelData.title
                note: modelData.urgent ? "wants attention" : ""
                noteColor: Look.urgent
                selected: modelData === Hyprland.activeToplevel
                onClicked: b => {
                    if (b === Qt.MiddleButton) modelData.wayland?.close()
                    else { modelData.wayland?.activate(); p.ctl.hide() }
                }
                AppIcon { appId: Apps.id(modelData); size: 20 }
            }
        }
    }
}
