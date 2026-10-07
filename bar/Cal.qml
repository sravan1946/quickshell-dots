pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Google Calendar events for the clock's calendar (scripts/gcal.py reads the calendar's
// secret iCal feed: read-only, no OAuth). Refreshed every 10 minutes and whenever the
// calendar opens. New events are made in the browser (newEvent()).
Singleton {
    id: root

    property var events: []
    property var byDay: ({})        // "yyyy-MM-dd" -> events touching that day
    property real fetched: 0
    property bool stale: false      // fetch failed, showing the cached feed
    property bool failed: false     // no events at all (no URL file, no cache)
    property string owner: ""
    property string tz: ""
    readonly property bool loading: proc.running

    SystemClock { id: clock; precision: SystemClock.Minutes }
    // the event on now or next today/tomorrow-ish: first timed one that hasn't ended
    readonly property var next: events.find(e => !e.allDay && new Date(e.end) > clock.date) ?? null

    function refresh() { if (!proc.running) proc.running = true }
    function key(d) { return Qt.formatDate(d, "yyyy-MM-dd") }
    function on(d) { return byDay[key(d)] ?? [] }

    function index(list) {
        const m = {}
        for (const e of list) {
            // every day the event touches; all-day ends are exclusive, so are midnight ends
            const s = new Date(e.start), end = new Date(e.end)
            const d = new Date(s.getFullYear(), s.getMonth(), s.getDate())
            do {
                (m[key(d)] = m[key(d)] ?? []).push(e)
                d.setDate(d.getDate() + 1)
            } while (d < end)
        }
        return m
    }

    // Google Calendar's "new event" page, prefilled; you press Save there
    function newEvent(title, day, hours, minutes) {
        const pad = n => String(n).padStart(2, "0")
        const ymd = d => `${d.getFullYear()}${pad(d.getMonth() + 1)}${pad(d.getDate())}`
        let dates
        if (hours === undefined) {
            const after = new Date(day); after.setDate(after.getDate() + 1)
            dates = `${ymd(day)}/${ymd(after)}`
        } else {
            const s = new Date(day.getFullYear(), day.getMonth(), day.getDate(), hours, minutes)
            const e = new Date(s.getTime() + 3600000)
            const t = d => `${ymd(d)}T${pad(d.getHours())}${pad(d.getMinutes())}00`
            dates = `${t(s)}/${t(e)}`
        }
        // authuser: open it in the calendar owner's account, not the browser's default one
        Qt.openUrlExternally("https://calendar.google.com/calendar/r/eventedit"
            + `?text=${encodeURIComponent(title)}&dates=${dates}`
            + (tz ? `&ctz=${encodeURIComponent(tz)}` : "")
            + (owner ? `&authuser=${encodeURIComponent(owner)}` : ""))
    }

    Process {
        id: proc
        command: ["uv", "run", "--quiet", "--script", Qt.resolvedUrl("scripts/gcal.py").toString().replace("file://", "")]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text)
                    root.events = d.events
                    root.byDay = root.index(d.events)
                    root.fetched = d.fetched
                    root.stale = d.stale
                    root.owner = d.owner
                    root.tz = d.tz
                    root.failed = false
                } catch (e) { root.failed = root.events.length === 0 }
            }
        }
        stderr: StdioCollector { onStreamFinished: if (text.trim()) console.warn("gcal:", text.trim()) }
    }
    Timer { interval: 10 * 60 * 1000; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.refresh() }
}
