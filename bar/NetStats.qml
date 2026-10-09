pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Default-route interface and its live rates, sampled once for every bar.
// modules/Network.qml draws it; refresh() fetches the nmcli details on demand.
Singleton {
    id: root

    readonly property int interval: Settings.netInterval

    property string iface: ""
    property real rx: 0
    property real tx: 0
    property real last: 0
    property real down: 0
    property real up: 0
    property string gateway: ""
    property var info: ({})
    property var hist: []            // last 60 [down, up] samples (2 min), for the graphs

    // reload() is async (text() right after it is stale), so compute once /proc/net/dev lands
    function sample() {
        routeFile.reload()
        devFile.reload()
    }

    function update() {
        let best = "", gw = "", metric = Infinity
        for (const l of routeFile.text().split("\n").slice(1)) {
            const f = l.trim().split(/\s+/)
            if (f.length > 6 && f[1] === "00000000" && +f[6] < metric) { best = f[0]; gw = f[2]; metric = +f[6] }
        }
        // /proc/net/route stores the gateway as little-endian hex
        gateway = gw ? [0, 2, 4, 6].map(i => parseInt(gw.substr(6 - i, 2), 16)).join(".") : ""
        const line = devFile.text().split("\n").find(l => l.trim().startsWith(best + ":"))
        if (best === "" || !line) { iface = ""; last = 0; return }
        const f = line.split(":")[1].trim().split(/\s+/)
        const r = +f[0], t = +f[8], now = Date.now()
        if (best === iface && last) {
            const dt = (now - last) / 1000
            down = Math.max(0, (r - rx) / dt)
            up = Math.max(0, (t - tx) / dt)
            hist = hist.concat([[down, up]]).slice(-60)
        }
        iface = best; rx = r; tx = t; last = now
    }

    // a refresh asked for mid-fetch (a network switch, the hover timer) runs once that one ends,
    // so the details never stay on the interface the fetch started with
    property bool again: false
    function refresh() { if (nm.running) again = true; else nm.running = true }
    onIfaceChanged: refresh()   // startup and network switches: quick settings shouldn't open on an empty info

    FileView { id: routeFile; path: "/proc/net/route" }
    FileView { id: devFile; path: "/proc/net/dev"; onLoaded: root.update() }
    Timer { interval: root.interval; running: true; repeat: true; triggeredOnStart: true; onTriggered: root.sample() }

    Process {
        id: nm
        onRunningChanged: if (!running && root.again) { root.again = false; running = true }
        command: ["sh", "-c", `
            ip -4 -o addr show dev '${root.iface}' | awk '{print "IP:" $4; exit}'
            nmcli -t -f GENERAL.CONNECTION dev show '${root.iface}'
            nmcli -t -f IN-USE,SSID,SIGNAL,FREQ dev wifi list --rescan no | grep '^\\*'
            echo "RADIO:$(nmcli radio wifi)"
            awk 'NR>2 {print "DBM:" int($4)}' /proc/net/wireless`]
        stdout: StdioCollector {
            onStreamFinished: {
                const o = {}
                for (const l of text.split("\n")) {
                    const kv = Util.nmFields(l)
                    if (kv[0] === "GENERAL.CONNECTION") o.conn = kv[1]
                    else if (kv[0] === "IP") o.ip = kv[1]
                    else if (kv[0] === "*") { o.ssid = kv[1]; o.signal = kv[2]; o.freq = kv[3] }
                    else if (kv[0] === "RADIO") o.wifiOn = kv[1] === "enabled"
                    else if (kv[0] === "DBM") o.dbm = kv[1]
                }
                root.info = o
            }
        }
    }
}
