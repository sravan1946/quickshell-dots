import QtQuick
import Quickshell
import qs
import qs.islands

// The calendar as a day planner. On top, the picked date large. Under it the week as a strip
// of day capsules (dots for events); the month button, or a tap on the date, folds the strip
// out into the whole month, each day tinted by how busy it is. Below, the picked day on an hour
// grid: each event a block as long as it lasts, overlapping ones side by side, a red line at
// the time now. It opens scrolled to now (or the day's first event). Tap an empty slot to add
// an event there: type a title and press Enter (Google Calendar opens prefilled). Tap a block
// for its event, the camera for its Meet. Scroll or ‹ › moves a week (a month while the month
// is out). Events come from Cal.qml.
// (The timeline design this replaced is kept in designs/cal-timeline.qml.)
Panel {
    id: p
    implicitWidth: 372
    spacing: 12
    SystemClock { id: clock; precision: SystemClock.Minutes }
    readonly property date now: clock.date
    readonly property int first: [Qt.locale().firstDayOfWeek % 7, 1, 0][Settings.weekStart]
    property date selected: now
    property bool monthOut: false
    Component.onCompleted: { Cal.refresh(); Qt.callLater(day.settle) }

    function sameDay(a, b) { return a.toDateString() === b.toDateString() }
    function plus(d, n) { return new Date(d.getFullYear(), d.getMonth(), d.getDate() + n) }
    function midnight(d) { return new Date(d.getFullYear(), d.getMonth(), d.getDate()) }
    // Qt's "h" is 24-hour unless the format has AP in it
    function hm(d) { return Settings.clock24h ? Qt.formatTime(d, "HH:mm") : Qt.formatTime(d, "h:mm AP").split(" ")[0] }
    function ap(d) { return Settings.clock24h ? "" : Qt.formatTime(d, "AP").toLowerCase() }
    function hourLabel(h) { return Settings.clock24h ? String(h).padStart(2, "0") : `${h % 12 || 12} ${h < 12 ? "am" : "pm"}` }
    readonly property bool onToday: sameDay(selected, now)

    // moving: a week, or a month while the month is out; the strip/grid slides the same way
    property int dir: 1
    function weekStart(d) { return plus(d, -((d.getDay() - first + 7) % 7)) }
    function pick(d) {
        const span = x => monthOut ? x.getFullYear() * 12 + x.getMonth() : weekStart(x).getTime()
        const moved = span(d) !== span(selected)
        dir = d > selected ? 1 : -1
        selected = d
        if (moved) slideIn.restart()
        day.settle()
    }
    function step(n) {
        pick(monthOut ? new Date(selected.getFullYear(), selected.getMonth() + n, Math.min(selected.getDate(), 28)) : plus(selected, 7 * n))
    }

    component IconBtn: Rectangle {
        id: ib
        property int glyph
        property bool on: false
        property color tint: Look.dim
        signal clicked()
        implicitWidth: 30
        implicitHeight: 30
        radius: 15
        color: on ? Qt.alpha(Look.accent, ih.hovered ? 0.3 : 0.2) : ih.hovered ? Look.hover : "transparent"
        Behavior on color { Fade {} }
        G { anchors.centerIn: parent; glyph: ib.glyph; font.pixelSize: 16; color: ib.on ? Look.accent : ih.hovered ? Look.text : ib.tint }
        HoverHandler { id: ih; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: ib.clicked() }
    }

    // ---- the date, large ----
    Item {
        width: parent.width
        height: 46
        Row {
            spacing: 10
            anchors.verticalCenter: parent.verticalCenter
            HoverHandler { id: dateH; cursorShape: Qt.PointingHandCursor }
            TapHandler { onTapped: p.monthOut = !p.monthOut }
            T {
                anchors.verticalCenter: parent.verticalCenter
                text: p.selected.getDate()
                font.pixelSize: 38
                font.weight: Font.Bold
                color: p.onToday ? Look.accent : Look.text
                Behavior on color { Fade {} }
            }
            Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: 1
                T {
                    text: p.onToday ? "Today" : p.sameDay(p.selected, p.plus(p.now, 1)) ? "Tomorrow"
                        : p.sameDay(p.selected, p.plus(p.now, -1)) ? "Yesterday" : Qt.formatDate(p.selected, "dddd")
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                    color: dateH.hovered ? Look.accent : Look.text
                    Behavior on color { Fade {} }
                }
                T {
                    text: Cal.failed ? "Couldn't load Google Calendar"
                        : Cal.stale ? "Offline, saved calendar"
                        : Qt.formatDate(p.selected, p.selected.getFullYear() === p.now.getFullYear() ? "MMMM" : "MMMM yyyy")
                          + (p.events.length ? "  ·  " + (p.events.length === 1 ? "1 event" : `${p.events.length} events`) : "")
                    color: Cal.failed || Cal.stale ? Look.urgent : Look.faint
                    font.pixelSize: Look.small
                }
            }
        }
        Row {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            IconBtn {
                glyph: 0xF00F6
                tint: Look.accent
                opacity: p.onToday ? 0 : 1
                visible: opacity > 0
                Behavior on opacity { Anim { type: "effects" } }
                onClicked: p.pick(p.midnight(p.now))
            }
            IconBtn { glyph: 0xF0141; onClicked: p.step(-1) }
            IconBtn { glyph: 0xF0142; onClicked: p.step(1) }
            IconBtn { glyph: 0xF0E18; on: p.monthOut; onClicked: p.monthOut = !p.monthOut }
        }
    }

    // ---- the week strip, or the month ----
    Item {
        id: dates
        width: parent.width
        height: p.monthOut ? month.implicitHeight : 58
        clip: true
        Behavior on height { Anim {} }
        WheelHandler { onWheel: e => p.step(e.angleDelta.y > 0 ? -1 : 1) }
        property real enter: 1
        Anim { id: slideIn; target: dates; property: "enter"; from: 0; to: 1; type: "enter" }

        // a week: day capsules
        Row {
            id: week
            x: (1 - dates.enter) * 30 * p.dir
            opacity: (p.monthOut ? 0 : 1) * dates.enter
            visible: opacity > 0
            Repeater {
                model: 7
                Item {
                    id: wd
                    required property int index
                    readonly property date d: p.plus(p.weekStart(p.selected), index)
                    readonly property bool picked: p.sameDay(d, p.selected)
                    readonly property bool today: p.sameDay(d, p.now)
                    readonly property int count: Cal.on(d).length
                    width: dates.width / 7
                    height: 58
                    Rectangle {
                        anchors.centerIn: parent
                        width: 42; height: 56
                        radius: 21
                        color: wd.picked ? Look.accent : wh.hovered ? Look.hover : "transparent"
                        border.width: wd.today && !wd.picked ? 1.5 : 0
                        border.color: Qt.alpha(Look.accent, 0.7)
                        Behavior on color { Fade {} }
                    }
                    Column {
                        anchors.centerIn: parent
                        spacing: 2
                        T {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: Qt.locale().dayName(wd.d.getDay(), Locale.ShortFormat).slice(0, 2)
                            color: wd.picked ? Qt.alpha(Look.accentInk, 0.7) : Look.faint
                            font.pixelSize: 10
                            font.weight: Font.DemiBold
                        }
                        T {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: wd.d.getDate()
                            color: wd.picked ? Look.accentInk : wd.today ? Look.accent : Look.text
                            font.pixelSize: 15
                            font.weight: wd.picked || wd.today ? Font.Bold : Font.Medium
                        }
                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 2
                            height: 4
                            Repeater {
                                model: Math.min(wd.count, 3)
                                Rectangle { width: 4; height: 4; radius: 2; color: wd.picked ? Look.accentInk : Look.warm }
                            }
                        }
                    }
                    HoverHandler { id: wh; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: p.pick(wd.d) }
                }
            }
        }

        // the month: each day tinted by how busy it is
        Column {
            id: month
            readonly property date m: new Date(p.selected.getFullYear(), p.selected.getMonth(), 1)
            readonly property int lead: (m.getDay() - p.first + 7) % 7
            readonly property int weeks: Math.ceil((lead + new Date(m.getFullYear(), m.getMonth() + 1, 0).getDate()) / 7)
            x: (1 - dates.enter) * 30 * p.dir
            width: dates.width
            opacity: (p.monthOut ? 1 : 0) * dates.enter
            visible: opacity > 0
            Row {
                Repeater {
                    model: 7
                    T {
                        required property int index
                        width: dates.width / 7
                        height: 20
                        horizontalAlignment: Text.AlignHCenter
                        text: Qt.locale().dayName((p.first + index) % 7, Locale.ShortFormat).slice(0, 2)
                        color: Look.faint
                        font.pixelSize: 10
                        font.weight: Font.DemiBold
                    }
                }
            }
            Grid {
                columns: 7
                Repeater {
                    model: month.weeks * 7
                    Item {
                        id: md
                        required property int index
                        readonly property date d: new Date(month.m.getFullYear(), month.m.getMonth(), 1 - month.lead + index)
                        readonly property bool inMonth: d.getMonth() === month.m.getMonth()
                        readonly property bool picked: p.sameDay(d, p.selected)
                        readonly property bool today: p.sameDay(d, p.now)
                        readonly property int count: Cal.on(d).length
                        width: dates.width / 7
                        height: 36
                        Rectangle {
                            anchors.centerIn: parent
                            width: 36; height: 32
                            radius: 10
                            color: md.picked ? Look.accent
                                : md.count > 0 ? Qt.alpha(Look.warm, Math.min(0.1 + 0.08 * md.count, 0.38) * (md.inMonth ? 1 : 0.4))
                                : mh.hovered ? Look.hover : "transparent"
                            border.width: md.today && !md.picked ? 1.5 : 0
                            border.color: Look.accent
                            Behavior on color { Fade {} }
                        }
                        T {
                            anchors.centerIn: parent
                            text: md.d.getDate()
                            color: md.picked ? Look.accentInk : md.today ? Look.accent : md.inMonth ? Look.text : Look.faint
                            opacity: md.inMonth ? 1 : 0.5
                            font.weight: md.picked || md.today ? Font.Bold : Font.Normal
                        }
                        HoverHandler { id: mh; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: { p.pick(md.d); p.monthOut = false } }
                    }
                }
            }
        }
    }

    // ---- all day ----
    readonly property var events: Cal.on(selected)
    readonly property var allDay: events.filter(e => e.allDay)
    Flow {
        visible: p.allDay.length > 0
        width: parent.width
        spacing: 6
        Repeater {
            model: p.allDay
            Rectangle {
                id: chip
                required property var modelData
                width: Math.min(chipRow.implicitWidth + 20, parent.width)
                height: 26
                radius: 8
                color: Qt.alpha(Look.accent, ch.hovered ? 0.3 : 0.18)
                Behavior on color { Fade {} }
                Row {
                    id: chipRow
                    anchors.centerIn: parent
                    spacing: 6
                    T { text: "All day"; color: Look.accent; font.pixelSize: 10; font.weight: Font.Bold; anchors.verticalCenter: parent.verticalCenter }
                    T {
                        width: Math.min(implicitWidth, p.implicitWidth - 90)   // not the chip: it sizes from this
                        text: chip.modelData.title
                        font.pixelSize: Look.small
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                HoverHandler { id: ch; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { Qt.openUrlExternally(chip.modelData.link); p.ctl.hide() } }
            }
        }
    }

    // ---- the day on an hour grid ----
    readonly property int hourH: 52
    readonly property color ground: Qt.rgba(Look.surface.r, Look.surface.g, Look.surface.b, 1)
    readonly property int gutter: 42
    // timed events placed: clipped to the day, overlapping ones split into columns
    readonly property var blocks: {
        const d0 = midnight(selected).getTime(), d1 = plus(selected, 1).getTime()
        const list = events.filter(e => !e.allDay).map(e => {
            const s = Math.max(new Date(e.start).getTime(), d0), en = Math.min(new Date(e.end).getTime(), d1)
            return { e: e, s: s, en: Math.max(en, s + 15 * 60000), col: 0, cols: 1 }
        }).sort((a, b) => a.s - b.s)
        let group = [], cols = [], end = 0
        const shut = () => { group.forEach(b => b.cols = cols.length); group = []; cols = [] }
        for (const b of list) {
            if (b.s >= end) shut()
            let c = cols.findIndex(x => x <= b.s)
            if (c < 0) { c = cols.length; cols.push(0) }
            cols[c] = b.en
            b.col = c
            group.push(b)
            end = Math.max(end, b.en)
        }
        shut()
        return list.map(b => Object.assign(b, { y: (b.s - d0) / 3600000 * hourH, h: (b.en - b.s) / 3600000 * hourH }))
    }
    property var draft: null         // { mins } while adding an event in an empty slot

    Item {
        width: parent.width
        height: 300
        Flickable {
            id: day
            anchors.fill: parent
            contentHeight: 24 * p.hourH + 12
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            // open on now today, else a little before the first event, else 8 in the morning
            function settle() {
                p.draft = null
                const b = p.blocks[0]
                const mins = p.onToday ? p.now.getHours() * 60 + p.now.getMinutes() - 60
                    : b ? (b.s - p.midnight(p.selected).getTime()) / 60000 - 30 : 8 * 60
                scroll.to = Math.max(0, Math.min(contentHeight - height, mins / 60 * p.hourH))
                scroll.restart()
            }
            Anim { id: scroll; target: day; property: "contentY"; type: "spatial" }
            onMovementStarted: scroll.stop()

            Item {
                id: canvas
                width: day.width
                height: day.contentHeight - 6
                y: 6
                // the hours
                Repeater {
                    model: 24
                    Item {
                        required property int index
                        y: index * p.hourH
                        width: canvas.width
                        T {
                            width: p.gutter - 8
                            y: -height / 2
                            horizontalAlignment: Text.AlignRight
                            visible: index > 0
                            text: p.hourLabel(index)
                            color: Look.faint
                            font.pixelSize: 10
                        }
                        Rectangle { x: p.gutter; width: canvas.width - p.gutter; height: 1; color: Look.line; visible: index > 0 }
                    }
                }
                // an empty slot: tap to add there (half-hour steps)
                TapHandler {
                    onTapped: (pt, button) => {
                        const x = pt.position.x, y = pt.position.y
                        const c = canvas.childAt(x, y)
                        if (x < p.gutter || (c && (c.e !== undefined || c.mins !== undefined))) return
                        p.draft = { mins: Math.max(0, Math.min(23 * 60, Math.floor(y / p.hourH * 2) * 30)) }
                        Qt.callLater(() => add.grab())
                    }
                }
                // the time now: under the blocks, so it never strikes a title through
                Item {
                    visible: p.onToday
                    y: (p.now.getHours() * 60 + p.now.getMinutes()) / 60 * p.hourH
                    width: canvas.width
                    Rectangle { x: p.gutter; y: -0.75; width: canvas.width - p.gutter; height: 1.5; color: Look.alert }
                    Rectangle {
                        y: -8
                        width: p.gutter - 2; height: 16; radius: 8
                        color: Look.alert
                        T { anchors.centerIn: parent; text: p.hm(p.now); color: "white"; font.pixelSize: 9; font.weight: Font.Bold }
                    }
                }
                // the events
                Repeater {
                    model: p.blocks
                    Rectangle {
                        id: blk
                        required property var modelData
                        readonly property var e: modelData.e
                        readonly property bool past: new Date(e.end) <= p.now
                        readonly property bool live: !past && new Date(e.start) <= p.now
                        readonly property real lane: (canvas.width - p.gutter - 4) / modelData.cols
                        readonly property color tone: live ? Look.warm : Look.accent
                        x: p.gutter + 4 + modelData.col * lane
                        y: modelData.y + 1
                        width: lane - 3
                        height: modelData.h - 2
                        radius: 8
                        // opaque, so the hour lines don't run through it
                        color: Qt.tint(p.ground, Qt.alpha(tone, bh.hovered ? 0.34 : past ? 0.1 : 0.22))
                        Behavior on color { Fade {} }
                        clip: true
                        Rectangle { width: 3; height: parent.height; color: blk.tone; opacity: blk.past ? 0.4 : 1 }
                        Column {
                            x: 10
                            y: blk.height < 30 ? (blk.height - implicitHeight) / 2 : 5
                            width: blk.width - x - (cam.visible ? 30 : 6)
                            spacing: 1
                            // a short block says when on the title's line
                            T {
                                width: parent.width
                                textFormat: Text.StyledText
                                text: blk.e.title.replace(/&/g, "&amp;").replace(/</g, "&lt;")
                                      + (blk.height < 40 ? `&nbsp;&nbsp;<font color="${Look.faint}">${p.hm(new Date(blk.e.start))}</font>` : "")
                                color: blk.past ? Look.dim : Look.text
                                font.pixelSize: Look.small
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                            T {
                                visible: blk.height >= 40
                                width: parent.width
                                text: `${p.hm(new Date(blk.e.start))} – ${p.hm(new Date(blk.e.end))}${p.ap(new Date(blk.e.end))}`
                                      + (blk.e.location && !blk.e.location.startsWith("http") ? "  ·  " + blk.e.location : "")
                                color: blk.live ? Look.warm : Look.faint
                                font.pixelSize: 10
                                elide: Text.ElideRight
                            }
                        }
                        Rectangle {
                            id: cam
                            visible: !!blk.e.meet && !blk.past && blk.width > 80
                            x: blk.width - width - 4
                            y: Math.min(4, (blk.height - height) / 2)
                            width: 24; height: Math.min(22, blk.height - 4)
                            radius: 8
                            color: camH.hovered ? blk.tone : Qt.alpha(blk.tone, 0.25)
                            Behavior on color { Fade {} }
                            G { anchors.centerIn: parent; glyph: 0xF0567; font.pixelSize: 12; color: camH.hovered ? Look.accentInk : blk.tone }
                            HoverHandler { id: camH; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: { Qt.openUrlExternally(blk.e.meet); p.ctl.hide() } }
                        }
                        HoverHandler { id: bh; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: { if (camH.hovered) return; Qt.openUrlExternally(blk.e.link); p.ctl.hide() } }
                    }
                }
                // adding: a block in the slot, with the title box in it
                Rectangle {
                    visible: p.draft !== null
                    readonly property real mins: p.draft?.mins ?? 0
                    readonly property date at: new Date(2000, 0, 1, 0, mins)
                    x: p.gutter + 4
                    y: mins / 60 * p.hourH + 1
                    width: canvas.width - x
                    height: p.hourH - 2
                    radius: 8
                    color: Qt.alpha(Look.accent, 0.12)
                    border.width: 1.5
                    border.color: Look.accent
                    Field {
                        id: add
                        x: 6
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 12
                        color: "transparent"
                        glyph: 0xF0415
                        hint: `New event at ${p.hm(parent.at)}${p.ap(parent.at)}`
                        onAccepted: if (text.trim() !== "") {
                            Cal.newEvent(text.trim(), p.selected, Math.floor(parent.mins / 60), parent.mins % 60)
                            text = ""
                            p.draft = null
                            p.ctl.hide()
                        }
                    }
                }
            }
        }
        // the edges fade, so the grid reads as going on
        Rectangle {
            width: parent.width; height: 14
            gradient: Gradient { GradientStop { position: 0; color: Look.surface } GradientStop { position: 1; color: "transparent" } }
        }
        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width; height: 14
            gradient: Gradient { GradientStop { position: 0; color: "transparent" } GradientStop { position: 1; color: Look.surface } }
        }
        // nothing timed that day
        Rectangle {
            visible: p.blocks.length === 0 && p.draft === null
            anchors.centerIn: parent
            width: free.implicitWidth + 24
            height: 28
            radius: 14
            color: Look.surface
            T {
                id: free
                anchors.centerIn: parent
                text: Cal.failed ? "No calendar feed" : "Free all day  ·  tap a slot to add"
                color: Look.faint
                font.pixelSize: Look.small
            }
        }
    }
}
