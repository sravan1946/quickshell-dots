pragma Singleton
import QtQuick
import Quickshell
import qs

// The network as the bar shows it. Rates come from NetStats (sampled once for every bar).
Singleton {
    readonly property var info: NetStats.info
    readonly property bool online: NetStats.iface !== ""
    readonly property bool wifi: !!info.ssid
    readonly property bool vpn: NetStats.vpn
    readonly property int signal: parseInt(info.signal) || 0
    // wifi-strength 1..4, ethernet, off
    readonly property int glyph: !online ? 0xF092F
        : !wifi ? 0xF0200
        : [0xF091F, 0xF0922, 0xF0925, 0xF0928][Math.min(3, Math.floor(signal / 25))]

    // at most four characters, so the readout keeps one width: 0.4k 12k 980k 1.2M
    function short(b) {
        const k = b / 1000
        return k >= 1000 ? (k / 1000).toFixed(1) + "M" : k >= 10 ? Math.round(k) + "k" : k.toFixed(1) + "k"
    }
    // full form for the panel
    function rate(b) {
        const u = ["B", "kB", "MB", "GB"]
        let i = 0
        while (b >= 1000 && i < u.length - 1) { b /= 1000; i++ }
        return (i ? b.toFixed(1) : Math.round(b)) + " " + u[i] + "/s"
    }
}
