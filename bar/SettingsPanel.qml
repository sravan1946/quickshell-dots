import QtQuick
import Quickshell
import Quickshell.Io
import qs.islands

// Settings, opened from quick settings (the cog), Config.openSettings() or IPC. A normal
// floating window ("Bar Settings", floated by a rule in hyprland.lua): drag the header to move
// it, Escape or the compositor closes it. Pages along the top; every control is two-way bound
// to Settings.* (which saves itself), so a reset or an IPC `set` shows up at once.
Scope {
    id: root

    property bool open: false
    property int page: 0
    readonly property var pages: ["Bar", "System", "Media", "Alerts", "Colours"]
    onOpenChanged: Config.settingsOpen = open

    // `qs -c bar ipc call settings toggle`, `... page media`, `... set hoverDelay 200`
    IpcHandler {
        target: "settings"
        function toggle(): void { Config.openSettings() }
        function set(key: string, value: string): void {
            if (Settings.defaults[key] !== undefined) Settings[key] = JSON.parse(value)
        }
        function page(name: string): void {
            root.page = Math.max(0, root.pages.findIndex(p => p.toLowerCase() === name.toLowerCase()))
            if (!root.open) Config.openSettings()
        }
    }
    Connections {
        target: Config
        function onOpenSettings() { root.open = !root.open }
    }

    FloatingWindow {
        id: win
        title: "Bar Settings"
        visible: root.open
        implicitWidth: 560
        implicitHeight: 560
        minimumSize: Qt.size(480, 420)
        color: "transparent"
        onClosed: root.open = false

        Rectangle {
            anchors.fill: parent
            radius: 18
            color: Qt.alpha(Look.surface, 0.97)
            border.width: 1
            border.color: Look.line
            focus: root.open
            Keys.onEscapePressed: root.open = false

            // ---- header: the title (drag it to move the window) and the pages ----
            Item {
                id: head
                width: parent.width
                height: 64
                MouseArea { anchors.fill: parent; cursorShape: Qt.SizeAllCursor; onPressed: win.startSystemMove() }
                T { x: 20; anchors.verticalCenter: parent.verticalCenter; text: "Settings"; font.pixelSize: 15; font.weight: Font.Bold }
                Rectangle {
                    id: tabs
                    anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                    width: tabRow.implicitWidth + 6
                    height: 32
                    radius: 16
                    color: Look.raise
                    // the lit tab slides between pages
                    Rectangle {
                        readonly property Item at: tabRow.children[root.page] ?? null
                        x: 3 + (at?.x ?? 0)
                        y: 3
                        width: at?.width ?? 0
                        height: 26
                        radius: 13
                        color: Look.accent
                        Behavior on x { Anim { type: "fast" } }
                        Behavior on width { Anim { type: "fast" } }
                    }
                    Row {
                        id: tabRow
                        x: 3; y: 3
                        Repeater {
                            model: root.pages
                            Item {
                                required property string modelData
                                required property int index
                                width: tl.implicitWidth + 24
                                height: 26
                                T {
                                    id: tl
                                    anchors.centerIn: parent
                                    text: parent.modelData
                                    font.pixelSize: Look.small
                                    font.weight: Font.DemiBold
                                    color: root.page === parent.index ? Look.accentInk : Look.dim
                                    Behavior on color { Fade {} }
                                }
                                TapHandler { onTapped: root.page = parent.index }
                                HoverHandler { cursorShape: Qt.PointingHandCursor }
                            }
                        }
                    }
                }
            }

            // ---- the page ----
            Flickable {
                id: flick
                anchors { top: head.bottom; left: parent.left; right: parent.right; bottom: foot.top; leftMargin: 20; rightMargin: 20 }
                contentHeight: pageCol.implicitHeight + 8
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                Column {
                    id: pageCol
                    width: flick.width
                    spacing: 6
                    // a new page settles in from slightly below
                    property real dy: 0
                    transform: Translate { y: pageCol.dy }
                    Connections {
                        target: root
                        function onPageChanged() { flick.contentY = 0; settle.restart() }
                    }
                    ParallelAnimation {
                        id: settle
                        NumberAnimation { target: pageCol; property: "opacity"; from: 0; to: 1; duration: Look.ms("effects"); easing.type: Easing.BezierSpline; easing.bezierCurve: Look.curves.effects }
                        Anim { target: pageCol; property: "dy"; from: 10; to: 0 }
                    }

                    // Bar
                    Group {
                        page: 0
                        Head { text: "Clock and calendar" }
                        Toggle { title: "24-hour time"; on: Settings.clock24h; onFlip: Settings.clock24h = !Settings.clock24h }
                        Pick {
                            title: "Week starts on"
                            options: ["Locale", "Monday", "Sunday"]
                            current: Settings.weekStart
                            onPicked: i => Settings.weekStart = i
                        }
                        Num { title: "Calendar refresh"; sub: "Opening the calendar always fetches"; from: 1; to: 60; step: 1; unit: " min"; value: Settings.calRefresh; onEdit: v => Settings.calRefresh = v }
                        Num { title: "Join turns solid"; sub: "Minutes before a meeting starts"; from: 0; to: 30; step: 1; unit: " min"; value: Settings.meetLead; onEdit: v => Settings.meetLead = v }
                        Head { text: "Hover" }
                        Num { title: "Hover delay"; sub: "How long the pointer rests before a panel drops"; from: 0; to: 600; step: 10; unit: " ms"; value: Settings.hoverDelay; onEdit: v => Settings.hoverDelay = v }
                    }
                    // System
                    Group {
                        page: 1
                        Head { text: "Usage" }
                        Num { title: "Sample every"; from: 1; to: 10; step: 0.5; unit: " s"; value: Settings.sysInterval / 1000; onEdit: v => Settings.sysInterval = Math.round(v * 1000) }
                        Colour { title: "CPU"; value: Settings.sysColCpu; onEdit: v => Settings.sysColCpu = v }
                        Colour { title: "Memory"; value: Settings.sysColRam; onEdit: v => Settings.sysColRam = v }
                        Head { text: "Network" }
                        Num { title: "Sample every"; from: 1; to: 10; step: 0.5; unit: " s"; value: Settings.netInterval / 1000; onEdit: v => Settings.netInterval = Math.round(v * 1000) }
                        Colour { title: "Download"; value: Settings.netColDown; onEdit: v => Settings.netColDown = v }
                        Colour { title: "Upload"; value: Settings.netColUp; onEdit: v => Settings.netColUp = v }
                    }
                    // Media
                    Group {
                        page: 2
                        Head { text: "Lyrics" }
                        Toggle { title: "Synced lyrics"; sub: "From lrclib.net, in the music panel"; on: Settings.lyrics; onFlip: Settings.lyrics = !Settings.lyrics }
                        Toggle { title: "Ask Musixmatch too"; sub: "Word timing where lrclib only has lines"; on: Settings.lyricsMusixmatch; onFlip: Settings.lyricsMusixmatch = !Settings.lyricsMusixmatch }
                        Num { title: "Offset"; sub: "Positive shows lines earlier"; from: -1.5; to: 1.5; step: 0.05; unit: " s"; value: Settings.lyricsOffset; onEdit: v => Settings.lyricsOffset = v }
                        Toggle { title: "Lyrics in the bar"; sub: "The line being sung replaces the title while it's sung"; on: Settings.lyricsInBar; onFlip: Settings.lyricsInBar = !Settings.lyricsInBar }
                        Head { text: "Beat glow" }
                        Toggle { title: "Beat effects"; sub: "The wave on the window border"; on: Settings.beatEffects; onFlip: Settings.beatEffects = !Settings.beatEffects }
                        Num { title: "Wave reach"; from: 400; to: 5000; step: 50; unit: " px"; value: Settings.waveReach; onEdit: v => Settings.waveReach = v }
                        Num { title: "Wave length"; from: 0.2; to: 3; step: 0.05; unit: " s"; value: Settings.waveDur; onEdit: v => Settings.waveDur = v }
                        Toggle { title: "Colour by sound"; sub: "Off: every kick is the cover colour"; on: Settings.kickTimbre; onFlip: Settings.kickTimbre = !Settings.kickTimbre }
                        Num { title: "Hue shift"; from: 0; to: 120; step: 1; unit: "°"; value: Settings.kickHue; onEdit: v => Settings.kickHue = v }
                        Num { title: "Lightness shift"; from: 0; to: 0.3; step: 0.01; value: Settings.kickLight; onEdit: v => Settings.kickLight = v }
                        Head { text: "Kick detection" }
                        Num { title: "Floor"; sub: "Higher catches fewer kicks"; from: 1; to: 12; step: 0.5; unit: " dB"; value: Settings.kickFloor; onEdit: v => Settings.kickFloor = v }
                        Num { title: "Gap between kicks"; from: 0.1; to: 0.6; step: 0.01; unit: " s"; value: Settings.kickGap; onEdit: v => Settings.kickGap = v }
                        Num { title: "Loudness margin"; sub: "Lower: fewer false kicks, quiet ones missed"; from: 2; to: 14; step: 0.5; unit: " dB"; value: Settings.kickMargin; onEdit: v => Settings.kickMargin = v }
                        Num { title: "Sync"; sub: "Positive shows kicks earlier"; from: -0.3; to: 0.3; step: 0.01; unit: " s"; value: Settings.kickOffset; onEdit: v => Settings.kickOffset = v }
                    }
                    // Alerts
                    Group {
                        page: 3
                        Head { text: "Notifications" }
                        Toggle { title: "Drop from the bell"; sub: "Every notification comes out of the bar; off, they pop up at the side"; on: Settings.notifDrop; onFlip: Settings.notifDrop = !Settings.notifDrop }
                        Num { title: "Popups stay"; sub: "When the app leaves it to the server"; from: 1; to: 20; step: 0.5; unit: " s"; value: Settings.notifTimeout / 1000; onEdit: v => Settings.notifTimeout = Math.round(v * 1000) }
                        Num { title: "History keeps"; from: 10; to: 500; step: 10; value: Settings.historyMax; onEdit: v => Settings.historyMax = v }
                        Head { text: "Volume and brightness level" }
                        Num { title: "Stays up"; from: 0.5; to: 5; step: 0.1; unit: " s"; value: Settings.osdTimeout / 1000; onEdit: v => Settings.osdTimeout = Math.round(v * 1000) }
                        Num { title: "Quiet at start-up"; from: 0; to: 5; step: 0.1; unit: " s"; value: Settings.osdArmDelay / 1000; onEdit: v => Settings.osdArmDelay = Math.round(v * 1000) }
                        Head { text: "Battery" }
                        Num { title: "Amber below"; from: 5; to: 50; step: 1; unit: "%"; value: Settings.batteryWarn; onEdit: v => Settings.batteryWarn = Math.max(v, Settings.batteryLow) }
                        Num { title: "Red and a notification below"; from: 3; to: 30; step: 1; unit: "%"; value: Settings.batteryLow; onEdit: v => Settings.batteryLow = Math.min(v, Settings.batteryWarn) }
                    }
                    // Colours
                    Group {
                        page: 4
                        T { width: parent.width; wrapMode: Text.Wrap; color: Look.dim; font.pixelSize: Look.small; text: "For notifications, the volume popup and the power menu. The bar follows the wallpaper. \"@name\" follows a HyDE colour, \"#hex\" stays fixed." }
                        Colour { title: "Background"; value: Settings.themeMainBg; onEdit: v => Settings.themeMainBg = v }
                        Colour { title: "Text"; value: Settings.themeMainFg; onEdit: v => Settings.themeMainFg = v }
                        Colour { title: "Active"; value: Settings.themeActBg; onEdit: v => Settings.themeActBg = v }
                        Colour { title: "Active text"; value: Settings.themeActFg; onEdit: v => Settings.themeActFg = v }
                        Colour { title: "Hover"; value: Settings.themeHvrBg; onEdit: v => Settings.themeHvrBg = v }
                        Colour { title: "Hover text"; value: Settings.themeHvrFg; onEdit: v => Settings.themeHvrFg = v }
                    }
                }
            }

            // ---- footer: reset, which asks for a second click ----
            Item {
                id: foot
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 52
                Rectangle { width: parent.width; height: 1; color: Look.line }
                property bool armed: false
                Timer { id: disarm; interval: 3000; onTriggered: foot.armed = false }
                Btn {
                    anchors { right: parent.right; rightMargin: 16; verticalCenter: parent.verticalCenter }
                    text: foot.armed ? "Click again to reset everything" : "Reset all"
                    strong: foot.armed
                    tone: Look.alert
                    onClicked: {
                        if (foot.armed) { Settings.reset(); foot.armed = false }
                        else { foot.armed = true; disarm.restart() }
                    }
                }
            }
        }
    }

    // one page's rows
    component Group: Column {
        property int page
        visible: root.page === page
        width: parent.width
        spacing: 6
    }
    // a row: title and an optional line under it on the left, a control on the right
    component Line: Item {
        id: r
        property string title
        property string sub: ""
        default property alias control: ctl.data
        width: parent.width
        implicitHeight: sub ? 42 : 34
        Column {
            anchors { left: parent.left; right: ctl.left; rightMargin: 12; verticalCenter: parent.verticalCenter }
            T { width: parent.width; text: r.title; elide: Text.ElideRight }
            T { visible: r.sub !== ""; width: parent.width; text: r.sub; color: Look.dim; font.pixelSize: Look.small; elide: Text.ElideRight }
        }
        Item {
            id: ctl
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            width: childrenRect.width
            height: 30
        }
    }
    component Toggle: Line {
        id: tg
        property bool on
        signal flip()
        Switch { on: tg.on; onToggled: tg.flip() }
    }
    component Num: Line {
        id: n
        property real from
        property real to
        property real step: 1
        property string unit: ""
        property real value
        signal edit(real v)
        readonly property int places: step < 0.01 ? 3 : step < 0.1 ? 2 : step < 1 ? 1 : 0
        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10
            Slide {
                width: 170
                value: (n.value - n.from) / (n.to - n.from)
                onMoved: v => n.edit(Math.round((n.from + v * (n.to - n.from)) / n.step) * n.step)
            }
            T { width: 62; anchors.verticalCenter: parent.verticalCenter; horizontalAlignment: Text.AlignRight; text: n.value.toFixed(n.places) + n.unit; color: Look.dim }
        }
    }
    component Pick: Line {
        id: pk
        property var options: []
        property int current
        signal picked(int i)
        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4
            Repeater {
                model: pk.options
                Btn {
                    required property string modelData
                    required property int index
                    text: modelData
                    strong: pk.current === index
                    onClicked: pk.picked(index)
                }
            }
        }
    }
    // "#hex" or "@hyde-name": the swatch shows what it resolves to, a red ring when it doesn't
    component Colour: Line {
        id: c
        property string value
        signal edit(string v)
        readonly property bool valid: field.text.startsWith("@") ? Theme.has(field.text.slice(1))
            : /^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.test(field.text)
        onValueChanged: if (field.text !== value) field.text = value
        Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: 22
                height: 22
                radius: 11
                color: c.valid ? Theme.color(field.text, "transparent") : "transparent"
                border.width: 1
                border.color: c.valid ? Look.line : Look.alert
            }
            Field {
                id: field
                width: 170
                text: c.value
                onTextChanged: if (c.valid && text !== c.value) c.edit(text)
            }
        }
    }
}
