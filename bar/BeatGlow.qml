import QtQuick
import Quickshell
import Quickshell.Io

// Hands each kick to the beatglow Hyprland plugin (~/.config/hypr/plugins/beatglow), which runs
// the bar's beat wave round the focused window's border: strength, the wave's timing, the kick's
// colour (Visualizer.kickColor) and where each screen's wave starts. One message per kick; the plugin animates on its
// own clock. Without the plugin Hyprland just answers "unknown request".
Scope {
    Connections {
        target: Visualizer
        function onBeat(s) {
            const c1 = Visualizer.beatCol, c2 = Qt.darker(Visualizer.beatCol, 1.8), o = Visualizer.origins   // the kick's own colour
            const f = v => v.toFixed(3)
            sock.next = ["beatglow", "beat", f(s), Visualizer.waveDur, Visualizer.waveReach,
                         f(c1.r), f(c1.g), f(c1.b), f(c2.r), f(c2.g), f(c2.b),
                         ...Object.keys(o).map(k => `${k}=${o[k].toFixed(1)}`)].join(" ")
            if (!sock.connected) sock.connected = true
        }
    }

    // one request per connection (Hyprland answers and hangs up)
    Socket {
        id: sock
        path: `${Quickshell.env("XDG_RUNTIME_DIR")}/hypr/${Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")}/.socket.sock`
        property string next: ""
        // hang up on the reply ourselves: Hyprland closing first logs a PeerClosedError
        parser: SplitParser { splitMarker: ""; onRead: sock.connected = false }
        onConnectedChanged: {
            if (connected) { write(next); flush(); next = "" }
            else if (next) connected = true
        }
    }
}
