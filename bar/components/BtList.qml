import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import qs

// Bluetooth devices: click a paired one to connect / disconnect, a new one to pair
// (blueman-applet is the agent that answers any PIN prompt) and connect; right-click
// a paired one to forget it. Discovers while `active`.
Column {
    id: list

    property bool active: false
    readonly property var adapter: Bluetooth.defaultAdapter
    // unnamed discoveries only carry their address as a name: noise
    readonly property var devices: (adapter?.devices.values ?? [])
        .filter(d => d.paired || d.deviceName !== "")
        .sort((a, b) => b.connected - a.connected || b.paired - a.paired || a.name.localeCompare(b.name))
        .slice(0, 8)
    property bool scanning: false   // our own discovery, so we don't stop someone else's
    property string want: ""        // address being paired, to connect once it is

    spacing: 3
    function scan(on) {
        if (!adapter?.enabled || on === scanning) return
        scanning = on
        adapter.discovering = on
    }
    onActiveChanged: scan(active)
    Component.onDestruction: scan(false)
    Connections {
        target: list.adapter
        function onEnabledChanged() { if (list.adapter.enabled && list.active) list.scan(true); else list.scanning = false }
    }

    function glyph(icon) {
        return /headset|headphone/.test(icon) ? 0xF02CB : /audio|speaker/.test(icon) ? 0xF04C3
            : /mouse/.test(icon) ? 0xF037D : /keyboard/.test(icon) ? 0xF030C : /gaming/.test(icon) ? 0xF0297
            : /phone/.test(icon) ? 0xF011C : /computer/.test(icon) ? 0xF0322 : 0xF00AF
    }
    function tap(d) {
        if (d.connected) d.disconnect()
        else if (d.paired) d.connect()
        else { want = d.address; d.trusted = true; d.pair() }
    }

    RowLayout {
        width: parent.width
        Text {
            Layout.fillWidth: true
            text: "Devices"
            color: Theme.mainFg
            opacity: 0.55
            font { family: Theme.font; pixelSize: 11; bold: true }
        }
        Text {
            text: Theme.g(0xF0450)
            color: Theme.mainFg
            opacity: list.adapter?.discovering ? 1 : 0.55
            font { family: Theme.font; pixelSize: 12 }
            RotationAnimator on rotation { running: !!list.adapter?.discovering; from: 0; to: 360; duration: 900; loops: Animation.Infinite }
            TapHandler { onTapped: list.scan(!list.scanning) }
        }
    }

    Text {
        visible: list.devices.length === 0
        width: parent.width
        leftPadding: 9
        text: list.adapter?.discovering ? "Looking for devices…" : "No devices"
        color: Theme.mainFg
        opacity: 0.45
        font { family: Theme.font; pixelSize: 11 }
    }

    // diffed by device: discovery churn updates rows in place instead of rebuilding them all
    Repeater {
        model: ScriptModel { values: list.devices }
        Rectangle {
            id: row
            required property var modelData
            readonly property var d: modelData
            readonly property bool busy: d.pairing || d.state === BluetoothDeviceState.Connecting
                || d.state === BluetoothDeviceState.Disconnecting
            width: parent.width
            height: 30
            radius: 9
            color: d.connected ? Qt.alpha(Theme.actBg, 0.25) : rowHover.hovered ? Qt.alpha(Theme.mainFg, 0.12) : "transparent"
            Behavior on color { ColorAnimation { duration: 120 } }
            HoverHandler { id: rowHover; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: if (!row.busy) list.tap(row.d) }
            TapHandler { acceptedButtons: Qt.RightButton; onTapped: if (row.d.paired) row.d.forget() }
            Connections {
                target: row.d
                function onPairedChanged() { if (row.d.paired && list.want === row.d.address) { list.want = ""; row.d.connect() } }
            }

            RowLayout {
                anchors { fill: parent; leftMargin: 9; rightMargin: 9 }
                spacing: 9
                Text {
                    text: Theme.g(list.glyph(row.d.icon))
                    color: Theme.mainFg
                    opacity: row.d.paired ? 1 : 0.6
                    font { family: Theme.font; pixelSize: 13 }
                }
                Text {
                    Layout.fillWidth: true
                    text: row.d.name
                    color: Theme.mainFg
                    elide: Text.ElideRight
                    font { family: Theme.font; pixelSize: 12; bold: row.d.connected }
                }
                Text {
                    visible: text !== ""
                    text: row.d.pairing ? "pairing…" : row.d.state === BluetoothDeviceState.Connecting ? "connecting…"
                        : row.d.state === BluetoothDeviceState.Disconnecting ? "disconnecting…"
                        : row.d.connected && row.d.batteryAvailable ? Math.round(row.d.battery * 100) + "%"
                        : row.d.paired && !row.d.connected ? "paired" : ""
                    color: row.busy ? Theme.actFg : Theme.mainFg
                    opacity: row.busy ? 1 : 0.55
                    font { family: Theme.font; pixelSize: 10 }
                }
                Text {
                    visible: row.d.connected
                    text: Theme.g(0xF012C)
                    color: Theme.actFg
                    font { family: Theme.font; pixelSize: 12 }
                }
            }
        }
    }
}
