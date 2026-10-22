pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Whether this checkout of the bar is behind GitHub (scripts/update.sh), for the banner in
// quick settings. Checked a minute after start, hourly, and on opening quick settings if the
// last check is over 10 minutes old. pull() fast-forwards; the reload unit picks up the files.
Singleton {
    id: root

    property int behind: 0
    property var subjects: []     // newest first, up to 5
    property string error: ""     // the last pull's failure, cleared by the next check
    readonly property bool busy: proc.running
    property double checkedAt: 0

    // the beatglow plugin is built but Hyprland didn't load it: almost always a Hyprland
    // update it refused (main.cpp's version check). rebuildPlugin() builds and loads it.
    property bool pluginStale: false
    readonly property bool pluginBusy: plugin.running
    readonly property string pluginDir: Qt.resolvedUrl("../hypr/beatglow").toString().replace("file://", "")
    function rebuildPlugin() {
        if (plugin.running) return
        plugin.command = ["sh", "-c", `make -s -C '${pluginDir}' load >/dev/null 2>&1; ${plugin.test}`]
        plugin.running = true
    }

    function check() { run([]); if (!plugin.running) { plugin.command = ["sh", "-c", plugin.test]; plugin.running = true } }
    function pull() { run(["pull"]) }
    function stale() { if (Date.now() - checkedAt > 10 * 60000) check() }

    function run(args) {
        if (proc.running) return
        proc.pulling = args.length > 0
        proc.command = ["sh", Qt.resolvedUrl("scripts/update.sh").toString().replace("file://", "")].concat(args)
        proc.running = true
    }

    Timer { interval: 60000; running: true; onTriggered: root.check() }
    Timer { interval: 3600000; running: true; repeat: true; onTriggered: root.check() }

    Process {
        id: plugin
        // exit 0: needs a rebuild
        readonly property string test: `[ -f '${root.pluginDir}/beatglow.so' ] && ! hyprctl plugin list | grep -q '^Plugin beatglow '`
        onExited: code => root.pluginStale = code === 0
    }

    Process {
        id: proc
        property bool pulling: false
        stdout: StdioCollector { id: out }
        onExited: code => {
            root.checkedAt = Date.now()
            if (code === 0) {
                const lines = out.text.trim().split("\n")
                root.behind = parseInt(lines[0]) || 0
                root.subjects = lines.slice(1)
                root.error = ""
            } else if (pulling) {
                // 2: offline / GitHub unreachable, 3: local edits in the way of a fast-forward
                root.error = code === 3 ? "Local changes are in the way: commit or stash them" : "Couldn't reach GitHub"
            }   // a failed background check keeps what it knew
        }
    }
}
