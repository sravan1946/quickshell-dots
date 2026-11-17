import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.islands

// Notification history as a timeline. Times run down a gutter on the left, then a rail: each
// run of notifications from one app hangs off that app's icon, and each later one in the run
// is a dot on the same line. Days break the rail. Long runs fold after two ("+4 more").
// Across the top: do not disturb, pause, clear all, and a row of app icons that filters.
// Hover a notification for copy and dismiss, swipe it right to dismiss, tap it for all it said.
// Anything newer than the last time the panel was open is marked in the accent colour.
// While it's open, new notifications land here instead of popping up (Config.historyOpen).
Panel {
    id: p
    implicitWidth: 400
    spacing: 12

    property real seenAt: 0
    property bool intro: true        // the first rows stagger in as it opens
    Timer { running: true; interval: 600; onTriggered: p.intro = false }
    Component.onCompleted: { seenAt = NoteState.seen; Config.historyOpen = true; NoteState.markRead(); rebuild() }
    Component.onDestruction: { Config.historyOpen = false; NoteState.markRead() }

    property string filter: ""       // one app, or "" for all
    property var expanded: ({})      // run key -> open
    property var apps: []            // [{ app, count, icon, entry, unread }], newest first
    property var rows: []            // the timeline, flat: day / note / more rows
    property int total: 0
    property int fresh: 0            // unread
    property string hint: ""         // what the pointer is on, in the subtitle
    onFilterChanged: rebuild()
    onExpandedChanged: rebuild()
    Connections { target: History.entries; function onCountChanged() { p.hint = ""; p.rebuild(); NoteState.markRead() } }

    readonly property int fold: 3    // a run longer than this shows its newest two
    function rebuild() {
        const by = {}, order = [], runs = []
        let fresh = 0
        for (let i = 0; i < History.entries.count; i++) {
            const m = History.entries.get(i)
            const e = { kind: "note", key: m.key, app: m.app, summary: m.summary, body: m.body, icon: m.icon,
                        entry: m.entry, critical: m.critical, time: m.time, unread: m.time > seenAt }
            if (e.unread) fresh++
            if (!by[e.app]) order.push(by[e.app] = { app: e.app, count: 0, icon: e.icon, entry: e.entry, unread: false })
            by[e.app].count++
            if (e.unread) by[e.app].unread = true
            if (filter && e.app !== filter) continue
            const day = dayOf(e.time), last = runs[runs.length - 1]
            if (last && last.day === day && last.app === e.app) last.items.push(e)
            else runs.push({ day: day, app: e.app, items: [e] })
        }
        if (filter && !by[filter]) { filter = ""; return }   // its last one went: back to all

        const out = []
        runs.forEach((r, ri) => {
            const key = r.items[r.items.length - 1].key   // the oldest: stays as newer ones land on top
            const newDay = ri === 0 || runs[ri - 1].day !== r.day
            if (newDay) out.push({ kind: "day", key: "d" + r.day, day: r.day, first: ri === 0 })
            const open = !!expanded[key], folds = r.items.length > fold
            const shown = folds && !open ? r.items.slice(0, 2) : r.items
            shown.forEach((e, i) => out.push(Object.assign(e, { head: i === 0, dayFirst: newDay && i === 0 })))
            if (folds) out.push({ kind: "more", key: "m" + key, run: key, app: r.app, open: open,
                                  hidden: r.items.length - 2, keys: r.items.map(x => x.key) })
        })
        // the rail stops at each day's last row
        out.forEach((x, i) => x.dayLast = x.kind !== "day" && (i === out.length - 1 || out[i + 1].kind === "day"))
        rows = out
        apps = order
        total = History.entries.count
        p.fresh = fresh
    }

    property real now: Date.now()
    Timer { interval: 30000; running: true; repeat: true; onTriggered: p.now = Date.now() }
    function dayOf(ms) { const d = new Date(ms); d.setHours(0, 0, 0, 0); return d.getTime() }
    function dayLabel(day) {
        const today = dayOf(now)
        return day === today ? "Today" : day === dayOf(today - 1) ? "Yesterday" : Qt.formatDate(new Date(day), "dddd d MMMM")
    }
    function when(ms) {
        const s = Math.max(0, Math.floor((now - ms) / 1000))
        return s < 60 ? "now" : s < 3600 ? Math.floor(s / 60) + "m" : Qt.formatTime(new Date(ms), "hh:mm")
    }
    function plain(s) { return s.replace(/<[^>]*>/g, "") }
    readonly property string subtitle: hint !== "" ? hint
        : Config.historyPaused ? "Paused, new ones aren't kept"
        : filter ? `${filter}  ·  ${apps.find(a => a.app === filter)?.count ?? 0}`
        : total === 0 ? "Nothing here"
        : fresh > 0 ? `${total}  ·  ${fresh} new` : `${total}`

    // ---- small round icon button: the subtitle says what it does ----
    component IconBtn: Rectangle {
        id: ib
        property int glyph
        property string tip
        property bool on: false
        property color tone: Look.accent
        signal clicked()
        implicitWidth: 30
        implicitHeight: 30
        radius: 15
        color: on ? Qt.alpha(tone, ih.hovered ? 0.32 : 0.22) : ih.hovered ? Look.hover : "transparent"
        Behavior on color { Fade {} }
        G {
            anchors.centerIn: parent
            glyph: ib.glyph
            font.pixelSize: 15
            color: ib.on ? ib.tone : ih.hovered ? Look.text : Look.dim
            Behavior on color { Fade {} }
        }
        HoverHandler { id: ih; cursorShape: Qt.PointingHandCursor; onHoveredChanged: p.hint = hovered ? ib.tip : (p.hint === ib.tip ? "" : p.hint) }
        TapHandler { onTapped: ib.clicked() }
    }

    // ---- header ----
    Item {
        width: parent.width
        height: 36
        Column {
            anchors.verticalCenter: parent.verticalCenter
            x: 2
            spacing: 1
            T { text: "Notifications"; font.pixelSize: 15; font.weight: Font.DemiBold }
            T {
                text: p.subtitle
                color: Config.historyPaused && p.hint === "" ? Look.urgent : Look.faint
                font.pixelSize: Look.small
                Behavior on color { Fade {} }
            }
        }
        Row {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: 2
            IconBtn {
                glyph: 0xF0A93
                tip: Config.dnd ? "Do not disturb is on" : "Do not disturb"
                on: Config.dnd
                onClicked: Config.dnd = !Config.dnd
            }
            IconBtn {
                glyph: Config.historyPaused ? 0xF040D : 0xF03E6
                tip: Config.historyPaused ? "Resume keeping history" : "Pause history"
                on: Config.historyPaused
                tone: Look.urgent
                onClicked: Config.historyPaused = !Config.historyPaused
            }
            IconBtn {
                glyph: 0xF039F
                tip: p.filter ? `Clear ${p.filter}` : "Clear all"
                tone: Look.alert
                opacity: p.total > 0 ? 1 : 0.3
                enabled: p.total > 0
                onClicked: { p.hint = ""; p.filter ? History.removeApp(p.filter) : History.clear() }
            }
        }
    }

    // ---- apps: an icon each, with its count; tap one to see only it ----
    component AppDot: Item {
        id: ad
        property string app
        property string icon: ""
        property string entry: ""
        property int glyph: 0
        property int count
        property bool unread: false
        readonly property bool on: glyph ? p.filter === "" : p.filter === app
        implicitWidth: 34
        implicitHeight: 38
        opacity: p.filter === "" || on || dh.hovered ? 1 : 0.4
        Behavior on opacity { Anim { type: "effects" } }
        Rectangle {
            id: disc
            width: 34; height: 34
            radius: 17
            color: dh.hovered ? Look.hover : Look.raise
            border.width: 2
            border.color: ad.on && p.apps.length > 1 ? Look.accent : "transparent"
            Behavior on color { Fade {} }
            Behavior on border.color { Fade {} }
            Image {
                visible: !ad.glyph && ad.icon !== ""
                anchors.centerIn: parent
                source: visible ? ad.icon : ""
                sourceSize: Qt.size(40, 40)
                width: 20; height: 20
                mipmap: true
            }
            AppIcon {
                visible: !ad.glyph && ad.icon === ""
                anchors.centerIn: parent
                appId: visible ? (ad.entry || ad.app) : ""
                size: 20
            }
            G { visible: ad.glyph !== 0; anchors.centerIn: parent; glyph: ad.glyph; font.pixelSize: 16; color: Look.dim }
        }
        // the count, on the disc's lower right edge
        Rectangle {
            x: disc.width - width + 4
            y: disc.height - height + 2
            width: Math.max(16, num.implicitWidth + 8)
            height: 16
            radius: 8
            color: ad.unread ? Look.accent : Qt.tint(Look.base, Qt.alpha("white", 0.16))
            border.width: 2
            border.color: Look.surface
            T {
                id: num
                anchors.centerIn: parent
                text: ad.count > 99 ? "99+" : ad.count
                color: ad.unread ? Look.accentInk : Look.text
                font.pixelSize: 9
                font.weight: Font.Bold
            }
        }
        HoverHandler {
            id: dh
            cursorShape: Qt.PointingHandCursor
            readonly property string tip: `${ad.app}  ·  ${ad.count}`
            onHoveredChanged: p.hint = hovered ? tip : (p.hint === tip ? "" : p.hint)
        }
        TapHandler { onTapped: p.filter = ad.glyph || ad.on ? "" : ad.app }
    }
    Flickable {
        visible: p.apps.length > 1
        width: parent.width
        height: 38
        contentWidth: dots.implicitWidth
        clip: contentWidth > width
        interactive: contentWidth > width
        boundsBehavior: Flickable.StopAtBounds
        WheelHandler {
            onWheel: e => parent.contentX = Math.max(0, Math.min(parent.contentWidth - parent.width, parent.contentX - e.angleDelta.y))
        }
        Row {
            id: dots
            spacing: 8
            AppDot { app: "Everything"; glyph: 0xF003B; count: p.total; unread: p.fresh > 0 }
            Repeater {
                model: p.apps
                AppDot {
                    required property var modelData
                    app: modelData.app || "Unknown"
                    icon: modelData.icon
                    entry: modelData.entry
                    count: modelData.count
                    unread: modelData.unread
                }
            }
        }
    }

    // ---- the timeline ----
    // gutter (time) | rail (icon or dot on a line) | what it said
    readonly property int gutter: 40
    readonly property int railX: gutter + 20        // the line's centre
    readonly property int textX: gutter + 46
    // the rail: a hairline down each day
    component Rail: Rectangle {
        x: p.railX - 0.5
        width: 1
        color: Look.line
    }
    ListView {
        id: list
        width: parent.width
        height: Math.min(contentHeight, 470)
        visible: p.rows.length > 0
        clip: true
        interactive: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds
        model: ScriptModel { values: p.rows }
        add: Transition { Anim { property: "opacity"; from: 0; to: 1; type: "effects" } }
        remove: Transition {
            ParallelAnimation {
                Anim { property: "opacity"; to: 0; type: "exit" }
                Anim { property: "x"; to: 60; type: "exit" }
            }
        }
        displaced: Transition {
            Anim { property: "y"; type: "spatial" }
            Anim { property: "opacity"; to: 1; type: "effects" }
            Anim { property: "x"; to: 0; type: "effects" }
        }

        // where you are in a long list: a thin thumb on the right, only while it scrolls
        Rectangle {
            visible: list.contentHeight > list.height
            parent: list
            x: list.width - 3
            width: 3
            radius: 1.5
            height: Math.max(24, list.height * list.height / list.contentHeight)
            y: (list.height - height) * (list.contentY / Math.max(1, list.contentHeight - list.height))
            color: Look.faint
            opacity: list.moving ? 0.8 : 0
            Behavior on opacity { Anim { type: "effects" } }
            z: 2
        }

        delegate: Item {
            id: del
            required property var modelData
            required property int index
            readonly property var d: modelData
            width: ListView.view.width
            height: ld.item?.height ?? 0

            // the first rows arrive one after another as the panel opens
            property real enter: p.intro && index < 12 ? 0 : 1
            Component.onCompleted: if (enter < 1) introAnim.start()
            SequentialAnimation {
                id: introAnim
                PauseAnimation { duration: del.index * 28 * Look.speed }
                Anim { target: del; property: "enter"; to: 1; type: "enter" }
            }

            Loader {
                id: ld
                width: parent.width
                opacity: del.enter
                transform: Translate { y: (1 - del.enter) * 10 }
                sourceComponent: del.d.kind === "day" ? dayRow : del.d.kind === "more" ? moreRow : noteRow
            }

            Component {
                id: dayRow
                Item {
                    height: del.d.first ? 24 : 40
                    T {
                        id: dl
                        x: 2
                        anchors.bottom: parent.bottom
                        bottomPadding: 6
                        text: p.dayLabel(del.d.day)
                        color: Look.dim
                        font.pixelSize: Look.small
                        font.weight: Font.DemiBold
                        font.letterSpacing: 0.4
                    }
                    Rectangle {
                        x: dl.x + dl.implicitWidth + 10
                        width: parent.width - x
                        height: 1
                        anchors.verticalCenter: dl.verticalCenter
                        anchors.verticalCenterOffset: -3
                        color: Look.line
                    }
                }
            }

            Component {
                id: moreRow
                Item {
                    height: 30
                    Rail { y: 0; height: del.d.dayLast ? parent.height / 2 : parent.height }
                    // three small dots on the line: more of the same, folded
                    Column {
                        x: p.railX - 1.5
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        Repeater { model: 3; Rectangle { width: 3; height: 3; radius: 1.5; color: Look.faint } }
                    }
                    T {
                        x: p.textX
                        anchors.verticalCenter: parent.verticalCenter
                        text: del.d.open ? "Show less" : `${del.d.hidden} more from ${del.d.app || "Unknown"}`
                        color: mh.hovered ? Look.text : Look.accent
                        font.pixelSize: Look.small
                        font.weight: Font.DemiBold
                        HoverHandler { id: mh; cursorShape: Qt.PointingHandCursor }
                        TapHandler {
                            onTapped: { const x = Object.assign({}, p.expanded); x[del.d.run] = !del.d.open; p.expanded = x }
                        }
                    }
                    T {
                        anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                        text: `Clear ${del.d.keys.length}`
                        color: ch.hovered ? Look.alert : Look.faint
                        font.pixelSize: Look.small
                        HoverHandler { id: ch; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: History.removeKeys(del.d.keys) }
                    }
                }
            }

            Component {
                id: noteRow
                Item {
                    id: row
                    readonly property var e: del.d
                    readonly property string code: History.otp(e.summary, e.body)
                    readonly property real gap: e.head && !e.dayFirst ? 10 : 0   // between runs
                    readonly property real padTop: gap + 6
                    // where the rail's node sits: the icon on a run's first row, a dot after
                    readonly property real nodeY: e.head ? padTop + 13 : padTop + summary.y + summary.height / 2
                    property bool full: false
                    property bool copied: false
                    height: padTop + col.implicitHeight + 8

                    Rail { y: 0; height: row.nodeY; visible: !row.e.dayFirst }
                    Rail { y: row.nodeY; height: row.height - row.nodeY; visible: !row.e.dayLast }

                    // time, level with what it says
                    T {
                        width: p.gutter
                        y: row.padTop + summary.y
                        height: summary.height
                        horizontalAlignment: Text.AlignRight
                        text: p.when(row.e.time)
                        color: row.e.unread ? Look.accent : Look.faint
                        font.pixelSize: Look.small
                        font.weight: row.e.unread ? Font.DemiBold : Font.Normal
                    }

                    // the node
                    Rectangle {
                        visible: row.e.head
                        x: p.railX - 13
                        y: row.padTop
                        width: 26; height: 26
                        radius: 13
                        color: Qt.tint(Look.base, Qt.alpha("white", 0.1))
                        border.width: row.e.critical || row.e.unread ? 2 : 0
                        border.color: row.e.critical ? Look.alert : Look.accent
                        Image {
                            visible: row.e.icon !== ""
                            anchors.centerIn: parent
                            source: visible ? row.e.icon : ""
                            sourceSize: Qt.size(36, 36)
                            width: 16; height: 16
                            mipmap: true
                        }
                        AppIcon { visible: row.e.icon === ""; anchors.centerIn: parent; appId: visible ? (row.e.entry || row.e.app) : ""; size: 16 }
                    }
                    Rectangle {
                        visible: !row.e.head
                        x: p.railX - 3.5
                        y: row.nodeY - 3.5
                        width: 7; height: 7
                        radius: 3.5
                        color: row.e.critical ? Look.alert : row.e.unread ? Look.accent : Qt.tint(Look.base, Qt.alpha("white", 0.3))
                    }

                    // what it said: hover lifts it, a swipe right dismisses it
                    Item {
                        id: slide
                        width: parent.width
                        height: parent.height
                        opacity: 1 - Math.min(1, x / (width / 2))
                        Rectangle {
                            x: p.textX - 10
                            y: row.gap
                            width: parent.width - x
                            height: parent.height - row.gap
                            radius: 12
                            color: nh.hovered || swipe.active ? Look.raise : "transparent"
                            Behavior on color { Fade {} }
                        }
                        Column {
                            id: col
                            x: p.textX
                            y: row.padTop
                            width: parent.width - x - 10
                            spacing: 2
                            T {
                                visible: row.e.head
                                width: parent.width - acts.width
                                text: (row.e.app || "Unknown") + (row.e.critical ? "  ·  urgent" : "")
                                color: row.e.critical ? Look.alert : Look.faint
                                font.pixelSize: Look.small
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                                bottomPadding: 1
                            }
                            T {
                                id: summary
                                width: parent.width - (row.e.head ? 0 : acts.width)
                                visible: text !== ""
                                text: row.e.summary
                                font.weight: Font.DemiBold
                                wrapMode: row.full ? Text.Wrap : Text.NoWrap
                                elide: Text.ElideRight
                            }
                            T {
                                id: body
                                width: parent.width
                                visible: text !== ""
                                text: row.e.body
                                textFormat: Text.StyledText
                                color: Look.dim
                                font.pixelSize: Look.small
                                wrapMode: Text.Wrap
                                maximumLineCount: row.full ? 40 : 2
                                elide: Text.ElideRight
                                lineHeight: 1.1
                            }
                            // a one-time code, big enough to read off
                            Item { visible: row.code !== ""; width: 1; height: 4 }
                            Rectangle {
                                id: otp
                                visible: row.code !== ""
                                width: otpRow.implicitWidth + 20
                                height: 30
                                radius: 9
                                color: Qt.alpha(Look.accent, oh.hovered ? 0.24 : 0.14)
                                border.width: 1
                                border.color: Qt.alpha(Look.accent, 0.35)
                                Behavior on color { Fade {} }
                                Row {
                                    id: otpRow
                                    anchors.centerIn: parent
                                    spacing: 8
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: row.code
                                        color: Look.text
                                        font.family: Look.icons
                                        font.pixelSize: 15
                                        font.weight: Font.Bold
                                        font.letterSpacing: 2.5
                                    }
                                    G {
                                        anchors.verticalCenter: parent.verticalCenter
                                        glyph: row.copied ? 0xF012C : 0xF018F
                                        color: Look.accent
                                        font.pixelSize: 13
                                    }
                                }
                                HoverHandler { id: oh; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: { History.copy(row.code); row.copied = true } }
                            }
                        }
                        // copy and dismiss, on hover, top right
                        Row {
                            id: acts
                            anchors { right: parent.right; rightMargin: 6; top: parent.top; topMargin: row.padTop - 3 }
                            spacing: 0
                            HoverHandler { id: ah }
                            opacity: nh.hovered ? 1 : 0
                            Behavior on opacity { Anim { type: "effects" } }
                            Repeater {
                                model: [
                                    { glyph: row.copied && row.code === "" ? 0xF012C : 0xF018F, kind: "copy" },
                                    { glyph: 0xF0156, kind: "close" }
                                ]
                                Rectangle {
                                    required property var modelData
                                    width: 22; height: 22; radius: 11
                                    color: bh.hovered ? Look.hover : "transparent"
                                    G {
                                        anchors.centerIn: parent
                                        glyph: parent.modelData.glyph
                                        font.pixelSize: 12
                                        color: bh.hovered ? (parent.modelData.kind === "close" ? Look.alert : Look.text) : Look.faint
                                    }
                                    HoverHandler { id: bh; cursorShape: Qt.PointingHandCursor }
                                    TapHandler {
                                        onTapped: {
                                            if (parent.modelData.kind === "close") return History.removeKeys([row.e.key])
                                            History.copy([row.e.summary, p.plain(row.e.body)].filter(s => s).join("\n"))
                                            row.copied = true
                                        }
                                    }
                                }
                            }
                        }
                        HoverHandler { id: nh }
                        TapHandler {
                            onTapped: {
                                if (ah.hovered || oh.hovered) return
                                if (body.truncated || summary.truncated || row.full) row.full = !row.full
                            }
                        }
                        DragHandler {
                            id: swipe
                            target: slide
                            yAxis.enabled: false
                            xAxis.minimum: 0
                            onActiveChanged: if (!active) {
                                if (slide.x > slide.width / 4 || centroid.velocity.x > 700) History.removeKeys([row.e.key])
                                else back.start()
                            }
                        }
                        Anim { id: back; target: slide; property: "x"; to: 0; type: "fast" }
                    }
                }
            }
        }
    }

    // ---- nothing ----
    Column {
        visible: p.rows.length === 0
        width: parent.width
        topPadding: 22
        bottomPadding: 22
        spacing: 8
        Rectangle {
            anchors.horizontalCenter: parent.horizontalCenter
            width: 52; height: 52; radius: 26
            color: Look.raise
            G {
                anchors.centerIn: parent
                glyph: Config.historyPaused ? 0xF03E6 : 0xF11E6
                font.pixelSize: 24
                color: Config.historyPaused ? Look.urgent : Look.dim
            }
        }
        T {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Config.historyPaused ? "History is paused" : "You're all caught up"
            font.weight: Font.DemiBold
        }
        T {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Config.historyPaused ? "Notifications still pop up, they just aren't kept" : "New notifications will collect here"
            color: Look.faint
            font.pixelSize: Look.small
        }
        Btn {
            visible: Config.historyPaused
            anchors.horizontalCenter: parent.horizontalCenter
            text: "Resume"
            onClicked: Config.historyPaused = false
        }
    }
}
