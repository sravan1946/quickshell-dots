import QtQuick
import qs
import qs.modules   // makes quickshell scan + hot-reload modules/ (they are loaded by name below)

// A row of pills: one side ("left", "center", "right") of Settings.barLayout. Shapes follow
// the screen edges (the outermost pill on each side is flat against it, centre pills hang
// from the top) and padding the outer modules (Config.pads).
Row {
    id: section
    property string side
    // modules switched off in Settings are left out; a pill left empty goes too
    readonly property var pills: Settings.barLayout[side]
        .map(p => p.filter(m => Settings.moduleShown(m))).filter(p => p.length)
    height: parent.height
    spacing: 20   // pill margins are 1em each side

    Repeater {
        model: section.pills
        Pill {
            required property var modelData
            required property int index
            shape: section.side === "center" ? "down"
                : section.side === "left" && index === 0 ? "right"
                : section.side === "right" && index === section.pills.length - 1 ? "left" : "full"
            padL: (Config.pads[modelData[0]] ?? [6, 6])[0]
            padR: (Config.pads[modelData[modelData.length - 1]] ?? [6, 6])[1]
            rim: !modelData.includes("Media")

            Repeater {
                model: modelData
                Loader {
                    required property string modelData
                    height: parent.height
                    source: Qt.resolvedUrl(`../modules/${modelData}.qml`)
                    onStatusChanged: if (status === Loader.Error) console.warn("bar: failed to load module", modelData)
                }
            }
        }
    }
}
