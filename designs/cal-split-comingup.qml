import QtQuick
import Quickshell
import qs
import qs.islands

// The calendar, in two halves. Left, the month: today filled, the picked day ringed, a warm dot
// per event (up to three); scroll or ‹ › for other months, the today button comes back. Under
// it, a box to add an event on the picked day ("Sync 4pm"; Google Calendar opens prefilled).
// Right, the picked day: all-day events as chips, then for today a card for what's on now or
// next (countdown, how far through, Join), then the rest of the day in order (past ones faded),
// then a look at the day after. Tap an event to open it in Google Calendar. Events: Cal.qml.
// (Earlier designs are kept in designs/.)
Panel {
    id: p
    readonly property int cell: 40
    readonly property int leftW: 7 * cell
    readonly property int rightW: 290
    readonly property int gap: 22
    implicitWidth: leftW + gap + rightW
    SystemClock { id: clock; precision: SystemClock.Minutes }
    readonly property date now: clock.date
    readonly property int first: [Qt.locale().firstDayOfWeek % 7, 1, 0][Settings.weekStart]
    property int shift: 0
    property date selected: now
    readonly property date month: new Date(now.getFullYear(), now.getMonth() + shift, 1)
    readonly property int lead: (month.getDay() - first + 7) % 7
    readonly property int weeks: Math.ceil((lead + new Date(month.getFullYear(), month.getMonth() + 1, 0).getDate()) / 7)
    readonly property bool onToday: sameDay(selected, now)
    Component.onCompleted: Cal.refresh()

    function sameDay(a, b) { return a.toDateString() === b.toDateString() }
    function plus(d, n) { return new Date(d.getFullYear(), d.getMonth(), d.getDate() + n) }
    // Qt's "h" is 24-hour unless the format has AP in it
    function hm(d) { return Settings.clock24h ? Qt.formatTime(d, "HH:mm") : Qt.formatTime(d, "h:mm AP").split(" ")[0] }
    function ap(d) { return Settings.clock24h ? "" : Qt.formatTime(d, "AP").toLowerCase() }
    function span(mins) {
        mins = Math.max(0, Math.round(mins))
        const h = Math.floor(mins / 60), m = mins % 60
        return h === 0 ? `${m} min` : m === 0 ? `${h} h` : `${h} h ${m} min`
    }
    function dayName(d) {
        return sameDay(d, now) ? "Today" : sameDay(d, plus(now, 1)) ? "Tomorrow"
            : sameDay(d, plus(now, -1)) ? "Yesterday" : Qt.formatDate(d, "dddd")
    }
    // "in 3 days", "next week": how far off a later event is
    function until(d) {
        const n = Math.round((new Date(d.getFullYear(), d.getMonth(), d.getDate()) - midnight(now)) / 864e5)
        return n === 0 ? "today" : n === 1 ? "tomorrow" : n < 0 ? `${-n} days ago` : n < 7 ? `in ${n} days` : n < 14 ? "next week" : `in ${Math.round(n / 7)} weeks`
    }
    function midnight(d) { return new Date(d.getFullYear(), d.getMonth(), d.getDate()) }
    function where(e) { return e.location && !e.location.startsWith("http") ? e.location : "" }
    function open(url) { Qt.openUrlExternally(url); p.ctl.hide() }

    // months slide in from the side they came from; a picked day cross-fades the right half
    property int dir: 1
    function go(step) { dir = step; shift += step; monthIn.restart() }
    function pick(d) { if (sameDay(d, selected)) return; selected = d; dayIn.restart() }
    function home() { if (shift !== 0) { dir = shift > 0 ? -1 : 1; shift = 0; monthIn.restart() } pick(now) }

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

    // the picked day
    readonly property var dayEvents: Cal.on(selected)
    readonly property var allDay: dayEvents.filter(e => e.allDay)
    readonly property var timed: dayEvents.filter(e => !e.allDay).sort((a, b) => new Date(a.start) - new Date(b.start))
    // today: what's on, or next (gets the card; the list leaves it out)
    readonly property var upNext: onToday ? (timed.find(e => new Date(e.end) > now) ?? null) : null
    readonly property var rest: timed.filter(e => e !== upNext)
    readonly property date after: plus(selected, 1)
    readonly property var afterEvents: Cal.on(after)
    // the next four events starting after the day after the picked one
    readonly property var later: { const from = plus(selected, 2); return Cal.events.filter(e => new Date(e.start) >= from).slice(0, 4) }

    component IconBtn: Rectangle {
        id: ib
        property int glyph
        property color tint: Look.dim
        signal clicked()
        implicitWidth: 28
        implicitHeight: 28
        radius: 14
        color: ih.hovered ? Look.hover : "transparent"
        Behavior on color { Fade {} }
        G { anchors.centerIn: parent; glyph: ib.glyph; font.pixelSize: 15; color: ih.hovered ? Look.text : ib.tint }
        HoverHandler { id: ih; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: ib.clicked() }
    }
    component Label: T {
        color: Look.faint
        font.pixelSize: 10
        font.weight: Font.Bold
        font.letterSpacing: 0.8
        font.capitalization: Font.AllUppercase
    }

    Item {
        width: p.implicitWidth
        height: Math.max(monthCol.implicitHeight + addBox.height + 10, Math.min(dayCol.implicitHeight, 520))   // the day half may run taller, then scrolls

        // ================= the month =================
        Column {
            id: monthCol
            width: p.leftW
            spacing: 10
            Item {
                width: parent.width
                height: 32
                Row {
                    x: 4
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6
                    T { id: monthName; text: Qt.formatDate(p.month, "MMMM"); font.pixelSize: 18; font.weight: Font.Bold }
                    T {
                        anchors.baseline: monthName.baseline
                        text: p.month.getFullYear()
                        color: Look.faint
                        font.pixelSize: 13
                    }
                }
                Row {
                    anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                    IconBtn {
                        glyph: 0xF00F6
                        tint: Look.accent
                        opacity: p.shift !== 0 || !p.onToday ? 1 : 0
                        visible: opacity > 0
                        Behavior on opacity { Anim { type: "effects" } }
                        onClicked: p.home()
                    }
                    IconBtn { glyph: 0xF0141; onClicked: p.go(-1) }
                    IconBtn { glyph: 0xF0142; onClicked: p.go(1) }
                }
            }
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
                        font.weight: Font.Bold
                    }
                }
            }
            Item {
                width: parent.width
                height: p.weeks * 40
                clip: true
                Behavior on height { Anim {} }
                WheelHandler { onWheel: e => p.go(e.angleDelta.y > 0 ? -1 : 1) }
                Grid {
                    id: grid
                    columns: 7
                    property real enter: 1
                    x: (1 - enter) * 34 * p.dir
                    opacity: enter
                    Anim { id: monthIn; target: grid; property: "enter"; from: 0; to: 1; type: "enter" }
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
                            height: 40
                            Rectangle {
                                anchors.centerIn: parent
                                width: 34; height: 34
                                radius: 17
                                color: day.today ? Look.accent : day.picked ? Qt.alpha(Look.accent, 0.16) : dh.hovered ? Look.hover : "transparent"
                                border.width: day.picked && !day.today ? 1.5 : 0
                                border.color: Qt.alpha(Look.accent, 0.8)
                                Behavior on color { Fade {} }
                            }
                            T {
                                anchors.centerIn: parent
                                anchors.verticalCenterOffset: day.count > 0 ? -2 : 0
                                text: day.d.getDate()
                                color: day.today ? Look.accentInk : day.picked ? Look.text
                                    : !day.inMonth ? Look.faint : day.past || day.weekend ? Look.dim : Look.text
                                opacity: day.inMonth ? 1 : 0.45
                                font.pixelSize: 13
                                font.weight: day.today || day.picked ? Font.Bold : Font.Normal
                            }
                            Row {
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 27
                                spacing: 2
                                opacity: day.inMonth ? (day.past && !day.today ? 0.5 : 1) : 0.35
                                Repeater {
                                    model: Math.min(day.count, 3)
                                    Rectangle { width: 4; height: 4; radius: 2; color: day.today ? Look.accentInk : Look.warm }
                                }
                            }
                            HoverHandler { id: dh; cursorShape: Qt.PointingHandCursor }
                            TapHandler {
                                onTapped: {
                                    p.pick(day.d)
                                    if (!day.inMonth) p.go(day.index < 7 ? -1 : 1)   // a neighbour's day: go there
                                }
                            }
                        }
                    }
                }
            }
            // further on: the next few events after the two days the right half shows
            Item { width: 1; height: 2 }
            Rectangle { width: parent.width; height: 1; color: Look.line; visible: p.later.length > 0 }
            Label { x: 4; visible: p.later.length > 0; text: "Coming up" }
            Column {
                visible: p.later.length > 0
                width: parent.width
                spacing: 2
                Repeater {
                    model: p.later
                    Rectangle {
                        id: up
                        required property var modelData
                        readonly property date s: new Date(modelData.start)
                        width: parent.width
                        height: 42
                        radius: 10
                        color: uh.hovered ? Look.raise : "transparent"
                        Behavior on color { Fade {} }
                        // a date tile: weekday over the day
                        Rectangle {
                            x: 4
                            anchors.verticalCenter: parent.verticalCenter
                            width: 34; height: 34
                            radius: 9
                            color: Qt.alpha(Look.warm, 0.14)
                            Column {
                                anchors.centerIn: parent
                                spacing: -2
                                T {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: Qt.formatDate(up.s, "ddd")
                                    color: Look.warm
                                    font.pixelSize: 8
                                    font.weight: Font.Bold
                                    font.capitalization: Font.AllUppercase
                                }
                                T {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: up.s.getDate()
                                    font.pixelSize: 13
                                    font.weight: Font.Bold
                                }
                            }
                        }
                        Column {
                            x: 48
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - x - 8
                            spacing: 0
                            T { width: parent.width; text: up.modelData.title; font.weight: Font.DemiBold; elide: Text.ElideRight }
                            T {
                                width: parent.width
                                text: (up.modelData.allDay ? "All day" : p.hm(up.s) + p.ap(up.s))
                                      + "  ·  " + p.until(up.s)
                                color: Look.faint
                                font.pixelSize: Look.small
                                elide: Text.ElideRight
                            }
                        }
                        HoverHandler { id: uh; cursorShape: Qt.PointingHandCursor }
                        TapHandler {
                            onTapped: {
                                const d = new Date(up.s.getFullYear(), up.s.getMonth(), up.s.getDate())
                                const m = (d.getFullYear() - p.now.getFullYear()) * 12 + d.getMonth() - p.now.getMonth()
                                if (m !== p.shift) { p.dir = m > p.shift ? 1 : -1; p.shift = m; monthIn.restart() }
                                p.pick(d)
                            }
                        }
                    }
                }
            }
        }
        // the add box keeps to the bottom, whatever the day half's height
        Field {
            id: addBox
            width: p.leftW
            anchors.bottom: parent.bottom
            hint: `Add to ${p.onToday ? "today" : Qt.formatDate(p.selected, "ddd d")}, e.g. Sync 4pm`
            glyph: 0xF0415
            onAccepted: if (text.trim() !== "") { p.add(text); text = "" }
            TapHandler { onTapped: parent.grab() }
        }

        // the seam
        Rectangle {
            x: p.leftW + p.gap / 2
            y: 4
            width: 1
            height: parent.height - 8
            color: Look.line
        }

        // ================= the day =================
        Flickable {
            id: dayView
            x: p.leftW + p.gap
            width: p.rightW
            height: parent.height
            contentHeight: dayCol.implicitHeight
            clip: contentHeight > height
            interactive: contentHeight > height
            boundsBehavior: Flickable.StopAtBounds
            Column {
                id: dayCol
                width: parent.width
                spacing: 12
                property real enter: 1
                opacity: enter
                transform: Translate { y: (1 - dayCol.enter) * 8 }
                Anim { id: dayIn; target: dayCol; property: "enter"; from: 0; to: 1; type: "enter" }

                // the day's name
                Item {
                    width: parent.width
                    height: 32
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 0
                        T { text: p.dayName(p.selected); font.pixelSize: 15; font.weight: Font.Bold; color: p.onToday ? Look.accent : Look.text }
                        T {
                            text: Cal.failed ? "Couldn't load Google Calendar" : Cal.stale ? "Offline, saved calendar"
                                : Qt.formatDate(p.selected, p.onToday ? "dddd d MMMM" : "d MMMM yyyy")
                            color: Cal.failed || Cal.stale ? Look.urgent : Look.faint
                            font.pixelSize: Look.small
                        }
                    }
                    IconBtn {
                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                        glyph: 0xF0450
                        tint: Cal.stale ? Look.urgent : Look.faint
                        rotation: Cal.loading ? 360 : 0
                        Behavior on rotation { enabled: Cal.loading; Anim { duration: 700 * Look.speed; type: "effects" } }
                        onClicked: Cal.refresh()
                    }
                }

                // all day
                Flow {
                    visible: p.allDay.length > 0
                    width: parent.width
                    spacing: 6
                    Repeater {
                        model: p.allDay
                        Rectangle {
                            id: chip
                            required property var modelData
                            width: Math.min(ct.implicitWidth + 22, p.rightW)
                            height: 26
                            radius: 13
                            color: Qt.alpha(Look.accent, chh.hovered ? 0.28 : 0.16)
                            Behavior on color { Fade {} }
                            T {
                                id: ct
                                anchors.centerIn: parent
                                width: Math.min(implicitWidth, p.rightW - 22)   // not the chip's: it sizes from this
                                text: chip.modelData.title
                                font.pixelSize: Look.small
                                font.weight: Font.DemiBold
                                elide: Text.ElideRight
                            }
                            HoverHandler { id: chh; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: p.open(chip.modelData.link) }
                        }
                    }
                }

                // now / next
                Rectangle {
                    id: hero
                    readonly property var e: p.upNext
                    readonly property date s: e ? new Date(e.start) : p.now
                    readonly property date end: e ? new Date(e.end) : p.now
                    readonly property bool live: !!e && s <= p.now
                    readonly property real mins: (s - p.now) / 60000
                    readonly property bool soon: live || mins <= Settings.meetLead
                    readonly property color tone: soon ? Look.warm : Look.accent
                    visible: !!e
                    width: parent.width
                    height: hc.implicitHeight + 28
                    radius: 16
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0; color: Qt.alpha(hero.tone, hh.hovered ? 0.3 : 0.22) }
                        GradientStop { position: 1; color: Qt.alpha(hero.tone, hh.hovered ? 0.12 : 0.06) }
                    }
                    border.width: 1
                    border.color: Qt.alpha(hero.tone, 0.3)
                    HoverHandler { id: hh; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: { if (jh.hovered) return; p.open(hero.e.link) } }
                    Column {
                        id: hc
                        x: 14; y: 14
                        width: parent.width - 28
                        spacing: 4
                        Row {
                            spacing: 6
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 7; height: 7; radius: 3.5
                                color: hero.tone
                            }
                            T {
                                text: hero.live ? `Now  ·  ${p.span((hero.end - p.now) / 60000)} left`
                                    : hero.mins < 1 ? "Starting" : `Next  ·  in ${p.span(hero.mins)}`
                                color: hero.tone
                                font.pixelSize: Look.small
                                font.weight: Font.Bold
                            }
                        }
                        T {
                            width: parent.width
                            text: hero.e?.title ?? ""
                            font.pixelSize: 16
                            font.weight: Font.Bold
                            wrapMode: Text.Wrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                        }
                        T {
                            width: parent.width
                            text: `${p.hm(hero.s)} – ${p.hm(hero.end)}${p.ap(hero.end)}` + (hero.e && p.where(hero.e) ? "  ·  " + p.where(hero.e) : "")
                            color: Look.dim
                            font.pixelSize: Look.small
                            elide: Text.ElideRight
                        }
                        Item { width: 1; height: 6 }
                        Item {
                            width: parent.width
                            height: 26
                            // how far through it is
                            Rectangle {
                                visible: hero.live
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - (join.visible ? join.width + 12 : 0)
                                height: 4
                                radius: 2
                                color: Qt.alpha(Look.text, 0.12)
                                Rectangle {
                                    width: Math.max(4, parent.width * Math.min(1, Math.max(0, (p.now - hero.s) / Math.max(1, hero.end - hero.s))))
                                    height: parent.height
                                    radius: 2
                                    color: hero.tone
                                }
                            }
                            Btn {
                                id: join
                                visible: !!hero.e?.meet
                                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                text: "Join"
                                strong: hero.soon
                                tone: hero.tone
                                HoverHandler { id: jh }
                                onClicked: p.open(hero.e.meet)
                            }
                        }
                    }
                }

                // the rest of the day
                Column {
                    visible: p.rest.length > 0
                    width: parent.width
                    spacing: 2
                    Label { visible: !!p.upNext; text: "Also today"; leftPadding: 2; bottomPadding: 4 }
                    Repeater {
                        model: p.rest
                        Rectangle {
                            id: ev
                            required property var modelData
                            readonly property var e: modelData
                            readonly property date s: new Date(e.start)
                            readonly property date end: new Date(e.end)
                            readonly property bool past: end <= p.now
                            width: parent.width
                            height: 46
                            radius: 10
                            color: eh.hovered ? Look.raise : "transparent"
                            Behavior on color { Fade {} }
                            opacity: past ? 0.5 : 1
                            Column {
                                x: 4
                                width: 40
                                anchors.verticalCenter: parent.verticalCenter
                                T { anchors.right: parent.right; text: p.hm(ev.s); font.pixelSize: 13; font.weight: Font.DemiBold }
                                T { anchors.right: parent.right; visible: text !== ""; text: p.ap(ev.s); color: Look.faint; font.pixelSize: 9 }
                            }
                            Rectangle {
                                x: 52
                                anchors.verticalCenter: parent.verticalCenter
                                width: 3; height: 30; radius: 1.5
                                color: ev.past ? Look.faint : Look.accent
                            }
                            Column {
                                x: 64
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - x - (cam.visible ? 36 : 8)
                                spacing: 1
                                T { width: parent.width; text: ev.e.title; font.weight: Font.DemiBold; elide: Text.ElideRight }
                                T {
                                    width: parent.width
                                    text: p.span((ev.end - ev.s) / 60000) + (p.where(ev.e) ? "  ·  " + p.where(ev.e) : "")
                                    color: Look.faint
                                    font.pixelSize: Look.small
                                    elide: Text.ElideRight
                                }
                            }
                            Rectangle {
                                id: cam
                                visible: !!ev.e.meet && !ev.past
                                anchors { right: parent.right; rightMargin: 6; verticalCenter: parent.verticalCenter }
                                width: 28; height: 28; radius: 14
                                color: camH.hovered ? Look.accent : Look.raise
                                Behavior on color { Fade {} }
                                G { anchors.centerIn: parent; glyph: 0xF0567; font.pixelSize: 13; color: camH.hovered ? Look.accentInk : Look.dim }
                                HoverHandler { id: camH; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: p.open(ev.e.meet) }
                            }
                            HoverHandler { id: eh; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: { if (camH.hovered) return; p.open(ev.e.link) } }
                        }
                    }
                }

                // nothing that day
                Column {
                    visible: p.dayEvents.length === 0 || (p.onToday && !p.upNext && p.rest.length === 0 && p.allDay.length === 0)
                    width: parent.width
                    topPadding: 18
                    bottomPadding: 12
                    spacing: 6
                    G {
                        anchors.horizontalCenter: parent.horizontalCenter
                        glyph: Cal.failed ? 0xF0B66 : 0xF0599
                        font.pixelSize: 26
                        height: 32
                        color: Cal.failed ? Look.urgent : Look.warm
                    }
                    T {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Cal.failed ? "No calendar feed" : p.onToday ? "Nothing else today" : "A free day"
                        font.weight: Font.DemiBold
                    }
                    T {
                        anchors.horizontalCenter: parent.horizontalCenter
                        visible: !Cal.failed
                        text: "Add something with the box on the left"
                        color: Look.faint
                        font.pixelSize: Look.small
                    }
                }

                // a look at the day after
                Column {
                    visible: p.afterEvents.length > 0
                    width: parent.width
                    spacing: 4
                    Rectangle { width: parent.width; height: 1; color: Look.line }
                    Item { width: 1; height: 4 }
                    Item {
                        width: parent.width
                        height: 16
                        Label { leftPadding: 2; text: p.dayName(p.after) === "Tomorrow" || p.dayName(p.after) === "Today" ? p.dayName(p.after) : Qt.formatDate(p.after, "dddd d") }
                        T {
                            anchors.right: parent.right
                            text: "Show"
                            color: sh.hovered ? Look.accent : Look.faint
                            font.pixelSize: Look.small
                            HoverHandler { id: sh; cursorShape: Qt.PointingHandCursor }
                            TapHandler { onTapped: p.pick(p.after) }
                        }
                    }
                    Repeater {
                        model: p.afterEvents.slice(0, 3)
                        Row {
                            required property var modelData
                            x: 2
                            spacing: 10
                            T {
                                width: 44
                                text: modelData.allDay ? "all day" : p.hm(new Date(modelData.start)) + p.ap(new Date(modelData.start))
                                color: Look.faint
                                font.pixelSize: Look.small
                            }
                            T { width: p.rightW - 60; text: modelData.title; color: Look.dim; font.pixelSize: Look.small; elide: Text.ElideRight }
                        }
                    }
                    T {
                        x: 56
                        visible: p.afterEvents.length > 3
                        text: `+${p.afterEvents.length - 3} more`
                        color: Look.faint
                        font.pixelSize: Look.small
                    }
                }
            }
        }
    }
}
