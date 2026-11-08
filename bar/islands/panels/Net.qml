import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import qs.components
import qs.islands

// The network: the link, two minutes of traffic, the addresses, and the Wi-Fi networks
// around. Saved networks connect on click, open ones join, secured new ones ask for the
// password here; right-click a saved one to forget it. Scans while open. VPNs (NetworkManager's,
// pritunl's included) go up and down on click; nm-applet still answers their secret prompts.
Panel {
    id: p
    implicitWidth: 300
    readonly property var info: NetStats.info
    Component.onCompleted: { NetStats.refresh(); scan() }
    Timer { interval: NetStats.interval; running: true; repeat: true; onTriggered: NetStats.refresh() }

    Head {
        text: NetState.wifi ? "Wi-Fi" : NetState.online ? "Wired" : "Offline"
        Switch {
            visible: p.info.wifiOn !== undefined
            on: !!p.info.wifiOn
            onToggled: Quickshell.execDetached(["sh", "-c", `nmcli radio wifi ${p.info.wifiOn ? "off" : "on"}`])
        }
    }
    Item {
        width: parent.width
        height: 22
        T {
            width: parent.width - detail.implicitWidth - 12
            elide: Text.ElideRight
            text: !NetState.online ? "Not connected" : p.info.ssid || p.info.conn || NetStats.iface
            font.pixelSize: 17
            font.weight: Font.Bold
            anchors.bottom: parent.bottom
        }
        T {
            id: detail
            anchors { right: parent.right; bottom: parent.bottom; bottomMargin: 2 }
            text: [p.info.freq, p.info.dbm ? p.info.dbm + " dBm" : "", NetStats.iface].filter(s => s).join(" · ")
            color: Look.dim
            font.pixelSize: Look.small
        }
    }
    NetGraph {
        visible: NetState.online
        width: parent.width
        height: 50
        samples: 60
        lineWidth: 1.5
        fillAlpha: 0.18
        down: Look.down
        up: Look.up
    }
    GridLayout {
        visible: NetState.online
        width: parent.width
        columns: 2
        rowSpacing: 3
        Repeater {
            model: [["Down / up", NetState.rate(NetStats.down) + " · " + NetState.rate(NetStats.up)],
                ["Address", (p.info.ip ?? "").split("/")[0]], ["Gateway", NetStats.gateway]]
            Item {
                required property var modelData
                Layout.columnSpan: 2
                Layout.fillWidth: true
                implicitHeight: 16
                T { text: parent.modelData[0]; color: Look.dim; font.pixelSize: Look.small }
                T { anchors.right: parent.right; text: parent.modelData[1]; font.pixelSize: Look.small }
            }
        }
    }

    // ---- VPNs ----
    property var vpns: []          // [{name, state}], state "" | "activating" | "activated" | "deactivating"
    function flip(v) {
        Quickshell.execDetached(["nmcli", "con", v.state === "" ? "up" : "down", "id", v.name])
        vpns = vpns.map(o => o.name === v.name ? Object.assign({}, o, { state: v.state === "" ? "activating" : "deactivating" }) : o)
    }
    Process {
        id: vpnList
        running: true
        command: ["sh", "-c", "nmcli -t -f NAME,TYPE,STATE con show | grep -E ':(vpn|wireguard):'"]
        stdout: StdioCollector {
            onStreamFinished: p.vpns = text.split("\n").filter(l => l).map(l => Util.nmFields(l))
                .map(f => ({ name: f[0], state: f[2] ?? "" })).sort((a, b) => a.name.localeCompare(b.name))
        }
    }
    Timer { interval: 1500; running: true; repeat: true; onTriggered: if (!vpnList.running) vpnList.running = true }

    Head { visible: p.vpns.length > 0; text: "VPN" }
    Column {
        visible: p.vpns.length > 0
        width: parent.width
        spacing: 2
        Repeater {
            model: ScriptModel { values: p.vpns.map(v => v.name) }
            Choice {
                id: vpn
                required property string modelData
                readonly property var v: p.vpns.find(o => o.name === modelData) ?? ({ name: modelData, state: "" })
                readonly property bool up: v.state === "activated"
                readonly property bool busy: v.state === "activating" || v.state === "deactivating"
                title: v.name
                selected: up
                note: v.state === "activating" ? "connecting…" : v.state === "deactivating" ? "disconnecting…" : up ? "connected" : ""
                noteColor: busy ? Look.accent : Look.faint
                onClicked: b => { if (b === Qt.LeftButton && !busy) p.flip(v) }
                G { anchors.centerIn: parent; glyph: vpn.up ? 0xF0565 : 0xF099D; opacity: vpn.up ? 1 : 0.6 }
            }
        }
    }

    // ---- networks around ----
    property var found: []        // [{ssid, signal, secure, inUse}], strongest first
    property var saved: []
    property string askFor: ""
    property string joining: ""
    property string failed: ""
    function scan() { if (!scanner.running) scanner.running = true; if (!rescan.running) rescan.running = true }
    function join(e) {
        if (e.inUse || joiner.running) return
        failed = ""
        if (saved.includes(e.ssid)) connect(e.ssid, ["nmcli", "con", "up", "id", e.ssid], "")
        else if (!e.secure) connect(e.ssid, ["nmcli", "dev", "wifi", "connect", e.ssid], "")
        else askFor = askFor === e.ssid ? "" : e.ssid
    }
    // argv, no shell; the password goes to nmcli --ask on stdin, never on a command line
    function connect(ssid, cmd, pw) { joining = ssid; joiner.pw = pw; joiner.command = cmd; joiner.running = true }
    Process {
        id: scanner
        command: ["sh", "-c", `
            nmcli -t -f NAME,TYPE con show | sed -n 's/:802-11-wireless$//p' | sed 's/^/SAVED:/'
            nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY dev wifi list --rescan no`]
        stdout: StdioCollector {
            onStreamFinished: {
                const saved = [], best = {}
                for (const l of text.split("\n")) {
                    if (l.startsWith("SAVED:")) { saved.push(l.slice(6).replace(/\\:/g, ":")); continue }
                    const f = Util.nmFields(l)
                    if (f.length < 4 || !f[1]) continue
                    const e = { ssid: f[1], inUse: f[0] === "*", signal: +f[2] || 0, secure: f[3] !== "" && f[3] !== "--" }
                    const o = best[e.ssid]
                    if (!o || e.inUse || (!o.inUse && e.signal > o.signal)) best[e.ssid] = e
                }
                p.saved = saved
                p.found = Object.values(best).sort((a, b) => b.inUse - a.inUse || b.signal - a.signal).slice(0, 6)
            }
        }
    }
    Process {
        id: joiner
        property string pw: ""
        stdinEnabled: true
        onStarted: if (pw !== "") { write(pw + "\n"); pw = "" }
        onExited: code => {
            if (code !== 0) p.failed = p.joining
            else p.askFor = ""
            p.joining = ""
            NetStats.refresh()
            p.scan()
        }
    }
    Process { id: rescan; command: ["nmcli", "dev", "wifi", "rescan"]; onExited: relist.restart() }
    Timer { id: relist; interval: 3500; onTriggered: if (!scanner.running) scanner.running = true }

    Head { visible: p.found.length > 0; text: "Networks" }
    Column {
        width: parent.width
        spacing: 2
        Repeater {
            model: ScriptModel { values: p.found.map(e => e.ssid) }
            Column {
                id: entry
                required property string modelData
                readonly property var e: p.found.find(f => f.ssid === modelData) ?? ({ ssid: modelData, signal: 0 })
                width: parent.width
                spacing: 4
                Choice {
                    title: entry.e.ssid
                    selected: !!entry.e.inUse
                    clickable: !entry.e.inUse
                    note: p.joining === entry.e.ssid ? "connecting…" : p.failed === entry.e.ssid ? "failed"
                        : entry.e.inUse ? "connected" : p.saved.includes(entry.e.ssid) ? "saved" : entry.e.secure ? "" : "open"
                    noteColor: p.failed === entry.e.ssid ? Look.alert : p.joining === entry.e.ssid ? Look.accent : Look.faint
                    onClicked: b => {
                        if (b === Qt.RightButton && p.saved.includes(entry.e.ssid)) {
                            Quickshell.execDetached(["nmcli", "con", "delete", "id", entry.e.ssid])
                            p.saved = p.saved.filter(n => n !== entry.e.ssid)
                        } else if (b === Qt.LeftButton) p.join(entry.e)
                    }
                    G { anchors.centerIn: parent; glyph: [0xF091F, 0xF0922, 0xF0925, 0xF0928][Math.min(3, Math.floor(entry.e.signal / 25))] }
                }
                Row {
                    visible: p.askFor === entry.e.ssid
                    width: parent.width
                    spacing: 6
                    leftPadding: 6
                    Field {
                        id: pw
                        width: parent.width - 70
                        hint: "Password"
                        glyph: 0xF033E
                        secret: true
                        onVisibleChanged: if (visible) { text = ""; grab() }
                        onAccepted: if (text !== "") p.connect(entry.e.ssid, ["nmcli", "--ask", "dev", "wifi", "connect", entry.e.ssid], text)
                    }
                    Btn { text: "Join"; strong: true; onClicked: if (pw.text !== "") p.connect(entry.e.ssid, ["nmcli", "--ask", "dev", "wifi", "connect", entry.e.ssid], pw.text) }
                }
            }
        }
    }

    Btn {
        anchors.right: parent.right
        text: "Network connections…"
        onClicked: { p.ctl.hide(); Quickshell.execDetached(["nm-connection-editor"]) }
    }
}
