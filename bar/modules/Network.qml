import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import qs.components

// network: live down/up rates of the default-route interface over a sparkline.
// Hover: a card with signal, graph and address (components/HoverCard). Click: the network panel with a
// bigger graph, details, the Wi-Fi switch and nearby networks to join.
// Rates are sampled once in NetStats.qml for every bar.
Mod {
    id: net

    readonly property color colDown: Theme.color(Settings.netColDown, "#99ffdd")
    readonly property color colUp: Theme.color(Settings.netColUp, "#ffcc66")

    readonly property string iface: NetStats.iface
    readonly property real down: NetStats.down
    readonly property real up: NetStats.up
    readonly property var info: NetStats.info
    readonly property bool wifi: !!info.ssid
    readonly property int signal: parseInt(info.signal) || 0
    readonly property string title: iface === "" ? "Disconnected" : (info.ssid || info.conn || iface)
    readonly property string status: iface === "" ? "Offline"
        : wifi ? ["Connected", info.freq, info.dbm ? info.dbm + " dBm" : ""].filter(s => s).join(" · ")
        : "Wired"

    // fixed width (each rate padded to 6 cells of the monospace font) so the pills to the
    // right don't shift every sample; the sparkline behind it is the last minute
    richText: iface !== ""
    minChars: 15
    text: iface === "" ? Theme.g(0xF05AA) + " "
        : `<font color="${colDown}">↓${short(down)}</font> <font color="${colUp}">↑${short(up)}</font>`

    onClicked: b => { if (b === Qt.LeftButton) panel.toggle() }
    onHoveredChanged: if (hovered) NetStats.refresh()

    // waybar pow_format: 1000-based, one decimal above bytes
    function rate(b) {
        const u = ["", "k", "M", "G", "T"]
        let i = 0
        while (b >= 1000 && i < u.length - 1) { b /= 1000; i++ }
        return (i ? b.toFixed(1) : Math.round(b)) + " " + u[i] + "B/s"
    }
    // bar form: no "B/s", padded with no-break spaces (rich text collapses plain ones)
    function short(b) {
        const u = ["B", "k", "M", "G", "T"]
        let i = 0
        while (b >= 1000 && i < u.length - 1) { b /= 1000; i++ }
        return ((i ? b.toFixed(1) : Math.round(b)) + u[i]).padStart(6, " ")
    }
    function netmask(cidr) {
        const bits = parseInt((cidr ?? "").split("/")[1])
        if (isNaN(bits)) return ""
        const m = bits === 0 ? 0 : (~0 << (32 - bits)) >>> 0
        return [24, 16, 8, 0].map(s => (m >>> s) & 255).join(".")
    }

    // a backdrop: kept to the lower band and faint, so spikes don't cut through the rates
    NetGraph {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; leftMargin: 3; rightMargin: 3; bottomMargin: 3 }
        height: parent.height * 0.42
        z: -1
        opacity: 0.28
        down: net.colDown
        up: net.colUp
    }

    // ---- hover card ----
    // poured out under the pill (components/HoverCard); kept shut while the click panel is up
    HoverCard { id: hover; content: hoverCard; glow: net.colDown; blocked: panel.visible }
    Component {
        id: hoverCard
        Column {
            width: 250
            spacing: 7

            RowLayout {
                width: parent.width
                spacing: 8
                Bars { visible: net.wifi; strength: net.signal }
                Text {
                    visible: !net.wifi
                    text: Theme.g(net.iface === "" ? 0xF05AA : 0xF0200)
                    color: Theme.mainFg
                    font { family: Theme.font; pixelSize: 14 }
                }
                Text {
                    Layout.fillWidth: true
                    text: net.title
                    color: Theme.mainFg
                    elide: Text.ElideRight
                    font { family: Theme.font; pixelSize: 13; bold: true }
                }
                Text {
                    text: net.wifi ? net.signal + "%" : ""
                    color: Theme.mainFg
                    opacity: 0.6
                    font { family: Theme.font; pixelSize: 11 }
                }
            }
            GraphBox { visible: net.iface !== ""; width: parent.width; height: 44; samples: 30 }
            RowLayout {
                visible: net.iface !== ""
                width: parent.width
                Text { text: "↓ " + net.rate(net.down); color: net.colDown; font { family: Theme.font; pixelSize: 12; bold: true } }
                Item { Layout.fillWidth: true }
                Text { text: "↑ " + net.rate(net.up); color: net.colUp; font { family: Theme.font; pixelSize: 12; bold: true } }
            }
            Text {
                visible: net.iface !== ""
                width: parent.width
                text: [(net.info.ip ?? "").split("/")[0], net.iface, net.wifi ? net.info.freq : ""].filter(s => s).join(" · ")
                color: Theme.mainFg
                opacity: 0.6
                elide: Text.ElideRight
                font { family: Theme.font; pixelSize: 11 }
            }
        }
    }

    // ---- click panel ----
    Timer { interval: NetStats.interval; running: panel.visible; repeat: true; onTriggered: NetStats.refresh() }
    Timer { id: refreshSoon; interval: 900; onTriggered: { NetStats.refresh(); wifiList.scan() } }

    Dropdown {
        id: panel
        target: net
        closeOnOutsideClick: true
        padX: 14
        padY: 14
        onVisibleChanged: if (visible) NetStats.refresh()

        Column {
            width: 330
            spacing: 12

            // header: signal, name, status, Wi-Fi switch
            RowLayout {
                width: parent.width
                spacing: 10
                Bars { visible: net.wifi; strength: net.signal; scale: 1.3; Layout.leftMargin: 3 }
                Text {
                    visible: !net.wifi
                    text: Theme.g(net.iface === "" ? 0xF05AA : 0xF0200)
                    color: Theme.mainFg
                    font { family: Theme.font; pixelSize: 18 }
                }
                Column {
                    Layout.fillWidth: true
                    Text {
                        width: parent.width
                        text: net.title
                        color: Theme.mainFg
                        elide: Text.ElideRight
                        font { family: Theme.font; pixelSize: 15; bold: true }
                    }
                    Text {
                        text: net.status
                        color: Theme.mainFg
                        opacity: 0.6
                        font { family: Theme.font; pixelSize: 11 }
                    }
                }
                Toggle {
                    text: "Wi-Fi"
                    checked: !!net.info.wifiOn
                    onToggled: { Util.run(`nmcli radio wifi ${net.info.wifiOn ? "off" : "on"}`); refreshSoon.restart() }
                }
            }

            // two-minute graph with the peak
            GraphBox {
                visible: net.iface !== ""
                width: parent.width
                height: 92
                samples: 60
                lineWidth: 1.5
                Text {
                    x: 8
                    y: 5
                    text: "peak " + net.rate(parent.peak)
                    color: Theme.mainFg
                    opacity: 0.55
                    font { family: Theme.font; pixelSize: 10 }
                }
                Text {
                    anchors { right: parent.right; bottom: parent.bottom; margins: 5; rightMargin: 8 }
                    text: "2 min"
                    color: Theme.mainFg
                    opacity: 0.4
                    font { family: Theme.font; pixelSize: 9 }
                }
            }
            RowLayout {
                visible: net.iface !== ""
                width: parent.width
                Text { text: "↓ " + net.rate(net.down); color: net.colDown; font { family: Theme.font; pixelSize: 14; bold: true } }
                Item { Layout.fillWidth: true }
                Text { text: "↑ " + net.rate(net.up); color: net.colUp; font { family: Theme.font; pixelSize: 14; bold: true } }
            }

            // details
            GridLayout {
                visible: net.iface !== ""
                width: parent.width
                columns: 4
                columnSpacing: 10
                rowSpacing: 4
                Repeater {
                    model: [].concat(
                        ["IP", (net.info.ip ?? "").split("/")[0]], ["Gateway", NetStats.gateway],
                        ["Netmask", net.netmask(net.info.ip)], ["Interface", net.iface])
                    Text {
                        required property string modelData
                        required property int index
                        Layout.fillWidth: index % 2 === 1
                        text: modelData
                        color: Theme.mainFg
                        opacity: index % 2 ? 1 : 0.55
                        elide: Text.ElideRight
                        font { family: Theme.font; pixelSize: 11; bold: index % 2 === 1 }
                    }
                }
            }

            WifiList {
                id: wifiList
                visible: !!net.info.wifiOn
                width: parent.width
                active: panel.visible
            }

            PillButton {
                text: Theme.g(0xF0493) + "  Connection editor"
                onClicked: { panel.close(); Util.run("nm-connection-editor") }
            }
        }
    }

    // rounded tray with the rate graph in it
    component GraphBox: Rectangle {
        property alias samples: graph.samples
        property alias lineWidth: graph.lineWidth
        readonly property alias peak: graph.peak
        radius: 9
        color: Qt.alpha(Theme.mainFg, 0.06)
        clip: true
        NetGraph {
            id: graph
            anchors { fill: parent; topMargin: 6 }
            down: net.colDown
            up: net.colUp
            fillAlpha: 0.3
        }
    }
}
