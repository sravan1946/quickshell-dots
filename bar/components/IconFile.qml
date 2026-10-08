import QtQuick
import Quickshell.Io
import qs

// Util.findIcon for `name`, kept current: `file` is "file://<path>" once the lookup for the
// current name has landed, "" until then (and when the theme has nothing).
// running = false doesn't stop a live lookup at once, so when the name flips fast (nm-applet on
// reconnect) the old name's lookup can land last: the name goes out first, a stale answer is
// ignored and the lookup reruns for the current name.
Process {
    id: finder

    property string name
    property string extra: ""        // a dir to try before the theme (an SNI IconThemePath)
    property string sizes: ""        // findIcon's size dirs; "" = its 16px panel default

    property string found: ""
    property string foundFor: ""
    readonly property string file: foundFor === name ? found : ""

    function look() { if (name !== "" && foundFor !== name) running = true }
    onNameChanged: look()
    Component.onCompleted: look()
    onRunningChanged: if (!running) look()

    command: ["sh", "-c", 'echo "$1"; ' + Util.findIcon, "sh", name, extra, sizes]
    stdout: StdioCollector {
        onStreamFinished: {
            const [n, f] = text.split("\n")
            finder.foundFor = n
            finder.found = f ? "file://" + f : ""
        }
    }
}
