import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Particles
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import Quickshell.Widgets
import qs
import qs.components

// Now Playing panel, shown while the pointer rests on the bar's media pill
// (modules/Media.qml) or with `qs -c bar ipc call media toggle`. Pours out of the point
// where the pointer rested, and on leaving vanishes from the point where the pointer
// went out, a hole spreading from there (Player.origin, components/LiquidCard). A record
// (components/Disc), or another centrepiece (Settings.panelCenter), sits inside a radial
// spectrum (components/Ring, styled by Settings.panelStyle) that throws sparks on the beat; it is all tinted from the cover art
// (Player palette) over a blurred copy of it. Click the record to play/pause, scroll it
// to scrub 5s. Closes once the pointer is on neither the pill nor the card.
Scope {
    IpcHandler {
        target: "media"
        function toggle(): void {
            const name = Hyprland.focusedMonitor?.name ?? Quickshell.screens[0].name
            const s = Quickshell.screens.find(s => s.name === name) ?? Quickshell.screens[0]
            const x = Player.pillX(s.name)
            Player.toggle(s.name, x >= 0 ? x : s.width / 2)   // under the pill, or centred without one
        }
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win
            required property var modelData
            readonly property var player: Player.player
            readonly property bool open: Player.open && Player.screen === modelData.name && !!player

            screen: modelData
            visible: card.progress > 0
            anchors { top: true; left: true }
            margins.top: Config.height + 4
            margins.left: Math.max(8, Math.min(modelData.width - width - 8, Player.anchorX - width / 2))
            implicitWidth: card.width + 48
            implicitHeight: card.height + 48
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            mask: Region { item: card }
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "nowplaying"

            onOpenChanged: {
                // pour out of / drain into Player.origin (on screen; the card is in window coordinates)
                const p = Qt.point(Player.origin.x - win.margins.left, Player.origin.y - win.margins.top)
                if (open) {
                    card.pour(p)
                    if (!Player.pillHovered) { closer.interval = 3000; closer.restart() }   // IPC: time to move the pointer onto it
                    Player.refreshPos()
                } else card.drain(p)
            }
            onPlayerChanged: if (!player) Player.open = false

            Timer { id: closer; onTriggered: if (!hover.hovered && !Player.pillHovered && !Player.pinned) Player.open = false }
            Connections {
                target: Player
                function onPillHoveredChanged() {
                    if (Player.pillHovered) closer.stop()
                    else if (win.open && !hover.hovered) { closer.interval = 300; closer.restart() }   // time to cross the gap
                }
            }
            HoverHandler {
                id: hover
                property point last   // pointer position in the window, kept for where it leaves
                onPointChanged: if (hovered) last = point.position
                onHoveredChanged: {
                    if (hovered) closer.stop()
                    else if (win.open) {
                        Player.origin = Qt.point(win.margins.left + last.x, win.margins.top + last.y)   // drains into here
                        closer.interval = 150   // just enough to cross back to the pill
                        closer.restart()
                    }
                }
            }

            function fmt(s) { return `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, "0")}` }

            LiquidCard {
                id: card
                property real kick: 0   // 0..1, jumps on a beat and eases off
                // 1 playing, 0 paused: the ring and its glow sink back while paused
                property real live: Player.playing ? 1 : 0
                Behavior on live { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
                readonly property real len: Player.length
                readonly property real pos: Player.pos
                readonly property real frac: Player.frac

                x: 24
                y: 4
                width: 360
                height: info.y + info.implicitHeight + 22
                radius: Theme.radius + 9
                color: Theme.mainBg
                border.color: Qt.alpha(Player.c1, 0.3)
                border.width: 1
                glow: Player.c1

                NumberAnimation { id: kickAnim; target: card; property: "kick"; to: 0; duration: 380; easing.type: Easing.OutCubic }
                Connections {
                    target: Visualizer
                    enabled: win.visible
                    function onBeat(s) {
                        kickAnim.stop()
                        card.kick = s
                        kickAnim.start()
                        live.item?.sparks.burst(Math.round(10 + s * 30))
                    }
                }

                // blurred cover behind everything, darkened towards the controls
                Art {
                    id: bg
                    anchors.fill: parent
                    sourceSize: Qt.size(160, 160)   // blurred anyway
                    visible: false
                }
                MultiEffect {
                    anchors.fill: parent
                    source: bg
                    autoPaddingEnabled: false
                    blurEnabled: true
                    blur: 1
                    blurMax: 64
                    saturation: 0.6
                    brightness: -0.45
                    opacity: bg.ready ? 0.85 : 0
                    Behavior on opacity { NumberAnimation { duration: 700 } }
                }
                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop { position: 0; color: Qt.alpha(Theme.mainBg, 0.5) }
                        GradientStop { position: 0.65; color: Qt.alpha(Theme.mainBg, 0.7) }
                        GradientStop { position: 1; color: Qt.alpha(Theme.mainBg, 0.92) }
                    }
                }

                // header: the player, or with several around, a chip each to pick which one
                // the pill and this panel follow; the album faded on the right
                Row {
                    id: players
                    readonly property var list: Mpris.players.values
                    x: 12
                    y: 9
                    spacing: 4
                    Repeater {
                        model: players.list
                        Rectangle {
                            id: chip
                            required property var modelData
                            readonly property bool current: modelData === win.player
                            readonly property bool many: players.list.length > 1
                            visible: many || current
                            width: chipText.implicitWidth + 12
                            height: 17
                            radius: 8.5
                            color: many && current ? Qt.alpha(Player.c1, 0.16) : chipHover.hovered && many ? Qt.alpha("white", 0.08) : "transparent"
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Text {
                                id: chipText
                                anchors.centerIn: parent
                                text: (chip.modelData.identity ?? "").toUpperCase()
                                color: chip.current ? Qt.alpha(Player.c1, 0.85) : Qt.alpha(Theme.menuFg, 0.45)
                                font { family: Theme.font; pixelSize: 9; letterSpacing: 2.5; bold: true }
                            }
                            HoverHandler { id: chipHover; enabled: chip.many; cursorShape: Qt.PointingHandCursor }
                            TapHandler { enabled: chip.many; onTapped: Player.picked = chip.modelData }
                        }
                    }
                }
                Text {
                    anchors { left: players.right; leftMargin: 12; right: parent.right; rightMargin: 18; verticalCenter: players.verticalCenter }
                    horizontalAlignment: Text.AlignRight
                    elide: Text.ElideRight
                    text: win.player?.trackAlbum || win.player?.metadata?.["xesam:album"] || ""
                    color: Qt.alpha(Theme.menuFg, 0.45)
                    font { family: Theme.font; pixelSize: 10 }
                }

                Item {
                    id: stage
                    // Settings.panelLayout: 0 turntable (record in a radial spectrum), 1 poster,
                    // 2 waveform, 3 LED matrix, 4 aurora; each sets its own height
                    readonly property int layout: Settings.panelLayout
                    width: 340
                    height: [340, 330, 150, 210, 200][layout] ?? 340
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 12

                    // the live parts exist only while the panel is up
                    Loader {
                        id: live
                        anchors.fill: parent
                        active: win.visible && stage.layout === 0
                        sourceComponent: Item {
                            property alias sparks: sparks
                            // bass bloom behind the record
                            Rectangle {
                                anchors.centerIn: parent
                                width: 250
                                height: 250
                                radius: 125
                                color: Player.c2
                                opacity: (0.1 + Visualizer.bass * 0.3 + card.kick * 0.25) * (0.3 + 0.7 * card.live)
                                layer.enabled: true
                                layer.effect: MultiEffect { blurEnabled: true; blur: 1; blurMax: 64 }
                            }

                            // sparks off the ring: a trickle with the bass, a burst on each beat
                            ParticleSystem { id: sparkSys; running: win.visible }
                            ImageParticle {
                                system: sparkSys
                                source: "qrc:///particleresources/glowdot.png"
                                color: Player.c1
                                colorVariation: 0.15
                                alpha: 0.9
                            }
                            Emitter {
                                id: sparks
                                system: sparkSys
                                anchors.centerIn: parent
                                width: 236
                                height: 236
                                shape: EllipseShape { fill: false }
                                emitRate: Visualizer.active ? 3 + Visualizer.bass * 30 : 0
                                lifeSpan: 1300
                                lifeSpanVariation: 400
                                size: 9
                                sizeVariation: 5
                                endSize: 1
                                velocity: TargetDirection { targetItem: sparks; magnitude: -80; magnitudeVariation: 50 }
                            }
                            Friction { system: sparkSys; factor: 0.8 }

                            Ring {
                                anchors.fill: parent
                                style: Settings.panelStyle
                                inner: 116
                                amp: 50
                                spokes: 120
                                thick: 0.5
                                halo: 0.8 + card.kick * 0.4
                                opacity: 0.35 + 0.65 * card.live
                            }
                        }
                    }

                    // the centrepiece (Settings.panelCenter): a record, the cover as a card, or
                    // the cover as a round orb.
                    // Each stays inside the ring's inner radius (116).
                    Loader {
                        anchors.centerIn: parent
                        active: stage.layout === 0
                        sourceComponent: [vinyl, coverCard, coverOrb][Settings.panelCenter] ?? vinyl
                    }
                    // the other layouts: the whole stage is theirs
                    Loader {
                        anchors.fill: parent
                        active: win.visible && stage.layout > 0
                        sourceComponent: [null, poster, waveform, matrix, aurora][stage.layout] ?? null
                    }
                    Component {
                        id: poster
                        // the cover big and edge to edge, the spectrum rising over its foot
                        Item {
                            Item {
                                width: 300
                                height: 300
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 22   // clear of the header row
                                scale: 1 + card.kick * 0.015
                                layer.enabled: true
                                layer.effect: MultiEffect {
                                    shadowEnabled: true
                                    shadowColor: Qt.alpha(Player.c2, 0.7)
                                    shadowBlur: 1
                                    blurMax: 40
                                    shadowVerticalOffset: 8
                                    saturation: -0.8 * (1 - card.live)
                                }
                                ClippingRectangle {
                                    anchors.fill: parent
                                    radius: 18
                                    color: Qt.alpha(Player.c2, 0.35)
                                    Text {
                                        anchors.centerIn: parent
                                        visible: !posterArt.ready
                                        text: Theme.g(0xF075A)
                                        color: Player.c1
                                        font { family: Theme.font; pixelSize: 110 }
                                    }
                                    Art { id: posterArt; anchors.fill: parent; sourceSize: Qt.size(600, 600) }
                                    Rectangle {   // the foot darkens so the bars read over any cover
                                        anchors.bottom: parent.bottom
                                        width: parent.width
                                        height: 140
                                        gradient: Gradient {
                                            GradientStop { position: 0; color: "transparent" }
                                            GradientStop { position: 1; color: Qt.alpha("black", 0.75) }
                                        }
                                    }
                                    Spectrum {
                                        anchors.bottom: parent.bottom
                                        width: parent.width
                                        height: 120
                                        style: 0
                                        glow: card.live
                                        kick: card.kick
                                    }
                                }
                                Rectangle {
                                    anchors.fill: parent
                                    radius: 18
                                    color: "transparent"
                                    border.color: Qt.alpha("white", 0.12)
                                }
                            }
                        }
                    }
                    Component {
                        id: waveform
                        // no art: a wide waveform, played part lit; click it to seek
                        Item {
                            Spectrum {
                                anchors.centerIn: parent
                                width: parent.width
                                height: 130
                                style: 1
                                frac: card.frac
                                glow: card.live
                                kick: card.kick
                            }
                        }
                    }
                    Component {
                        id: matrix
                        Item {
                            Spectrum {
                                anchors.fill: parent
                                anchors.margins: 8
                                style: 2
                                glow: card.live
                                kick: card.kick
                            }
                        }
                    }
                    Component {
                        id: aurora
                        Spectrum {
                            style: 3
                            glow: card.live
                            kick: card.kick
                        }
                    }
                    Component {
                        id: vinyl
                        Disc {
                            spinning: win.visible
                            width: 200
                            height: 200
                            scale: 1 + card.kick * 0.035
                        }
                    }
                    Component {
                        id: coverCard
                        Item {
                            width: 160
                            height: 160
                            scale: 1 + card.kick * 0.03
                            layer.enabled: true
                            layer.effect: MultiEffect {
                                shadowEnabled: true
                                shadowColor: Qt.alpha(Player.c2, 0.8)
                                shadowBlur: 1
                                blurMax: 32
                                shadowVerticalOffset: 6
                                saturation: -0.8 * (1 - card.live)
                            }
                            ClippingRectangle {
                                anchors.fill: parent
                                radius: 16
                                color: Qt.alpha(Player.c2, 0.35)
                                Text {
                                    anchors.centerIn: parent
                                    visible: !cardArt.ready
                                    text: Theme.g(0xF075A)
                                    color: Player.c1
                                    font { family: Theme.font; pixelSize: 64 }
                                }
                                Art { id: cardArt; anchors.fill: parent; sourceSize: Qt.size(320, 320) }
                                Rectangle {   // glass sheen across the top
                                    anchors.fill: parent
                                    gradient: Gradient {
                                        GradientStop { position: 0; color: Qt.alpha("white", 0.14) }
                                        GradientStop { position: 0.45; color: "transparent" }
                                    }
                                }
                            }
                            Rectangle {
                                anchors.fill: parent
                                radius: 16
                                color: "transparent"
                                border.color: Qt.alpha("white", 0.14)
                            }
                        }
                    }
                    Component {
                        id: coverOrb
                        Item {
                            width: 208
                            height: 208
                            scale: 1 + Visualizer.bass * 0.025 * card.live + card.kick * 0.025
                            layer.enabled: true
                            layer.effect: MultiEffect { saturation: -0.8 * (1 - card.live) }
                            ClippingRectangle {
                                anchors.fill: parent
                                radius: width / 2
                                color: Qt.alpha(Player.c2, 0.35)
                                Text {
                                    anchors.centerIn: parent
                                    visible: !orbArt.ready
                                    text: Theme.g(0xF075A)
                                    color: Player.c1
                                    font { family: Theme.font; pixelSize: 80 }
                                }
                                Art { id: orbArt; anchors.fill: parent; sourceSize: Qt.size(416, 416) }
                                Rectangle {   // light from above, darker towards the bottom: a sphere, not a sticker
                                    anchors.fill: parent
                                    gradient: Gradient {
                                        GradientStop { position: 0; color: Qt.alpha("white", 0.16) }
                                        GradientStop { position: 0.4; color: "transparent" }
                                        GradientStop { position: 1; color: Qt.alpha("black", 0.3) }
                                    }
                                }
                            }
                            Rectangle {   // glass rim
                                anchors.fill: parent
                                radius: width / 2
                                color: "transparent"
                                border.width: 1.5
                                border.color: Qt.alpha(Player.c1, 0.35)
                            }
                        }
                    }
                    // click: play/pause (on the waveform: seek there); scroll: scrub 5s
                    MouseArea {
                        anchors.centerIn: parent
                        width: stage.layout === 0 ? 200 : stage.width
                        height: stage.layout === 0 ? 200 : stage.height
                        cursorShape: Qt.PointingHandCursor
                        property real wheelAcc: 0
                        onClicked: e => {
                            if (stage.layout === 2 && win.player?.canSeek && card.len > 0)
                                win.player.position = Math.max(0, Math.min(1, e.x / width)) * card.len
                            else win.player?.togglePlaying()
                        }
                        onWheel: e => {
                            wheelAcc += e.angleDelta.y
                            if (Math.abs(wheelAcc) < 120 || !win.player?.canSeek) return
                            win.player.position = Math.max(0, Math.min(card.len, card.pos + (wheelAcc > 0 ? 5 : -5)))
                            wheelAcc = 0
                        }
                    }
                }

                ColumnLayout {
                    id: info
                    anchors { left: parent.left; right: parent.right; top: stage.bottom; topMargin: stage.layout === 0 ? -18 : 10; leftMargin: 24; rightMargin: 24 }
                    spacing: 3

                    Swap {
                        id: names
                        Layout.fillWidth: true
                        implicitHeight: nameCol.implicitHeight
                        value: ({ title: win.player?.trackTitle || win.player?.identity || "", artist: win.player?.trackArtist ?? "" })
                        Column {
                            id: nameCol
                            width: parent.width
                            spacing: 3
                            Text {
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                text: names.shown?.title ?? ""
                                color: Theme.menuFg
                                font { family: Theme.font; pixelSize: 15; bold: true }
                            }
                            Text {
                                width: parent.width
                                horizontalAlignment: Text.AlignHCenter
                                elide: Text.ElideRight
                                text: names.shown?.artist ?? ""
                                color: Player.c1
                                font { family: Theme.font; pixelSize: 12 }
                            }
                        }
                    }
                    // elapsed | seek bar | remaining; click or drag the bar to seek
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 10
                        spacing: 10
                        visible: card.len > 0
                        Text {
                            text: win.fmt(seek.dragging ? seek.at * card.len : card.pos)
                            color: Qt.alpha(Theme.menuFg, 0.6)
                            font { family: Theme.font; pixelSize: 10 }
                        }
                        Item {
                            id: seek
                            readonly property bool dragging: seekArea.pressed
                            readonly property bool hot: seekArea.containsMouse || dragging
                            property real at: 0   // 0..1 under the pointer while dragging
                            property real over: 0 // 0..1 under the pointer while hovering
                            readonly property real shown: dragging ? at : card.frac
                            Layout.fillWidth: true
                            implicitHeight: 14

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width
                                height: seek.hot ? 5 : 3
                                radius: height / 2
                                color: Qt.alpha("white", 0.12)
                                Behavior on height { NumberAnimation { duration: 120 } }
                            }
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.max(height, parent.width * seek.shown)
                                height: seek.hot ? 5 : 3
                                radius: height / 2
                                color: Player.c1
                                Behavior on height { NumberAnimation { duration: 120 } }
                                layer.enabled: true
                                layer.effect: MultiEffect { shadowEnabled: true; shadowColor: Player.c1; shadowOpacity: 0.8; shadowBlur: 0.6; blurMax: 12; shadowVerticalOffset: 0 }
                            }
                            Rectangle {   // knob
                                property real d: seek.hot ? 12 : 8
                                x: parent.width * seek.shown - d / 2
                                anchors.verticalCenter: parent.verticalCenter
                                width: d
                                height: d
                                radius: d / 2
                                color: Qt.lighter(Player.c1, 1.3)
                                Behavior on d { NumberAnimation { duration: 120 } }
                            }
                            Rectangle {   // where a click lands
                                readonly property real f: seek.dragging ? seek.at : seek.over
                                visible: seek.hot && card.len > 0
                                x: Math.max(-14, Math.min(parent.width - width + 14, parent.width * f - width / 2))
                                y: -height - 4
                                width: tip.implicitWidth + 12
                                height: 18
                                radius: 6
                                color: Qt.alpha(Theme.mainBg, 0.9)
                                border.color: Qt.alpha(Player.c1, 0.4)
                                Text {
                                    id: tip
                                    anchors.centerIn: parent
                                    text: win.fmt(parent.f * card.len)
                                    color: Theme.menuFg
                                    font { family: Theme.font; pixelSize: 10 }
                                }
                            }
                            MouseArea {
                                id: seekArea
                                anchors.fill: parent
                                anchors.margins: -4
                                hoverEnabled: true
                                enabled: !!win.player?.canSeek
                                cursorShape: Qt.PointingHandCursor
                                onPressed: e => seek.at = Math.max(0, Math.min(1, (e.x - 4) / seek.width))
                                onPositionChanged: e => {
                                    seek.over = Math.max(0, Math.min(1, (e.x - 4) / seek.width))
                                    if (pressed) seek.at = seek.over
                                }
                                onReleased: win.player.position = seek.at * card.len
                            }
                        }
                        Text {
                            text: "-" + win.fmt(Math.max(0, card.len - (seek.dragging ? seek.at * card.len : card.pos)))
                            color: Qt.alpha(Theme.menuFg, 0.6)
                            font { family: Theme.font; pixelSize: 10 }
                        }
                    }
                    RowLayout {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 2
                        spacing: 22
                        Btn { icon: 0xF04AE; enabled: !!win.player?.canGoPrevious; onClicked: win.player.previous() }
                        Btn { icon: Player.playing ? 0xF03E4 : 0xF040A; big: true; onClicked: win.player.togglePlaying() }
                        Btn { icon: 0xF04AD; enabled: !!win.player?.canGoNext; onClicked: win.player.next() }
                    }
                }
            }
        }
    }

    component Btn: Rectangle {
        id: b
        property int icon
        property bool big: false
        signal clicked()

        implicitWidth: big ? 52 : 40
        implicitHeight: implicitWidth
        radius: width / 2
        opacity: enabled ? 1 : 0.35
        color: big ? Player.c1 : bh.hovered && enabled ? Qt.alpha("white", 0.12) : "transparent"
        Behavior on color { ColorAnimation { duration: 150 } }
        scale: bt.pressed ? 0.85 : bh.hovered && enabled ? 1.08 : 1
        Behavior on scale { SpringAnimation { spring: 7; damping: 0.3; epsilon: 0.002 } }
        layer.enabled: big
        layer.effect: MultiEffect { shadowEnabled: true; shadowColor: Player.c1; shadowOpacity: 0.6; shadowBlur: 0.8; blurMax: 24; shadowVerticalOffset: 0 }
        HoverHandler { id: bh; cursorShape: Qt.PointingHandCursor }
        TapHandler { id: bt; onTapped: b.clicked() }
        Text {
            anchors.centerIn: parent
            text: Theme.g(b.icon)
            color: b.big ? Theme.mainBg : Theme.menuFg
            font { family: Theme.font; pixelSize: b.big ? 24 : 21 }
        }

    }
}
