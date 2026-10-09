import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.components

// clock: left-click opens the calendar, right-click toggles the long format. Pinning the
// pointer to the screen edge above it opens the calendar too, hover-style: it goes again once
// the pointer leaves the clock and the calendar (no click grab: that needs a real click).
// In the calendar: scroll or ‹ › to change month, click the title to come back to today,
// click a day for its Google Calendar events (Cal.qml), click an event to open it,
// type in the box to add one on that day (opens Google Calendar prefilled).
Mod {
    id: clock

    property bool alt: false

    // minute ticks: nothing shown has seconds
    SystemClock { id: sys; precision: SystemClock.Minutes }
    readonly property date now: sys.date

    text: alt
        ? Qt.formatDateTime(now, "HH:mm") + " " + Theme.g(0xF00ED) + " " + Qt.formatDateTime(now, "dd·MM·yy")
        : Qt.formatDateTime(now, Settings.clock24h ? "HH:mm" : "hh:mm AP")
    tip: panel.visible ? "" : Qt.formatDate(now, "dddd, d MMMM yyyy")
        + (Cal.next ? `<br><font color="${Theme.actFg}">${Theme.g(0xF00F0)} ${nextText(Cal.next)}</font>` : "")
        + "<br>Click: calendar · Right-click: format"

    onClicked: b => {
        if (b === Qt.LeftButton) {
            if (!panel.visible) open(true)
            else panel.toggle()
        } else if (b === Qt.RightButton) alt = !alt
    }
    function open(grab) {
        cal.shift = 0
        cal.selected = now
        // the popup window is reused, so focus from an earlier click would come back the
        // moment Hyprland hands it the keyboard on hover: the field waits for a real click
        input.focus = false
        Cal.refresh()
        panel.closeOnOutsideClick = grab
        panel.toggle()
    }

    // the clock's pill touches the top, so y 0 is the screen edge
    HoverHandler {
        id: edge
        readonly property bool atEdge: hovered && point.position.y <= 1
        onAtEdgeChanged: if (atEdge && !panel.visible) edgeDwell.restart(); else edgeDwell.stop()
    }
    Timer { id: edgeDwell; interval: Settings.hoverDelay; onTriggered: clock.open(false) }
    Timer {
        interval: 350
        running: panel.visible && !panel.closeOnOutsideClick && !edge.hovered && !panel.hovered
        onTriggered: panel.close()
    }

    function hm(d) { return Qt.formatTime(d, "HH:mm") }
    function nextText(e) {
        const s = new Date(e.start)
        if (s <= now) return `Now: ${e.title} (until ${hm(new Date(e.end))})`
        const mins = Math.round((s - now) / 60000)
        const when = mins < 60 ? `in ${mins} min`
            : s.toDateString() === now.toDateString() ? `at ${hm(s)}`
            : Qt.formatDate(s, "ddd d MMM") + " " + hm(s)
        return `Next: ${e.title} ${when}`
    }
    function duration(e) {
        const m = Math.round((new Date(e.end) - new Date(e.start)) / 60000)
        return m < 60 ? m + "m" : m % 60 ? `${Math.floor(m / 60)}h${m % 60}m` : m / 60 + "h"
    }
    // "Standup 10:30", "Lunch at 1pm", "Call 3:15pm" -> timed; anything else -> all day.
    // A bare number doesn't count as a time ("Sprint 2").
    function add(text) {
        const m = text.trim().match(/^(.*?)\s+(?:at\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)?$/i)
        if (m && (m[3] || m[4]) && m[1]) {
            let h = +m[2] % (m[4] ? 12 : 24)
            if (m[4] && m[4].toLowerCase() === "pm") h += 12
            Cal.newEvent(m[1], cal.selected, h, +(m[3] ?? 0))
        } else Cal.newEvent(text.trim(), cal.selected)
        panel.close()
    }

    Dropdown {
        id: panel
        target: clock
        closeOnOutsideClick: true
        padX: 14
        padY: 12

        Column {
            id: cal
            readonly property int cell: 36
            readonly property int first: Qt.locale().firstDayOfWeek % 7   // 0 = Sunday
            property int shift: 0
            property date selected: clock.now
            readonly property date month: new Date(clock.now.getFullYear(), clock.now.getMonth() + shift, 1)
            readonly property int lead: (month.getDay() - first + 7) % 7   // days shown from the previous month
            readonly property var dayEvents: Cal.on(selected)

            width: 7 * cell
            spacing: 6

            WheelHandler { onWheel: e => cal.shift += e.angleDelta.y > 0 ? -1 : 1 }

            // the new month slides in from the side it came from (not when opening on today)
            property int lastShift: 0
            onShiftChanged: {
                monthIn.dir = shift > lastShift ? 1 : -1
                lastShift = shift
                if (panel.visible) monthIn.restart()
            }
            ParallelAnimation {
                id: monthIn
                property int dir: 1
                NumberAnimation { target: grid; property: "opacity"; from: 0.2; to: 1; duration: 220; easing.type: Easing.OutCubic }
                NumberAnimation { target: gridShift; property: "x"; from: 10 * monthIn.dir; to: 0; duration: 220; easing.type: Easing.OutCubic }
            }

            Item {
                width: parent.width
                height: 28
                NavButton { anchors.left: parent.left; glyph: 0xF0141; onClicked: cal.shift-- }
                Text {
                    anchors.centerIn: parent
                    text: Qt.formatDate(cal.month, "MMMM yyyy")
                    color: titleHover.hovered && cal.shift !== 0 ? Theme.actFg : Theme.mainFg
                    Behavior on color { ColorAnimation { duration: 120 } }
                    font { family: Theme.font; pixelSize: 14; bold: true }
                    HoverHandler { id: titleHover; cursorShape: cal.shift !== 0 ? Qt.PointingHandCursor : Qt.ArrowCursor }
                    TapHandler { onTapped: { cal.shift = 0; cal.selected = clock.now } }
                }
                NavButton { anchors.right: parent.right; glyph: 0xF0142; onClicked: cal.shift++ }
            }

            Row {
                Repeater {
                    model: 7
                    Text {
                        required property int index
                        readonly property int dow: (cal.first + index) % 7
                        width: cal.cell
                        horizontalAlignment: Text.AlignHCenter
                        text: Qt.locale().dayName(dow, Locale.ShortFormat).slice(0, 2)
                        color: dow === 0 || dow === 6 ? Theme.actBg : Theme.mainFg
                        opacity: 0.7
                        font { family: Theme.font; pixelSize: 11; bold: true }
                    }
                }
            }

            // always 6 weeks, so the panel doesn't change height between months
            Grid {
                id: grid
                columns: 7
                transform: Translate { id: gridShift }
                Repeater {
                    model: 42
                    Item {
                        id: day
                        required property int index
                        readonly property date d: new Date(cal.month.getFullYear(), cal.month.getMonth(), 1 - cal.lead + index)
                        readonly property bool inMonth: d.getMonth() === cal.month.getMonth()
                        readonly property bool today: d.toDateString() === clock.now.toDateString()
                        readonly property bool picked: d.toDateString() === cal.selected.toDateString()
                        readonly property bool weekend: d.getDay() === 0 || d.getDay() === 6
                        readonly property int count: Cal.on(d).length

                        width: cal.cell
                        height: 34

                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 1
                            width: 30
                            height: 30
                            radius: 15
                            color: day.today ? Theme.actBg : dayHover.hovered ? Qt.alpha(Theme.mainFg, 0.15) : "transparent"
                            border.color: day.picked && !day.today ? Theme.mainFg : "transparent"
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 8
                            text: day.d.getDate()
                            color: day.today ? Theme.mainBg : day.weekend ? Theme.actFg : Theme.mainFg
                            opacity: day.inMonth ? 1 : 0.3
                            font { family: Theme.font; pixelSize: 12; bold: day.today }
                        }
                        // one dot per event, up to three
                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 24
                            spacing: 2
                            opacity: day.inMonth ? 1 : 0.4
                            Repeater {
                                model: Math.min(3, day.count)
                                Rectangle { width: 3; height: 3; radius: 1.5; color: day.today ? Theme.mainBg : Theme.actFg }
                            }
                        }
                        HoverHandler { id: dayHover; cursorShape: Qt.PointingHandCursor }
                        TapHandler { onTapped: cal.selected = day.d }
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: Qt.alpha(Theme.mainFg, 0.15) }

            // the picked day's events
            RowLayout {
                width: parent.width
                Text {
                    Layout.fillWidth: true
                    text: cal.selected.toDateString() === clock.now.toDateString() ? "Today"
                        : Qt.formatDate(cal.selected, "dddd, d MMM")
                    color: Theme.mainFg
                    font { family: Theme.font; pixelSize: 12; bold: true }
                }
                Text {
                    text: Theme.g(0xF0450)
                    color: Cal.stale ? "#e0af68" : Theme.mainFg
                    opacity: Cal.loading ? 1 : 0.5
                    font { family: Theme.font; pixelSize: 12 }
                    RotationAnimator on rotation { running: Cal.loading; from: 0; to: 360; duration: 900; loops: Animation.Infinite }
                    TapHandler { onTapped: Cal.refresh() }
                }
            }
            Text {
                visible: cal.dayEvents.length === 0
                text: Cal.failed ? "Couldn't load Google Calendar" : "No events"
                color: Theme.mainFg
                opacity: 0.5
                font { family: Theme.font; pixelSize: 11 }
            }
            Column {
                width: parent.width
                spacing: 2
                Repeater {
                    model: cal.dayEvents
                    Rectangle {
                        id: ev
                        required property var modelData
                        readonly property var e: modelData
                        readonly property bool past: new Date(e.end) <= clock.now
                        width: parent.width
                        height: 30
                        radius: 8
                        color: evHover.hovered ? Qt.alpha(Theme.mainFg, 0.12) : "transparent"
                        Behavior on color { ColorAnimation { duration: 120 } }
                        opacity: past ? 0.5 : 1
                        HoverHandler { id: evHover; cursorShape: Qt.PointingHandCursor }
                        // the Join pill has its own tap: the row's must not open the event as well
                        TapHandler { onTapped: if (!joinHover.hovered) { Qt.openUrlExternally(ev.e.link); panel.close() } }

                        RowLayout {
                            anchors { fill: parent; leftMargin: 6; rightMargin: 6 }
                            spacing: 7
                            Rectangle { width: 3; height: 18; radius: 1.5; color: Theme.actBg }
                            Text {
                                text: ev.e.allDay ? "all day" : clock.hm(new Date(ev.e.start))
                                color: Theme.actFg
                                font { family: Theme.font; pixelSize: 11; bold: true }
                            }
                            Text {
                                Layout.fillWidth: true
                                text: ev.e.title
                                color: Theme.mainFg
                                elide: Text.ElideRight
                                font { family: Theme.font; pixelSize: 11 }
                            }
                            Text {
                                visible: !ev.e.allDay
                                text: clock.duration(ev.e)
                                color: Theme.mainFg
                                opacity: 0.5
                                font { family: Theme.font; pixelSize: 10 }
                            }
                            // Google Meet, in the calendar's account (gcal.py adds authuser); solid
                            // from 10 minutes before it starts until it ends
                            Rectangle {
                                id: join
                                readonly property bool soon: new Date(ev.e.start) - clock.now <= 600000
                                visible: !!ev.e.meet && !ev.past
                                implicitWidth: joinRow.implicitWidth + 14
                                implicitHeight: 20
                                radius: 10
                                color: soon ? Theme.actBg : joinHover.hovered ? Qt.alpha(Theme.mainFg, 0.15) : "transparent"
                                border.color: soon ? "transparent" : Qt.alpha(Theme.mainFg, 0.3)
                                Behavior on color { ColorAnimation { duration: 120 } }
                                HoverHandler { id: joinHover; cursorShape: Qt.PointingHandCursor }
                                TapHandler { onTapped: { Qt.openUrlExternally(ev.e.meet); panel.close() } }
                                Row {
                                    id: joinRow
                                    anchors.centerIn: parent
                                    spacing: 4
                                    Text {
                                        text: Theme.g(0xF0567)
                                        color: join.soon ? Theme.actFg : Theme.mainFg
                                        font { family: Theme.font; pixelSize: 12 }
                                    }
                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "Join"
                                        color: join.soon ? Theme.actFg : Theme.mainFg
                                        font { family: Theme.font; pixelSize: 10; bold: true }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // quick add on the picked day
            Rectangle {
                width: parent.width
                height: 28
                radius: 9
                color: Qt.alpha(Theme.mainFg, 0.08)
                border.color: input.activeFocus ? Theme.mainFg : Qt.alpha(Theme.mainFg, 0.2)
                Text {
                    x: 9
                    anchors.verticalCenter: parent.verticalCenter
                    text: Theme.g(0xF0415)
                    color: Theme.mainFg
                    opacity: 0.6
                    font { family: Theme.font; pixelSize: 12 }
                }
                TextInput {
                    id: input
                    anchors { fill: parent; leftMargin: 26; rightMargin: 9 }
                    verticalAlignment: TextInput.AlignVCenter
                    color: Theme.mainFg
                    clip: true
                    font { family: Theme.font; pixelSize: 11 }
                    onAccepted: if (text.trim() !== "") { clock.add(text); text = "" }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: input.text === "" && !input.activeFocus
                        text: "Add on " + Qt.formatDate(cal.selected, "d MMM") + " (e.g. Sync 4pm)"
                        color: Theme.mainFg
                        opacity: 0.4
                        font: input.font
                    }
                }
            }
        }
    }

    component NavButton: Rectangle {
        id: nb
        property int glyph
        signal clicked()
        anchors.verticalCenter: parent.verticalCenter
        width: 26
        height: 26
        radius: 13
        color: nbHover.hovered ? Qt.alpha(Theme.mainFg, 0.15) : "transparent"
        Behavior on color { ColorAnimation { duration: 120 } }
        HoverHandler { id: nbHover; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: nb.clicked() }
        Text {
            anchors.centerIn: parent
            text: Theme.g(nb.glyph)
            color: Theme.mainFg
            font { family: Theme.font; pixelSize: 16 }
        }
    }
}
