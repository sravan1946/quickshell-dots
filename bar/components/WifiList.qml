import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs

// Nearby Wi-Fi networks to join: saved ones come up directly, open ones join on click,
// secured new ones ask for the password inline. Scans while `active`.
// Used by the Network panel (modules/Network.qml) and quick settings.
Column {
    id: list

    property bool active: false
    property var nearby: []      // [{ssid, signal, secure, inUse}], strongest first
    readonly property var bySsid: nearby.reduce((m, e) => (m[e.ssid] = e, m), ({}))
    property var saved: []       // saved Wi-Fi connection names
    property string askFor: ""   // ssid whose password field is open
    property string joining: ""
    property string failed: ""

    spacing: 3
    onActiveChanged: if (active) scan(); else { askFor = ""; failed = "" }

    function scan() { if (!scanner.running) scanner.running = true }
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
            nmcli -t -f IN-USE,SSID,SIGNAL,SECURITY dev wifi list --rescan auto`]
        stdout: StdioCollector {
            onStreamFinished: {
                const saved = [], best = {}
                for (const l of text.split("\n")) {
                    if (l.startsWith("SAVED:")) { saved.push(l.slice(6).replace(/\\:/g, ":")); continue }
                    // nmcli -t escapes ":" inside values as "\\:"
                    const f = l.replace(/\\:/g, "\u0001").split(":").map(s => s.replace(/\u0001/g, ":"))
                    if (f.length < 4 || !f[1]) continue
                    const e = { ssid: f[1], inUse: f[0] === "*", signal: +f[2] || 0, secure: f[3] !== "" && f[3] !== "--" }
                    const o = best[e.ssid]
                    if (!o || e.inUse || (!o.inUse && e.signal > o.signal)) best[e.ssid] = e
                }
                list.saved = saved
                list.nearby = Object.values(best).sort((a, b) => b.inUse - a.inUse || b.signal - a.signal).slice(0, 7)
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
    Timer { interval: 10000; running: list.active; repeat: true; onTriggered: list.scan() }

    RowLayout {
        width: parent.width
        Text {
            Layout.fillWidth: true
            text: "Networks"
            color: Theme.mainFg
            opacity: 0.55
            font { family: Theme.font; pixelSize: 11; bold: true }
        }
        Text {
            text: Theme.g(0xF0450)
            color: Theme.mainFg
            opacity: scanner.running ? 1 : 0.55
            font { family: Theme.font; pixelSize: 12 }
            RotationAnimator on rotation { running: scanner.running; from: 0; to: 360; duration: 900; loops: Animation.Infinite }
            TapHandler { onTapped: list.scan() }
        }
    }

    // keyed by ssid: a rescan updates rows in place instead of rebuilding them all
    Repeater {
        model: ScriptModel { values: list.nearby.map(e => e.ssid) }
        Column {
            id: entry
            required property string modelData
            readonly property var e: list.bySsid[modelData] ?? ({ ssid: modelData, signal: 0, inUse: false, secure: false })
            width: parent.width

            Rectangle {
                width: parent.width
                height: 30
                radius: 9
                color: entry.e.inUse ? Qt.alpha(Theme.actBg, 0.25) : rowHover.hovered ? Qt.alpha(Theme.mainFg, 0.12) : "transparent"
                Behavior on color { ColorAnimation { duration: 120 } }
                HoverHandler { id: rowHover; cursorShape: entry.e.inUse ? Qt.ArrowCursor : Qt.PointingHandCursor }
                TapHandler { onTapped: list.join(entry.e) }

                RowLayout {
                    anchors { fill: parent; leftMargin: 9; rightMargin: 9 }
                    spacing: 9
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
                        text: list.joining === entry.e.ssid ? "connecting…" : list.failed === entry.e.ssid ? "failed" : ""
                        color: list.failed === entry.e.ssid ? "#f7768e" : Theme.actFg
                        font { family: Theme.font; pixelSize: 10 }
                    }
                    Text {
                        text: Theme.g(entry.e.inUse ? 0xF012C : entry.e.secure ? 0xF033E : 0xF033F)
                        color: entry.e.inUse ? Theme.actFg : Theme.mainFg
                        opacity: entry.e.inUse ? 1 : 0.5
                        font { family: Theme.font; pixelSize: 12 }
                    }
                }
            }

            // password for a new secured network
            RowLayout {
                visible: list.askFor === entry.e.ssid
                width: parent.width
                spacing: 6
                Rectangle {
                    Layout.fillWidth: true
                    Layout.leftMargin: 9
                    implicitHeight: 26
                    radius: 8
                    color: Qt.alpha(Theme.mainFg, 0.08)
                    border.color: pw.activeFocus ? Theme.mainFg : Qt.alpha(Theme.mainFg, 0.25)
                    TextInput {
                        id: pw
                        anchors { fill: parent; leftMargin: 9; rightMargin: 9 }
                        verticalAlignment: TextInput.AlignVCenter
                        echoMode: TextInput.Password
                        color: Theme.mainFg
                        font { family: Theme.font; pixelSize: 12 }
                        clip: true
                        onVisibleChanged: if (visible) { text = ""; forceActiveFocus() }
                        onAccepted: if (text !== "") list.connect(entry.e.ssid, ["nmcli", "--ask", "dev", "wifi", "connect", entry.e.ssid], text)
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: pw.text === ""
                            text: "Password"
                            color: Theme.mainFg
                            opacity: 0.4
                            font: pw.font
                        }
                    }
                }
                PillButton {
                    text: "Join"
                    onClicked: if (pw.text !== "") list.connect(entry.e.ssid, ["nmcli", "--ask", "dev", "wifi", "connect", entry.e.ssid], pw.text)
                }
            }
        }
    }
}
