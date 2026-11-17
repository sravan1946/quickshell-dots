import QtQuick
import Quickshell
import Quickshell.Bluetooth
import qs
import qs.islands

// Bluetooth. What's connected gets a card: for Nothing / CMF buds, a capsule per bud and the
// case filling to its battery (warm with a bolt while charging, amber then red as it runs low);
// anything else with a battery, one bar. Hover a card to disconnect. Under it the paired devices
// (tap to connect, hover for the bin to forget) and, while the panel is open, the new ones
// nearby (tap to pair; blueman-applet answers any PIN prompt).
Panel {
    id: p
    implicitWidth: 330
    spacing: 12
    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool on: !!adapter?.enabled
    readonly property var all: adapter?.devices.values ?? []
    readonly property var connected: all.filter(d => d.connected).sort((a, b) => a.name.localeCompare(b.name))
    readonly property var paired: all.filter(d => d.paired && !d.connected).sort((a, b) => a.name.localeCompare(b.name))
    readonly property var nearby: all.filter(d => !d.paired && d.deviceName !== "").sort((a, b) => a.name.localeCompare(b.name)).slice(0, 6)
    property bool scanning: false
    property string want: ""
    function scan(go) {
        if (!adapter?.enabled || go === scanning) return
        scanning = go
        adapter.discovering = go
    }
    Component.onCompleted: scan(true)
    Component.onDestruction: scan(false)
    onOnChanged: if (on) scan(true)
    function busy(d) { return d.pairing || d.state === BluetoothDeviceState.Connecting || d.state === BluetoothDeviceState.Disconnecting }
    function busyText(d) {
        return d.pairing ? "pairing…" : d.state === BluetoothDeviceState.Connecting ? "connecting…"
            : d.state === BluetoothDeviceState.Disconnecting ? "disconnecting…" : ""
    }
    // BlueZ calls earbuds and headphones both "audio-headset": earbuds go by the name (as in the bar)
    function glyph(icon, name) {
        return /buds|earbud|pods|\bear\b|cmf/i.test(name ?? "") && /audio|head/.test(icon) ? 0xF184F
            : /headset|headphone/.test(icon) ? 0xF02CB : /audio|speaker/.test(icon) ? 0xF04C3
            : /mouse/.test(icon) ? 0xF037D : /keyboard/.test(icon) ? 0xF030C : /phone/.test(icon) ? 0xF011C : 0xF00AF
    }
    function tone(pct, charging) { return charging ? Look.warm : pct <= 15 ? Look.alert : pct <= 30 ? Look.urgent : Look.good }

    // the panel's small caps section label
    component Label: T {
        x: 2
        color: Look.faint
        font.pixelSize: 10
        font.weight: Font.Bold
        font.letterSpacing: 0.8
        font.capitalization: Font.AllUppercase
    }
    // a bud or the case: a capsule filling to its level
    component Capsule: Row {
        id: cap
        property string label
        property var level: null          // [pct, charging], or null when it isn't reporting
        readonly property int pct: level ? level[0] : 0
        readonly property bool charging: !!level && !!level[1]
        spacing: 8
        Rectangle {
            width: 12; height: 26
            radius: 5
            color: Qt.alpha(Look.text, 0.1)
            border.width: cap.level ? 0 : 1
            border.color: Qt.alpha(Look.text, 0.18)
            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: cap.level ? Math.max(4, parent.height * cap.pct / 100) : 0
                radius: 5
                color: p.tone(cap.pct, cap.charging)
                Behavior on height { Anim { type: "effects" } }
                Behavior on color { Fade {} }
            }
        }
        Column {
            anchors.verticalCenter: parent.verticalCenter
            T { text: cap.label; color: Look.faint; font.pixelSize: 10; font.weight: Font.Bold }
            Row {
                spacing: 2
                T { text: cap.level ? cap.pct + "%" : "–"; font.pixelSize: 13; font.weight: Font.DemiBold; color: cap.level ? Look.text : Look.faint }
                G { visible: cap.charging; glyph: 0xF140B; font.pixelSize: 11; color: Look.warm; height: 18 }
            }
        }
    }

    // ---- header ----
    Item {
        width: parent.width
        height: 30
        Row {
            x: 2
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8
            T { id: title; text: "Bluetooth"; font.pixelSize: 15; font.weight: Font.Bold }
            T {
                anchors.baseline: title.baseline
                visible: p.on && p.connected.length > 0
                text: p.connected.length === 1 ? "1 connected" : `${p.connected.length} connected`
                color: Look.faint
                font.pixelSize: Look.small
            }
        }
        Row {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: 10
            G {
                anchors.verticalCenter: parent.verticalCenter
                glyph: 0xF0493
                font.pixelSize: 15
                color: sh.hovered ? Look.text : Look.faint
                HoverHandler { id: sh; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { p.ctl.hide(); Quickshell.execDetached(["blueman-manager"]) } }
            }
            Switch { on: p.on; onToggled: if (p.adapter) p.adapter.enabled = !p.adapter.enabled }
        }
    }

    // off
    Row {
        visible: !p.on
        x: 2
        spacing: 10
        G { glyph: 0xF00B2; font.pixelSize: 16; color: Look.faint }
        T { anchors.verticalCenter: parent.verticalCenter; text: p.adapter ? "Bluetooth is off" : "No Bluetooth adapter"; color: Look.dim }
    }

    // ---- connected: cards ----
    Column {
        visible: p.on && p.connected.length > 0
        width: parent.width
        spacing: 8
        Repeater {
            model: ScriptModel { values: p.connected }
            Rectangle {
                id: card
                required property var modelData
                readonly property var d: modelData
                readonly property var buds: BudsState.of(d)
                readonly property bool hasBuds: !!buds && !!(buds.left || buds.right || buds.case)
                width: parent.width
                height: cc.implicitHeight + 26
                radius: 14
                color: Look.raise
                Behavior on height { Anim {} }
                HoverHandler { id: cardH }
                Column {
                    id: cc
                    x: 13; y: 13
                    width: parent.width - 26
                    spacing: 12
                    Item {
                        width: parent.width
                        height: 34
                        Rectangle {
                            width: 34; height: 34; radius: 17
                            color: Qt.alpha(Look.accent, 0.18)
                            G { anchors.centerIn: parent; glyph: p.glyph(card.d.icon, card.d.name); font.pixelSize: 17; color: Look.accent }
                        }
                        Column {
                            x: 46
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - x - 96
                            T { width: parent.width; text: card.d.name; font.weight: Font.DemiBold; elide: Text.ElideRight }
                            T {
                                text: p.busyText(card.d) || "Connected"
                                color: p.busy(card.d) ? Look.accent : Look.faint
                                font.pixelSize: Look.small
                            }
                        }
                        // the battery when there's one number, or disconnect under the pointer
                        Item {
                            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                            width: 90
                            height: parent.height
                            Row {
                                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                spacing: 8
                                visible: !card.hasBuds && card.d.batteryAvailable
                                opacity: cardH.hovered ? 0 : 1
                                Behavior on opacity { Anim { type: "effects" } }
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 40; height: 5; radius: 2.5
                                    color: Qt.alpha(Look.text, 0.12)
                                    Rectangle {
                                        width: parent.width * card.d.battery
                                        height: parent.height
                                        radius: 2.5
                                        color: p.tone(card.d.battery * 100, false)
                                    }
                                }
                                T { text: Math.round(card.d.battery * 100) + "%"; font.pixelSize: Look.small; font.weight: Font.DemiBold }
                            }
                            T {
                                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                text: "Disconnect"
                                color: dh.hovered ? Look.alert : Look.dim
                                font.pixelSize: Look.small
                                font.weight: Font.DemiBold
                                opacity: cardH.hovered && !p.busy(card.d) ? 1 : 0
                                visible: opacity > 0
                                Behavior on opacity { Anim { type: "effects" } }
                                HoverHandler { id: dh; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: card.d.disconnect() }
                            }
                        }
                    }
                    // buds: each bud and the case
                    Row {
                        visible: card.hasBuds
                        x: 2
                        spacing: 26
                        Capsule { label: "LEFT"; level: card.buds?.left ?? null }
                        Capsule { label: "RIGHT"; level: card.buds?.right ?? null }
                        Capsule { label: "CASE"; level: card.buds?.case ?? null }
                    }
                }
            }
        }
    }

    // ---- paired, and new ones nearby: rows ----
    component DeviceRow: Rectangle {
        id: row
        required property var modelData
        readonly property var d: modelData
        property string action
        signal act()
        width: parent?.width ?? 300
        height: 38
        radius: 10
        color: rh.hovered ? Look.hover : "transparent"
        Behavior on color { Fade {} }
        Rectangle {
            x: 6
            anchors.verticalCenter: parent.verticalCenter
            width: 28; height: 28; radius: 14
            color: Look.raise
            G { anchors.centerIn: parent; glyph: p.glyph(row.d.icon, row.d.name); font.pixelSize: 14; color: row.d.paired ? Look.dim : Look.faint }
        }
        T {
            x: 44
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - x - 104
            text: row.d.name
            color: row.d.paired ? Look.text : Look.dim
            elide: Text.ElideRight
        }
        // a fixed-width end: what's going on, else what a tap does (and the bin) under the pointer
        Item {
            anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
            width: 96
            height: parent.height
            T {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                visible: p.busy(row.d)
                text: p.busyText(row.d)
                color: Look.accent
                font.pixelSize: Look.small
            }
            Row {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                spacing: 10
                opacity: rh.hovered && !p.busy(row.d) ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { Anim { type: "effects" } }
                T { anchors.verticalCenter: parent.verticalCenter; text: row.action; color: Look.accent; font.pixelSize: Look.small; font.weight: Font.DemiBold }
                G {
                    visible: row.d.paired
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: 0xF0A7A
                    font.pixelSize: 14
                    color: bin.hovered ? Look.alert : Look.faint
                    HoverHandler { id: bin; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: row.d.forget() }
                }
            }
        }
        HoverHandler { id: rh; cursorShape: Qt.PointingHandCursor }
        TapHandler { acceptedButtons: Qt.LeftButton; onTapped: if (!bin.hovered && !p.busy(row.d)) row.act() }
        TapHandler { acceptedButtons: Qt.RightButton; onTapped: if (row.d.paired) row.d.forget() }
    }

    Column {
        visible: p.on && p.paired.length > 0
        width: parent.width
        spacing: 2
        Label { text: "Paired"; bottomPadding: 4 }
        Repeater {
            model: ScriptModel { values: p.paired }
            DeviceRow { action: "Connect"; onAct: d.connect() }
        }
    }

    Column {
        visible: p.on
        width: parent.width
        spacing: 2
        Item {
            width: parent.width
            height: 18
            Label { anchors.verticalCenter: parent.verticalCenter; text: "Nearby" }
            // looking: three dots stepping on a timer, not a running animation
            Row {
                visible: !!p.adapter?.discovering
                anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                spacing: 4
                property int lit: 0
                Timer { interval: 450; repeat: true; running: parent.visible; onTriggered: parent.lit = (parent.lit + 1) % 3 }
                Repeater {
                    model: 3
                    Rectangle {
                        required property int index
                        width: 4; height: 4; radius: 2
                        color: Look.accent
                        opacity: parent.lit === index ? 1 : 0.25
                    }
                }
            }
        }
        T {
            visible: p.nearby.length === 0
            x: 2
            topPadding: 2
            text: p.adapter?.discovering ? "Looking for devices…" : "Nothing new nearby"
            color: Look.faint
            font.pixelSize: Look.small
        }
        Repeater {
            model: ScriptModel { values: p.nearby }
            DeviceRow {
                id: nr
                action: "Pair"
                onAct: { p.want = d.address; d.trusted = true; d.pair() }
                Connections {
                    target: nr.d
                    function onPairedChanged() { if (nr.d.paired && p.want === nr.d.address) { p.want = ""; nr.d.connect() } }
                }
            }
        }
    }
}
