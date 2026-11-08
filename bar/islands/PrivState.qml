pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Pipewire

// Apps recording the mic or capturing the screen. A stream's properties stay empty until it is
// tracked, so every stream is. Monitor and capture-sink streams record what's playing (the
// visualizer's cava), not the mic. Screen capture that doesn't go through a Pipewire stream
// (wf-recorder, a portal share Hyprland serves itself) comes from Hyprland's screencast event.
Singleton {
    id: root
    readonly property var all: Pipewire.nodes.values.filter(n => n.isStream)
    PwObjectTracker { objects: root.all }
    readonly property var streams: all.filter(n => String(n.properties["stream.monitor"]) !== "true"
        && String(n.properties["stream.capture.sink"]) !== "true")
    readonly property var mics: streams.filter(n => n.properties["media.class"] === "Stream/Input/Audio")
    readonly property var casts: streams.filter(n => n.properties["media.class"] === "Stream/Input/Video")
    // only a capture that lasts: a screenshot (grim, a colour picker) is one too, for an instant,
    // and flashed the indicator in and out, resizing the island each time
    property bool screencast: false
    property bool casting: false     // what Hyprland last said
    Connections {
        target: Hyprland
        function onRawEvent(e) {
            if (e.name !== "screencast") return
            root.casting = e.data.split(",")[0] === "1"
            if (root.casting) lasting.restart()
            else { lasting.stop(); root.screencast = false }
        }
    }
    Timer { id: lasting; interval: 1200; onTriggered: root.screencast = root.casting }
    readonly property bool capturing: casts.length > 0 || screencast
    readonly property bool on: mics.length > 0 || capturing
    function app(n) { return n.properties["application.name"] ?? n.name }
}
