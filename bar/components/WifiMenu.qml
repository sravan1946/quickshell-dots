import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs

// The panel nm-applet's tray icon opens in place of its own menu (modules/Tray.qml), laid
// out like Control Center: round Wi-Fi / VPN / hotspot / networking toggles, then a
// Wi-Fi | VPN switch over one short list. Wi-Fi shows the current network (details and
// actions folded under it) and the four strongest others, "more…" for the rest; VPN shows
// the VPN connections. While the hotspot is on, its name, password and a QR to join take
// the current network's place; right-click the hotspot toggle for its settings. The hotspot
// only ever starts alongside the Wi-Fi link (scripts/hotspot.sh says when it can't).
// nm-applet keeps running underneath as the secret agent that asks for VPN/Wi-Fi passwords.
Dropdown {
    id: menu

    readonly property var info: NetStats.info
    readonly property bool radio: !!info.wifiOn
    readonly property bool linked: !!info.ssid
    readonly property int signal: parseInt(info.signal) || 0
    readonly property string band: { const f = parseInt(info.freq); return !f ? "" : f >= 5900 ? "6 GHz" : f >= 4900 ? "5 GHz" : "2.4 GHz" }

    // from `state`, refreshed every 2s while open
    property string dev: ""          // the Wi-Fi device
    property bool networking: true
    property var vpns: []            // [{name, state, ts}], state "" | "activating" | "activated" | "deactivating"
    property var link: ({})          // {mac, conn, ip, gw, dns, rate, sec} of the Wi-Fi device
    // the hotspot runs alongside the Wi-Fi link on ap0 (scripts/hotspot.sh), never in its place
    readonly property string spotSh: Qt.resolvedUrl("../scripts/hotspot.sh").toString().replace("file://", "")
    property bool hotspot: false     // the "Hotspot" connection is active
    property string spotWhy: ""      // why it can't start now: "" | "no-dnsmasq" | "no-link" | "radar" | "no-sudo"
    property bool spotNote: false    // that reason showing, after a click it refused
    readonly property var vpnUp: vpns.filter(v => v.state === "activated" || v.state === "activating")

    property string section: "wifi" // "wifi" | "vpn": the tab showing
    property bool details: false
    property bool showAll: false
    property bool hiddenOpen: false
    property string password: ""     // revealed on demand, dropped on close
    property var spot: ({})          // {ssid, psk} of the Hotspot profile, read while it's on
    property bool spotReveal: false  // password and QR shown
    property string spotQr: ""       // QR image of the join string (in the runtime dir, user-only)
    property string armed: ""        // "networking" | "forget": the next click goes through

    closeOnOutsideClick: true
    padX: 12
    padY: 12
    onVisibleChanged: {
        if (visible) { refresh(); spotCan.running = true }
        else { section = "wifi"; spotReveal = false; spotNote = false; details = false; showAll = false; hiddenOpen = false; password = ""; armed = "" }
    }

    onHotspotChanged: { spot = {}; spotQr = ""; spotReveal = false; if (hotspot) spotRead.running = true }
    function refresh() { NetStats.refresh(); if (!poll.running) poll.running = true }
    function run(argv) { Quickshell.execDetached(argv); armed = ""; soon.restart() }
    // risky clicks (dropping the link) take a second click within 3s
    function arm(what) { if (armed === what) return true; armed = what; disarm.restart(); return false }
    function toggleVpn() {
        if (vpnUp.length) for (const v of vpnUp) run(["nmcli", "con", "down", "id", v.name])
        else if (vpns.length) run(["nmcli", "con", "up", "id", vpns.reduce((a, b) => b.ts > a.ts ? b : a).name])
    }
    function flip(v) {
        run(["nmcli", "con", v.state === "" ? "up" : "down", "id", v.name])
        vpns = vpns.map(o => o.name === v.name ? Object.assign({}, o, { state: v.state === "" ? "activating" : "deactivating" }) : o)
    }

    Timer { interval: 2000; running: menu.visible; repeat: true; onTriggered: menu.refresh() }
    Timer { id: soon; interval: 900; onTriggered: { menu.refresh(); networks.scan(); spotCan.running = true } }
    Timer { id: spotNoteHide; interval: 5000; onTriggered: menu.spotNote = false }
    Timer { id: disarm; interval: 3000; onTriggered: menu.armed = "" }

    Process {
        id: poll
        command: ["sh", "-c", `
            d=$(nmcli -t -f DEVICE,TYPE dev | awk -F: '$2=="wifi" && $1!="ap0" {print $1; exit}')
            echo "DEV:$d"
            echo "NET:$(nmcli networking)"
            echo "HOT:$(nmcli -t -f NAME con show --active | grep -cx Hotspot)"
            nmcli -t -f NAME,TYPE,STATE,TIMESTAMP con show | grep -E ':(vpn|wireguard):' | sed 's/^/VPN:/'
            [ -n "$d" ] || exit 0
            nmcli -t -f GENERAL.HWADDR,GENERAL.CONNECTION,IP4.ADDRESS,IP4.GATEWAY,IP4.DNS dev show "$d"
            iw dev "$d" link | awk '/tx bitrate/ {print "RATE:" $3 " " $4}'
            nmcli -t -f IN-USE,SECURITY dev wifi list --rescan no | sed -n 's/^\\*:/SEC:/p'`]
        stdout: StdioCollector {
            onStreamFinished: {
                const vpns = [], l = { dns: [] }
                for (const line of text.split("\n")) {
                    // nmcli -t escapes ":" inside values as "\\:"
                    const f = line.replace(/\\:/g, "\u0001").split(":").map(s => s.replace(/\u0001/g, ":"))
                    const k = f[0], v = f.slice(1).join(":")
                    if (k === "DEV") menu.dev = v
                    else if (k === "NET") menu.networking = v === "enabled"
                    else if (k === "HOT") menu.hotspot = v !== "0"
                    else if (k === "VPN") vpns.push({ name: f[1], state: f[3] ?? "", ts: +f[4] || 0 })
                    else if (k === "GENERAL.HWADDR") l.mac = v
                    else if (k === "GENERAL.CONNECTION") l.conn = v
                    else if (k.startsWith("IP4.ADDRESS")) l.ip = l.ip ?? v
                    else if (k === "IP4.GATEWAY") l.gw = v
                    else if (k.startsWith("IP4.DNS")) l.dns.push(v)
                    else if (k === "RATE") l.rate = v
                    else if (k === "SEC") l.sec = v
                }
                menu.vpns = vpns.sort((a, b) => a.name.localeCompare(b.name))
                menu.link = l
            }
        }
    }
    Process {
        id: spotCan
        command: ["sh", menu.spotSh, "can"]
        stdout: StdioCollector { onStreamFinished: menu.spotWhy = text.trim() }
    }
    Process {
        id: spotRead
        command: ["nmcli", "-s", "-g", "802-11-wireless.ssid,802-11-wireless-security.psk", "con", "show", "Hotspot"]
        stdout: StdioCollector {
            onStreamFinished: {
                const [ssid, psk] = text.split("\n")
                menu.spot = { ssid: ssid ?? "", psk: psk ?? "" }
                // the standard Wi-Fi join string phones read; \ ; , : " are escaped
                const esc = v => v.replace(/([\\;,:"])/g, "\\$1")
                spotQrGen.target = `${Quickshell.env("XDG_RUNTIME_DIR")}/quickshell-hotspot-${Date.now()}.png`
                spotQrGen.command = ["sh", "-c", 'rm -f "$(dirname "$1")"/quickshell-hotspot-*.png; qrencode -s 6 -m 2 -o "$1" "$2"', "sh",
                                     spotQrGen.target, `WIFI:T:WPA;S:${esc(menu.spot.ssid)};P:${esc(menu.spot.psk)};;`]
                spotQrGen.running = true
            }
        }
    }
    Process {
        id: spotQrGen
        property string target
        onExited: code => menu.spotQr = code === 0 ? "file://" + target : ""
    }
    Process {
        id: reveal
        command: ["nmcli", "dev", "wifi", "show-password"]
        stdout: StdioCollector { onStreamFinished: menu.password = (text.match(/^Password: (.*)$/m) ?? [])[1] ?? "" }
    }

    Column {
        width: 320
        spacing: 12

        // ---- round toggles ----
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 22
            Round {
                icon: menu.radio ? 0xF05A9 : 0xF05AA
                label: "Wi-Fi"
                on: menu.radio
                onClicked: menu.run(["nmcli", "radio", "wifi", menu.radio ? "off" : "on"])
            }
            Round {
                icon: menu.vpnUp.length ? 0xF0565 : 0xF099D
                label: "VPN"
                on: menu.vpnUp.length > 0
                enabled: menu.vpns.length > 0
                onClicked: menu.toggleVpn()
            }
            Round {
                icon: 0xF0003   // access-point
                label: "Hotspot"
                on: menu.hotspot
                opacity: menu.hotspot || menu.spotWhy === "" ? 1 : 0.4
                // its settings: the Hotspot profile in the connection editor, once there is one
                onRightClicked: {
                    menu.close()
                    Quickshell.execDetached(["sh", "-c", 'u=$(nmcli -g connection.uuid con show Hotspot 2>/dev/null); exec nm-connection-editor ${u:+--edit=$u}'])
                }
                onClicked: {
                    if (menu.hotspot) menu.run(["sh", menu.spotSh, "off"])
                    else if (menu.spotWhy === "") menu.run(["sh", menu.spotSh, "on"])
                    else { menu.spotNote = true; spotNoteHide.restart() }
                }
            }
            Round {
                icon: menu.networking ? 0xF0318 : 0xF0319   // lan-connect / lan-disconnect
                label: menu.armed === "networking" ? "Again?" : "Net"
                on: menu.networking
                onClicked: {
                    if (!menu.networking) menu.run(["nmcli", "networking", "on"])
                    else if (menu.arm("networking")) menu.run(["nmcli", "networking", "off"])
                }
            }
        }

        Text {   // why the hotspot didn't start
            visible: menu.spotNote
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: menu.spotWhy === "radar" ? "Hotspot can't start: Wi-Fi is on a radar channel, and it has to share that channel. Wi-Fi left as is."
                : menu.spotWhy === "no-sudo" ? "Hotspot needs a one-time sudo rule (see scripts/hotspot.sh)."
                : menu.spotWhy === "no-dnsmasq" ? "Hotspot needs dnsmasq to give joining devices addresses: install it."
                : "Hotspot runs alongside Wi-Fi: connect to a network first."
            color: "#e0af68"
            font { family: Theme.font; pixelSize: 10 }
        }

        // ---- Wi-Fi | VPN ----
        Rectangle {
            id: tabs
            width: parent.width
            height: 32
            radius: 16
            color: Qt.alpha(Theme.mainFg, 0.07)
            Rectangle {   // the selected half
                x: menu.section === "vpn" ? parent.width / 2 + 2 : 2
                y: 2
                width: parent.width / 2 - 4
                height: parent.height - 4
                radius: height / 2
                color: Qt.alpha(Theme.actBg, 0.3)
                border.color: Qt.alpha(Theme.actBg, 0.6)
                Behavior on x { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
            }
            Row {
                anchors.fill: parent
                Tab { key: "wifi"; text: "Wi-Fi"; lit: menu.linked }
                Tab { key: "vpn"; text: "VPN"; lit: menu.vpnUp.length > 0 }
            }
        }

        // the list slides in from the side of the tab picked
        Item {
            width: parent.width
            height: lists.implicitHeight
            clip: true
            Column {
                id: lists
                width: parent.width
                spacing: 10
                property real shift: 0
                transform: Translate { x: lists.shift }
                ParallelAnimation {
                    id: turn
                    property real from: 0
                    NumberAnimation { target: lists; property: "shift"; from: turn.from; to: 0; duration: 260; easing.type: Easing.OutCubic }
                    NumberAnimation { target: lists; property: "opacity"; from: 0; to: 1; duration: 200; easing.type: Easing.OutCubic }
                }
                Connections {
                    target: menu
                    function onSectionChanged() { turn.from = menu.section === "vpn" ? 40 : -40; turn.restart() }
                }

                // ---- Wi-Fi ----
                Text {
                    visible: menu.section === "wifi" && !menu.radio
                    width: parent.width
                    topPadding: 12
                    bottomPadding: 12
                    horizontalAlignment: Text.AlignHCenter
                    text: "Wi-Fi is off"
                    color: Theme.mainFg
                    opacity: 0.5
                    font { family: Theme.font; pixelSize: 12 }
                }
                Column {
                    visible: menu.section === "wifi" && menu.radio
                    width: parent.width
                    spacing: 10
                    // ---- the hotspot while it's on: name, password, QR to join ----
                    Rectangle {
                        visible: menu.hotspot
                        width: parent.width
                        height: spotCol.implicitHeight
                        radius: 12
                        color: Qt.alpha(Theme.actBg, 0.12)
                        border.color: Qt.alpha(Theme.actBg, 0.45)
                        Column {
                            id: spotCol
                            x: 10
                            width: parent.width - 20
                            topPadding: 10
                            bottomPadding: 10
                            spacing: 8
                            RowLayout {
                                width: parent.width
                                spacing: 10
                                Text {
                                    text: Theme.g(0xF0003)
                                    color: Theme.actFg
                                    font { family: Theme.font; pixelSize: 18 }
                                }
                                Column {
                                    Layout.fillWidth: true
                                    Text {
                                        text: "Hotspot on"
                                        color: Theme.mainFg
                                        font { family: Theme.font; pixelSize: 13; bold: true }
                                    }
                                    Text {
                                        text: "Others can join this network"
                                        color: Theme.mainFg
                                        opacity: 0.6
                                        font { family: Theme.font; pixelSize: 10 }
                                    }
                                }
                                PillButton {
                                    text: Theme.g(menu.spotReveal ? 0xF0209 : 0xF0208) + (menu.spotReveal ? " Hide" : " Show")
                                    checked: menu.spotReveal
                                    onClicked: menu.spotReveal = !menu.spotReveal
                                }
                            }
                            GridLayout {
                                width: parent.width
                                columns: 2
                                columnSpacing: 6
                                Cell { label: "Name"; value: menu.spot.ssid ?? "" }
                                Cell {
                                    label: "Password"
                                    value: menu.spotReveal ? menu.spot.psk ?? "" : menu.spot.psk ? "••••••••" : ""
                                    copy: menu.spot.psk ?? ""
                                }
                            }
                            Rectangle {   // scan to join; white quiet zone so phones read it on the dark card
                                visible: menu.spotReveal && menu.spotQr !== ""
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 140
                                height: 140
                                radius: 10
                                color: "white"
                                Image {
                                    anchors.fill: parent
                                    anchors.margins: 6
                                    source: menu.spotQr
                                    smooth: false
                                    fillMode: Image.PreserveAspectFit
                                }
                            }
                        }
                    }

                    // ---- the current network; details and actions fold out ----
                    Rectangle {
                        visible: menu.linked && !menu.hotspot
                        width: parent.width
                        height: cur.implicitHeight
                        radius: 12
                        color: Qt.alpha(Theme.mainFg, 0.06)
                        border.color: Qt.alpha(Theme.actBg, menu.details ? 0.4 : 0)
                        Behavior on border.color { ColorAnimation { duration: 150 } }

                        Column {
                            id: cur
                            width: parent.width
                            bottomPadding: menu.details ? 10 : 0

                            Item {
                                width: parent.width
                                height: 48
                                HoverHandler { id: curHover; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: menu.details = !menu.details }
                                RowLayout {
                                    anchors { fill: parent; leftMargin: 12; rightMargin: 10 }
                                    spacing: 10
                                    Bars { strength: menu.signal }
                                    Column {
                                        Layout.fillWidth: true
                                        Text {
                                            width: parent.width
                                            text: menu.info.ssid ?? ""
                                            color: Theme.mainFg
                                            elide: Text.ElideRight
                                            font { family: Theme.font; pixelSize: 13; bold: true }
                                        }
                                        Text {
                                            width: parent.width
                                            text: [menu.band, menu.signal + "%", menu.link.rate ?? ""].filter(s => s).join(" · ")
                                            color: Theme.mainFg
                                            opacity: 0.6
                                            elide: Text.ElideRight
                                            font { family: Theme.font; pixelSize: 10 }
                                        }
                                    }
                                    Text {
                                        text: Theme.g(0xF0140)   // chevron-down
                                        color: Theme.mainFg
                                        opacity: menu.details || curHover.hovered ? 1 : 0.6
                                        rotation: menu.details ? 180 : 0
                                        Behavior on rotation { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                                        font { family: Theme.font; pixelSize: 16 }
                                    }
                                }
                            }

                            GridLayout {
                                visible: menu.details
                                x: 8
                                width: parent.width - 16
                                columns: 2
                                columnSpacing: 6
                                rowSpacing: 6
                                Cell { label: "IP"; value: (menu.link.ip ?? "").split("/")[0] }
                                Cell { label: "Gateway"; value: menu.link.gw ?? "" }
                                Cell { label: "DNS"; value: (menu.link.dns ?? []).join(", ") }
                                Cell { label: "Security"; value: menu.link.sec ?? "" }
                                Cell { label: "MAC"; value: menu.link.mac ?? "" }
                                Cell { label: "Device"; value: menu.dev }
                                Cell { visible: menu.password !== ""; label: "Password"; value: menu.password; Layout.columnSpan: 2 }
                            }
                            Row {
                                visible: menu.details
                                x: 8
                                topPadding: 8
                                spacing: 6
                                PillButton {
                                    text: Theme.g(0xF05AA) + " Disconnect"
                                    onClicked: menu.run(["nmcli", "dev", "disconnect", menu.dev])
                                }
                                PillButton {
                                    text: Theme.g(0xF0A7A) + (menu.armed === "forget" ? " Sure?" : " Forget")
                                    checked: menu.armed === "forget"
                                    onClicked: if (menu.arm("forget")) menu.run(["nmcli", "con", "delete", "id", menu.link.conn])
                                }
                                PillButton {
                                    text: Theme.g(menu.password ? 0xF0209 : 0xF0208) + " Password"
                                    onClicked: { if (menu.password) menu.password = ""; else if (!reveal.running) reveal.running = true }
                                }
                            }
                        }
                    }

                    WifiList {
                        id: networks
                        width: parent.width
                        active: menu.visible
                        hideInUse: true
                        limit: menu.showAll ? 99 : 4
                    }
                    // ---- hidden network ----
                    RowLayout {
                        visible: menu.hiddenOpen
                        width: parent.width
                        spacing: 6
                        Field { id: hidSsid; Layout.fillWidth: true; hint: "Network name" }
                        Field { id: hidPw; Layout.fillWidth: true; hint: "Password"; secret: true; onAccepted: joinHidden() }
                        PillButton { text: "Join"; onClicked: joinHidden() }
                    }
                    Text {
                        visible: menu.hiddenOpen && text !== ""
                        text: networks.joining === hidSsid.text ? "connecting…" : networks.failed === hidSsid.text ? "couldn't join" : ""
                        color: networks.failed === hidSsid.text ? "#f7768e" : Theme.actFg
                        font { family: Theme.font; pixelSize: 10 }
                    }
                }

                // ---- VPN ----
                Column {
                    visible: menu.section === "vpn"
                    width: parent.width
                    spacing: 3
                    Text {
                        visible: menu.vpns.length === 0
                        width: parent.width
                        topPadding: 12
                        bottomPadding: 12
                        horizontalAlignment: Text.AlignHCenter
                        text: "No VPNs set up"
                        color: Theme.mainFg
                        opacity: 0.5
                        font { family: Theme.font; pixelSize: 12 }
                    }
                    Repeater {
                        model: ScriptModel { values: menu.vpns.map(v => v.name) }
                        Rectangle {
                            id: vpn
                            required property string modelData
                            readonly property var v: menu.vpns.find(o => o.name === modelData) ?? ({ name: modelData, state: "" })
                            readonly property bool up: v.state === "activated"
                            readonly property bool busy: v.state === "activating" || v.state === "deactivating"
                            width: parent.width
                            height: 30
                            radius: 9
                            color: up ? Qt.alpha(Theme.actBg, 0.25) : vpnHover.hovered ? Qt.alpha(Theme.mainFg, 0.12) : "transparent"
                            Behavior on color { ColorAnimation { duration: 120 } }
                            HoverHandler { id: vpnHover; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: if (!vpn.busy) menu.flip(vpn.v) }

                            RowLayout {
                                anchors { fill: parent; leftMargin: 9; rightMargin: 9 }
                                spacing: 9
                                Text {
                                    text: Theme.g(vpn.up ? 0xF0565 : 0xF099D)   // shield-check / shield-off-outline
                                    color: vpn.up ? Theme.actFg : Theme.mainFg
                                    opacity: vpn.up ? 1 : 0.6
                                    font { family: Theme.font; pixelSize: 13 }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: vpn.v.name
                                    color: Theme.mainFg
                                    elide: Text.ElideRight
                                    font { family: Theme.font; pixelSize: 12; bold: vpn.up }
                                }
                                Text {
                                    text: vpn.v.state === "activating" ? "connecting…" : vpn.v.state === "deactivating" ? "disconnecting…" : vpn.up ? "on" : ""
                                    color: Theme.actFg
                                    font { family: Theme.font; pixelSize: 10 }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ---- more… / hidden network / settings ----
        RowLayout {
            width: parent.width
            Link {
                visible: menu.section === "wifi" && menu.radio && networks.total > 4
                text: menu.showAll ? "fewer" : `more… (${networks.total - 4})`
                onClicked: menu.showAll = !menu.showAll
            }
            Link {
                visible: menu.section === "wifi" && menu.radio
                text: Theme.g(0xF0415) + " hidden"
                onClicked: { menu.hiddenOpen = !menu.hiddenOpen; if (menu.hiddenOpen) hidSsid.grab() }
            }
            Item { Layout.fillWidth: true }
            IconButton {
                icon: 0xF0493   // cog
                size: 15
                onClicked: { menu.close(); Util.run("nm-connection-editor") }
            }
        }
    }

    function joinHidden() {
        if (hidSsid.text === "") return
        networks.connect(hidSsid.text, ["nmcli", "--ask", "dev", "wifi", "connect", hidSsid.text, "hidden", "yes"], hidPw.text)
    }

    // label over a value; click copies the value
    component Cell: Rectangle {
        id: cell
        property string label
        property string value
        property string copy: value   // what a click copies, when it isn't what's shown
        property bool copied: false
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        implicitHeight: 36
        radius: 9
        color: Qt.alpha(Theme.mainFg, cellHover.hovered ? 0.12 : 0.05)
        Behavior on color { ColorAnimation { duration: 120 } }
        HoverHandler { id: cellHover; cursorShape: Qt.PointingHandCursor }
        TapHandler {
            onTapped: if (cell.copy) { Quickshell.execDetached(["wl-copy", cell.copy]); cell.copied = true; copiedTimer.restart() }
        }
        Timer { id: copiedTimer; interval: 1200; onTriggered: cell.copied = false }
        Column {
            anchors { fill: parent; leftMargin: 9; rightMargin: 8; topMargin: 5 }
            spacing: 1
            Text {
                text: cell.copied ? "COPIED" : cell.label.toUpperCase()
                color: cell.copied ? Theme.actFg : Theme.mainFg
                opacity: cell.copied ? 1 : 0.5
                font { family: Theme.font; pixelSize: 8; bold: true; letterSpacing: 1 }
            }
            Text {
                width: parent.width
                text: cell.value || "—"
                color: Theme.mainFg
                elide: Text.ElideRight
                font { family: Theme.font; pixelSize: 11; bold: true }
            }
        }
    }

    // round toggle with its name under it
    component Round: Column {
        id: rd
        property int icon
        property string label
        property bool on: false
        signal clicked()
        signal rightClicked()
        spacing: 5
        opacity: enabled ? 1 : 0.4
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 48
            height: 48
            radius: 24
            color: rd.on ? (rdHover.hovered ? Qt.lighter(Theme.actBg, 1.08) : Theme.actBg)
                         : Qt.alpha(Theme.mainFg, rdHover.hovered && rd.enabled ? 0.16 : 0.08)
            Behavior on color { ColorAnimation { duration: 200 } }
            scale: rdTap.pressed ? 0.9 : 1
            Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
            HoverHandler { id: rdHover; cursorShape: Qt.PointingHandCursor }
            TapHandler {
                id: rdTap
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onTapped: (p, button) => button === Qt.RightButton ? rd.rightClicked() : rd.clicked()
            }
            Text {
                anchors.centerIn: parent
                text: Theme.g(rd.icon)
                color: rd.on ? Theme.mainBg : Theme.mainFg
                Behavior on color { ColorAnimation { duration: 200 } }
                font { family: Theme.font; pixelSize: 20 }
            }
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: rd.label
            color: Theme.mainFg
            opacity: rd.on ? 0.9 : 0.55
            font { family: Theme.font; pixelSize: 10 }
        }
    }

    // half of the Wi-Fi | VPN switch; a dot when that side is connected
    component Tab: Item {
        id: tb
        property string key
        property string text
        property bool lit: false
        width: tabs.width / 2
        height: tabs.height
        HoverHandler { id: tbHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: menu.section = tb.key }
        Row {
            anchors.centerIn: parent
            spacing: 6
            Text {
                text: tb.text
                color: Theme.mainFg
                opacity: menu.section === tb.key || tbHover.hovered ? 1 : 0.55
                Behavior on opacity { NumberAnimation { duration: 150 } }
                font { family: Theme.font; pixelSize: 12; bold: menu.section === tb.key }
            }
            Rectangle {
                visible: tb.lit
                anchors.verticalCenter: parent.verticalCenter
                width: 6
                height: 6
                radius: 3
                color: Theme.actFg
            }
        }
    }

    component Link: Text {
        signal clicked()
        leftPadding: 9
        color: Theme.mainFg
        opacity: linkHover.hovered ? 1 : 0.6
        font { family: Theme.font; pixelSize: 11 }
        HoverHandler { id: linkHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: parent.clicked() }
    }

    component Field: Rectangle {
        property string hint
        property bool secret: false
        property alias text: input.text
        signal accepted()
        function grab() { input.forceActiveFocus() }
        implicitHeight: 26
        radius: 8
        color: Qt.alpha(Theme.mainFg, 0.08)
        border.color: input.activeFocus ? Theme.mainFg : Qt.alpha(Theme.mainFg, 0.25)
        TextInput {
            id: input
            anchors { fill: parent; leftMargin: 9; rightMargin: 9 }
            verticalAlignment: TextInput.AlignVCenter
            echoMode: parent.secret ? TextInput.Password : TextInput.Normal
            color: Theme.mainFg
            font { family: Theme.font; pixelSize: 12 }
            clip: true
            onAccepted: parent.accepted()
            Text {
                anchors.verticalCenter: parent.verticalCenter
                visible: input.text === ""
                text: parent.parent.hint
                color: Theme.mainFg
                opacity: 0.4
                font: input.font
            }
        }
    }
}
