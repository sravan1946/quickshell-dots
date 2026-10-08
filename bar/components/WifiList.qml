import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs

// Nearby Wi-Fi networks to join: saved ones come up directly, open ones join on click,
// secured new ones ask for the password inline; right-click a saved one to forget it.
// Scans while `active`.
// Used by the Network panel (modules/Network.qml) and quick settings.
Column {
    id: list

    property bool active: false
    property int limit: 7
    property bool hideInUse: false   // when the caller shows the current network itself
    property var found: []       // [{ssid, signal, secure, inUse}], strongest first
    readonly property var nearby: found.filter(e => !(hideInUse && e.inUse)).slice(0, limit)
    readonly property int total: found.filter(e => !(hideInUse && e.inUse)).length
    readonly property var bySsid: found.reduce((m, e) => (m[e.ssid] = e, m), ({}))
    property var saved: []       // saved Wi-Fi connection names
    property string askFor: ""   // ssid whose password field is open
    property string joining: ""
    property string failed: ""

    spacing: 3
    onActiveChanged: if (active) scan(); else { askFor = ""; failed = "" }

    // the cached list right away, then once the background rescan has had time to land
    // (`--rescan auto` blocked for seconds whenever the last scan was over 30s old)
    function scan() { list.fetch(); if (!rescan.running) rescan.running = true }
    function fetch() { if (!scanner.running) scanner.running = true }
    function join(e) {
        if (e.inUse || joiner.running) return
        failed = ""
        if (saved.includes(e.ssid)) connect(e.ssid, ["nmcli", "con", "up", "id", e.ssid], "")
        else if (!e.secure) connect(e.ssid, ["nmcli", "dev", "wifi", "connect", e.ssid], "")
        else askFor = askFor === e.ssid ? "" : e.ssid
    }
    // argv, no shell; the password goes to nmcli --ask on stdin, never on a command line
    function connect(ssid, cmd, pw) {
        joining = ssid
        joiner.pw = pw
        joiner.command = cmd
        joiner.running = true
    }

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
                list.saved = saved
                list.found = Object.values(best).sort((a, b) => b.inUse - a.inUse || b.signal - a.signal)
            }
        }
    }
    Process {
        id: joiner
        property string pw: ""
        stdinEnabled: true
        onStarted: if (pw !== "") { write(pw + "\n"); pw = "" }
        onExited: code => {
            if (code !== 0) list.failed = list.joining
            else list.askFor = ""
            list.joining = ""
            NetStats.refresh()
            list.scan()
        }
    }
    Process { id: rescan; command: ["nmcli", "dev", "wifi", "rescan"]; onExited: relist.restart() }
    Timer { id: relist; interval: 3500; onTriggered: list.fetch() }
    Timer { interval: 10000; running: list.active; repeat: true; onTriggered: list.scan() }

    ListHeader {
        width: parent.width
        text: "Networks"
        refreshable: true
        busy: relist.running
        onRefresh: list.scan()
    }

    // keyed by ssid: a rescan updates rows in place instead of rebuilding them all
    Repeater {
        model: ScriptModel { values: list.nearby.map(e => e.ssid) }
        Column {
            id: entry
            required property string modelData
            readonly property var e: list.bySsid[modelData] ?? ({ ssid: modelData, signal: 0, inUse: false, secure: false })
            width: parent.width

            ListRow {
                width: parent.width
                selected: entry.e.inUse
                clickable: !entry.e.inUse
                onClicked: list.join(entry.e)
                onRightClicked: if (list.saved.includes(entry.e.ssid)) { Quickshell.execDetached(["nmcli", "con", "delete", "id", entry.e.ssid]); list.saved = list.saved.filter(n => n !== entry.e.ssid) }

                Bars { strength: entry.e.signal }
                Text {
                    Layout.fillWidth: true
                    text: entry.e.ssid
                    color: Theme.mainFg
                    elide: Text.ElideRight
                    font { family: Theme.font; pixelSize: 12; bold: entry.e.inUse }
                }
                Text {
                    visible: text !== ""
                    readonly property bool note: list.joining === entry.e.ssid || list.failed === entry.e.ssid
                    text: list.joining === entry.e.ssid ? "connecting…" : list.failed === entry.e.ssid ? "failed"
                        : !entry.e.inUse && list.saved.includes(entry.e.ssid) ? "saved" : ""
                    color: list.failed === entry.e.ssid ? "#f7768e" : note ? Theme.actFg : Theme.mainFg
                    opacity: note ? 1 : 0.45
                    font { family: Theme.font; pixelSize: 10 }
                }
                Text {
                    text: Theme.g(entry.e.inUse ? 0xF012C : entry.e.secure ? 0xF033E : 0xF033F)
                    color: entry.e.inUse ? Theme.actFg : Theme.mainFg
                    opacity: entry.e.inUse ? 1 : 0.5
                    font { family: Theme.font; pixelSize: 12 }
                }
            }

            // password for a new secured network
            RowLayout {
                visible: list.askFor === entry.e.ssid
                width: parent.width
                spacing: 6
                Field {
                    id: pw
                    Layout.fillWidth: true
                    Layout.leftMargin: 9
                    hint: "Password"
                    secret: true
                    onVisibleChanged: if (visible) { text = ""; grab() }
                    onAccepted: if (text !== "") list.connect(entry.e.ssid, ["nmcli", "--ask", "dev", "wifi", "connect", entry.e.ssid], text)
                }
                PillButton {
                    text: "Join"
                    onClicked: if (pw.text !== "") list.connect(entry.e.ssid, ["nmcli", "--ask", "dev", "wifi", "connect", entry.e.ssid], pw.text)
                }
            }
        }
    }
}
