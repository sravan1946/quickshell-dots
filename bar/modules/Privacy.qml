import QtQuick
import Quickshell.Services.Pipewire
import qs
import qs.components

// privacy: icons while an app records the mic or captures the screen
// (waybar defaults: screenshare + audio-in).
Row {
    id: root

    // node.properties stays empty until the node is tracked, so track every stream to read them.
    // Monitor and capture-sink streams record what's playing (cava's visualizer), not the mic.
    readonly property var all: Pipewire.nodes.values.filter(n => n.isStream)
    PwObjectTracker { objects: root.all }
    readonly property var streams: all.filter(n => String(n.properties["stream.monitor"]) !== "true"
        && String(n.properties["stream.capture.sink"]) !== "true")
    readonly property var mics: streams.filter(n => n.properties["media.class"] === "Stream/Input/Audio")
    readonly property var casts: streams.filter(n => n.properties["media.class"] === "Stream/Input/Video")

    readonly property color alert: "#f7768e"

    // past startup: indicators that show up after this grow in
    property bool settled: false
    Timer { running: true; interval: 1000; onTriggered: root.settled = true }

    function apps(nodes) { return nodes.map(n => n.properties["application.name"] ?? n.name).join("<br>") }

    Mod {
        visible: root.casts.length > 0
        text: Theme.g(0xF0379)
        growIn: root.settled
        fg: root.alert
        tip: "Screensharing:<br>" + root.apps(root.casts)
    }
    Mod {
        visible: root.mics.length > 0
        text: Theme.g(0xF036C)
        growIn: root.settled
        fg: root.alert   // red (the mic glyph)
        tip: "Microphone in use:<br>" + root.apps(root.mics)
    }
}
