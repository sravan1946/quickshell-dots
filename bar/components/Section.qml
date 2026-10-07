import QtQuick
import qs.modules   // makes quickshell scan + hot-reload modules/ (they are loaded by name below)

// A row of pills built from one of Config's left/center/right lists.
Row {
    id: section
    property var groups: []
    height: parent.height
    spacing: 20   // pill margins are 1em each side

    Repeater {
        model: section.groups
        Pill {
            required property var modelData
            shape: modelData.shape ?? "full"
            padL: modelData.padL ?? 6
            padR: modelData.padR ?? 6
            rim: !modelData.modules.includes("Media")

            Repeater {
                model: modelData.modules
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
