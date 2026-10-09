import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs
import qs.components

// Central settings GUI, opened by Config.openSettings() (the quick-settings tile) or IPC.
// A normal floating window ("Bar Settings", floated by a rule in hyprland.lua): move it
// with SUPER+drag or by dragging the sidebar header, close it with the X, Escape or the
// compositor. A category sidebar and the chosen page of editors. Every control is two-way
// bound to Settings.* (which debounce-persists) or to live Config state, so an external
// change or a reset() shows up at once.
Scope {
    id: root

    property bool open: false
    property int page: 0
    // on the Media page the Now Playing panel is held open under the pill on the focused
    // monitor: every style choice shows live on the real pill and panel
    readonly property bool previewing: open && pages[page].title === "Media"
    onPreviewingChanged: {
        Player.pinned = previewing
        if (previewing) {
            const s = Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]
            Player.showAtPill(s)
        } else Player.open = false
    }

    readonly property var pages: [
        { title: "Bar",           icon: 0xF0570 },   // dock-top
        { title: "Theme",         icon: 0xF03D8 },   // palette
        { title: "System",        icon: 0xF0EE0 },   // cpu
        { title: "Media",         icon: 0xF075A },   // music
        { title: "Panels",        icon: 0xF0328 },   // layers
        { title: "Alerts",        icon: 0xF009A },   // bell
    ]
    // friendlier names for the module chips
    readonly property var moduleNames: ({ SysStats: "System stats", Idle: "Caffeine", Dnd: "Notifications", Backlight: "Brightness" })

    // reflect open state so other surfaces (e.g. the OSD) can stay quiet, mirroring Config.quickOpen
    onOpenChanged: {
        Config.settingsOpen = open
        card.progress = open ? 1 : 0   // a normal window: no pour, the compositor animates it
    }

    // `qs -c bar ipc call settings toggle`, or `... page media` to open on a page
    IpcHandler {
        target: "settings"
        function toggle(): void { Config.openSettings() }
        // `... set mediaStyle 2`: any Settings key, value as JSON (saved like a GUI change)
        function set(key: string, value: string): void {
            if (Settings.defaults[key] !== undefined) Settings[key] = JSON.parse(value)
        }
        function page(name: string): void {
            root.page = Math.max(0, root.pages.findIndex(p => p.title.toLowerCase() === name.toLowerCase()))
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
        implicitWidth: 620
        implicitHeight: 540
        minimumSize: Qt.size(620, 480)   // the pages are laid out for 620 wide
        color: "transparent"
        onClosed: root.open = false   // closed by the compositor (killactive)

        Item {
            anchors.fill: parent
            focus: root.open
            Keys.onEscapePressed: root.open = false
        }

        LiquidCard {
            id: card
            anchors.fill: parent
            radius: Theme.radius + 5
            color: Qt.alpha(Theme.mainBg, 0.98)
            border.color: Qt.alpha(Theme.mainFg, 0.35)
            border.width: 1


            // ---- sidebar ----
            Rectangle {
                id: side
                width: 168
                height: parent.height
                color: Qt.alpha(Theme.mainFg, 0.04)

                // the header ("Settings") is the title bar: drag it to move the window
                MouseArea {
                    z: 1
                    width: parent.width
                    height: 50
                    cursorShape: Qt.SizeAllCursor
                    onPressed: win.startSystemMove()
                }

                Column {
                    x: 12
                    y: 16
                    width: parent.width - 24
                    spacing: 4

                    Row {
                        spacing: 10
                        bottomPadding: 14
                        leftPadding: 4
                        Text {
                            text: Theme.g(0xF0493)   // cog
                            color: Theme.actBg
                            font { family: Theme.font; pixelSize: 20 }
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: "Settings"
                            color: Theme.mainFg
                            font { family: Theme.font; pixelSize: 15; bold: true }
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    Item {
                        width: parent.width
                        height: pageList.height
                        // highlight slides between pages
                        Rectangle {
                            width: parent.width
                            height: 32
                            radius: 10
                            y: root.page * 36
                            color: Qt.alpha(Theme.actBg, 0.22)
                            border.color: Qt.alpha(Theme.actBg, 0.45)
                            border.width: 1
                            Behavior on y { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                        }
                        Column {
                            id: pageList
                            width: parent.width
                            spacing: 4
                            Repeater {
                                model: root.pages
                                Item {
                                    required property var modelData
                                    required property int index
                                    width: pageList.width
                                    height: 32
                                    HoverHandler { id: ph; cursorShape: Qt.PointingHandCursor }
                                    TapHandler { onTapped: root.page = index }
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 10
                                        color: ph.hovered && root.page !== index ? Qt.alpha(Theme.mainFg, 0.08) : "transparent"
                                    }
                                    Row {
                                        x: 10
                                        spacing: 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        Text {
                                            width: 18
                                            text: Theme.g(modelData.icon)
                                            color: root.page === index ? Theme.actFg : Theme.mainFg
                                            font { family: Theme.font; pixelSize: 15 }
                                        }
                                        Text {
                                            text: modelData.title
                                            color: root.page === index ? Theme.actFg : Theme.mainFg
                                            opacity: root.page === index || ph.hovered ? 1 : 0.75
                                            font { family: Theme.font; pixelSize: 12; bold: root.page === index }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                PillButton {
                    anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 16 }
                    text: Theme.g(0xF0450) + "  Reset all"
                    onClicked: Settings.reset()
                }
            }

            // ---- page ----
            Item {
                id: pane
                anchors { left: side.right; right: parent.right; top: parent.top; bottom: parent.bottom }

                RowLayout {
                    id: header
                    anchors { top: parent.top; left: parent.left; right: parent.right; margins: 16; leftMargin: 22 }
                    Text {
                        Layout.fillWidth: true
                        text: root.pages[root.page].title
                        color: Theme.mainFg
                        font { family: Theme.font; pixelSize: 15; bold: true }
                    }
                    Rectangle {
                        implicitWidth: 28; implicitHeight: 28
                        radius: 14
                        color: closeHover.hovered ? Qt.alpha(Theme.mainFg, 0.18) : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }
                        HoverHandler { id: closeHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: root.open = false }
                        Text {
                            anchors.centerIn: parent
                            text: Theme.g(0xF0156)   // close
                            color: Theme.mainFg
                            font { family: Theme.font; pixelSize: 15 }
                        }
                    }
                }

                Flickable {
                    id: scroll
                    anchors { top: header.bottom; topMargin: 10; left: parent.left; right: parent.right; bottom: parent.bottom; bottomMargin: 12; leftMargin: 22; rightMargin: 18 }
                    clip: true
                    contentWidth: width
                    contentHeight: pageLoader.height
                    boundsBehavior: Flickable.StopAtBounds

                    Loader {
                        id: pageLoader
                        width: scroll.width
                        sourceComponent: [barPage, themePage, systemPage, mediaPage, panelsPage, alertsPage][root.page]
                        onSourceComponentChanged: { scroll.contentY = 0; swap.restart() }
                        NumberAnimation { id: swap; target: pageLoader; property: "opacity"; from: 0; to: 1; duration: 180; easing.type: Easing.OutCubic }
                    }
                }
            }
        }
    }

    // ---------- pages ----------

    Component {
        id: barPage
        ColumnLayout {
            spacing: 12
            SectionHeader { text: "Modules" }
            Hint { text: "Pick what shows in the bar. A pill left with nothing in it disappears." }
            Repeater {
                model: [["Left", Config.left], ["Centre", Config.center], ["Right", Config.right]]
                ColumnLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 6
                    Text {
                        text: modelData[0]
                        color: Theme.mainFg
                        opacity: 0.55
                        font { family: Theme.font; pixelSize: 11 }
                    }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 6
                        Repeater {
                            model: [].concat(...modelData[1].map(g => g.modules))
                            PillButton {
                                required property string modelData
                                implicitHeight: 24
                                checked: Settings.moduleShown(modelData)
                                text: (checked ? Theme.g(0xF012C) + " " : "") + (root.moduleNames[modelData] ?? modelData)
                                onClicked: Settings.setModuleShown(modelData, !checked)
                            }
                        }
                    }
                }
            }
            SectionHeader { text: "Clock" }
            SettingToggle { label: "24-hour time"; checked: Settings.clock24h; onToggled: Settings.clock24h = !Settings.clock24h }
            SectionHeader { text: "Visibility" }
            SettingToggle {
                label: "Show the bar"
                hint: "Also SUPER+CTRL+B"
                checked: Config.barVisible
                onToggled: Config.barVisible = !Config.barVisible
            }
        }
    }

    Component {
        id: themePage
        ColumnLayout {
            spacing: 12
            SectionHeader { text: "Bar colours" }
            Hint { text: "Pick a HyDE colour to follow theme and wallpaper switches, or type a #hex to fix it (8 digits put alpha first: #AARRGGBB). Every colour in these settings works the same way." }
            ColorRow { label: "Bar background"; value: Settings.themeBarBg; onEdited: v => Settings.themeBarBg = v }
            ColorRow { label: "Pill background"; value: Settings.themeMainBg; onEdited: v => Settings.themeMainBg = v }
            ColorRow { label: "Text"; value: Settings.themeMainFg; onEdited: v => Settings.themeMainFg = v }
            ColorRow { label: "Active"; value: Settings.themeActBg; onEdited: v => Settings.themeActBg = v }
            ColorRow { label: "Active text"; value: Settings.themeActFg; onEdited: v => Settings.themeActFg = v }
            ColorRow { label: "Hover"; value: Settings.themeHvrBg; onEdited: v => Settings.themeHvrBg = v }
            ColorRow { label: "Hover text"; value: Settings.themeHvrFg; onEdited: v => Settings.themeHvrFg = v }
            ColorRow { label: "Menu text"; value: Settings.themeMenuFg; onEdited: v => Settings.themeMenuFg = v }
        }
    }

    Component {
        id: systemPage
        ColumnLayout {
            spacing: 12
            SectionHeader { text: "System stats" }
            SettingSlider {
                label: "Sample every"
                suffix: " s"
                decimals: 1
                from: 1; to: 10; step: 0.5
                value: Settings.sysInterval / 1000
                onEdited: v => Settings.sysInterval = Math.round(v * 1000)
            }
            SettingToggle {
                label: "Rolling numbers"
                hint: "Off saves a little CPU: each roll repaints the bar"
                checked: Settings.numberRoll
                onToggled: Settings.numberRoll = !Settings.numberRoll
            }
            ColorRow { label: "CPU colour"; value: Settings.sysColCpu; onEdited: v => Settings.sysColCpu = v }
            ColorRow { label: "RAM colour"; value: Settings.sysColRam; onEdited: v => Settings.sysColRam = v }
            ColorRow { label: "Temp colour"; value: Settings.sysColTemp; onEdited: v => Settings.sysColTemp = v }

            SectionHeader { text: "Network graph" }
            ColorRow { label: "Download colour"; value: Settings.netColDown; onEdited: v => Settings.netColDown = v }
            ColorRow { label: "Upload colour"; value: Settings.netColUp; onEdited: v => Settings.netColUp = v }
        }
    }

    Component {
        id: mediaPage
        ColumnLayout {
            spacing: 12
            Hint { visible: !Player.player; text: "Play something to preview these live on the pill and the panel." }
            SectionHeader { text: "Now playing pill" }
            Hint { text: "What the pill draws from the music behind or beside the title." }
            StyleChoice {
                names: ["Columns", "Ambient", "Mini EQ", "Strip", "Waveform"]
                value: Settings.mediaStyle
                onPicked: i => Settings.mediaStyle = i
            }
            SectionHeader { text: "Now playing panel" }
            StyleChoice {
                names: ["Turntable", "Poster", "Waveform", "Matrix", "Aurora"]
                value: Settings.panelLayout
                onPicked: i => Settings.panelLayout = i
            }
            Hint { visible: Settings.panelLayout === 0; text: "Turntable: what sits in the middle, and the spectrum around it." }
            StyleChoice {
                visible: Settings.panelLayout === 0
                names: ["Vinyl", "Cover", "Orb"]
                value: Settings.panelCenter
                onPicked: i => Settings.panelCenter = i
            }
            StyleChoice {
                visible: Settings.panelLayout === 0
                names: ["Spokes", "Aura", "Liquid", "LED"]
                value: Settings.panelStyle
                onPicked: i => Settings.panelStyle = i
            }
            SectionHeader { text: "Beat effects" }
            SettingToggle {
                label: "React to the beat"
                hint: "The wave along the bar, pill rims, window-border glow and sparks"
                checked: Settings.beatEffects
                onToggled: Settings.beatEffects = !Settings.beatEffects
            }
            SettingSlider {
                enabled: Settings.beatEffects
                label: "Wave reach"
                suffix: " px"
                from: 400; to: 5000; step: 50
                value: Settings.waveReach
                onEdited: v => Settings.waveReach = v
            }
            SettingSlider {
                enabled: Settings.beatEffects
                label: "Wave duration"
                suffix: " s"
                decimals: 2
                from: 0.2; to: 3.0; step: 0.05
                value: Settings.waveDur
                onEdited: v => Settings.waveDur = v
            }
            SectionHeader { text: "Beat detection" }
            Hint { text: "A kick is a bass rise that stands out from the last few seconds. Lower sensitivity and floor catch more (and more false) beats." }
            SettingSlider {
                enabled: Settings.beatEffects
                label: "Sensitivity"
                suffix: " sd"
                decimals: 2
                from: 0; to: 2.0; step: 0.05
                value: Settings.beatSens
                onEdited: v => Settings.beatSens = v
            }
            SettingSlider {
                enabled: Settings.beatEffects
                label: "Rise floor"
                decimals: 3
                from: 0; to: 0.08; step: 0.002
                value: Settings.beatFloor
                onEdited: v => Settings.beatFloor = v
            }
            SettingSlider {
                enabled: Settings.beatEffects
                label: "Min gap"
                suffix: " s"
                decimals: 2
                from: 0.1; to: 0.6; step: 0.01
                value: Settings.beatGap
                onEdited: v => Settings.beatGap = v
            }
            SectionHeader { text: "Lyrics" }
            SettingToggle {
                label: "Show synced lyrics"
                hint: "From lrclib.net, under the artist in the Now Playing panel"
                checked: Settings.lyrics
                onToggled: Settings.lyrics = !Settings.lyrics
            }
            SettingSlider {
                enabled: Settings.lyrics
                label: "Offset"
                suffix: " s"
                decimals: 2
                from: -1.5; to: 1.5; step: 0.05
                value: Settings.lyricsOffset
                onEdited: v => Settings.lyricsOffset = v
            }
            Hint { visible: Settings.lyrics; text: "Lyrics early? Slide left. Bluetooth headphones usually want about −0.3 s." }
        }
    }

    Component {
        id: panelsPage
        ColumnLayout {
            spacing: 12
            SectionHeader { text: "Hover cards" }
            Hint { text: "Now Playing, system stats and network pour out of their pill when the pointer rests on it." }
            SettingSlider {
                label: "Open after"
                suffix: " ms"
                from: 0; to: 1000; step: 20
                value: Settings.hoverDelay
                onEdited: v => Settings.hoverDelay = v
            }
            SettingSlider {
                label: "Liquid speed"
                suffix: "×"
                decimals: 2
                from: 0.5; to: 2.5; step: 0.05
                value: Settings.liquidSpeed
                onEdited: v => Settings.liquidSpeed = v
            }
            SectionHeader { text: "Quick settings" }
            SettingToggle {
                label: "Open from the screen edge"
                hint: "Rest the pointer on the right edge, under the bar"
                checked: Settings.quickEdge
                onToggled: Settings.quickEdge = !Settings.quickEdge
            }
        }
    }

    Component {
        id: alertsPage
        ColumnLayout {
            spacing: 12
            SectionHeader { text: "Notifications" }
            SettingToggle {
                label: "Do not disturb"
                hint: "Popups are held until it's turned off"
                checked: Config.dnd
                onToggled: Config.dnd = !Config.dnd
            }
            SettingToggle {
                label: "Pause history"
                checked: Config.historyPaused
                onToggled: Config.historyPaused = !Config.historyPaused
            }
            SettingSlider {
                label: "Default timeout"
                suffix: " s"
                decimals: 1
                from: 1; to: 20; step: 0.5
                value: Settings.notifTimeout / 1000
                onEdited: v => Settings.notifTimeout = Math.round(v * 1000)
            }

            SectionHeader { text: "On-screen display" }
            SettingSlider {
                label: "Stays up for"
                suffix: " s"
                decimals: 1
                from: 0.5; to: 5; step: 0.1
                value: Settings.osdTimeout / 1000
                onEdited: v => Settings.osdTimeout = Math.round(v * 1000)
            }
            SettingSlider {
                label: "Quiet at startup"
                suffix: " s"
                decimals: 1
                from: 0; to: 5; step: 0.1
                value: Settings.osdArmDelay / 1000
                onEdited: v => Settings.osdArmDelay = Math.round(v * 1000)
            }

            SectionHeader { text: "Battery" }
            SettingSlider {
                label: "Warning below"
                suffix: "%"
                from: 5; to: 50; step: 1
                value: Settings.batteryWarn
                onEdited: v => Settings.batteryWarn = Math.max(v, Settings.batteryLow)
            }
            SettingSlider {
                label: "Critical below"
                suffix: "%"
                from: 3; to: 30; step: 1
                value: Settings.batteryLow
                onEdited: v => Settings.batteryLow = Math.min(v, Settings.batteryWarn)
            }
            Hint { text: "Critical also sends one notification per discharge." }
        }
    }

    // ---------- row components ----------

    // a titled section divider (components/Section.qml is the bar's pill row, not this)
    component SectionHeader: RowLayout {
        id: sh
        property string text: ""
        Layout.fillWidth: true
        Layout.topMargin: 6
        spacing: 8
        Text {
            text: sh.text
            color: Theme.actBg
            font { family: Theme.font; pixelSize: 12; bold: true }
        }
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 1
            color: Qt.alpha(Theme.mainFg, 0.18)
        }
    }

    component Hint: Text {
        Layout.fillWidth: true
        wrapMode: Text.WordWrap
        color: Theme.mainFg
        opacity: 0.5
        font { family: Theme.font; pixelSize: 11 }
    }

    // label (and an optional hint under it) with a switch on the right
    component SettingToggle: RowLayout {
        id: trow
        property string label
        property string hint: ""
        property bool checked: false
        signal toggled()
        Layout.fillWidth: true
        spacing: 10
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            Text {
                Layout.fillWidth: true   // keeps the switch at the right edge when there's no hint
                text: trow.label
                color: Theme.mainFg
                font { family: Theme.font; pixelSize: 12 }
            }
            Text {
                visible: trow.hint !== ""
                Layout.fillWidth: true
                text: trow.hint
                wrapMode: Text.WordWrap
                color: Theme.mainFg
                opacity: 0.5
                font { family: Theme.font; pixelSize: 10 }
            }
        }
        Toggle { checked: trow.checked; onToggled: trow.toggled() }
    }

    // numeric slider row: label, Slider, live readout. Reads `value`, maps it to the
    // Slider's 0..1, writes back via edited(real).
    component SettingSlider: RowLayout {
        id: srow
        property string label
        property string suffix: ""
        property real from: 0
        property real to: 1
        property real step: 0
        property int decimals: 0
        property real value: 0
        signal edited(real v)

        Layout.fillWidth: true
        spacing: 10
        opacity: enabled ? 1 : 0.4

        Text {
            Layout.preferredWidth: 120
            text: srow.label
            color: Theme.mainFg
            font { family: Theme.font; pixelSize: 12 }
            elide: Text.ElideRight
        }
        Slider {
            Layout.fillWidth: true
            value: srow.to > srow.from ? (srow.value - srow.from) / (srow.to - srow.from) : 0
            onMoved: v => {
                let raw = srow.from + v * (srow.to - srow.from)
                if (srow.step > 0) raw = Math.round(raw / srow.step) * srow.step
                srow.edited(raw)
            }
        }
        Text {
            Layout.preferredWidth: 60
            horizontalAlignment: Text.AlignRight
            text: srow.value.toFixed(srow.decimals) + srow.suffix
            color: Theme.actFg
            font { family: Theme.font; pixelSize: 12; bold: true }
        }
    }

    // colour row: label, swatch, value field and a palette button. The value is "@name" (a
    // HyDE colour variable, followed through theme switches) or a fixed "#hex": pick a swatch
    // from the palette for the first, type a hex for the second.
    component ColorRow: ColumnLayout {
        id: crow
        property string label
        property string value: "#000000"
        signal edited(string v)
        property bool picking: false
        property string hoverName: ""
        readonly property bool isVar: field.text.startsWith("@")
        // a variable only counts if HyDE actually defines it right now
        readonly property bool valid: isVar ? Theme.has(field.text.slice(1))
            : /^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.test(field.text)
        readonly property color resolved: Theme.color(field.text, "transparent")

        Layout.fillWidth: true
        spacing: 6

        RowLayout {
            Layout.fillWidth: true
            spacing: 10
            Text {
                Layout.preferredWidth: 120
                text: crow.label
                color: Theme.mainFg
                font { family: Theme.font; pixelSize: 12 }
                elide: Text.ElideRight
            }
            // what the value resolves to right now; a "?" when it resolves to nothing
            Rectangle {
                implicitWidth: 22; implicitHeight: 22
                radius: 6
                color: crow.valid ? crow.resolved : "transparent"
                border.color: crow.valid ? Qt.alpha(Theme.mainFg, 0.4) : "#f7768e"
                border.width: 1
                TapHandler { onTapped: crow.picking = !crow.picking }
                Text {
                    anchors.centerIn: parent
                    visible: !crow.valid
                    text: "?"
                    color: "#f7768e"
                    font { family: Theme.font; pixelSize: 12; bold: true }
                }
            }
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 26
                radius: 7
                color: Qt.alpha(Theme.mainFg, 0.08)
                border.color: field.activeFocus ? Theme.actBg
                    : crow.valid ? Qt.alpha(Theme.mainFg, 0.25) : "#f7768e"
                border.width: 1
                Behavior on border.color { ColorAnimation { duration: 120 } }
                TextInput {
                    id: field
                    anchors { fill: parent; leftMargin: 8; rightMargin: badge.width + 12 }
                    verticalAlignment: TextInput.AlignVCenter
                    text: crow.value
                    color: Theme.mainFg
                    font { family: Theme.font; pixelSize: 12 }
                    selectByMouse: true
                    clip: true
                    onTextEdited: if (crow.valid) crow.edited(text)
                    // follow the model (reset / external change / palette pick) while not being edited
                    Connections {
                        target: crow
                        function onValueChanged() { if (!field.activeFocus) field.text = crow.value }
                    }
                }
                // which kind it is: following HyDE, or fixed
                Rectangle {
                    id: badge
                    anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                    implicitWidth: badgeText.implicitWidth + 10
                    implicitHeight: 18
                    radius: 9
                    readonly property bool hyde: crow.isVar
                    readonly property bool missing: hyde && !crow.valid
                    color: missing ? Qt.alpha("#f7768e", 0.2) : hyde ? Qt.alpha(Theme.actBg, 0.25) : Qt.alpha(Theme.mainFg, 0.12)
                    Text {
                        id: badgeText
                        anchors.centerIn: parent
                        // a followed variable shows what it is right now
                        text: badge.missing ? "not in HyDE" : badge.hyde ? "HyDE " + Qt.color(crow.resolved).toString() : "custom"
                        color: badge.missing ? "#f7768e" : badge.hyde ? Theme.actBg : Theme.mainFg
                        opacity: badge.hyde ? 1 : 0.6
                        font { family: Theme.font; pixelSize: 9; bold: true }
                    }
                }
            }
            Rectangle {
                implicitWidth: 26; implicitHeight: 26
                radius: 7
                color: crow.picking ? Qt.alpha(Theme.actBg, 0.3) : palHover.hovered ? Qt.alpha(Theme.mainFg, 0.15) : Qt.alpha(Theme.mainFg, 0.08)
                Behavior on color { ColorAnimation { duration: 120 } }
                HoverHandler { id: palHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: crow.picking = !crow.picking }
                Text {
                    anchors.centerIn: parent
                    text: Theme.g(0xF03D8)   // palette
                    color: crow.picking ? Theme.actFg : Theme.mainFg
                    font { family: Theme.font; pixelSize: 14 }
                }
            }
        }

        // the palette: HyDE's bar colours and the four wallbash groups (primary, text, nine accents)
        Loader {
            active: crow.picking
            visible: active
            Layout.fillWidth: true
            Layout.leftMargin: 130
            sourceComponent: Rectangle {
                implicitHeight: pal.implicitHeight + 16
                radius: 9
                color: Qt.alpha(Theme.mainFg, 0.05)
                border.color: Qt.alpha(Theme.mainFg, 0.12)
                border.width: 1
                Column {
                    id: pal
                    x: 8; y: 8
                    width: parent.width - 16
                    spacing: 5
                    Text { text: "Bar theme"; color: Theme.mainFg; opacity: 0.5; font { family: Theme.font; pixelSize: 10 } }
                    Row { spacing: 4; Repeater { model: Theme.themeVars; Swatch { required property string modelData; row: crow; name: modelData } } }
                    Text { topPadding: 2; text: "Wallbash"; color: Theme.mainFg; opacity: 0.5; font { family: Theme.font; pixelSize: 10 } }
                    Repeater {
                        model: Theme.paletteVars
                        Row {
                            required property var modelData
                            spacing: 4
                            Repeater { model: modelData; Swatch { required property string modelData; row: crow; name: modelData } }
                        }
                    }
                    RowLayout {
                        width: parent.width
                        Text {
                            Layout.fillWidth: true
                            text: crow.hoverName ? "@" + crow.hoverName : (field.text.startsWith("@") ? "following " + field.text : "custom colour")
                            color: Theme.mainFg
                            opacity: 0.7
                            elide: Text.ElideRight
                            font { family: Theme.font; pixelSize: 10 }
                        }
                        // turn a followed colour into a fixed one, starting from what it is now
                        PillButton {
                            visible: field.text.startsWith("@")
                            text: "Make custom"
                            onClicked: crow.edited(Qt.color(Theme.color(crow.value, "#000000")).toString())
                        }
                    }
                }
            }
        }
    }

    // one palette colour; picks "@name" for its row
    component Swatch: Rectangle {
        property var row
        property string name
        readonly property bool current: row.value === "@" + name
        width: 18; height: 18
        radius: 5
        visible: Theme.has(name)   // a theme without it leaves no empty slot
        color: Theme.color("@" + name, "transparent")
        border.color: current ? Theme.actFg : Qt.alpha(Theme.mainFg, 0.25)
        border.width: current ? 2 : 1
        scale: sh.hovered ? 1.15 : 1
        Behavior on scale { NumberAnimation { duration: 100 } }
        HoverHandler {
            id: sh
            cursorShape: Qt.PointingHandCursor
            onHoveredChanged: if (hovered) row.hoverName = name; else if (row.hoverName === name) row.hoverName = ""
        }
        TapHandler { onTapped: row.edited("@" + name) }
    }
}
