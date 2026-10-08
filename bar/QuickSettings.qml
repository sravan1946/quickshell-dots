import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Widgets
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris
import Quickshell.Services.UPower
import qs
import qs.components

// Quick settings, one per monitor. Rest the pointer on the right screen edge (top part,
// below the bar) and the panel pours out of that point like liquid
// (components/LiquidCard.qml); once the pointer leaves, a hole opens where it went out and
// eats the panel away (the Now Playing panel's animation). The Wi-Fi and Bluetooth tiles'
// chevrons pull out a device list under the tiles.
// Only the outer right edge is hot: an edge shared with another monitor would fire on
// every crossing. `qs -c bar ipc call quick toggle` opens it on the focused monitor.
Scope {
    id: root

    required property var modelData
    readonly property var screen: modelData   // null for a moment when its monitor is unplugged
    readonly property bool outerRight: !!screen && !Quickshell.screens.some(s => s.x === screen.x + screen.width
        && s.y < screen.y + screen.height && s.y + s.height > screen.y)

    property bool open: false
    property real edgeY: 0       // where the pointer touched the edge (panel-window y); spawn point
    property string section: ""  // "wifi" | "bt": the list pulled out under the tiles
    readonly property bool busy: out.pressed || mic.pressed || bri.pressed   // mid-drag: don't close

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var src: Pipewire.defaultAudioSource
    readonly property var bt: Bluetooth.defaultAdapter
    readonly property var btOn: Bluetooth.devices.values.filter(d => d.connected)
    readonly property var player: Mpris.players.values.find(p => p.isPlaying) ?? Mpris.players.values[0] ?? null
    readonly property var bat: UPower.displayDevice
    readonly property int batPct: Math.round(bat.percentage <= 1 ? bat.percentage * 100 : bat.percentage)

    PwObjectTracker { objects: [root.sink, root.src] }

    // ---- power-profiles-daemon (powerprofilesctl) ----
    // Current profile + whether the tool exists at all. `powerprofilesctl get` prints the
    // active profile (power-saver | balanced | performance) or fails if ppd/the CLI is
    // missing -- in which case ppdAvailable stays false and the tile degrades to a no-op.
    property string ppProfile: ""
    property bool ppAvailable: false
    readonly property var ppOrder: ["power-saver", "balanced", "performance"]
    function ppIcon(p) {
        return p === "power-saver" ? 0xF0335          // leaf
            : p === "performance" ? 0xF0E31           // rocket-launch
            : 0xF140B                                 // scale-balance (balanced)
    }
    function ppRefresh() { ppGet.running = true }
    function ppCycle() {
        if (!ppAvailable) return
        const i = ppOrder.indexOf(ppProfile)
        const next = ppOrder[(i + 1) % ppOrder.length]
        ppSet.command = ["powerprofilesctl", "set", next]
        ppSet.running = true
    }
    Process {
        id: ppGet
        command: ["powerprofilesctl", "get"]
        stdout: StdioCollector {
            onStreamFinished: { const p = text.trim(); if (p) { root.ppProfile = p; root.ppAvailable = true } }
        }
        onExited: code => { if (code !== 0) root.ppAvailable = false }
    }
    Process {
        id: ppSet
        onExited: root.ppRefresh()
    }
    // read the current profile when the panel opens (and once at startup)
    Component.onCompleted: ppRefresh()

    onOpenChanged: {
        Config.quickOpen = open
        if (open) {
            NetStats.refresh()
            ppRefresh()
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
        // the Wi-Fi password field needs the keyboard
        WlrLayershell.keyboardFocus: root.open && root.section === "wifi" ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

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

                // battery · lock · power
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Text {
                        visible: root.bat.isPresent
                        text: Util.pick(Util.batteryIcons, root.batPct)
                            + `  ${root.batPct}%`
                        color: Theme.mainFg
                        font { family: Theme.font; pixelSize: 13; bold: true }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: UPowerDeviceState.toString(root.bat.state)
                        color: Theme.mainFg
                        opacity: 0.6
                        font { family: Theme.font; pixelSize: 11 }
                        elide: Text.ElideRight
                    }
                    IconButton { icon: 0xF062E; onClicked: { root.open = false; Util.run("pavucontrol-qt -t 3 || pavucontrol -t 3") } }   // mixer
                    IconButton { icon: 0xF0341; onClicked: { root.open = false; Util.run("hyde-shell lockscreen.sh") } }
                    IconButton { icon: 0xF0425; onClicked: { root.open = false; Util.run("hyde-shell logoutlaunch 1") } }
                }

                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    columnSpacing: 8
                    rowSpacing: 8
                    Tile {
                        icon: NetStats.info.wifiOn ? 0xF05A9 : 0xF05AA
                        label: "Wi-Fi"
                        sub: !NetStats.info.wifiOn ? "Off" : NetStats.info.ssid || NetStats.info.conn || "On"
                        on: !!NetStats.info.wifiOn
                        more: true
                        expanded: root.section === "wifi"
                        onClicked: { Util.run(`nmcli radio wifi ${NetStats.info.wifiOn ? "off" : "on"}`); refreshSoon.restart() }
                        onExpand: root.section = expanded ? "" : "wifi"
                    }
                    Tile {
                        icon: root.bt?.enabled ? 0xF00AF : 0xF00B2
                        label: "Bluetooth"
                        sub: !root.bt ? "No adapter" : !root.bt.enabled ? "Off"
                            : root.btOn.length === 1 ? root.btOn[0].name : root.btOn.length ? `${root.btOn.length} devices` : "On"
                        on: !!root.bt?.enabled
                        more: !!root.bt
                        expanded: root.section === "bt"
                        onClicked: if (root.bt) root.bt.enabled = !root.bt.enabled
                        onExpand: root.section = expanded ? "" : "bt"
                    }
                    Tile {
                        icon: Config.dnd ? 0xF009B : 0xF009A
                        label: "Do not disturb"
                        sub: Config.dnd ? `${Config.held} held` : "Off"
                        on: Config.dnd
                        onClicked: Config.dnd = !Config.dnd
                    }
                    Tile {
                        icon: Config.caffeine ? 0xF0176 : 0xF06CA
                        label: "Caffeine"
                        sub: Config.caffeine ? "Staying awake" : "Off"
                        on: Config.caffeine
                        onClicked: Config.caffeine = !Config.caffeine
                    }
                    Tile {
                        // power-profiles-daemon: show current profile, click to cycle
                        icon: root.ppAvailable ? root.ppIcon(root.ppProfile) : 0xF06CA
                        label: "Power profile"
                        sub: !root.ppAvailable ? "Unavailable"
                            : root.ppProfile === "power-saver" ? "Power saver"
                            : root.ppProfile === "performance" ? "Performance" : "Balanced"
                        on: root.ppAvailable && root.ppProfile === "performance"
                        onClicked: root.ppCycle()
                    }
                    Tile {
                        // open the central settings GUI; close the quick panel first
                        icon: 0xF0493   // cog
                        label: "Settings"
                        sub: "Configure bar"
                        onClicked: { root.open = false; Config.openSettings() }
                    }
                }

                // pulled-out list for the Wi-Fi / Bluetooth tile. Never hidden (that would zero
                // the list's height it opens to): collapsed it is 0 tall and cancels its own spacing
                Item {
                    Layout.fillWidth: true
                    Layout.topMargin: -body.spacing
                    implicitHeight: root.section ? lists.implicitHeight + body.spacing : 0
                    Behavior on implicitHeight { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }
                    clip: true
                    Column {
                        id: lists
                        y: body.spacing
                        width: parent.width
                        spacing: 8
                        readonly property bool radioOn: root.section === "wifi" ? !!NetStats.info.wifiOn : !!root.bt?.enabled
                        WifiList {
                            visible: root.section === "wifi" && lists.radioOn
                            width: parent.width
                            active: root.open && root.section === "wifi" && lists.radioOn
                        }
                        BtList {
                            visible: root.section === "bt" && lists.radioOn
                            width: parent.width
                            active: root.open && root.section === "bt" && lists.radioOn
                        }
                        Text {
                            visible: !lists.radioOn
                            leftPadding: 9
                            text: root.section === "wifi" ? "Wi-Fi is off" : "Bluetooth is off"
                            color: Theme.mainFg
                            opacity: 0.45
                            font { family: Theme.font; pixelSize: 11 }
                        }
                        PillButton {
                            text: root.section === "wifi" ? Theme.g(0xF0493) + "  Connection editor" : Theme.g(0xF0493) + "  Bluetooth manager"
                            onClicked: { root.open = false; Util.run(root.section === "wifi" ? "nm-connection-editor" : "blueman-manager") }
                        }
                    }
                }

                SliderRow {
                    id: out
                    icon: root.sink?.audio?.muted ? 0xF0581 : Util.headphones(root.sink) ? 0xF02CB : 0xF057E
                    value: root.sink?.audio?.volume ?? 0
                    muted: !!root.sink?.audio?.muted
                    onIconClicked: if (root.sink?.audio) root.sink.audio.muted = !root.sink.audio.muted
                    onMoved: v => { if (root.sink?.audio) root.sink.audio.volume = v }
                }
                SliderRow {
                    id: mic
                    icon: root.src?.audio?.muted ? 0xF036D : 0xF036C
                    value: root.src?.audio?.volume ?? 0
                    muted: !!root.src?.audio?.muted
                    onIconClicked: if (root.src?.audio) root.src.audio.muted = !root.src.audio.muted
                    onMoved: v => { if (root.src?.audio) root.src.audio.volume = v }
                }
                SliderRow {
                    id: bri
                    icon: Brightness.pct < 50 ? 0xF00DF : 0xF00E0
                    value: Brightness.pct / 100
                    onMoved: v => Brightness.set(v * 100)
                }

                // now playing
                Rectangle {
                    visible: !!root.player
                    Layout.fillWidth: true
                    implicitHeight: 68
                    radius: 14
                    color: Qt.alpha(Theme.mainFg, 0.08)

                    // MPRIS position isn't pushed; ask for it while it's on screen
                    Timer {
                        interval: 1000
                        repeat: true
                        running: root.open && !!root.player?.isPlaying
                        onTriggered: root.player.positionChanged()
                    }

                    RowLayout {
                        anchors { fill: parent; margins: 10 }
                        spacing: 10
                        ClippingRectangle {
                            implicitWidth: 48
                            implicitHeight: 48
                            radius: 8
                            color: Qt.alpha(Theme.mainFg, 0.15)
                            Text {
                                anchors.centerIn: parent
                                visible: art.status !== Image.Ready
                                text: Theme.g(0xF075A)
                                color: Theme.mainFg
                                font { family: Theme.font; pixelSize: 22 }
                            }
                            Image {
                                id: art
                                anchors.fill: parent
                                source: root.player?.trackArtUrl ?? ""
                                fillMode: Image.PreserveAspectCrop
                                sourceSize: Qt.size(96, 96)
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Text {
                                Layout.fillWidth: true
                                text: root.player?.trackTitle || root.player?.identity || ""
                                color: Theme.mainFg
                                font { family: Theme.font; pixelSize: 12; bold: true }
                                elide: Text.ElideRight
                            }
                            Text {
                                Layout.fillWidth: true
                                text: root.player?.trackArtist ?? ""
                                color: Theme.actFg
                                font { family: Theme.font; pixelSize: 11 }
                                elide: Text.ElideRight
                            }
                            Rectangle {
                                Layout.fillWidth: true
                                Layout.topMargin: 4
                                implicitHeight: 3
                                radius: 2
                                color: Qt.alpha(Theme.mainFg, 0.18)
                                Rectangle {
                                    height: parent.height
                                    radius: 2
                                    color: Theme.mainFg
                                    width: root.player?.lengthSupported && root.player.length > 0
                                        ? parent.width * Math.min(1, root.player.position / root.player.length) : 0
                                }
                            }
                        }
                        IconButton { icon: 0xF04AE; enabled: !!root.player?.canGoPrevious; onClicked: root.player.previous() }
                        IconButton {
                            icon: root.player?.isPlaying ? 0xF03E4 : 0xF040A
                            size: 20
                            onClicked: root.player.togglePlaying()
                        }
                        IconButton { icon: 0xF04AD; enabled: !!root.player?.canGoNext; onClicked: root.player.next() }
                    }
                }
            }
        }

    }
    Timer { id: refreshSoon; interval: 700; onTriggered: NetStats.refresh() }

    component SliderRow: RowLayout {
        id: sr
        property int icon
        property real value
        property bool muted: false
        readonly property bool pressed: slider.pressed
        signal iconClicked()
        signal moved(real v)

        Layout.fillWidth: true
        spacing: 10
        IconButton { icon: sr.icon; dim: sr.muted; onClicked: sr.iconClicked() }
        Slider {
            id: slider
            Layout.fillWidth: true
            value: sr.value
            dim: sr.muted
            onMoved: v => sr.moved(v)
        }
        Text {
            Layout.preferredWidth: 38
            horizontalAlignment: Text.AlignRight
            text: Math.round(sr.value * 100) + "%"
            color: sr.muted ? Qt.alpha(Theme.mainFg, 0.5) : Theme.actFg
            font { family: Theme.font; pixelSize: 12; bold: true }
        }
    }
}
