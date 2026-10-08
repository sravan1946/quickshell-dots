import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import qs
import qs.components

// Now playing pill. The pill itself is the visualizer (shaders/pill.frag): an EQ behind
// frosted glass glowing up from its floor, the track progress along its bottom edge and a
// faint rim flash on the beat, all in the cover art's colours (Player palette). The cover
// glows with the bass and greys out on pause; titles slide in on a new track and scroll,
// edge-faded, when they don't fit. Resting the pointer on it shows the Now Playing panel
// (NowPlaying.qml) below; click plays/pauses.
// Folds away while no player is around. Wants a pill with padL/padR 0 (Config.qml).
Item {
    id: m
    readonly property var player: Player.player
    readonly property string screenName: QsWindow.window?.screen?.name ?? ""
    readonly property string title: player?.trackTitle || player?.identity || ""
    // beat response, run on Visualizer's frame clock (no animation timers): each of the
    // last four beats' rim lights goes 0 -> 1 over 650 ms (`sweeps`), `kick` is a quick
    // 0..1 punch for the cover from the newest one. The bar's beat wave leaves from here too.
    readonly property real since: Visualizer.t - Visualizer.beatAt
    readonly property vector4d sweeps: {
        const a = Visualizer.beatAts, t = Visualizer.t
        const f = at => Math.min(1, Math.max(0, (t - at) / 0.65))
        return Qt.vector4d(f(a.x), f(a.y), f(a.z), f(a.w))
    }
    readonly property real kick: Visualizer.beatStrength * Math.pow(Math.max(0, 1 - since / 0.34), 2)
    // 0 paused .. 1 playing, eased: everything that dims on pause follows this one
    property real live: Player.playing ? 1 : 0
    Behavior on live { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }

    // the beat wave starts from the pill's centre: tell the bar, and the window border by screen
    Connections {
        target: Visualizer
        function onBeat() {
            const w = m.QsWindow.window
            const x = m.mapToItem(null, m.width / 2, 0).x
            if (w && "beatX" in w) w.beatX = x
            if (w?.screen) Visualizer.origins[w.screen.name] = w.screen.x + x
        }
    }

    readonly property real textMin: 130   // short titles still get a pill wide enough to show the spectrum
    readonly property real textMax: 190
    readonly property real textW: Math.max(textMin, Math.min(line.implicitWidth, textMax))
    height: parent ? parent.height : 24
    implicitWidth: player ? 32 + textW + 14 : 0
    Behavior on implicitWidth { NumberAnimation { duration: 380; easing.type: Easing.OutQuint } }

    // a short dwell, so sweeping the pointer across the bar doesn't pop it open
    Timer {
        id: dwell
        interval: Settings.hoverDelay
        onTriggered: {
            Player.show(m.screenName, m.mapToItem(null, m.width / 2, 0).x, pillArea.mapToItem(null, pillArea.mouseX, pillArea.mouseY))
            Player.pillHovered = true
        }
    }

    // visuals clipped to the pill while its width animates; the pointer area below sits
    // outside the clip so it can reach over the bar edges (Config.pillInset)
    Item {
        anchors.fill: parent
        clip: true

        ShaderEffect {
            anchors.fill: parent
            readonly property vector2d res: Qt.vector2d(width, height)
            readonly property real radius: Math.min(Theme.radius, height / 2)
            readonly property real pitch: 4
            readonly property real frac: Player.frac
            readonly property vector2d textSpan: Qt.vector2d(box.x, box.x + Math.min(line.implicitWidth, box.width))
            readonly property vector4d sweeps: m.sweeps
            readonly property vector4d punches: Visualizer.beatPows
            readonly property real glow: 0.3 + 0.7 * m.live
            readonly property color bg: Theme.mainBg
            readonly property color c1: Player.c1
            readonly property color c2: Player.c2
            readonly property color c3: Player.c3
            readonly property vector4d l0: Visualizer.l0
            readonly property vector4d l1: Visualizer.l1
            readonly property vector4d l2: Visualizer.l2
            readonly property vector4d l3: Visualizer.l3
            readonly property vector4d l4: Visualizer.l4
            readonly property vector4d l5: Visualizer.l5
            readonly property vector4d l6: Visualizer.l6
            readonly property vector4d l7: Visualizer.l7
            // Qt caches shaders by URL across reloads: bump ?v= after shaders/build.sh
            fragmentShader: Qt.resolvedUrl("../shaders/pill.frag.qsb?v=11")
        }

        // cover: a tinted glow behind it breathes with the bass
        Rectangle {
            anchors.centerIn: cover
            width: cover.width
            height: cover.height
            radius: cover.radius
            color: Player.c1
            opacity: m.live * (0.2 + Visualizer.bass * 0.6 + m.kick * 0.3)
            layer.enabled: true
            layer.effect: MultiEffect { blurEnabled: true; blur: 1; blurMax: 12 }
        }
        ClippingRectangle {
            id: cover
            x: 4
            anchors.verticalCenter: parent.verticalCenter
            width: 18
            height: 18
            radius: 6
            color: Qt.alpha(Player.c2, 0.35)
            scale: 1 + m.kick * 0.1
            layer.enabled: true
            layer.effect: MultiEffect {
                saturation: -0.9 * (1 - m.live)
                brightness: -0.15 * (1 - m.live)
            }
            Text {
                anchors.centerIn: parent
                visible: !art.ready
                text: Theme.g(0xF075A)
                color: Player.c1
                font { family: Theme.font; pixelSize: 11 }
            }
            Art {
                id: art
                anchors.fill: parent
                sourceSize: Qt.size(54, 54)
            }
            Rectangle {   // hairline inner border, keeps dark covers from melting into the pill
                anchors.fill: parent
                radius: cover.radius
                color: "transparent"
                border.color: Qt.alpha("white", 0.12)
                border.width: 1
            }
        }

        // title • artist, edge-faded and scrolling when it doesn't fit
        Item {
            id: box
            x: 30
            width: m.textW
            height: parent.height
            clip: true
            // a tight dark shadow under the letters; edge fade only while it scrolls
            layer.enabled: true
            layer.effect: MultiEffect {
                autoPaddingEnabled: false   // keep the fade mask aligned with the box
                shadowEnabled: true
                shadowColor: "black"
                shadowOpacity: 0.85
                shadowBlur: 0.25
                blurMax: 6
                shadowHorizontalOffset: 0
                shadowVerticalOffset: 0.5
                maskEnabled: line.overflow > 0
                maskSource: fadeMask
                maskThresholdMin: 0
                maskSpreadAtMin: 1
            }

            Swap {
                id: swap
                width: parent.width
                height: parent.height
                value: ({ title: m.title, artist: m.player?.trackArtist ?? "" })
                onSwapped: {
                    marquee.stop()
                    line.x = 0
                    if (line.overflow > 0) marquee.restart()
                }

                Row {
                    id: line
                    readonly property real overflow: Math.max(0, implicitWidth - m.textMax)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 5

                    Text {
                        text: swap.shown?.title ?? ""
                        color: Qt.alpha(Theme.menuFg, 0.5 + 0.5 * m.live)
                        font { family: Theme.font; pixelSize: Theme.fontSize + 1; bold: true }
                    }
                    Text {
                        visible: !!swap.shown?.artist
                        text: "•"
                        color: Qt.alpha(Theme.menuFg, 0.35)
                        font { family: Theme.font; pixelSize: Theme.fontSize }
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        visible: !!swap.shown?.artist
                        text: swap.shown?.artist ?? ""
                        // a light tint of the accent: related to the bars, never the same colour as them
                        color: Qt.alpha(Qt.tint(Theme.menuFg, Qt.alpha(Player.c1, 0.35)), 0.5 + 0.4 * m.live)
                        font { family: Theme.font; pixelSize: Theme.fontSize + 1 }
                    }
                }
            }
            SequentialAnimation {
                id: marquee
                running: line.overflow > 0
                loops: Animation.Infinite
                PauseAnimation { duration: 3000 }
                NumberAnimation { target: line; property: "x"; to: -line.overflow; duration: line.overflow * 35; easing.type: Easing.InOutSine }
                PauseAnimation { duration: 2000 }
                NumberAnimation { target: line; property: "x"; to: 0; duration: line.overflow * 35; easing.type: Easing.InOutSine }
            }
        }
        // fade the ends that are scrolled out of view (only the side with hidden text)
        Rectangle {
            id: fadeMask
            visible: false
            width: box.width
            height: box.height
            layer.enabled: true
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: line.x < -1 ? "transparent" : "white" }
                GradientStop { position: 0.16; color: "white" }
                GradientStop { position: 0.8; color: "white" }
                GradientStop { position: 1; color: line.x > -line.overflow + 1 ? "transparent" : "white" }
            }
        }
    }

    MouseArea {
        anchors { fill: parent; topMargin: -Config.pillInset; bottomMargin: -Config.pillInset }
        id: pillArea
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        cursorShape: Qt.PointingHandCursor
        hoverEnabled: true
        property point last   // pointer position, kept for where it leaves
        onPositionChanged: e => last = Qt.point(e.x, e.y)
        onContainsMouseChanged: {
            if (containsMouse) dwell.restart()
            else {
                dwell.stop()
                if (Player.open) Player.origin = mapToItem(null, last.x, last.y)   // the panel drains back here
            }
            Player.pillHovered = containsMouse && Player.open
        }
        onClicked: m.player?.togglePlaying()
    }
}
