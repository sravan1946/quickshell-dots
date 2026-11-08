pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Bluetooth

// Each earbud's battery (and the case's, while they're in it) for connected Nothing / CMF buds:
// BlueZ only knows one number. scripts/buds.py asks the buds themselves, on connecting and
// then once a minute.
Singleton {
    id: root
    // address -> { left: [pct, charging], right: [...], case: [...] }, whichever they report
    property var levels: ({})
    readonly property var buds: (Bluetooth.defaultAdapter?.devices.values ?? [])
        .filter(d => d.connected && /nothing|cmf|\bear\b/i.test(d.name))
    function of(d) { return d ? levels[d.address] ?? null : null }
    // "L 90  R 85": the two buds, for the bar
    function short(d) {
        const l = of(d)
        return l && (l.left || l.right) ? [l.left && "L " + l.left[0], l.right && "R " + l.right[0]].filter(s => s).join("  ") : ""
    }
    function low(d) { const l = of(d); return !!l && [l.left, l.right].some(p => p && p[0] <= 20 && !p[1]) }

    // buds just connected take a moment before they answer
    onBudsChanged: soon.restart()
    Timer { id: soon; interval: 4000; onTriggered: root.poll() }
    Timer { interval: 60000; repeat: true; running: root.buds.length > 0; onTriggered: root.poll() }

    property var queue: []
    function poll() {
        if (req.running) return
        queue = buds.map(d => d.address)
        next()
    }
    function next() {
        if (!queue.length) return
        req.addr = queue[0]
        queue = queue.slice(1)
        req.command = ["python3", Qt.resolvedUrl("../scripts/buds.py").toString().replace("file://", ""), req.addr]
        req.running = true
    }
    Process {
        id: req
        property string addr
        stdout: StdioCollector {
            onStreamFinished: {
                let r = {}
                try { r = JSON.parse(text) } catch (e) {}
                // nothing back (out of range, busy): keep the last reading
                if (Object.keys(r).length) { const l = Object.assign({}, root.levels); l[req.addr] = r; root.levels = l }
            }
        }
        onExited: root.next()
    }
}
