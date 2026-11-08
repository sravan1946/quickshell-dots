import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.islands

// The calendar: scroll or ‹ › for other months, click the month to come back, click a day
// for its Google Calendar events (Cal.qml), click an event to open it, and type in the box to
// add one on that day (opens Google Calendar prefilled).
Panel {
    id: p
    implicitWidth: 7 * cell
    spacing: 6
    readonly property int cell: 34
    SystemClock { id: clock; precision: SystemClock.Minutes }
    readonly property date now: clock.date
    readonly property int first: [Qt.locale().firstDayOfWeek % 7, 1, 0][Settings.weekStart]
    property int shift: 0
    property date selected: now
    readonly property date month: new Date(now.getFullYear(), now.getMonth() + shift, 1)
    readonly property int lead: (month.getDay() - first + 7) % 7
    readonly property var dayEvents: Cal.on(selected)
    Component.onCompleted: Cal.refresh()
    WheelHandler { onWheel: e => p.shift += e.angleDelta.y > 0 ? -1 : 1 }

    function hm(d) { return Qt.formatTime(d, Settings.clock24h ? "HH:mm" : "h:mm") }
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

    Item {
        width: parent.width
        height: 26
        T {
            anchors.verticalCenter: parent.verticalCenter
            leftPadding: 4
            text: Qt.formatDate(p.month, "MMMM yyyy")
            font.pixelSize: 13
            font.weight: Font.DemiBold
            color: back.hovered && p.shift !== 0 ? Look.accent : Look.text
            HoverHandler { id: back; cursorShape: p.shift !== 0 ? Qt.PointingHandCursor : Qt.ArrowCursor }
            TapHandler { onTapped: { p.shift = 0; p.selected = p.now } }
        }
        Row {
            anchors { right: parent.right; verticalCenter: parent.verticalCenter }
            Nav { glyph: 0xF0141; onTap: p.shift-- }
            Nav { glyph: 0xF0142; onTap: p.shift++ }
        }
    }
    Row {
        Repeater {
            model: 7
            T {
                required property int index
                width: p.cell
                horizontalAlignment: Text.AlignHCenter
                text: Qt.locale().dayName((p.first + index) % 7, Locale.ShortFormat).slice(0, 1)
                color: Look.faint
                font.pixelSize: 11
                font.weight: Font.DemiBold
            }
        }
    }
    Grid {
        columns: 7
        Repeater {
            model: 42
            Item {
                id: day
                required property int index
                readonly property date d: new Date(p.month.getFullYear(), p.month.getMonth(), 1 - p.lead + index)
                readonly property bool inMonth: d.getMonth() === p.month.getMonth()
                readonly property bool today: d.toDateString() === p.now.toDateString()
                readonly property bool picked: d.toDateString() === p.selected.toDateString()
                readonly property int count: Cal.on(d).length
                width: p.cell
                height: 30
                Rectangle {
                    anchors.centerIn: parent
                    width: 28
                    height: 28
                    radius: 9
                    color: day.today ? Look.accent : dh.hovered ? Look.hover : "transparent"
                    border.width: day.picked && !day.today ? 1 : 0
                    border.color: Qt.alpha(Look.accent, 0.6)
                    Behavior on color { Fade {} }
                }
                T {
                    anchors.centerIn: parent
                    text: day.d.getDate()
                    color: day.today ? Look.accentInk : Look.dim
                    opacity: day.inMonth ? 1 : 0.35
                    font.weight: day.today ? Font.Bold : Font.Normal
                }
                Rectangle {
                    visible: day.count > 0
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 23
                    width: 3; height: 3; radius: 1.5
                    color: day.today ? Look.accentInk : Look.warm
                }
                HoverHandler { id: dh; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: p.selected = day.d }
            }
        }
    }
    Rectangle { width: parent.width; height: 1; color: Look.line }
    Head {
        text: p.selected.toDateString() === p.now.toDateString() ? "Today" : Qt.formatDate(p.selected, "dddd, d MMM")
        G {
            glyph: 0xF0450
            font.pixelSize: 12
            color: Cal.stale ? Look.urgent : Look.faint
            TapHandler { onTapped: Cal.refresh() }
        }
    }
    T {
        visible: p.dayEvents.length === 0
        leftPadding: 4
        text: Cal.failed ? "Couldn't load Google Calendar" : "No events"
        color: Look.dim
        font.pixelSize: Look.small
    }
    Column {
        width: parent.width
        spacing: 1
        Repeater {
            model: p.dayEvents
            Rectangle {
                id: ev
                required property var modelData
                readonly property var e: modelData
                readonly property bool past: new Date(e.end) <= p.now
                readonly property bool soon: !past && new Date(e.start) - p.now <= Settings.meetLead * 60000
                width: parent.width
                height: 28
                radius: 8
                color: evh.hovered ? Look.hover : "transparent"
                opacity: past ? 0.45 : 1
                Behavior on color { Fade {} }
                HoverHandler { id: evh; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: { Qt.openUrlExternally(ev.e.link); p.ctl.hide() } }
                RowLayout {
                    anchors { fill: parent; leftMargin: 4; rightMargin: 4 }
                    spacing: 9
                    T { Layout.preferredWidth: 44; text: ev.e.allDay ? "all day" : p.hm(new Date(ev.e.start)); color: ev.soon ? Look.warm : Look.dim; font.pixelSize: Look.small }
                    Rectangle { width: 3; height: 16; radius: 1.5; color: ev.soon ? Look.warm : Look.accent }
                    T { Layout.fillWidth: true; text: ev.e.title; elide: Text.ElideRight; font.weight: ev.soon ? Font.DemiBold : Font.Normal }
                    Btn { visible: !!ev.e.meet && !ev.past; text: "Join"; strong: ev.soon; tone: Look.warm; onClicked: { Qt.openUrlExternally(ev.e.meet); p.ctl.hide() } }
                }
            }
        }
    }
    Field {
        hint: "Add on " + Qt.formatDate(p.selected, "d MMM") + ", e.g. Sync 4pm"
        glyph: 0xF0415
        onAccepted: if (text.trim() !== "") { p.add(text); text = "" }
        TapHandler { onTapped: parent.grab() }
    }

    component Nav: Rectangle {
        id: n
        property int glyph
        signal tap()
        width: 26
        height: 26
        radius: 9
        color: nh.hovered ? Look.hover : "transparent"
        Behavior on color { Fade {} }
        G { anchors.centerIn: parent; glyph: n.glyph; color: Look.dim; font.pixelSize: 15 }
        HoverHandler { id: nh; cursorShape: Qt.PointingHandCursor }
        TapHandler { onTapped: n.tap() }
    }
}
