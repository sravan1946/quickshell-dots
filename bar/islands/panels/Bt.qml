import QtQuick
import Quickshell
import Quickshell.Bluetooth
import qs.islands

// Bluetooth: the switch and the devices. Click a paired one to connect or disconnect, a new
// one to pair (blueman-applet answers any PIN prompt); right-click a paired one to forget it.
// Looks for new devices while the panel is open.
Panel {
    id: p
    implicitWidth: 280
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property var devices: (adapter?.devices.values ?? [])
        .filter(d => d.paired || d.deviceName !== "")
        .sort((a, b) => b.connected - a.connected || b.paired - a.paired || a.name.localeCompare(b.name))
        .slice(0, 8)
    property bool scanning: false
    property string want: ""
    function scan(on) {
        if (!adapter?.enabled || on === scanning) return
        scanning = on
        adapter.discovering = on
    }
    Component.onCompleted: scan(true)
    Component.onDestruction: scan(false)
    // BlueZ calls earbuds and headphones both "audio-headset": earbuds go by the name (as in the bar)
    function glyph(icon, name) {
        return /buds|earbud|pods|\bear\b|cmf/i.test(name ?? "") && /audio|head/.test(icon) ? 0xF184F
            : /headset|headphone/.test(icon) ? 0xF02CB : /audio|speaker/.test(icon) ? 0xF04C3
            : /mouse/.test(icon) ? 0xF037D : /keyboard/.test(icon) ? 0xF030C : /phone/.test(icon) ? 0xF011C : 0xF00AF
    }

    Head { text: "Bluetooth"; Switch { on: !!p.adapter?.enabled; onToggled: if (p.adapter) p.adapter.enabled = !p.adapter.enabled } }
    T {
        visible: p.devices.length === 0
        leftPadding: 4
        text: !p.adapter?.enabled ? "Off" : p.adapter.discovering ? "Looking for devices…" : "No devices"
        color: Look.dim
        font.pixelSize: Look.small
    }
    Column {
        width: parent.width
        spacing: 2
        Repeater {
            model: ScriptModel { values: p.devices }
            Choice {
                id: row
                required property var modelData
                readonly property var d: modelData
                readonly property bool busy: d.pairing || d.state === BluetoothDeviceState.Connecting || d.state === BluetoothDeviceState.Disconnecting
                title: d.name
                selected: d.connected
                // Nothing / CMF buds: each bud and the case (BudsState)
                readonly property var buds: d.connected ? BudsState.of(d) : null
                sub: !buds ? "" : [["Left", buds.left], ["Right", buds.right], ["Case", buds.case]]
                    .filter(e => e[1]).map(e => `${e[0]} ${e[1][0]}%${e[1][1] ? " ⚡" : ""}`).join("  ·  ")
                note: d.pairing ? "pairing…" : d.state === BluetoothDeviceState.Connecting ? "connecting…"
                    : d.state === BluetoothDeviceState.Disconnecting ? "disconnecting…"
                    : d.connected && d.batteryAvailable && !buds ? Math.round(d.battery * 100) + "%"
                    : !d.paired ? "new" : ""
                noteColor: busy ? Look.accent : Look.faint
                onClicked: b => {
                    if (b === Qt.RightButton) { if (d.paired) d.forget(); return }
                    if (busy) return
                    if (d.connected) d.disconnect()
                    else if (d.paired) d.connect()
                    else { p.want = d.address; d.trusted = true; d.pair() }
                }
                Connections {
                    target: row.d
                    function onPairedChanged() { if (row.d.paired && p.want === row.d.address) { p.want = ""; row.d.connect() } }
                }
                G { anchors.centerIn: parent; glyph: p.glyph(row.d.icon, row.d.name); opacity: row.d.paired ? 1 : 0.6 }
            }
        }
    }
    Btn {
        anchors.right: parent.right
        text: "Bluetooth devices…"
        onClicked: { p.ctl.hide(); Quickshell.execDetached(["blueman-manager"]) }
    }
}
