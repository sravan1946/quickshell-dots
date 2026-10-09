import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import qs
import qs.components

// Quick settings, one per monitor. Rest the pointer on the right screen edge (top part,
// below the bar) and the panel pours out of that point like liquid
// (components/LiquidCard.qml); once the pointer leaves, a hole opens where it went out and
// eats the panel away (the Now Playing panel's animation).
// Only the outer right edge is hot: an edge shared with another monitor would fire on
// every crossing. `qs -c bar ipc call quick toggle` opens it on the focused monitor.
// It holds only what the bar doesn't: Wi-Fi, Bluetooth, DND, caffeine, battery, volume,
// brightness and media all have their pill. Here: session buttons, night light, airplane
// mode, mic, the phone (KDE Connect), audio device pickers and a per-app mixer.
Scope {
    id: root

    required property var modelData
    readonly property var screen: modelData   // null for a moment when its monitor is unplugged
    readonly property bool outerRight: !!screen && !Quickshell.screens.some(s => s.x === screen.x + screen.width
        && s.y < screen.y + screen.height && s.y + s.height > screen.y)

    property bool open: false
    property real edgeY: 0       // where the pointer touched the edge (panel-window y); spawn point
    property string section: ""  // "out" | "in": the device list pulled out under its row
    property int mixDrag: 0      // per-app sliders being dragged
    readonly property bool busy: mic.pressed || nl.pressed || mixDrag > 0   // mid-drag: don't close

    readonly property var src: Pipewire.defaultAudioSource
    readonly property var bt: Bluetooth.defaultAdapter
    // playback streams: apps sending audio out. Quickshell counts these as sinks (Spotify's
    // stream: isSink true; cava's recording stream: false), and node.properties stays empty
    // until a node is tracked, so media.class can't be used to pick them
    readonly property var streams: Pipewire.nodes.values.filter(n => n.isStream && n.isSink && n.audio)
    PwObjectTracker { objects: [root.src].concat(root.streams) }

    // apps by name; ALSA devices by profile ("Speaker", not "Ryzen HD Audio Controller Speaker")
    function nodeName(n) { return n?.properties?.["application.name"] || n?.properties?.["device.profile.description"] || n?.description || n?.nickname || n?.name || "" }
    function launch(cmd) { root.open = false; Util.run(cmd) }

    // ---- uptime ----
    property string uptime: ""
    Process {
        id: up
        command: ["cat", "/proc/uptime"]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = Math.floor(parseFloat(text) / 60), h = Math.floor(m / 60), d = Math.floor(h / 24)
                root.uptime = d ? `${d}d ${h % 24}h` : h ? `${h}h ${m % 60}m` : `${m}m`
            }
        }
    }

    // ---- night light: HyDE's hyprsunset.sh and its state file (temp|gamma|on|identity) ----
    // "On" means toggled on AND warmer than identity: HyDE ships it on at 6000K, which tints nothing.
    readonly property var nlState: (nlFile.text() || "6000|100|0|6000").trim().split("|").map(Number)
    readonly property int nlTemp: nlState[0]
    readonly property int nlIdentity: nlState[3] || 6000
    readonly property bool nlOn: nlState[2] === 1 && nlTemp < nlIdentity
    readonly property int nlMin: 2500
    property int nlLive: 0       // temperature mid-drag, before the script saves it
    FileView {
        id: nlFile
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/hyde/hyprsunset"
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.nlLive = 0
    }
    function nlToggle() {
        const sh = "hyde-shell hyprsunset.sh -q"
        if (nlOn) return Util.run(`${sh} -t`)
        const t = nlTemp < nlIdentity ? nlTemp : 4500
        Util.run(nlState[2] === 1 ? `${sh} -s ${t}` : `${sh} -s ${t}; ${sh} -t`)
    }
    // while dragging talk to hyprsunset directly (the script is a slow bash start-up); save on release
    Timer { id: nlApply; interval: 50; onTriggered: Util.run(`hyprctl --quiet hyprsunset temperature ${root.nlLive}`) }

    // ---- phone (KDE Connect): first reachable device, its name and battery ----
    property var phone: null     // { id, name, charge, charging }
    Process {
        id: phoneGet
        command: ["sh", "-c", `
            id=$(kdeconnect-cli -a --id-only 2>/dev/null | head -1); [ -n "$id" ] || exit 0
            p=/modules/kdeconnect/devices/$id; g() { busctl --user get-property org.kde.kdeconnect "$@" 2>/dev/null | cut -d' ' -f2-; }
            echo "$id|$(g $p org.kde.kdeconnect.device name | tr -d '"')|$(g $p/battery org.kde.kdeconnect.device.battery charge)|$(g $p/battery org.kde.kdeconnect.device.battery isCharging)"`]
        stdout: StdioCollector {
            onStreamFinished: {
                const f = text.trim().split("|")
                root.phone = f.length < 4 ? null : { id: f[0], name: f[1], charge: parseInt(f[2]), charging: f[3] === "true" }
            }
        }
    }

    onOpenChanged: {
        if (open) Update.stale()
        Config.quickOpen = open
        if (open) {
            NetStats.refresh()
            up.running = true
            phoneGet.running = true
            // out of the screen edge (8px right of the card) where the pointer touched it
            card.pour(Qt.point(card.x + card.width + 8, card.y + Math.max(0, Math.min(card.height, root.edgeY))))
        } else card.drain(hover.last)
    }
    Connections {
        target: Config
        function onToggleQuick() {
            const focused = Hyprland.focusedMonitor?.name ?? Quickshell.screens[0].name
            if (focused === root.screen?.name) { root.edgeY = 0; root.open = !root.open; if (root.open) closer.stop() }
        }
    }


    // pointer left the panel (or never reached it after an edge open)
    // the pointer pressed against the screen edge (edge strip) still counts as being on the panel
    Timer { id: closer; interval: 220; onTriggered: if (!hover.hovered && !edgeHover.hovered && !root.busy) root.open = false }
    Timer {
        id: dwell
        interval: 90
        onTriggered: {
            root.edgeY = edgeHover.point.position.y - 6   // the strip starts 6px above the panel window
            root.open = true
            closer.interval = 900
            closer.restart()
        }
    }

    // hot edge: the outer 2px take the pointer (the window is wider only to draw in).
    // A faint accent line marks the zone; under the pointer it brightens and a marker
    // shows where the panel will pour out from.
    PanelWindow {
        id: edgeWin
        screen: root.screen
        visible: root.outerRight && Settings.quickEdge
        anchors { top: true; right: true }
        margins.top: Config.height
        implicitWidth: 10
        implicitHeight: card.fullH + 12
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        mask: Region { x: edgeWin.width - 2; width: 2; height: edgeWin.height }
        WlrLayershell.namespace: "quicksettings-edge"
        HoverHandler {
            id: edgeHover
            onHoveredChanged: {
                if (hovered) { if (!root.open) dwell.restart(); else closer.stop() }
                else { dwell.stop(); if (root.open && !hover.hovered) { closer.interval = 220; closer.restart() } }
            }
        }

        // soft glowing line: fades out at both ends, a blurred halo instead of a hard outline
        Item {
            id: line
            anchors { right: parent.right; rightMargin: 2; top: parent.top; bottom: parent.bottom; topMargin: 6; bottomMargin: 6 }
            width: 4
            opacity: root.open ? 0 : edgeHover.hovered ? 1 : 0.7
            Behavior on opacity { NumberAnimation { duration: 160 } }
            layer.enabled: true
            layer.effect: MultiEffect { blurEnabled: true; blur: 0.35; blurMax: 8; brightness: edgeHover.hovered ? 0.15 : 0 }
            Rectangle {
                anchors.centerIn: parent
                width: edgeHover.hovered ? 3 : 2.5
                height: parent.height
                radius: width / 2
                Behavior on width { NumberAnimation { duration: 120 } }
                gradient: Gradient {
                    GradientStop { position: 0; color: "transparent" }
                    GradientStop { position: 0.2; color: Theme.actBg }
                    GradientStop { position: 0.8; color: Theme.actBg }
                    GradientStop { position: 1; color: "transparent" }
                }
            }
        }
        Rectangle {
            readonly property bool on: edgeHover.hovered && !root.open
            anchors.right: parent.right
            y: Math.max(0, Math.min(parent.height - height, edgeHover.point.position.y - height / 2))
            width: on ? 6 : 0
            height: 36
            radius: 3
            color: Theme.actBg
            opacity: on ? 1 : 0
            Behavior on width { SpringAnimation { spring: 6; damping: 0.35; epsilon: 0.1 } }
            Behavior on opacity { NumberAnimation { duration: 100 } }
        }
    }

    PanelWindow {
        id: win
        screen: root.screen
        // always mapped, click-through while closed: no window to create when it opens
        visible: true
        anchors { top: true; right: true }
        margins.top: Config.height + 6
        // room around the card for the shadow; full height so a pulled-out list never resizes the surface
        implicitWidth: card.fullW + 8 + 40
        implicitHeight: (root.screen?.height ?? 0) - Config.height - 6
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        mask: root.open ? hit : nothing
        Region { id: hit; item: hitArea }
        Region { id: nothing }
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quicksettings"

        HoverHandler {
            id: hover
            property point last   // pointer position in the window, kept for where it leaves
            onPointChanged: if (hovered) last = point.position
            onHoveredChanged: {
                if (hovered) closer.stop()
                else { closer.interval = 220; closer.restart() }
            }
        }

        // the card plus the gap to the screen edge: a pointer pressed against the edge stays "on" it
        Item { id: hitArea; x: card.x; width: win.width - card.x; height: card.height }

        LiquidCard {
            id: card
            readonly property real fullW: 348
            readonly property real fullH: body.implicitHeight + 32
            onClosed: root.section = ""

            x: win.width - width - 8
            width: fullW
            height: fullH
            radius: Theme.radius + 5
            color: Qt.alpha(Theme.mainBg, 0.97)
            border.color: Qt.alpha(Theme.mainFg, 0.35)
            border.width: 1


            ColumnLayout {
                id: body
                x: 16
                y: 16
                width: card.fullW - 32        // fixed: the layout doesn't reflow while the card morphs
                spacing: 14

                // who · uptime · settings · lock · power
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Rectangle {
                        implicitWidth: 30
                        implicitHeight: 30
                        radius: 15
                        color: Theme.actBg
                        T { anchors.centerIn: parent; text: Theme.g(0xF0004); color: Theme.mainBg; font.pixelSize: 16 }   // account
                    }
                    ColumnLayout {
                        Layout.leftMargin: 4
                        spacing: 0
                        T { text: Quickshell.env("USER"); font.bold: true; font.pixelSize: 13 }
                        T { visible: !!root.uptime; text: "up " + root.uptime; opacity: 0.6; font.pixelSize: 11 }
                    }
                    Item { Layout.fillWidth: true }   // pushes the buttons to the right edge
                    IconButton { icon: 0xF0493; onClicked: { root.open = false; Config.openSettings() } }   // cog
                    IconButton { icon: 0xF0341; onClicked: root.launch("hyde-shell lockscreen.sh") }       // lock
                    IconButton { icon: 0xF0425; onClicked: { root.open = false; Config.togglePower() } }   // power menu
                }

                // the bar's code is behind GitHub (Update.qml)
                RowLayout {
                    visible: Update.behind > 0
                    Layout.fillWidth: true
                    spacing: 10
                    T { text: Theme.g(0xF06B0); color: Theme.actBg; font.pixelSize: 18 }   // update
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        T {
                            text: Update.behind === 1 ? "1 update on GitHub" : `${Update.behind} updates on GitHub`
                            font.bold: true
                        }
                        T {
                            Layout.fillWidth: true
                            text: Update.error || (Update.subjects[0] ?? "")
                            color: Update.error ? "#e06c75" : Theme.mainFg
                            opacity: Update.error ? 1 : 0.6
                            elide: Text.ElideRight
                            font.pixelSize: 11
                        }
                    }
                    PillButton {
                        implicitHeight: 24
                        text: Update.busy ? "Updating…" : "Update"
                        onClicked: Update.pull()
                    }
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    columnSpacing: 8
                    rowSpacing: 8
                    Tile {
                        icon: 0xF0594   // weather-night
                        label: "Night light"
                        sub: root.nlOn ? `${root.nlLive || root.nlTemp}K` : "Off"
                        on: root.nlOn
                        onClicked: root.nlToggle()
                    }
                    Tile {
                        readonly property bool wifi: !!NetStats.info.wifiOn
                        icon: on ? 0xF001D : 0xF001E   // airplane / airplane-off
                        label: "Airplane mode"
                        sub: on ? "Radios off" : "Off"
                        on: !wifi && !root.bt?.enabled
                        onClicked: {
                            Util.run(`nmcli radio wifi ${on ? "on" : "off"}`)
                            if (root.bt) root.bt.enabled = on
                            refreshSoon.restart()
                        }
                    }
                    Tile {
                        readonly property bool muted: !!root.src?.audio?.muted
                        icon: muted ? 0xF036D : 0xF036C
                        label: "Microphone"
                        sub: !root.src ? "None" : muted ? "Muted" : "On"
                        on: !!root.src && !muted
                        onClicked: if (root.src?.audio) root.src.audio.muted = !muted
                    }
                    Tile {
                        icon: 0xF011C   // cellphone
                        label: root.phone?.name || "Phone"
                        sub: !root.phone ? "Not connected"
                            : `${root.phone.charge}%${root.phone.charging ? " · charging" : ""} · tap to ring`
                        on: !!root.phone
                        onClicked: root.phone ? Util.run(`kdeconnect-cli -d ${root.phone.id} --ring`) : root.launch("kdeconnect-app")
                    }
                }

                SliderRow {
                    id: nl
                    visible: root.nlOn
                    icon: 0xF050F   // thermometer
                    readonly property int temp: root.nlLive || root.nlTemp
                    value: (temp - root.nlMin) / (root.nlIdentity - root.nlMin)
                    text: temp + "K"
                    onIconClicked: root.nlToggle()
                    onMoved: v => {
                        root.nlLive = Math.round((root.nlMin + v * (root.nlIdentity - root.nlMin - 100)) / 100) * 100
                        if (!nlApply.running) nlApply.start()
                    }
                    onPressedChanged: if (!pressed && root.nlLive) Util.run(`hyde-shell hyprsunset.sh -q -s ${root.nlLive}`)
                }

                // audio devices, each with its list pulled out under it
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    DevicePicker { sink: true }
                    DevicePicker { sink: false }
                }

                SliderRow {
                    id: mic
                    icon: root.src?.audio?.muted ? 0xF036D : 0xF036C
                    value: root.src?.audio?.volume ?? 0
                    muted: !!root.src?.audio?.muted
                    onIconClicked: if (root.src?.audio) root.src.audio.muted = !root.src.audio.muted
                    onMoved: v => { if (root.src?.audio) root.src.audio.volume = v }
                }

                // per-app mixer
                ColumnLayout {
                    visible: root.streams.length > 0
                    Layout.fillWidth: true
                    spacing: 4
                    RowLayout {
                        Layout.fillWidth: true
                        ListHeader { Layout.fillWidth: true; text: "Apps" }
                        IconButton { icon: 0xF062E; implicitWidth: 24; implicitHeight: 24; size: 13; onClicked: root.launch("pavucontrol-qt -t 1 || pavucontrol -t 1") }
                    }
                    Repeater {
                        model: root.streams
                        SliderRow {
                            id: app
                            required property var modelData
                            readonly property var a: modelData.audio
                            icon: a?.muted ? 0xF0581 : 0xF057E
                            label: root.nodeName(modelData)
                            value: a?.volume ?? 0
                            muted: !!a?.muted
                            onIconClicked: if (a) a.muted = !a.muted
                            onMoved: v => { if (a) a.volume = v }
                            onPressedChanged: root.mixDrag += pressed ? 1 : -1
                            Component.onDestruction: if (pressed) root.mixDrag--
                        }
                    }
                }
            }
        }

    }
    Timer { id: refreshSoon; interval: 700; onTriggered: NetStats.refresh() }

    component T: Text {
        color: Theme.mainFg
        font { family: Theme.font; pixelSize: 12 }
    }

    // "Output  Speakers ▾": click pulls out every device of that kind, click one to make it the default
    component DevicePicker: ColumnLayout {
        id: dp
        property bool sink
        readonly property string key: sink ? "out" : "in"
        readonly property bool expanded: root.section === key
        readonly property var current: sink ? Pipewire.defaultAudioSink : Pipewire.defaultAudioSource
        readonly property var nodes: Pipewire.nodes.values.filter(n => n.audio && !n.isStream && n.isSink === dp.sink)
        Layout.fillWidth: true
        spacing: 2
        ListRow {
            Layout.fillWidth: true
            onClicked: root.section = dp.expanded ? "" : dp.key
            T { text: Theme.g(dp.sink ? 0xF04C3 : 0xF036C); font.pixelSize: 14 }   // speaker / microphone
            T { text: dp.sink ? "Output" : "Input"; opacity: 0.55; font.pixelSize: 11; Layout.preferredWidth: 40 }
            T { Layout.fillWidth: true; text: dp.current ? root.nodeName(dp.current) : "None"; elide: Text.ElideRight }
            T {
                text: Theme.g(0xF0140)   // chevron-down
                opacity: dp.expanded ? 1 : 0.5
                rotation: dp.expanded ? 180 : 0
                Behavior on rotation { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            }
        }
        Item {
            Layout.fillWidth: true
            implicitHeight: dp.expanded ? devList.implicitHeight : 0
            Behavior on implicitHeight { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
            clip: true
            Column {
                id: devList
                width: parent.width
                leftPadding: 22
                spacing: 2
                Repeater {
                    model: dp.nodes
                    ListRow {
                        required property var modelData
                        width: devList.width - devList.leftPadding
                        selected: modelData === dp.current
                        onClicked: {
                            if (dp.sink) Pipewire.preferredDefaultAudioSink = modelData
                            else Pipewire.preferredDefaultAudioSource = modelData
                            root.section = ""
                        }
                        T { Layout.fillWidth: true; text: root.nodeName(modelData); elide: Text.ElideRight; font.pixelSize: 11 }
                    }
                }
            }
        }
    }

    component SliderRow: RowLayout {
        id: sr
        property int icon
        property string label: ""     // a name before the slider (the mixer's apps)
        property real value
        property bool muted: false
        property string text: Math.round(value * 100) + "%"
        readonly property bool pressed: slider.pressed
        signal iconClicked()
        signal moved(real v)

        Layout.fillWidth: true
        spacing: 10
        IconButton { icon: sr.icon; dim: sr.muted; onClicked: sr.iconClicked() }
        T {
            visible: !!sr.label
            Layout.preferredWidth: 72
            text: sr.label
            elide: Text.ElideRight
            font.pixelSize: 11
            opacity: sr.muted ? 0.5 : 0.85
        }
        Slider {
            id: slider
            Layout.fillWidth: true
            value: sr.value
            dim: sr.muted
            onMoved: v => sr.moved(v)
        }
        Text {
            Layout.preferredWidth: 44
            horizontalAlignment: Text.AlignRight
            text: sr.text
            color: sr.muted ? Qt.alpha(Theme.mainFg, 0.5) : Theme.actFg
            font { family: Theme.font; pixelSize: 12; bold: true }
        }
    }
}
