pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Night light: hyprsunset, driven over `hyprctl hyprsunset`. The bar owns the state ("on temp" in
// $XDG_STATE_HOME/quickshell-nightlight) and puts it back at login, retrying until hyprsunset's
// socket is up (both start together under the session target). The quick settings tile and its
// slider use it (panels/Quick.qml).
Singleton {
    id: root
    property bool on: false
    property int temp: 4500
    readonly property int identity: 6000    // the slider's warm end runs up to this
    readonly property int min: 2500

    function set(t) { temp = t; on = true; save(); apply() }
    function toggle() { on = !on; save(); apply() }
    function apply() {
        Quickshell.execDetached(["sh", "-c", 'for i in $(seq 40); do hyprctl --quiet hyprsunset "$@" && exit; sleep 0.5; done',
            "sh"].concat(on ? ["temperature", String(temp)] : ["identity"]))
    }
    function save() { state.setText(`${on ? 1 : 0} ${temp}\n`) }

    FileView {
        id: state
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/quickshell-nightlight"
        printErrors: false
        onLoaded: {
            const [o, t] = text().trim().split(/\s+/).map(Number)
            root.on = o === 1
            if (t >= root.min && t < root.identity) root.temp = t
            root.apply()
        }
    }
}
