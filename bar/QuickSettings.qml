import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
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
// (components/Dissolve.qml); once the pointer leaves, a hole opens where it went out and
// eats the panel away (the Now Playing panel's animation). The Wi-Fi and Bluetooth tiles'
// chevrons pull out a device list under the tiles.
// Only the outer right edge is hot: an edge shared with another monitor would fire on
// every crossing. `qs -c bar ipc call quick toggle` opens it on the focused monitor.
Scope {
    id: root

    required property var modelData
    readonly property var screen: modelData
    readonly property bool outerRight: !Quickshell.screens.some(s => s.x === screen.x + screen.width
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

    onOpenChanged: {
        Config.quickOpen = open
        if (open) {
            NetStats.refresh()
            card.seed = Math.random() * 100
            card.spawn = Qt.vector2d(1 + 8 / card.width, Math.max(0, Math.min(1, root.edgeY / card.height)))
            card.closing = false
            burn.stop()
            form.restart()
        } else {
            // settled: eat it away from where the pointer left; still forming: drain it back
            if (card.progress >= 1) {
                card.spawn = Qt.vector2d((hover.last.x - card.x) / card.width, hover.last.y / card.height)
                card.closing = true
            }
            form.stop()
            burn.restart()
        }
    }
    // same timing as the Now Playing panel
    NumberAnimation { id: form; target: card; property: "progress"; to: 1; duration: 700; easing.type: Easing.OutQuart }
    NumberAnimation { id: burn; target: card; property: "progress"; to: 0; duration: 420; easing.type: Easing.OutCubic; onFinished: root.section = "" }
    Connections {
        target: Config
        function onToggleQuick() {
            const focused = Hyprland.focusedMonitor?.name ?? Quickshell.screens[0].name
            if (focused === root.screen.name) { root.edgeY = 0; root.open = !root.open; if (root.open) closer.stop() }
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
        visible: root.outerRight
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
        implicitHeight: root.screen.height - Config.height - 6
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

        // analytic shadow: no offscreen blur to redo on every frame of a list sliding open
        RectangularShadow {
            anchors.fill: card
            radius: card.radius
            opacity: Math.max(0, (card.progress - 0.8) / 0.2)   // only once the blob has filled the card
            color: Qt.alpha("black", 0.5)
            blur: 32
            offset.y: 5
        }

        Rectangle {
            id: card
            readonly property real fullW: 348
            readonly property real fullH: body.implicitHeight + 32
            property real progress: 0
            property real seed: 0
            property vector2d spawn: Qt.vector2d(1, 0)   // Dissolve origin, frozen per transition
            property bool closing: false
            visible: progress > 0

            x: win.width - width - 8
            width: fullW
            height: fullH
            radius: Theme.radius + 5
            color: Qt.alpha(Theme.mainBg, 0.97)
            border.color: Qt.alpha(Theme.mainFg, 0.35)
            border.width: 1
            // the effect only runs mid-transition; settled, the card renders directly (crisp text)
            layer.enabled: progress < 1
            // opens at the screen edge (8px right of the card) where the pointer was
            layer.effect: Dissolve {
                progress: card.progress
                seed: card.seed
                origin: card.spawn
                hole: card.closing ? 1 : 0
            }

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
                        text: Util.pick([0xF008E, 0xF007A, 0xF007B, 0xF007C, 0xF007D, 0xF007E, 0xF007F, 0xF0080, 0xF0081, 0xF0082, 0xF0079], root.batPct)
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

    // Toggle tile. Turning on floods it with the accent from where you clicked, like
    // liquid filling it; turning off drains back into that point.
    component Tile: ClippingRectangle {
        id: t
        property int icon
        property string label
        property string sub: ""
        property bool on: false
        property bool more: false      // has a list to pull out: the right end is a chevron
        property bool expanded: false
        property point origin: Qt.point(width / 2, height / 2)
        readonly property real reach: Math.hypot(Math.max(origin.x, width - origin.x), Math.max(origin.y, height - origin.y))
        property color ink: on ? Theme.mainBg : Theme.mainFg
        signal clicked()
        signal expand()

        Layout.fillWidth: true
        implicitHeight: 54
        radius: 14
        color: th.hovered ? Qt.alpha(Theme.mainFg, 0.16) : Qt.alpha(Theme.mainFg, 0.08)
        Behavior on color { ColorAnimation { duration: 150 } }
        // press only: a resting hover scale left the tile's text resampled (soft) the whole time
        scale: tap.pressed ? 0.95 : 1
        Behavior on scale { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        Behavior on ink { ColorAnimation { duration: 260 } }

        Rectangle {
            property real r: t.on ? t.reach : 0
            Behavior on r { NumberAnimation { duration: 460; easing.type: Easing.OutCubic } }
            x: t.origin.x - r
            y: t.origin.y - r
            width: 2 * r
            height: 2 * r
            radius: r
            color: th.hovered ? Qt.lighter(Theme.actBg, 1.08) : Theme.actBg
            Behavior on color { ColorAnimation { duration: 150 } }
        }

        HoverHandler { id: th; cursorShape: Qt.PointingHandCursor }
        TapHandler {
            id: tap
            onTapped: {
                if (t.more && tap.point.position.x > t.width - 34) return t.expand()
                t.origin = tap.point.position
                t.clicked()
            }
        }
        Text {
            visible: t.more
            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
            text: Theme.g(0xF0140)   // chevron-down
            color: t.ink
            opacity: t.expanded ? 1 : 0.6
            rotation: t.expanded ? 180 : 0
            Behavior on rotation { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
            font { family: Theme.font; pixelSize: 16 }
        }

        Row {
            anchors.verticalCenter: parent.verticalCenter
            x: 12
            spacing: 10
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: Theme.g(t.icon)
                color: t.ink
                font { family: Theme.font; pixelSize: 18 }
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                Text {
                    text: t.label
                    color: t.ink
                    font { family: Theme.font; pixelSize: 12; bold: true }
                }
                Text {
                    width: t.width - 52 - (t.more ? 24 : 0)
                    text: t.sub
                    color: t.ink
                    opacity: 0.75
                    elide: Text.ElideRight
                    font { family: Theme.font; pixelSize: 10 }
                }
            }
        }
    }

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

    component IconButton: Rectangle {
        id: ib
        property int icon
        property int size: 16
        property bool dim: false
        signal clicked()

        implicitWidth: 30
        implicitHeight: 30
        radius: 15
        opacity: enabled ? 1 : 0.35
        color: ih.hovered && enabled ? Qt.alpha(Theme.mainFg, 0.18) : "transparent"
        Behavior on color { ColorAnimation { duration: 120 } }
        scale: ibTap.pressed ? 0.86 : 1
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        HoverHandler { id: ih; cursorShape: Qt.PointingHandCursor }
        TapHandler { id: ibTap; onTapped: ib.clicked() }
        Text {
            anchors.centerIn: parent
            text: Theme.g(ib.icon)
            color: ib.dim ? Qt.alpha(Theme.mainFg, 0.5) : Theme.mainFg
            font { family: Theme.font; pixelSize: ib.size }
        }
    }
}
