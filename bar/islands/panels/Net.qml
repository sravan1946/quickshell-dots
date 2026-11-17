import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.islands

// The network. A card for the link: its name and signal, the addresses, and two minutes of
// traffic as a mirrored flow (download up from the axis, upload down from it) with the peak it
// reached; the bar already shows the rates. Under it the VPNs as chips (tap to bring one up or
// down; only one is up at a time), then the Wi-Fi networks around: each row's background
// fills to its signal. Saved ones connect on tap, open ones join, secured new ones open a
// password box in the row; hover a saved one for the bin to forget it. Scans while open.
// nm-applet still answers VPN secret prompts.
Panel {
    id: p
    implicitWidth: 340
    spacing: 12
    readonly property var info: NetStats.info
    readonly property bool radio: info.wifiOn !== false
    Component.onCompleted: { NetStats.refresh(); scan() }
    Timer { interval: NetStats.interval; running: true; repeat: true; onTriggered: NetStats.refresh() }

    function band(f) { const m = parseInt(f) || 0; return m >= 5925 ? "6 GHz" : m >= 4900 ? "5 GHz" : m ? "2.4 GHz" : "" }

    // four rising bars, `level` 0..4 of them lit
    component Bars: Row {
        id: bars
        property int level: 0
        property color tint: Look.text
        property real unit: 3
        spacing: unit * 0.7
        Repeater {
            model: 4
            Rectangle {
                required property int index
                anchors.bottom: parent.bottom
                width: bars.unit
                height: bars.unit * (1.4 + index * 1.1)
                radius: bars.unit / 2
                color: index < bars.level ? bars.tint : Qt.alpha(Look.text, 0.15)
                Behavior on color { Fade {} }
            }
        }
    }
    function level(signal) { return signal <= 0 ? 0 : Math.min(4, Math.ceil(signal / 25)) }

    // ---- header ----
    Item {
        width: parent.width
        height: 30
        T { anchors.verticalCenter: parent.verticalCenter; x: 2; text: "Network"; font.pixelSize: 15; font.weight: Font.Bold }
        Row {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: 10
            G {
                anchors.verticalCenter: parent.verticalCenter
                glyph: 0xF0493
                font.pixelSize: 15
                color: sh.hovered ? Look.text : Look.faint
                HoverHandler { id: sh; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { p.ctl.hide(); Quickshell.execDetached(["nm-connection-editor"]) } }
            }
            T { anchors.verticalCenter: parent.verticalCenter; visible: p.info.wifiOn !== undefined; text: "Wi-Fi"; color: Look.faint; font.pixelSize: Look.small }
            Switch {
                visible: p.info.wifiOn !== undefined
                on: !!p.info.wifiOn
                onToggled: Quickshell.execDetached(["nmcli", "radio", "wifi", p.info.wifiOn ? "off" : "on"])
            }
        }
    }

    // ---- the link ----
    Rectangle {
        width: parent.width
        height: NetState.online ? 152 : 64
        radius: 14
        color: Look.raise
        clip: true
        Behavior on height { Anim {} }

        // offline
        Row {
            visible: !NetState.online
            anchors.centerIn: parent
            spacing: 10
            G { glyph: p.radio ? 0xF0A8E : 0xF05AA; font.pixelSize: 18; color: Look.faint; anchors.verticalCenter: parent.verticalCenter }
            T { text: p.radio ? "Not connected" : "Wi-Fi is off"; color: Look.dim; anchors.verticalCenter: parent.verticalCenter }
        }

        Item {
            visible: NetState.online
            anchors.fill: parent
            // name, and the signal drawn large
            T {
                x: 14; y: 12
                width: parent.width - 28 - sig.width - 12
                text: p.info.ssid || p.info.conn || NetStats.iface
                font.pixelSize: 17
                font.weight: Font.Bold
                elide: Text.ElideRight
            }
            Column {
                id: sig
                anchors { right: parent.right; rightMargin: 14; top: parent.top; topMargin: 12 }
                spacing: 3
                Bars {
                    anchors.right: parent.right
                    visible: NetState.wifi
                    level: p.level(NetState.signal)
                    tint: Look.accent
                    unit: 4
                }
                G { anchors.right: parent.right; visible: !NetState.wifi; glyph: 0xF0200; font.pixelSize: 18; color: Look.accent; height: 20 }
                T {
                    anchors.right: parent.right
                    text: NetState.wifi ? [p.band(p.info.freq), p.info.dbm ? p.info.dbm + " dBm" : ""].filter(s => s).join("  ·  ") : "Wired"
                    color: Look.faint
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                }
            }
            T {
                x: 14; y: 36
                width: parent.width - 28 - sig.width - 12
                // the addresses only; dBm sits with the band, so nothing runs out of room
                text: (p.info.ip ?? "").split("/")[0] + (NetStats.gateway ? "  →  " + NetStats.gateway : "")
                color: Look.dim
                font.family: Look.icons
                font.pixelSize: 10
                elide: Text.ElideRight
            }

            // recent traffic (48 samples): a strip of thin bars, download rising from the axis and
            // upload hanging from it, older ones fading out to the left. Square-root scale, so a
            // trickle still shows next to a burst. Beside it the speeds now, and the peaks.
            Canvas {
                id: flow
                x: 14; y: 64
                width: parent.width - 28 - legend.width - 14
                height: parent.height - y - 14
                readonly property int samples: 48
                readonly property var pts: NetStats.hist.slice(-samples)
                readonly property real realD: Math.max(0, ...pts.map(s => s[0]))
                readonly property real realU: Math.max(0, ...pts.map(s => s[1]))
                // the scale: what it reached, with a floor so an idle link stays low
                readonly property real peakD: Math.max(60000, realD)
                readonly property real peakU: Math.max(30000, realU)
                readonly property real axis: Math.round(height * 0.6)
                onPtsChanged: requestPaint()
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onPaint: {
                    const ctx = getContext("2d")
                    ctx.reset()
                    const n = samples, gap = 1.5, w = (width - gap * (n - 1)) / n
                    const h = pts, off = n - h.length
                    const bar = (i, v, peak, room, down, c) => {
                        const len = Math.max(1.5, Math.sqrt(Math.min(1, v / peak)) * room)
                        const x = (off + i) * (w + gap)
                        ctx.fillStyle = c
                        ctx.globalAlpha = 0.25 + 0.75 * Math.pow((off + i + 1) / n, 1.6)
                        down ? ctx.roundedRect(x, axis - len, w, len, w / 2, w / 2)
                             : ctx.roundedRect(x, axis + 2, w, len, w / 2, w / 2)
                    }
                    for (let i = 0; i < h.length; i++) {
                        ctx.beginPath(); bar(i, h[i][0], peakD, axis - 1, true, Look.down); ctx.fill()
                        ctx.beginPath(); bar(i, h[i][1], peakU, height - axis - 2, false, Look.up); ctx.fill()
                    }
                }
            }
            Column {
                id: legend
                anchors { right: parent.right; rightMargin: 14; bottom: parent.bottom; bottomMargin: 12 }
                width: 92
                spacing: 8
                Repeater {
                    model: [
                        { arrow: 0xF0045, now: NetStats.down, peak: flow.realD, tint: Look.down },
                        { arrow: 0xF005D, now: NetStats.up, peak: flow.realU, tint: Look.up }
                    ]
                    Row {
                        id: rate
                        required property var modelData
                        spacing: 4
                        G { glyph: rate.modelData.arrow; font.pixelSize: 12; color: rate.modelData.tint; height: 16 }
                        Column {
                            T { text: NetState.rate(rate.modelData.now); font.pixelSize: 12; font.weight: Font.DemiBold; color: rate.modelData.tint }
                            T { text: "peak " + NetState.rate(rate.modelData.peak); font.pixelSize: 9; color: Look.faint }
                        }
                    }
                }
            }
        }
    }

    // ---- VPNs: chips ----
    property var vpns: []          // [{name, state}], state "" | "activating" | "activated" | "deactivating"
    // one VPN at a time (their routes clash): bringing one up takes the others down first.
    // Names go in as arguments, never into the script text.
    function flip(v) {
        if (v.state !== "") {
            Quickshell.execDetached(["nmcli", "con", "down", "id", v.name])
            vpns = vpns.map(o => o.name === v.name ? Object.assign({}, o, { state: "deactivating" }) : o)
            return
        }
        const others = vpns.filter(o => o.name !== v.name && o.state !== "" && o.state !== "deactivating").map(o => o.name)
        Quickshell.execDetached(["sh", "-c", 'up="$1"; shift; for n in "$@"; do nmcli con down id "$n"; done; nmcli con up id "$up"',
                                 "sh", v.name, ...others])
        vpns = vpns.map(o => o.name === v.name ? Object.assign({}, o, { state: "activating" })
                           : others.includes(o.name) ? Object.assign({}, o, { state: "deactivating" }) : o)
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
    // a busy chip's dot blinks on a stepped timer, not a running animation
    property bool blink: false
    Timer { interval: 600; repeat: true; running: p.vpns.some(v => v.state.endsWith("ing")); onTriggered: p.blink = !p.blink }

    Flow {
        visible: p.vpns.length > 0
        width: parent.width
        spacing: 6
        G { glyph: 0xF099D; font.pixelSize: 14; color: Look.faint; height: 26 }
        Repeater {
            model: ScriptModel { values: p.vpns.map(v => v.name) }
            Rectangle {
                id: chip
                required property string modelData
                readonly property var v: p.vpns.find(o => o.name === modelData) ?? ({ name: modelData, state: "" })
                readonly property bool up: v.state === "activated"
                readonly property bool busy: v.state === "activating" || v.state === "deactivating"
                width: cr.implicitWidth + 22
                height: 26
                radius: 13
                color: up ? (ch.hovered ? Qt.lighter(Look.accent, 1.08) : Look.accent) : ch.hovered ? Look.hover : "transparent"
                border.width: up ? 0 : 1
                border.color: busy ? Look.accent : Qt.alpha(Look.text, 0.14)
                Behavior on color { Fade {} }
                Row {
                    id: cr
                    anchors.centerIn: parent
                    spacing: 6
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 6; height: 6; radius: 3
                        color: chip.up ? Look.accentInk : chip.busy ? Look.accent : Look.faint
                        opacity: chip.busy && p.blink ? 0.25 : 1
                    }
                    T {
                        text: chip.v.name
                        color: chip.up ? Look.accentInk : Look.text
                        font.pixelSize: Look.small
                        font.weight: Font.DemiBold
                    }
                }
                HoverHandler { id: ch; cursorShape: chip.busy ? Qt.ArrowCursor : Qt.PointingHandCursor }
                TapHandler { onTapped: if (!chip.busy) p.flip(chip.v) }
            }
        }
    }

    // ---- networks around ----
    property var found: []        // [{ssid, signal, secure, inUse}], strongest first
    property var saved: []
    property string askFor: ""
    property string joining: ""
    property string failed: ""
    readonly property bool scanning: scanner.running || rescan.running || relist.running
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
    function forget(ssid) {
        Quickshell.execDetached(["nmcli", "con", "delete", "id", ssid])
        saved = saved.filter(n => n !== ssid)
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
                p.saved = saved
                // the one in use is the card above
                p.found = Object.values(best).filter(e => !e.inUse).sort((a, b) => b.signal - a.signal).slice(0, 7)
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

    Item {
        visible: p.radio && NetStats.info.wifiOn !== undefined
        width: parent.width
        height: 20
        T { x: 2; anchors.verticalCenter: parent.verticalCenter; text: "Networks"; color: Look.faint; font.pixelSize: 10; font.weight: Font.Bold; font.letterSpacing: 0.8; font.capitalization: Font.AllUppercase }
        G {
            anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
            glyph: 0xF0450
            font.pixelSize: 14
            color: p.scanning ? Qt.alpha(Look.text, 0.18) : rh.hovered ? Look.text : Look.faint
            Behavior on color { Fade {} }
            HoverHandler { id: rh; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: p.scan() }
        }
    }
    T {
        visible: p.radio && NetStats.info.wifiOn !== undefined && p.found.length === 0
        x: 4
        text: p.scanning ? "Looking for networks…" : "No other networks in range"
        color: Look.faint
        font.pixelSize: Look.small
    }
    Column {
        visible: p.radio
        width: parent.width
        spacing: 3
        Repeater {
            model: ScriptModel { values: p.found.map(e => e.ssid) }
            Column {
                id: entry
                required property string modelData
                readonly property var e: p.found.find(f => f.ssid === modelData) ?? ({ ssid: modelData, signal: 0 })
                readonly property bool known: p.saved.includes(e.ssid)
                readonly property bool asking: p.askFor === e.ssid
                readonly property bool busy: p.joining === e.ssid
                readonly property bool bad: p.failed === e.ssid
                width: parent.width
                spacing: 6
                Rectangle {
                    width: parent.width
                    height: 36
                    radius: 10
                    // a faint track, so the signal fill reads as a meter
                    color: wh.hovered || entry.asking ? Look.hover : Qt.alpha(Look.text, 0.025)
                    Behavior on color { Fade {} }
                    clip: true
                    // the signal, as how far the row fills
                    Rectangle {
                        width: parent.width * Math.max(0.04, entry.e.signal / 100)
                        height: parent.height
                        radius: 10
                        color: Qt.alpha(Look.accent, entry.busy ? 0.2 : 0.08)
                        Behavior on width { Anim { type: "effects" } }
                        Behavior on color { Fade {} }
                    }
                    Bars { x: 12; anchors.verticalCenter: parent.verticalCenter; level: p.level(entry.e.signal); tint: Look.text }
                    T {
                        x: 40
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - x - 96
                        text: entry.e.ssid
                        font.weight: entry.known ? Font.DemiBold : Font.Normal
                        elide: Text.ElideRight
                    }
                    // a fixed-width end: the note, or the bin for a saved one under the pointer
                    Item {
                        anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                        width: 84
                        height: parent.height
                        Row {
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            spacing: 6
                            opacity: wh.hovered && entry.known && !entry.busy ? 0 : 1
                            Behavior on opacity { Anim { type: "effects" } }
                            T {
                                anchors.verticalCenter: parent.verticalCenter
                                text: entry.busy ? "connecting…" : entry.bad ? "failed" : entry.known ? "saved" : entry.e.secure ? "" : "open"
                                color: entry.bad ? Look.alert : entry.busy ? Look.accent : Look.faint
                                font.pixelSize: Look.small
                            }
                            G { anchors.verticalCenter: parent.verticalCenter; visible: entry.e.secure; glyph: 0xF0341; font.pixelSize: 12; color: Look.faint }
                        }
                        G {
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            glyph: 0xF0A7A
                            font.pixelSize: 14
                            color: bin.hovered ? Look.alert : Look.dim
                            opacity: wh.hovered && entry.known && !entry.busy ? 1 : 0
                            visible: opacity > 0
                            Behavior on opacity { Anim { type: "effects" } }
                            HoverHandler { id: bin; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: p.forget(entry.e.ssid) }
                        }
                    }
                    HoverHandler { id: wh; cursorShape: Qt.PointingHandCursor }
                    TapHandler { acceptedButtons: Qt.LeftButton; onTapped: if (!bin.hovered) p.join(entry.e) }
                    TapHandler { acceptedButtons: Qt.RightButton; onTapped: if (entry.known) p.forget(entry.e.ssid) }
                }
                // a secured new one: the password, in place
                Row {
                    visible: entry.asking
                    width: parent.width
                    spacing: 6
                    Field {
                        id: pw
                        property bool show: false
                        width: parent.width - join.width - close.width - 12
                        hint: "Password for " + entry.e.ssid
                        glyph: 0xF033E
                        secret: !show
                        onVisibleChanged: if (visible) { text = ""; grab() }
                        onAccepted: if (text !== "") p.connect(entry.e.ssid, ["nmcli", "--ask", "dev", "wifi", "connect", entry.e.ssid], text)
                        G {
                            anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                            glyph: pw.show ? 0xF0209 : 0xF0208
                            font.pixelSize: 13
                            color: eye.hovered ? Look.text : Look.faint
                            HoverHandler { id: eye; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: pw.show = !pw.show }
                        }
                    }
                    Btn {
                        id: join
                        anchors.verticalCenter: parent.verticalCenter
                        text: entry.busy ? "…" : "Join"
                        strong: true
                        onClicked: if (pw.text !== "" && !entry.busy) p.connect(entry.e.ssid, ["nmcli", "--ask", "dev", "wifi", "connect", entry.e.ssid], pw.text)
                    }
                    Rectangle {
                        id: close
                        anchors.verticalCenter: parent.verticalCenter
                        width: 24; height: 24; radius: 12
                        color: xh.hovered ? Look.hover : "transparent"
                        G { anchors.centerIn: parent; glyph: 0xF0156; font.pixelSize: 13; color: xh.hovered ? Look.text : Look.faint }
                        HoverHandler { id: xh; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: { p.askFor = ""; p.failed = "" } }
                    }
                }
            }
        }
    }
}
