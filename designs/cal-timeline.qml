import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.islands

// The calendar. On top, what's next (a countdown, how far through it is, Join). Then the
// month: today filled, the picked day ringed, a dot per event (up to three); scroll or ‹ › for
// other months, the today button comes back. Under it the picked day as a timeline like the
// notification history: start times in a gutter, a node per event on a rail (filled while it
// runs, faint once past), a "now" line across it today. All-day events sit above as chips.
// Tap an event for Google Calendar, Join for its Meet; type in the box to add one on that day
// (opens Google Calendar prefilled). Events come from Cal.qml.
Panel {
    id: p
    implicitWidth: 360
    spacing: 12
    SystemClock { id: clock; precision: SystemClock.Minutes }
    readonly property date now: clock.date
    readonly property int first: [Qt.locale().firstDayOfWeek % 7, 1, 0][Settings.weekStart]
    property int shift: 0
    property date selected: now
    readonly property date month: new Date(now.getFullYear(), now.getMonth() + shift, 1)
    readonly property int lead: (month.getDay() - first + 7) % 7
    readonly property int days: new Date(month.getFullYear(), month.getMonth() + 1, 0).getDate()
    readonly property int weeks: Math.ceil((lead + days) / 7)
    readonly property real cell: implicitWidth / 7
    readonly property bool onToday: sameDay(selected, now)
    readonly property bool home: shift === 0 && onToday
    Component.onCompleted: Cal.refresh()
    WheelHandler { onWheel: e => p.go(e.angleDelta.y > 0 ? -1 : 1) }

    function sameDay(a, b) { return a.toDateString() === b.toDateString() }
    // Qt's "h" is 24-hour unless the format has AP in it
    function hm(d) { return Settings.clock24h ? Qt.formatTime(d, "HH:mm") : Qt.formatTime(d, "h:mm AP").split(" ")[0] }
    function ap(d) { return Settings.clock24h ? "" : Qt.formatTime(d, "AP").toLowerCase() }
    function span(mins) {
        mins = Math.max(0, Math.round(mins))
        const h = Math.floor(mins / 60), m = mins % 60
        return h === 0 ? `${m} min` : m === 0 ? `${h} h` : `${h} h ${m} min`
    }
    // which way the month grid slides in
    property int dir: 1
    function go(step) { dir = step; shift += step; gridIn.restart() }
    function backHome() { dir = shift > 0 ? -1 : 1; const moved = shift !== 0; shift = 0; selected = now; if (moved) gridIn.restart() }

    // "Standup 10:30", "Lunch at 1pm" -> timed; anything else -> all day. A bare number isn't a time.
    function add(text) {
        const m = text.trim().match(/^(.*?)\s+(?:at\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)?$/i)
        if (m && (m[3] || m[4]) && m[1]) {
            let h = +m[2] % (m[4] ? 12 : 24)
            if (m[4] && m[4].toLowerCase() === "pm") h += 12
            Cal.newEvent(m[1], selected, h, +(m[3] ?? 0))
        } else Cal.newEvent(text.trim(), selected)
        ctl.hide()
    }

    // the picked day: all-day ones apart, timed ones with a "now" row slotted in today
    readonly property var dayEvents: Cal.on(selected)
    readonly property var allDay: dayEvents.filter(e => e.allDay)
    readonly property var agenda: {
        const out = dayEvents.filter(e => !e.allDay).map(e => ({ kind: "event", e: e }))
        if (onToday && out.length) {
            const i = out.findIndex(x => new Date(x.e.start) > now)
            out.splice(i < 0 ? out.length : i, 0, { kind: "now" })
        }
        return out
    }
    readonly property int remaining: dayEvents.filter(e => !e.allDay && new Date(e.end) > now).length

    // ---- small round icon button ----
    component IconBtn: Rectangle {
        id: ib
        property int glyph
        property color tint: Look.dim
        signal clicked()
        implicitWidth: 30
        implicitHeight: 30
        radius: 15
        color: ih.hovered ? Look.hover : "transparent"
        Behavior on color { Fade {} }
        G { anchors.centerIn: parent; glyph: ib.glyph; font.pixelSize: 16; color: ih.hovered ? Look.text : ib.tint }
        HoverHandler { id: ih; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: ib.clicked() }
    }

    // ---- header: the month on show, how today looks ----
    Item {
        width: parent.width
        height: 36
        Column {
            x: 2
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1
            T {
                text: Qt.formatDate(p.month, p.month.getFullYear() === p.now.getFullYear() ? "MMMM" : "MMMM yyyy")
                font.pixelSize: 15
                font.weight: Font.DemiBold
            }
            T {
                text: Cal.failed ? "Couldn't load Google Calendar"
                    : Cal.stale ? "Offline, showing the saved calendar"
                    : Qt.formatDate(p.now, "dddd d") + "  ·  "
                      + (p.remaining === 0 ? "nothing left today" : p.remaining === 1 ? "1 event left" : `${p.remaining} events left`)
                color: Cal.failed || Cal.stale ? Look.urgent : Look.faint
                font.pixelSize: Look.small
            }
        }
        Row {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            spacing: 0
            IconBtn {
                glyph: 0xF00F6
                tint: Look.accent
                opacity: p.home ? 0 : 1
                visible: opacity > 0
                Behavior on opacity { Anim { type: "effects" } }
                onClicked: p.backHome()
            }
            IconBtn { glyph: 0xF0141; onClicked: p.go(-1) }
            IconBtn { glyph: 0xF0142; onClicked: p.go(1) }
            IconBtn {
                glyph: 0xF0450
                tint: Cal.stale ? Look.urgent : Look.dim
                rotation: Cal.loading ? 360 : 0
                Behavior on rotation { enabled: Cal.loading; Anim { duration: 700 * Look.speed; type: "effects" } }
                onClicked: Cal.refresh()
            }
        }
    }

    // ---- up next: within the next 12 hours, or on now ----
    Rectangle {
        id: hero
        readonly property var e: Cal.next
        readonly property date s: e ? new Date(e.start) : p.now
        readonly property date end: e ? new Date(e.end) : p.now
        readonly property bool live: !!e && s <= p.now
        readonly property real mins: (s - p.now) / 60000
        readonly property bool soon: live || mins <= Settings.meetLead
        visible: !!e && (live || mins <= 12 * 60)
        width: parent.width
        height: heroCol.implicitHeight + 24
        radius: 14
        color: hh.hovered ? Qt.alpha(soon ? Look.warm : Look.accent, 0.16) : Qt.alpha(soon ? Look.warm : Look.accent, 0.1)
        border.width: 1
        border.color: Qt.alpha(soon ? Look.warm : Look.accent, 0.25)
        Behavior on color { Fade {} }
        HoverHandler { id: hh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: { if (jh.hovered) return; Qt.openUrlExternally(hero.e.link); p.ctl.hide() } }
        Column {
            id: heroCol
            x: 14; y: 12
            width: parent.width - 28
            spacing: 3
            T {
                text: hero.live ? "Now" : hero.mins < 1 ? "Starting" : "In " + p.span(hero.mins)
                color: hero.soon ? Look.warm : Look.accent
                font.pixelSize: Look.small
                font.weight: Font.Bold
                font.letterSpacing: 0.3
            }
            T {
                width: parent.width - (join.visible ? join.width + 10 : 0)
                text: hero.e?.title ?? ""
                font.pixelSize: 14
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }
            T {
                width: parent.width - (join.visible ? join.width + 10 : 0)
                text: (hero.live ? `${p.span((hero.end - p.now) / 60000)} left`
                                 : `${p.hm(hero.s)}${p.ap(hero.s)} – ${p.hm(hero.end)}${p.ap(hero.end)}`)
                      + (hero.e?.location && !hero.e.location.startsWith("http") ? "  ·  " + hero.e.location : "")
                color: Look.dim
                font.pixelSize: Look.small
                elide: Text.ElideRight
            }
            // how far through it is
            Rectangle {
                visible: hero.live
                width: parent.width
                height: 3
                radius: 1.5
                color: Qt.alpha(Look.text, 0.12)
                Rectangle {
                    width: parent.width * Math.min(1, Math.max(0, (p.now - hero.s) / Math.max(1, hero.end - hero.s)))
                    height: parent.height
                    radius: 1.5
                    color: Look.warm
                }
            }
        }
        Btn {
            id: join
            visible: !!hero.e?.meet
            anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
            text: "Join"
            strong: hero.soon
            tone: Look.warm
            HoverHandler { id: jh }
            onClicked: { Qt.openUrlExternally(hero.e.meet); p.ctl.hide() }
        }
    }

    // ---- the month ----
    Column {
        width: parent.width
        spacing: 2
        Row {
            Repeater {
                model: 7
                T {
                    required property int index
                    readonly property int dow: (p.first + index) % 7
                    width: p.cell
                    horizontalAlignment: Text.AlignHCenter
                    text: Qt.locale().dayName(dow, Locale.ShortFormat).slice(0, 2)
                    color: dow === 0 || dow === 6 ? Qt.alpha(Look.text, 0.22) : Look.faint
                    font.pixelSize: 10
                    font.weight: Font.DemiBold
                    font.letterSpacing: 0.4
                }
            }
        }
        Item {
            width: parent.width
            height: p.weeks * 38
            clip: true
            Behavior on height { Anim {} }
            Grid {
                id: grid
                columns: 7
                property real enter: 1
                x: (1 - enter) * 28 * p.dir
                opacity: enter
                Anim { id: gridIn; target: grid; property: "enter"; from: 0; to: 1; type: "enter" }
                Repeater {
                    model: p.weeks * 7
                    Item {
                        id: day
                        required property int index
                        readonly property date d: new Date(p.month.getFullYear(), p.month.getMonth(), 1 - p.lead + index)
                        readonly property bool inMonth: d.getMonth() === p.month.getMonth()
                        readonly property bool today: p.sameDay(d, p.now)
                        readonly property bool picked: p.sameDay(d, p.selected)
                        readonly property bool past: d < new Date(p.now.getFullYear(), p.now.getMonth(), p.now.getDate())
                        readonly property bool weekend: d.getDay() === 0 || d.getDay() === 6
                        readonly property int count: Cal.on(d).length
                        width: p.cell
                        height: 38
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 2
                            width: 32; height: 32
                            radius: 16
                            color: day.today ? Look.accent : dh.hovered ? Look.hover : day.picked ? Look.raise : "transparent"
                            border.width: day.picked && !day.today ? 1.5 : 0
                            border.color: Qt.alpha(Look.accent, 0.7)
                            Behavior on color { Fade {} }
                        }
                        T {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 2
                            height: 32
                            text: day.d.getDate()
                            color: day.today ? Look.accentInk : day.picked ? Look.text : day.past || day.weekend ? Look.faint : Look.dim
                            opacity: day.inMonth ? 1 : 0.4
                            font.weight: day.today || day.picked ? Font.Bold : Font.Normal
                        }
                        // one dot per event, up to three
                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 28
                            spacing: 2
                            opacity: day.inMonth ? 1 : 0.4
                            Repeater {
                                model: Math.min(day.count, 3)
                                Rectangle {
                                    width: 3; height: 3; radius: 1.5
                                    color: day.today ? Look.accentInk : day.past ? Look.faint : Look.warm
                                }
                            }
                        }
                        HoverHandler { id: dh; cursorShape: Qt.PointingHandCursor }
                        TapHandler {
                            onTapped: {
                                p.selected = day.d
                                if (!day.inMonth) p.go(day.index < 7 ? -1 : 1)   // a neighbour's day: go there
                            }
                        }
                    }
                }
            }
        }
    }

    // ---- the picked day ----
    Item {
        width: parent.width
        height: 20
        T {
            x: 2
            anchors.verticalCenter: parent.verticalCenter
            text: p.onToday ? "Today" : p.sameDay(p.selected, new Date(p.now.getTime() + 864e5)) ? "Tomorrow"
                : Qt.formatDate(p.selected, "dddd d MMMM")
            color: Look.dim
            font.pixelSize: Look.small
            font.weight: Font.DemiBold
            font.letterSpacing: 0.4
        }
        T {
            anchors { right: parent.right; rightMargin: 2; verticalCenter: parent.verticalCenter }
            visible: p.dayEvents.length > 0
            text: p.dayEvents.length === 1 ? "1 event" : `${p.dayEvents.length} events`
            color: Look.faint
            font.pixelSize: Look.small
        }
    }

    // all-day ones: chips
    Flow {
        visible: p.allDay.length > 0
        width: parent.width
        spacing: 6
        Repeater {
            model: p.allDay
            Rectangle {
                id: chip
                required property var modelData
                width: Math.min(ct.implicitWidth + 20, parent.width)
                height: 26
                radius: 13
                color: Qt.alpha(Look.accent, ch.hovered ? 0.22 : 0.13)
                Behavior on color { Fade {} }
                T {
                    id: ct
                    anchors.centerIn: parent
                    width: Math.min(implicitWidth, chip.width - 20)
                    text: chip.modelData.title
                    color: Look.text
                    font.pixelSize: Look.small
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                HoverHandler { id: ch; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { Qt.openUrlExternally(chip.modelData.link); p.ctl.hide() } }
            }
        }
    }

    // timed ones: the timeline
    readonly property int gutter: 44
    readonly property int railX: gutter + 14
    readonly property int textX: gutter + 30
    Column {
        visible: p.agenda.length > 0
        width: parent.width
        Repeater {
            model: p.agenda
            Item {
                id: row
                required property var modelData
                required property int index
                readonly property bool isNow: modelData.kind === "now"
                readonly property var e: modelData.e
                readonly property date s: e ? new Date(e.start) : p.now
                readonly property date end: e ? new Date(e.end) : p.now
                readonly property bool past: !isNow && end <= p.now
                readonly property bool live: !isNow && s <= p.now && !past
                readonly property bool soon: !isNow && !past && (live || (s - p.now) <= Settings.meetLead * 60000)
                readonly property bool firstRow: index === 0
                readonly property bool lastRow: index === p.agenda.length - 1
                readonly property real nodeY: isNow ? height / 2 : 6 + title.height / 2
                width: parent.width
                height: isNow ? 22 : info.implicitHeight + 14

                // the rail
                Rectangle {
                    visible: !row.firstRow
                    x: p.railX - 0.5; width: 1
                    height: row.nodeY
                    color: row.past || row.isNow ? Qt.alpha(Look.text, 0.18) : Look.line
                }
                Rectangle {
                    visible: !row.lastRow
                    x: p.railX - 0.5; width: 1
                    y: row.nodeY
                    height: row.height - row.nodeY
                    color: row.past ? Qt.alpha(Look.text, 0.18) : Look.line
                }

                // now: a line across the day
                T {
                    visible: row.isNow
                    width: p.gutter
                    height: row.height
                    horizontalAlignment: Text.AlignRight
                    text: p.hm(p.now)
                    color: Look.alert
                    font.pixelSize: Look.small
                    font.weight: Font.Bold
                }
                Rectangle {
                    visible: row.isNow
                    x: p.railX - 4; y: row.nodeY - 4
                    width: 8; height: 8; radius: 4
                    color: Look.alert
                }
                Rectangle {
                    visible: row.isNow
                    x: p.railX + 4; y: row.nodeY - 0.5
                    width: row.width - x; height: 1
                    color: Qt.alpha(Look.alert, 0.6)
                }

                // an event
                Rectangle {
                    visible: !row.isNow
                    x: p.textX - 10; y: 1
                    width: row.width - x
                    height: row.height - 2
                    radius: 10
                    color: eh.hovered ? Look.raise : "transparent"
                    Behavior on color { Fade {} }
                }
                Column {
                    visible: !row.isNow
                    width: p.gutter
                    y: 6
                    T {
                        width: parent.width
                        horizontalAlignment: Text.AlignRight
                        text: p.hm(row.s)
                        height: title.height
                        color: row.live || row.soon ? Look.warm : row.past ? Look.faint : Look.dim
                        font.pixelSize: Look.small
                        font.weight: row.live ? Font.Bold : Font.Normal
                    }
                    T {
                        visible: !Settings.clock24h
                        width: parent.width
                        horizontalAlignment: Text.AlignRight
                        text: p.ap(row.s)
                        color: Look.faint
                        font.pixelSize: 9
                    }
                }
                Rectangle {
                    visible: !row.isNow
                    x: p.railX - 5; y: row.nodeY - 5
                    width: 10; height: 10; radius: 5
                    color: row.live ? Look.warm : row.past ? Qt.tint(Look.base, Qt.alpha("white", 0.25)) : Qt.tint(Look.base, Qt.alpha("white", 0.06))
                    border.width: row.past || row.live ? 0 : 2
                    border.color: row.soon ? Look.warm : Look.accent
                }
                Column {
                    id: info
                    visible: !row.isNow
                    x: p.textX
                    y: 6
                    width: row.width - x - (rj.visible ? rj.width + 16 : 10)
                    spacing: 1
                    T {
                        id: title
                        width: parent.width
                        text: row.e?.title ?? ""
                        color: row.past ? Look.dim : Look.text
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }
                    T {
                        width: parent.width
                        text: (row.live ? `now  ·  ${p.span((row.end - p.now) / 60000)} left` : `${p.hm(row.s)} – ${p.hm(row.end)}${p.ap(row.end)}  ·  ${p.span((row.end - row.s) / 60000)}`)
                              + (row.e?.location && !row.e.location.startsWith("http") ? "  ·  " + row.e.location : "")
                        color: row.live ? Look.warm : Look.faint
                        font.pixelSize: Look.small
                        elide: Text.ElideRight
                    }
                }
                Btn {
                    id: rj
                    visible: !row.isNow && !!row.e?.meet && !row.past
                    anchors { right: parent.right; rightMargin: 8; verticalCenter: parent.verticalCenter }
                    text: "Join"
                    strong: row.soon
                    tone: Look.warm
                    HoverHandler { id: rjh }
                    onClicked: { Qt.openUrlExternally(row.e.meet); p.ctl.hide() }
                }
                HoverHandler { id: eh; enabled: !row.isNow; cursorShape: Qt.PointingHandCursor }
                TapHandler {
                    enabled: !row.isNow
                    onTapped: { if (rjh.hovered) return; Qt.openUrlExternally(row.e.link); p.ctl.hide() }
                }
            }
        }
    }

    // nothing that day
    Row {
        visible: p.dayEvents.length === 0
        x: 2
        spacing: 10
        G { glyph: Cal.failed ? 0xF0B66 : 0xF06CA; font.pixelSize: 16; color: Look.faint }
        T {
            anchors.verticalCenter: parent.verticalCenter
            text: Cal.failed ? "No calendar feed" : p.onToday ? "Nothing else on today" : "Nothing planned"
            color: Look.dim
            font.pixelSize: Look.small
        }
    }

    Field {
        hint: "Add on " + Qt.formatDate(p.selected, "d MMM") + ", e.g. Sync 4pm"
        glyph: 0xF00F3
        onAccepted: if (text.trim() !== "") { p.add(text); text = "" }
        TapHandler { onTapped: parent.grab() }
    }
}
