import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs

// The panel nm-applet's tray icon opens in place of its own menu (modules/Tray.qml), laid
// out like quick settings: Wi-Fi / VPN / hotspot / networking tiles (the VPN chevron pulls
// out the VPN list), the current network with its details and actions folded under it,
// nearby networks, then joining a hidden network and the connection editor.
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
    // ponytail: `nmcli dev wifi hotspot` names its connection "Hotspot"; one made by hand under another name reads as off
    readonly property bool hotspot: link.conn === "Hotspot"
    readonly property var vpnUp: vpns.filter(v => v.state === "activated" || v.state === "activating")

    property bool vpnOpen: false
    property bool details: false
    property bool showAll: false
    property bool hiddenOpen: false
    property string password: ""     // revealed on demand, dropped on close
    property string armed: ""        // "hotspot" | "networking" | "forget": the next click goes through

    closeOnOutsideClick: true
    padX: 12
    padY: 12
    onVisibleChanged: {
        if (visible) refresh()
        else { details = false; showAll = false; hiddenOpen = false; password = ""; armed = "" }
    }

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
    Timer { id: soon; interval: 900; onTriggered: { menu.refresh(); networks.scan() } }
    Timer { id: disarm; interval: 3000; onTriggered: menu.armed = "" }

    Process {
        id: poll
        command: ["sh", "-c", `
            d=$(nmcli -t -f DEVICE,TYPE dev | awk -F: '$2=="wifi" {print $1; exit}')
            echo "DEV:$d"
            echo "NET:$(nmcli networking)"
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
        id: reveal
        command: ["nmcli", "dev", "wifi", "show-password"]
        stdout: StdioCollector { onStreamFinished: menu.password = (text.match(/^Password: (.*)$/m) ?? [])[1] ?? "" }
    }

    Column {
        width: 320
        spacing: 10

        // ---- tiles ----
        GridLayout {
            width: parent.width
            columns: 2
            columnSpacing: 8
            rowSpacing: 8
            Tile {
                icon: menu.radio ? 0xF05A9 : 0xF05AA
                label: "Wi-Fi"
                sub: !menu.radio ? "Off" : menu.info.ssid || "Not connected"
                on: menu.radio
                onClicked: menu.run(["nmcli", "radio", "wifi", menu.radio ? "off" : "on"])
            }
            Tile {
                icon: menu.vpnUp.length ? 0xF0565 : 0xF099D
                label: "VPN"
                sub: menu.vpnUp.length ? menu.vpnUp.map(v => v.name).join(", ") : menu.vpns.length ? "Off" : "None set up"
                on: menu.vpnUp.length > 0
                more: menu.vpns.length > 0
                expanded: menu.vpnOpen
                onClicked: menu.toggleVpn()
                onExpand: menu.vpnOpen = !menu.vpnOpen
            }
            Tile {
                icon: 0xF0003   // access-point
                label: "Hotspot"
                sub: menu.armed === "hotspot" ? "Again: drops Wi-Fi" : menu.hotspot ? "Sharing" : "Off"
                on: menu.hotspot
                onClicked: {
                    if (menu.hotspot) menu.run(["nmcli", "con", "down", "id", "Hotspot"])
                    else if (menu.arm("hotspot")) menu.run(["nmcli", "dev", "wifi", "hotspot"])
                }
            }
            Tile {
                icon: menu.networking ? 0xF0318 : 0xF0319   // lan-connect / lan-disconnect
                label: "Networking"
                sub: menu.armed === "networking" ? "Again: all offline" : menu.networking ? "On" : "Off"
                on: menu.networking
                onClicked: {
                    if (!menu.networking) menu.run(["nmcli", "networking", "on"])
                    else if (menu.arm("networking")) menu.run(["nmcli", "networking", "off"])
                }
            }
        }

        // ---- VPN list, pulled out of the tile ----
        Column {
            visible: menu.vpnOpen && menu.vpns.length > 0
            width: parent.width
            spacing: 3
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
            Link { text: Theme.g(0xF0493) + "  Configure VPN…"; onClicked: { menu.close(); Util.run("nm-connection-editor") } }
        }

        // ---- the current network; details and actions fold out ----
        Rectangle {
            visible: menu.linked
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

        // ---- nearby ----
        WifiList {
            id: networks
            visible: menu.radio
            width: parent.width
            active: menu.visible
            hideInUse: true
            limit: menu.showAll ? 99 : 6
        }
        Link {
            visible: menu.radio && networks.total > 6
            text: menu.showAll ? "Show fewer" : `Show all ${networks.total}`
            onClicked: menu.showAll = !menu.showAll
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

        Row {
            spacing: 6
            PillButton {
                text: Theme.g(0xF0415) + " Hidden network"
                checked: menu.hiddenOpen
                onClicked: { menu.hiddenOpen = !menu.hiddenOpen; if (menu.hiddenOpen) hidSsid.grab() }
            }
            PillButton {
                text: Theme.g(0xF0493) + " Edit connections"
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
        property bool copied: false
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        implicitHeight: 36
        radius: 9
        color: Qt.alpha(Theme.mainFg, cellHover.hovered ? 0.12 : 0.05)
        Behavior on color { ColorAnimation { duration: 120 } }
        HoverHandler { id: cellHover; cursorShape: Qt.PointingHandCursor }
        TapHandler {
            onTapped: if (cell.value) { Quickshell.execDetached(["wl-copy", cell.value]); cell.copied = true; copiedTimer.restart() }
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
