import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Bluetooth
import Quickshell.Services.Pipewire
import Quickshell.Services.SystemTray
import Quickshell.Services.UPower
import qs

// The island bar on one screen: three floating islands (workspaces and the window you're in;
// the time; music and status) and one card that grows out from under whichever item the
// pointer rests on and slides from item to item. Built to CRAFT.md:
//  - one drawing window with a live input mask, and a separate 1px window that reserves the space
//  - islands size for where their slots are heading; the card for the content it is switching to
//  - geometry on the spatial curves, opacity and colour on effects, closing on exit
Scope {
    id: scope
    required property var modelData

    // reserves the strip at the top; draws nothing and takes no input
    PanelWindow {
        screen: scope.modelData
        visible: Config.barVisible
        anchors { top: true; left: true; right: true }
        implicitHeight: 1
        exclusiveZone: Look.reserve
        color: "transparent"
        mask: Region {}
        WlrLayershell.namespace: "islands-reserve"
    }

    PanelWindow {
        id: win
        screen: scope.modelData
        anchors { top: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.namespace: "islands"
        // keyboard only while a card is open (the calendar's quick add, a Wi-Fi password), and
        // all of it while an authentication prompt is out, so typing goes straight in
        WlrLayershell.keyboardFocus: win.authing || (card.open && (card.key === "clips" || card.key === "emoji" || card.key === "glyph")) ? WlrKeyboardFocus.Exclusive
            : card.open ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        // a real fullscreen window covers the bar: stop drawing it
        readonly property var monitor: Hyprland.monitorFor(scope.modelData)
        readonly property var workspace: monitor?.activeWorkspace ?? null
        readonly property bool covered: !!workspace?.hasFullscreen
            && workspace.toplevels.values.some(t => (t.lastIpcObject.fullscreen ?? 0) & 2)
        Connections {
            target: Hyprland
            function onRawEvent(e) { if (e.name === "fullscreen") Hyprland.refreshToplevels() }
        }
        // (an authentication prompt shows even over a fullscreen window or a hidden bar)
        visible: (Config.barVisible && !covered) || win.authing

        // one fixed height: resizing a layer surface flashes a squashed copy of the old buffer
        // for a frame, so the window never resizes and the mask alone decides what takes input
        implicitHeight: scope.modelData.height
        mask: Region {
            Region { item: left.hitBox }
            Region { item: centre.hitBox }
            Region { item: right.hitBox }
            Region { item: card.open || card.closing ? card : null }
            Region { item: win.pinned ? bar : null }   // a tapped-open card: the whole screen, so a tap anywhere else closes it
        }

        IdleInhibitor { window: win; enabled: Config.caffeine }

        // ---------------- hover and the card: the controller every Hit reports to ----------------
        readonly property var ctl: win
        property Item hot: null          // the item the card hangs from
        property Item pending: null      // waiting out the first rest
        readonly property bool open: card.open
        property var hits: ({})          // key -> Hit, for IPC
        function register(h) { if (h.key) hits[h.key] = h }

        // a card opened by a finger is pinned: nothing hovers to hold it open, and the touch's
        // synthesized pointer coming and going mustn't close it. A tap on its item (or a real
        // pointer arriving on an item later) lets go.
        property bool pinned: false
        function tap(h) {
            dwell.stop(); aimWait.stop(); pending = null
            if (pinned && card.open && !card.closing && hot === h) { hide(); return }   // only one a tap opened: a slow tap's own hover may have opened this one
            show(h, true)
            pinned = true
        }
        function enter(h) {
            if (pinned) { if (h === hot) return; pinned = false }
            leaveT.stop()
            if (card.open && !card.closing) {
                if (h !== hot && aiming()) { pending = h; aimWait.restart() }   // just passing on the way to the card
                else show(h)
            }
            else { pending = h; dwell.restart() }
        }
        function leave(h) {
            if (pinned) return
            if (pending === h) { dwell.stop(); aimWait.stop(); pending = null }
            leaveT.restart()
        }
        Timer { id: dwell; interval: Settings.hoverDelay; onTriggered: if (win.pending) win.show(win.pending) }
        // ...unless it stays there: then it's wanted after all
        Timer { id: aimWait; interval: 250; onTriggered: if (win.pending?.hovered) win.show(win.pending) }

        // Menu aim: the pointer heading down for the open card, on a line that lands on it, may
        // cross a neighbouring item on the way (to an option at the card's far side): that
        // mustn't swap the card. aimFrom is where it was ~30 ms before aimAt.
        property point aimFrom
        property point aimAt
        property double aimTime: 0
        function track(p) {
            const t = Date.now()
            if (t - aimTime > 30) { aimFrom = aimAt; aimTime = t }
            aimAt = p
        }
        function aiming() {
            const dx = aimAt.x - aimFrom.x, dy = aimAt.y - aimFrom.y
            if (dy < 0.5) return false
            const x = aimAt.x + dx * (card.y - aimAt.y) / dy   // where it would cross the card's top
            return x > card.x - 12 && x < card.x + card.width + 12
        }
        Timer {
            id: leaveT
            interval: 160
            onTriggered: if (!win.pinned && !cardHover.hovered && !(win.hot?.hovered ?? false)) win.hide()
        }
        // an authentication prompt stays until it is answered or cancelled: hover, clicks and
        // other drops don't move the card away from it
        readonly property bool authing: card.key === "auth" && AuthState.showing
        function show(h, sticky) { if (authing) return; card.attach(h); if (sticky) leaveT.stop() }
        function hide() { pinned = false; if (!authing) card.detach() }
        function toggle(h) { card.open && hot === h ? hide() : show(h) }

        // ---- the beat: each kick's wave leaves from the music (Wave; the window border too, BeatGlow) ----
        property real beatX: width / 2
        Connections {
            target: Visualizer
            function onBeat() {
                if (!media.shown) return
                win.beatX = mediaHit.mapToItem(bar, mediaHit.width / 2, 0).x
                Visualizer.origins[scope.modelData.name] = scope.modelData.x + win.beatX
            }
        }

        // ---- room: the side islands stop short of the clock; their titles give way first ----
        readonly property real roomL: centre.targetX - 8 - Look.edge
        readonly property real roomR: bar.width - Look.edge - (centre.targetX + centre.targetW) - 8
        // an island's width without one of its pieces (read from the others, so no loop)
        function restOf(isl, ...skip) {
            let w = 2 * isl.pad
            for (const c of isl.row.children)
                if (!skip.includes(c) && c.visible) w += (c.target ?? c.implicitWidth) + isl.row.spacing
            return w
        }

        // ---------------- the three islands ----------------
        Item {
            id: bar
            anchors.fill: parent
            HoverHandler { onPointChanged: win.track(point.position) }
            MouseArea { anchors.fill: parent; enabled: win.pinned; acceptedButtons: Qt.AllButtons; onPressed: win.hide() }

            Island {
                id: left
                align: "left"
                join: card.joinOf(left)
                bl: card.cornerL(left)
                br: card.cornerR(left)
                Isle { parent: left.deco; island: left
                    // the music's own light, under the media item
                    eq: media.shown ? Qt.vector2d(left.row.x + media.x + mediaHit.x, left.row.x + media.x + mediaHit.x + mediaHit.width) : Qt.vector2d(0, 0)
                }
                // the track's progress just under the island, from under the cover to the end of
                // the title: as long as the media item
                Progress {
                    parent: left.deco
                    visible: media.shown
                    len: Math.max(0, mediaHit.width - 2 * mediaHit.padX - cover.x)
                    x: left.row.x + media.x + mediaHit.x + mediaHit.padX + cover.x - pad
                    y: parent.height + 3 - height / 2
                }

                Hit {
                    key: "sys"
                    spacing: 3
                    Component.onCompleted: win.register(this)
                    onClicked: b => { if (b === Qt.LeftButton) { win.hide(); Util.run("kitty -e btop") } }
                    // room for two digits (tabular), so a reading changing doesn't shift anything
                    Ring { value: SysMon.cpu; base: Look.cpu }
                    BT { text: Math.round(SysMon.cpu) + "%"; width: Math.max(implicitWidth, pct.advanceWidth("00%")); color: cpuHot.on ? Look.alert : Look.text }
                    Item { width: 2; height: 1 }
                    Ring { value: SysMon.ram; base: Look.ram }
                    BT { text: Math.round(SysMon.ram) + "%"; width: Math.max(implicitWidth, pct.advanceWidth("00%")); color: ramHot.on ? Look.alert : Look.text }
                    // the rings warm with every spike; the number turns red only when it stays up
                    Pinned { id: cpuHot; high: SysMon.cpu > 90 }
                    Pinned { id: ramHot; high: SysMon.ram > 90 }
                    FontMetrics { id: pct; font.family: Look.sans; font.pixelSize: Look.barText; font.features: ({ tnum: 1 }) }
                }
                Sep {}
                Workspaces { ctl: win; monitor: win.monitor }
                Sep {}
                Hit {
                    id: wins
                    // only the window you're in (nothing to show on an empty workspace)
                    key: focused ? "wins" : ""
                    Component.onCompleted: win.hits.wins = this
                    readonly property var focused: {
                        const a = Hyprland.activeToplevel
                        if (a && a.workspace === win.workspace) return a
                        return win.workspace?.toplevels.values[0] ?? null
                    }
                    AppIcon { appId: Apps.id(wins.focused); visible: !!wins.focused; size: 15 }
                    // as wide as the title, up to 200; narrower when the island would otherwise reach the clock
                    readonly property real room: win.roomL - win.restOf(left, wins) - (2 * padX + 15 + spacing)
                    readonly property real least: 2 * padX + 15 + spacing + appName.implicitWidth
                    Item {
                        width: wins.focused ? Math.max(appName.implicitWidth, Math.min(appName.implicitWidth + 6 + winTitle.implicitWidth, 200, wins.room)) : appName.implicitWidth
                        height: Look.item
                        Row {
                            height: parent.height
                            spacing: 6
                            BT {
                                id: appName
                                text: wins.focused ? Apps.name(wins.focused) : "Desktop"
                                font.weight: Font.DemiBold
                                color: wins.focused ? Look.text : Look.dim
                            }
                            BT {
                                id: winTitle
                                width: Math.max(0, parent.parent.width - appName.width - 6)
                                visible: width > 20
                                text: wins.focused?.title ?? ""
                                color: Look.dim
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
                Slot {
                    id: media
                    shown: !!Player.player && !Player.idle
                    Sep { id: mediaSep }
                    Hit {
                        id: mediaHit
                        key: "media"
                        Component.onCompleted: win.register(this)
                        onClicked: b => { if (b === Qt.LeftButton) Player.player?.togglePlaying(); else if (b === Qt.MiddleButton) Player.player?.next() }
                        // a notch seeks 5 s
                        onScrolled: st => {
                            const pl = Player.player
                            if (!pl?.canSeek) return
                            pl.position = Math.max(0, Math.min(Player.length || Infinity, Player.pos + 5 * st))
                            Player.refreshPos()
                        }
                        Cover { id: cover; width: 16; height: 16; radius: 4 }
                        MediaTitle {
                            // the title gives way before the island reaches the clock, counting the
                            // window title at its narrowest (that one gives way first)
                            readonly property real room: win.roomL - win.restOf(left, media, wins) - wins.least
                                - (cover.width + mediaHit.spacing + 2 * mediaHit.padX + mediaSep.width + 2)
                            cover: cover
                            lyrics: true
                            width: Math.max(0, Math.min(implicitWidth, room))
                            height: Look.item
                            // hidden once squeezed under 24 px, but a short title ("PO") that fits whole stays
                            visible: width > 0 && width >= Math.min(24, implicitWidth)
                            font { family: Look.sans; pixelSize: Look.barText; weight: Font.DemiBold; features: ({ tnum: 1 }) }
                            opacity: Player.playing ? 1 : 0.6
                            Behavior on opacity { Anim { type: "effects" } }
                        }
                    }
                }
            }

            Island {
                id: centre
                align: "center"
                join: card.joinOf(centre)
                bl: card.cornerL(centre)
                br: card.cornerR(centre)

                Hit {
                    key: "caf"
                    padX: 4
                    lit: Config.caffeine
                    Component.onCompleted: win.register(this)
                    onClicked: Config.caffeine = !Config.caffeine
                    G { glyph: Config.caffeine ? 0xF0176 : 0xF06CA; color: Config.caffeine ? Look.accentInk : Qt.alpha(Look.text, 0.86) }
                }
                Hit {
                    key: "cal"
                    padX: 8
                    spacing: 3
                    Component.onCompleted: win.register(this)
                    BT {
                        width: clockM.advanceWidth("00:00")
                        horizontalAlignment: Text.AlignHCenter
                        // Qt's "h" is 24-hour unless the format has AP in it
                        text: Settings.clock24h ? Qt.formatTime(clock.date, "HH:mm") : Qt.formatTime(clock.date, "h:mm AP").split(" ")[0]
                        font.pixelSize: 13
                        font.weight: Font.Bold
                    }
                    BT {
                        visible: !Settings.clock24h
                        text: Qt.formatTime(clock.date, "AP").toLowerCase()
                        color: Look.dim
                        font.pixelSize: 10
                        font.weight: Font.Medium
                    }
                    FontMetrics { id: clockM; font.family: Look.sans; font.pixelSize: 13; font.weight: Font.Bold }
                }
                Slot {
                    shown: meeting.soon
                    Hit {
                        key: "meet"
                        padX: 7
                        Component.onCompleted: win.register(this)
                        onClicked: if (Cal.next?.meet) Qt.openUrlExternally(Cal.next.meet)
                        // a ring while it's a way off, filled warm once it's close or on
                        Rectangle {
                            width: 6; height: 6; radius: 3
                            anchors.verticalCenter: parent.verticalCenter
                            color: meeting.near ? Look.warm : "transparent"
                            border.width: meeting.near ? 0 : 1.5
                            border.color: Look.accent
                            Behavior on color { Fade {} }
                        }
                        // a fixed cell, so 5m → 30m → now never moves the clock
                        BT {
                            width: meetM.advanceWidth("00m")
                            text: meeting.label
                            color: meeting.near ? Look.warm : Look.dim
                            font.weight: Font.DemiBold
                            font.features: ({ tnum: 1 })
                            Behavior on color { Fade {} }
                            // on now: how far through it, a hairline under the minutes left
                            Rectangle {
                                visible: meeting.live
                                anchors { bottom: parent.bottom; bottomMargin: 2 }
                                width: parent.width; height: 2; radius: 1
                                color: Qt.alpha(Look.text, 0.1)
                                Rectangle { width: parent.width * meeting.through; height: 2; radius: 1; color: Look.warm }
                            }
                        }
                        FontMetrics { id: meetM; font.family: Look.sans; font.pixelSize: Look.barText; font.weight: Font.DemiBold; font.features: ({ tnum: 1 }) }
                    }
                }
            }

            Island {
                id: right
                align: "right"
                join: card.joinOf(right)
                bl: card.cornerL(right)
                br: card.cornerR(right)

                Hit {
                    key: "net"
                    Component.onCompleted: win.register(this)
                    onClicked: b => { if (b === Qt.LeftButton) win.toggle(this) }
                    G {
                        glyph: NetState.glyph
                        color: NetState.online ? Qt.alpha(Look.text, 0.86) : Look.faint
                        // a VPN is up: an accent dot on the glyph's corner (the panel's "up" chip),
                        // cut out of the glyph by a ring of the surface, so nothing moves
                        Rectangle {
                            x: parent.width - 6
                            y: parent.height / 2 + 1
                            width: NetState.vpn ? 9 : 0; height: width; radius: width / 2
                            color: Qt.rgba(Look.surface.r, Look.surface.g, Look.surface.b, 1)
                            Behavior on width { Anim { type: "fast" } }
                            Rectangle { anchors.centerIn: parent; width: Math.max(0, parent.width - 3); height: width; radius: width / 2; color: Look.accent }
                        }
                    }
                    // only the direction that's moving lights up; offline says so in the same room
                    BT {
                        width: rateM.advanceWidth("↓000k")
                        text: NetState.online ? "↓" + NetState.short(NetStats.down) : "offline"
                        color: NetState.online && NetStats.down >= 1000 ? Look.down : Look.faint
                        Behavior on color { Fade {} }
                    }
                    BT {
                        width: rateM.advanceWidth("↑000k")
                        text: NetState.online ? "↑" + NetState.short(NetStats.up) : ""
                        color: NetStats.up >= 1000 ? Look.up : Look.faint
                        Behavior on color { Fade {} }
                    }
                    FontMetrics { id: rateM; font.family: Look.sans; font.pixelSize: Look.barText; font.features: ({ tnum: 1 }) }
                }
                Slot {
                    shown: PrivState.on
                    Hit {
                        key: "priv"
                        padX: 4
                        Component.onCompleted: win.register(this)
                        G { glyph: PrivState.capturing ? 0xF0379 : 0xF036C; color: Look.alert }
                    }
                }
                Sep {}
                Hit {
                    id: bt
                    key: "bt"
                    // something connected: a filled pill with that device (earbuds, headphones,
                    // mouse...) and its battery; on and idle, a dim rune; off, a faint one. Always
                    // there: with no adapter (Bluetooth restarting, blocked) it shows as off
                    lit: on
                    padX: on ? 3 : 4
                    Component.onCompleted: win.register(this)
                    readonly property var a: Bluetooth.defaultAdapter
                    // the device shown: an audio one first, else whatever is connected
                    readonly property var dev: {
                        const ds = (a?.devices.values ?? []).filter(d => d.connected)
                        return ds.find(d => /audio|head/.test(d.icon)) ?? ds[0] ?? null
                    }
                    readonly property bool on: !!dev && !!a?.enabled
                    // BlueZ calls earbuds and headphones both "audio-headset": go by the name
                    readonly property bool earbuds: !!dev && /buds|earbud|pods|\bear\b|cmf/i.test(dev.name)
                    // the lower bud for Nothing / CMF buds (BudsState), else what BlueZ says; -1: unknown
                    readonly property int batt: {
                        const l = BudsState.of(dev)
                        // the buds in use; one charging in the case doesn't count while the other's out
                        const all = l ? [l.left, l.right].filter(x => x) : []
                        const out = all.filter(x => !x[1])
                        const b = (out.length ? out : all).map(x => x[0])
                        return b.length ? Math.min(...b) : dev?.batteryAvailable ? Math.round(dev.battery * 100) : -1
                    }
                    onClicked: b => { if (b === Qt.MiddleButton && a) a.enabled = !a.enabled }
                    // the device's battery as a ring around its glyph: it reads as that device's
                    // charge, not as another of the bar's numbers, and costs no width (the exact
                    // figure is in the menu)
                    Item {
                        id: btBox
                        readonly property bool ringed: bt.on && bt.batt >= 0
                        // Nothing / CMF buds: a capsule each side of the glyph, one per bud (the panel's)
                        readonly property var buds: bt.earbuds ? BudsState.of(bt.dev) : null
                        // a bud in use: reported and out of the case. One in your ear and the other
                        // charging in the case: only the one in use shows (both charging: both)
                        readonly property var worn: !buds ? [] : [buds.left, buds.right].map((u, i, all) =>
                            u && !(u[1] && all[1 - i] && !all[1 - i][1]) ? u : null)
                        readonly property bool pair: bt.on && !!buds && worn.some(u => u)
                        width: pair ? 26 : ringed ? 20 : btG.width
                        height: Look.item
                        G {
                            id: btG
                            anchors.centerIn: parent
                            font.pixelSize: parent.pair ? 12 : parent.ringed ? 10 : 13
                            glyph: !bt.on ? 0xF00AF : bt.earbuds ? 0xF184F : /headset|headphone/.test(bt.dev.icon) ? 0xF02CB
                                : /audio|speaker/.test(bt.dev.icon) ? 0xF04C3 : /mouse/.test(bt.dev.icon) ? 0xF037D
                                : /keyboard/.test(bt.dev.icon) ? 0xF030C : /phone/.test(bt.dev.icon) ? 0xF011C : 0xF00B1
                            color: bt.on ? Look.accentInk : bt.a?.enabled ? Look.dim : Look.faint
                            Behavior on color { Fade {} }
                        }
                        Repeater {
                            model: btBox.pair ? btBox.worn : []
                            Rectangle {
                                required property var modelData
                                required property int index
                                visible: !!modelData
                                x: index ? btBox.width - width : 0
                                anchors.verticalCenter: parent.verticalCenter
                                width: 4; height: 12; radius: 2
                                color: Qt.alpha(Look.accentInk, 0.22)
                                Rectangle {
                                    anchors.bottom: parent.bottom
                                    width: parent.width
                                    height: modelData ? Math.max(2, parent.height * modelData[0] / 100) : 0
                                    radius: 2
                                    color: modelData && modelData[0] <= 15 ? Look.alert : Look.accentInk
                                    Behavior on height { Anim { type: "effects" } }
                                }
                            }
                        }
                        Shape {
                            anchors.fill: parent
                            visible: parent.ringed && !parent.pair
                            preferredRendererType: Shape.CurveRenderer
                            ShapePath {
                                strokeColor: Qt.alpha(Look.accentInk, 0.22)
                                strokeWidth: 2
                                fillColor: "transparent"
                                PathAngleArc { centerX: 10; centerY: Look.item / 2; radiusX: 8.5; radiusY: 8.5; startAngle: 0; sweepAngle: 360 }
                            }
                            ShapePath {
                                strokeColor: bt.batt <= 20 ? Look.alert : Look.accentInk
                                strokeWidth: 2
                                fillColor: "transparent"
                                capStyle: ShapePath.RoundCap
                                PathAngleArc { centerX: 10; centerY: Look.item / 2; radiusX: 8.5; radiusY: 8.5; startAngle: -90; sweepAngle: 360 * Math.max(0.01, bt.batt / 100) }
                            }
                        }
                    }
                }
                Repeater {
                    model: SystemTray.items
                    Hit {
                        id: ti
                        required property SystemTrayItem modelData
                        // Wi-Fi and Bluetooth have their own items and panels
                        visible: modelData.status !== Status.Passive && modelData.id !== "nm-applet" && modelData.id !== "blueman"
                        key: "tray:" + modelData.id
                        property var arg: modelData
                        padX: 4
                        Component.onCompleted: win.register(this)
                        onClicked: b => {
                            if (b === Qt.LeftButton && !modelData.onlyMenu) modelData.activate()
                            else if (b === Qt.MiddleButton) modelData.secondaryActivate()
                            else win.show(ti, true)
                        }
                        onScrolled: s => modelData.scroll(s, false)
                        TrayIcon { item: ti.modelData }
                    }
                }
                Sep {}
                Hit {
                    key: "bat"
                    visible: UPower.displayDevice.isPresent
                    spacing: 2
                    Component.onCompleted: win.register(this)
                    // the laptop's own: a cell that fills with the charge, its number inside, so it
                    // can't be mistaken for any other reading. Plugged in, the nub becomes a bolt:
                    // the item is the same width either way
                    Item {
                        width: 33; height: Look.item
                        // a soft track with a solid fill (the volume meter's language); the number
                        // is light over the empty part and dark over the fill, split where it ends
                        Item {
                            id: cell
                            width: 24; height: 14
                            anchors.verticalCenter: parent.verticalCenter
                            Rectangle { anchors.fill: parent; radius: 4; color: Qt.alpha(Look.text, 0.16) }
                            T { id: capN; anchors.centerIn: parent; text: BatState.cap; font.pixelSize: 9; font.weight: Font.Bold }
                            Item {
                                width: parent.width * Math.min(1, BatState.cap / 100); height: parent.height
                                clip: true
                                Rectangle { width: cell.width; height: cell.height; radius: 4; color: BatState.colour }
                                T { x: capN.x; y: capN.y; text: capN.text; font: capN.font; color: Qt.rgba(0, 0, 0, 0.78) }
                            }
                            // charging up to a limit: where it'll stop (the panel's dashed line)
                            Rectangle {
                                visible: BatState.charging && BatState.limit < 100
                                x: Math.round(cell.width * BatState.limit / 100)
                                anchors.verticalCenter: parent.verticalCenter
                                width: 1; height: 8
                                color: Qt.rgba(0, 0, 0, 0.45)
                            }
                        }
                        Rectangle {
                            x: cell.width + 1; width: 2; height: 6; radius: 1
                            anchors.verticalCenter: parent.verticalCenter
                            color: Qt.alpha(Look.text, 0.16)
                            opacity: BatState.charging ? 0 : 1
                            Behavior on opacity { Anim { type: "effects" } }
                        }
                        G {
                            x: cell.width
                            anchors.verticalCenter: parent.verticalCenter
                            glyph: 0xF140B
                            color: Look.good
                            font.pixelSize: 10
                            opacity: BatState.charging ? 1 : 0
                            Behavior on opacity { Anim { type: "effects" } }
                        }
                    }
                }
                Hit {
                    key: "bri"
                    padX: 4
                    Component.onCompleted: win.register(this)
                    onScrolled: s => Brightness.step(s)
                    // warm means light (the panel's track); the sun steps with the level
                    G { glyph: Brightness.pct < 34 ? 0xF00DE : Brightness.pct < 67 ? 0xF00DF : 0xF00E0; color: Qt.alpha(Look.warm, 0.95) }
                }
                Hit {
                    id: vol
                    key: "vol"
                    spacing: 5
                    Component.onCompleted: win.register(this)
                    readonly property var sink: Pipewire.defaultAudioSink
                    readonly property int vol: Math.round((sink?.audio?.volume ?? 0) * 100)
                    PwObjectTracker { objects: [Pipewire.defaultAudioSink] }
                    // smooth: the wheel moves a target 5% a notch (touchpad strokes in fractions of
                    // that), and the volume walks there at most 1% every 16 ms instead of jumping
                    property real want: -1   // where the wheel is taking it; -1 while it isn't
                    property real at: 0      // where the walk has got to
                    onWheeled: n => {
                        if (!sink?.audio) return
                        if (want < 0) want = at = sink.audio.volume
                        want = Math.max(0, Math.min(1, want + 0.05 * n))
                        walk.start()
                    }
                    Timer {
                        id: walk
                        interval: 16
                        repeat: true
                        onTriggered: {
                            const d = vol.want - vol.at
                            if (Math.abs(d) < 0.0005) { stop(); vol.want = -1; return }
                            vol.at += Math.sign(d) * Math.min(Math.abs(d), 0.01)
                            Util.setVolume(vol.sink, vol.at)
                        }
                    }
                    onClicked: b => {
                        if (b === Qt.MiddleButton && sink?.audio) Util.setMuted(sink, !sink.audio.muted)
                        else if (b === Qt.RightButton) Util.run("pavucontrol-qt -t 3 || pavucontrol -t 3")
                    }
                    // the glyph says where it goes (the meter says how loud)
                    G {
                        glyph: vol.sink?.audio?.muted ? 0xF0581 : Util.audioGlyph(vol.sink)
                        color: vol.sink?.audio?.muted ? Look.faint : Qt.alpha(Look.text, 0.86)
                    }
                    // the level as a short meter (amber past 100%); the exact number drops out of
                    // the icon while it changes (panels/Level.qml)
                    Rectangle {
                        width: 24; height: 4; radius: 2
                        anchors.verticalCenter: parent.verticalCenter
                        color: Qt.alpha(Look.text, 0.16)
                        opacity: vol.sink?.audio?.muted ? 0.45 : 1
                        Rectangle {
                            width: Math.max(height, parent.width * Math.min(1, vol.vol / 100))
                            visible: vol.vol > 0
                            height: parent.height; radius: 2
                            color: vol.sink?.audio?.muted ? Look.faint : vol.vol > 100 ? Look.urgent : Look.accent
                            Behavior on width { enabled: !walk.running; Anim { type: "effects" } }
                        }
                    }
                }
                Sep {}
                Hit {
                    id: bell
                    key: "notif"
                    padX: 4
                    Component.onCompleted: win.register(this)
                    onClicked: b => { if (b === Qt.RightButton) Config.dnd = !Config.dnd }
                    G { glyph: Config.dnd ? 0xF009B : 0xF009A; color: Config.dnd ? Look.faint : Qt.alpha(Look.text, 0.86) }
                    // unread (anything logged since the panel was last open): an accent dot, red
                    // when one came in critical; under do-not-disturb a hollow ring, waiting
                    Rectangle {
                        parent: bell
                        x: bell.width - 11; y: 2
                        width: NoteState.unread ? 9 : 0; height: width; radius: width / 2
                        color: Qt.rgba(Look.surface.r, Look.surface.g, Look.surface.b, 1)
                        Behavior on width { Anim { type: "fast" } }
                        Rectangle {
                            anchors.centerIn: parent
                            width: Math.max(0, parent.width - 3); height: width; radius: width / 2
                            color: Config.dnd ? "transparent" : NoteState.urgent ? Look.alert : Look.accent
                            border.width: Config.dnd ? 1.5 : 0
                            border.color: Look.dim
                            Behavior on color { Fade {} }
                        }
                    }
                }
                // quick settings: session, night light, airplane mode, mic, phone
                Hit {
                    key: "quick"
                    padX: 4
                    Component.onCompleted: win.register(this)
                    onClicked: win.toggle(this)
                    G { glyph: 0xF062E }
                }
            }
        }

        // `qs -c bar ipc call quick toggle` (Config.toggleQuick): quick settings on the focused monitor
        Connections {
            target: Config
            function onToggleQuick() {
                if (Hyprland.focusedMonitor?.name !== scope.modelData.name) return
                win.toggle(win.hits.quick)
            }
        }

        // ---------------- the card ----------------
        Card { id: card; ctl: win; islands: [left, centre, right] }
        // Hyprland blurs this surface only while a card is out: it is full-screen and redraws with
        // every music frame, and a standing blur re-blurred the whole screen each frame (~7 GPU
        // points). Mirrors the islands_blur rule in hyprland.lua, which ships blur = false.
        function blur(on) {
            Quickshell.execDetached(["hyprctl", "eval", `hl.layer_rule({name="islands_blur", match={namespace="^islands$"}, blur=${on}, ignore_alpha=0.4, no_anim=true})`])
        }
        Connections { target: card; function onShownChanged() { win.blur(card.shown) } }
        // the beatglow plugin keeps the window-border glow out from under the card (where it
        // showed through and read as the bar's wave coming down the card from the wrong side):
        // the box the card is heading for, a little wider for its necks, until it has closed. It
        // reaches up to the screen edge: the glow's bloom rises above the window into the strip
        // behind the islands, and the blur (on while a card is out) smeared that into the card
        function mask() {
            const s = scope.modelData, m = 6
            Quickshell.execDetached(["hyprctl", "beatglow", "mask", s.name].concat(card.shown ? [
                s.x + card.targetX - m, s.y, card.targetW + 2 * m, Look.top + Look.h + card.targetH + m, 20 + m].map(String) : []))
        }
        Connections {
            target: card
            function onShownChanged() { Qt.callLater(win.mask) }
            function onTargetXChanged() { if (card.shown) Qt.callLater(win.mask) }
            function onTargetWChanged() { if (card.shown) Qt.callLater(win.mask) }
            function onTargetHChanged() { if (card.shown) Qt.callLater(win.mask) }
        }
        // each kick's wave, over everything (Wave.qml): a strip over the islands, and a box round
        // the card below it while one is out (each draws only its own pixels: no overlap)
        Wave { islands: [left, centre, right]; card: card; originX: win.beatX; width: bar.width; height: Look.top + Look.h + 4 }
        Wave {
            islands: [left, centre, right]; card: card; originX: win.beatX
            on: card.shown
            x: card.x - 48
            y: Look.top + Look.h + 4
            width: card.width + 96
            height: Math.max(0, card.height - 2)
        }
        HoverHandler {
            id: cardHover
            target: card
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad | PointerDevice.Stylus   // a finger lifting off the card mustn't close it
            onHoveredChanged: hovered ? leaveT.stop() : leaveT.restart()
        }

        // volume and brightness drop a level out of their icon (panels/Level.qml) for a moment as
        // they change, whoever changed them (keys, scroll, pavucontrol), on the focused monitor;
        // not while another card is out (their own hover card already shows it)
        QtObject {
            id: levels
            property bool armed: false   // values arrive as Pipewire and sysfs load: not the user
            function flash(k) {
                if (!armed || !win.visible || Hyprland.focusedMonitor?.name !== scope.modelData.name) return
                if (card.open && !card.key.startsWith("level")) return
                card.attach(win.hits[k], "level:" + k)
                levelT.restart()
            }
        }
        Timer { running: true; interval: Settings.osdArmDelay; onTriggered: levels.armed = true }
        Timer {
            id: levelT
            interval: Settings.osdTimeout
            onTriggered: {
                if (!card.open || !card.key.startsWith("level")) return
                if (cardHover.hovered) restart()
                else win.hide()
            }
        }
        Connections {
            target: Pipewire.defaultAudioSink?.audio ?? null
            function onVolumeChanged() { levels.flash("vol") }
            function onMutedChanged() { levels.flash("vol") }
        }
        Connections { target: Brightness; function onPctChanged() { levels.flash("bri") } }

        // a copy drops out of the clock (panels/Clip.qml) the same way, for the same time
        Connections {
            target: ClipState
            function onCopied() {
                if (!levels.armed || !win.visible || Hyprland.focusedMonitor?.name !== scope.modelData.name) return
                if (card.open && card.key !== "clip") return
                card.attach(win.hits.cal, "clip")
                clipT.restart()
            }
        }
        // SUPER+V (`qs -c bar ipc call clip toggle`): the history opens out of the same place,
        // pinned like a tapped card, so a click anywhere else closes it
        Connections {
            target: ClipState
            function onSummoned() {
                if (Hyprland.focusedMonitor?.name !== scope.modelData.name || win.authing) return
                if (card.open && card.key === "clips") { win.hide(); return }
                card.attach(win.hits.cal, "clips")
                leaveT.stop()
                win.pinned = true
            }
        }
        // SUPER+. / SUPER+, (`qs -c bar ipc call emoji|glyph toggle`): the symbol pickers
        // (Picker.qml), out of the same place and pinned the same way
        function summon(key) {
            if (Hyprland.focusedMonitor?.name !== scope.modelData.name || win.authing) return
            if (card.open && card.key === key) { win.hide(); return }
            card.attach(win.hits.cal, key)
            leaveT.stop()
            win.pinned = true
        }
        Connections { target: EmojiState.data; function onSummoned() { win.summon("emoji") } }
        Connections { target: GlyphState.data; function onSummoned() { win.summon("glyph") } }
        Timer {
            id: clipT
            interval: Settings.osdTimeout
            onTriggered: {
                if (!card.open || card.key !== "clip") return
                if (cardHover.hovered) restart()
                else win.hide()
            }
        }

        // new notifications drop out of the bell (NoteState.drops) on the focused monitor, at
        // once if the card is free, else as soon as it closes (or a fullscreen window goes);
        // they go back up the popup time after the last arrived, never while the pointer is on them
        function dropIfAny() {
            if (!NoteState.drops.length || !visible || Hyprland.focusedMonitor?.name !== scope.modelData.name) return
            if (card.key === "auth") return
            // a critical one interrupts another card, unless the pointer is on it
            if (card.open && card.key !== "toast" && !(NoteState.holding && !cardHover.hovered)) return
            card.attach(bell, "toast")
            toastT.restart()
        }
        onVisibleChanged: dropIfAny()
        Connections {
            target: NoteState
            function onArrived() { win.dropIfAny() }
            function onEmptied() { if (card.key === "toast") win.hide() }
        }
        Connections { target: card; function onKeyChanged() { if (card.key === "") Qt.callLater(win.dropIfAny) } }
        Timer {
            id: toastT
            interval: Settings.notifTimeout
            onTriggered: {
                if (card.key !== "toast" || !card.open || NoteState.holding) return   // critical: until dismissed
                if (cardHover.hovered) restart()
                else win.hide()
            }
        }

        // polkit asking (AuthState): the prompt drops out of the clock on the focused monitor
        Connections {
            target: AuthState
            function onShowingChanged() {
                if (!AuthState.showing) { if (card.key === "auth") card.detach(); return }
                const f = Hyprland.focusedMonitor?.name
                const here = f ? f === scope.modelData.name : scope.modelData === Quickshell.screens[0]
                if (here) card.attach(win.hits.cal, "auth")
            }
        }

        SystemClock { id: clock; precision: SystemClock.Minutes }
        // the next timed event, when it starts within half an hour or is on now
        QtObject {
            id: meeting
            readonly property var e: Cal.next
            readonly property real mins: e ? (new Date(e.start) - clock.date) / 60000 : 1e9
            readonly property bool soon: !!e && mins <= 30 && new Date(e.end) > clock.date
            readonly property bool live: !!e && mins <= 0
            readonly property bool near: live || mins <= Settings.meetLead
            readonly property real remain: e ? (new Date(e.end) - clock.date) / 60000 : 0
            readonly property real through: e ? Math.min(1, Math.max(0, -mins / Math.max(1, (new Date(e.end) - new Date(e.start)) / 60000))) : 0
            // before: minutes to it; on: "now" for its first minute, then minutes left
            readonly property string label: !live ? Math.ceil(mins) + "m" : mins > -1 ? "now"
                : remain < 60 ? Math.ceil(remain) + "m" : Math.floor(remain / 60) + "h"
        }

        IpcHandler {
            target: "islands" + (Quickshell.screens.length > 1 ? "-" + scope.modelData.name : "")
            function open(key: string): void { const h = win.hits[key]; if (h) win.show(h, true) }
            function close(): void { win.hide() }
            function slow(k: real): void { Look.speed = k }
            function keys(): string { return Object.keys(win.hits).join(" ") }
        }
    }

    // `high` held for 30 s straight; drops as soon as it isn't
    component Pinned: Timer {
        property bool high
        property bool on: false
        interval: 30000
        running: high && !on
        onTriggered: on = true
        onHighChanged: if (!high) on = false
    }

    component Sep: Item {
        width: 5
        height: 14
        anchors.verticalCenter: parent?.verticalCenter
        Rectangle { x: 2; width: 1; height: parent.height; color: Look.line }
    }
}
