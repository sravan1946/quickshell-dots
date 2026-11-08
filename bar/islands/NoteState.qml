pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import qs

// Unread notifications: anything logged since the panel was last open. Not kept across
// restarts; a fresh bar starts with everything read.
Singleton {
    id: root
    property real seen: Date.now()
    property int count: History.entries.count   // re-reads on every add/remove
    readonly property bool unread: count > 0 && (count, History.entries.get(0)?.time ?? 0) > seen
    function markRead() { seen = Date.now() }

    // the notifications dropping out of the bell (Settings.notifDrop), newest first. The
    // notification daemon hands every new one here instead of popping it up at the side; the
    // bar on the focused monitor drops them out as soon as its card is free (arrived).
    property var drops: []
    signal arrived()
    signal emptied()
    // a burst (each within 1.5 s of the last) shows together; anything later replaces what's
    // been showing, which is in the history by then. Critical ones stay until dismissed.
    property double lastAt: 0
    function critical(n) { return n?.urgency === NotificationUrgency.Critical }
    readonly property bool holding: drops.some(n => critical(n))
    function take(n) {
        if (drops.includes(n)) return
        const now = Date.now()
        if (now - lastAt > 1500) {
            const seen = drops.filter(x => !critical(x))
            drops = drops.filter(x => critical(x))
            seen.forEach(x => x.tracked = false)
        }
        lastAt = now
        drops = [n].concat(drops)
        n.closed.connect(() => remove(n))   // the app took it back, or it was dismissed
        arrived()
    }
    function remove(n) {
        if (!drops.includes(n)) return
        drops = drops.filter(x => x !== n)
        if (!drops.length) emptied()
    }
    // done with one, or all: dismissed (they're in the history)
    function dismiss(n) { if (!n) return; markRead(); remove(n); n.tracked = false }   // touched it = seen it
    function dismissAll() { const all = drops; drops = []; all.forEach(n => n.tracked = false) }
}
