import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Bluetooth
import qs

// The panel blueman's tray icon opens in place of its own menu (modules/Tray.qml), laid out
// like the Wi-Fi one (WifiMenu): round power / visible toggles, a card per connected device
// (battery, disconnect), then the rest (BtList: click to connect or pair, right-click to
// forget). blueman-applet keeps running underneath as the agent that answers PIN prompts;
// the cog opens blueman-manager for the rest.
Dropdown {
    id: menu

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool on: !!adapter?.enabled
    readonly property var connected: (adapter?.devices.values ?? []).filter(d => d.connected)
        .sort((a, b) => a.name.localeCompare(b.name))

    closeOnOutsideClick: true
    padX: 12
    padY: 12

    Column {
        width: 320
        spacing: 12

        // ---- round toggles ----
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 22
            Round {
                icon: menu.on ? 0xF00AF : 0xF00B2   // bluetooth / bluetooth-off
                label: "Bluetooth"
                on: menu.on
                enabled: !!menu.adapter
                onClicked: menu.adapter.enabled = !menu.on
            }
            Round {
                icon: menu.adapter?.discoverable ? 0xF0208 : 0xF0209   // eye / eye-off
                label: "Visible"
                on: !!menu.adapter?.discoverable
                enabled: menu.on
                onClicked: menu.adapter.discoverable = !menu.adapter.discoverable
            }
        }

        Text {
            visible: !menu.on
            width: parent.width
            topPadding: 12
            bottomPadding: 12
            horizontalAlignment: Text.AlignHCenter
            text: menu.adapter ? "Bluetooth is off" : "No Bluetooth adapter"
            color: Theme.mainFg
            opacity: 0.5
            font { family: Theme.font; pixelSize: 12 }
        }

        // ---- connected devices ----
        Repeater {
            model: ScriptModel { values: menu.on ? menu.connected : [] }
            Card {
                id: card
                required property var modelData
                readonly property var d: modelData
                readonly property bool leaving: d.state === BluetoothDeviceState.Disconnecting
                accent: true
                width: parent.width
                height: 52
                RowLayout {
                    anchors { fill: parent; leftMargin: 12; rightMargin: 10 }
                    spacing: 10
                    Text {
                        text: Theme.g(devices.glyph(card.d.icon))
                        color: Theme.actFg
                        font { family: Theme.font; pixelSize: 20 }
                    }
                    Column {
                        Layout.fillWidth: true
                        Text {
                            width: parent.width
                            text: card.d.name
                            color: Theme.mainFg
                            elide: Text.ElideRight
                            font { family: Theme.font; pixelSize: 13; bold: true }
                        }
                        Text {
                            width: parent.width
                            text: card.leaving ? "Disconnecting…"
                                : "Connected" + (card.d.batteryAvailable ? ` · battery ${Math.round(card.d.battery * 100)}%` : "")
                            color: Theme.mainFg
                            opacity: 0.6
                            elide: Text.ElideRight
                            font { family: Theme.font; pixelSize: 10 }
                        }
                    }
                    PillButton {
                        text: Theme.g(0xF00B2) + " Disconnect"   // bluetooth-off
                        enabled: !card.leaving
                        opacity: enabled ? 1 : 0.5
                        onClicked: card.d.disconnect()
                    }
                }
            }
        }

        // all of them, not quick settings' 8: past ~8 rows they scroll
        Scroller {
            visible: menu.on
            width: parent.width
            BtList {
                id: devices
                width: parent.width
                active: menu.visible && menu.on
                hideConnected: true
                limit: 99
            }
        }

        // ---- this machine's name / settings ----
        RowLayout {
            width: parent.width
            Text {
                Layout.fillWidth: true
                leftPadding: 9
                visible: menu.on
                text: Theme.g(0xF0322) + "  " + (menu.adapter?.name ?? "")
                    + (menu.adapter?.discoverable ? " · visible to others" : "")
                color: Theme.mainFg
                opacity: 0.5
                elide: Text.ElideRight
                font { family: Theme.font; pixelSize: 11 }
            }
            Item { Layout.fillWidth: !menu.on }
            IconButton {
                icon: 0xF0493   // cog
                size: 15
                onClicked: { menu.close(); Util.run("blueman-manager") }
            }
        }
    }
}
