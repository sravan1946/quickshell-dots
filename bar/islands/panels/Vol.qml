import QtQuick
import Quickshell.Services.Pipewire
import qs
import qs.islands

// Sound: the speaker and mic levels, which output and input are in use, and each app's level.
// Click an icon to mute it.
Panel {
    id: p
    implicitWidth: 310
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var src: Pipewire.defaultAudioSource
    readonly property var sinks: Pipewire.nodes.values.filter(n => n.audio && n.isSink && !n.isStream)
    readonly property var sources: Pipewire.nodes.values.filter(n => n.audio && !n.isSink && !n.isStream)
    // apps playing: Quickshell counts their streams as sinks (cava's recording stream isn't one)
    readonly property var apps: Pipewire.nodes.values.filter(n => n.audio && n.isStream && n.isSink)
    PwObjectTracker { objects: [p.sink, p.src].concat(p.sinks, p.sources, p.apps) }
    // apps by name, ALSA devices by profile ("Speaker", not "Ryzen HD Audio Controller Speaker")
    function name(n) { return n?.properties?.["application.name"] || n?.properties?.["device.profile.description"] || n?.description || n?.nickname || n?.name || "" }

    Head { text: "Sound"; note: "scroll on the icon to change" }
    Level { node: p.sink; glyph: p.sink?.audio?.muted ? 0xF0581 : Util.headphones(p.sink) ? 0xF02CB : 0xF057E }
    Level { node: p.src; glyph: p.src?.audio?.muted ? 0xF036D : 0xF036C }

    Head { text: "Output" }
    Column {
        width: parent.width
        spacing: 2
        Repeater {
            model: p.sinks
            Choice {
                required property var modelData
                title: p.name(modelData)
                selected: modelData === p.sink
                onClicked: Pipewire.preferredDefaultAudioSink = modelData
                G { anchors.centerIn: parent; glyph: Util.headphones(modelData) ? 0xF02CB : 0xF04C3 }
            }
        }
    }
    Head { visible: p.sources.length > 1; text: "Input" }
    Column {
        visible: p.sources.length > 1
        width: parent.width
        spacing: 2
        Repeater {
            model: p.sources
            Choice {
                required property var modelData
                title: p.name(modelData)
                selected: modelData === p.src
                onClicked: Pipewire.preferredDefaultAudioSource = modelData
                G { anchors.centerIn: parent; glyph: 0xF036C }
            }
        }
    }
    Head { visible: p.apps.length > 0; text: "Apps" }
    Repeater {
        model: p.apps
        Level {
            required property var modelData
            node: modelData
            label: p.name(modelData)
            glyph: modelData.audio?.muted ? 0xF0581 : 0xF057E
        }
    }

    // icon (click to mute), an optional name, the slider and the level
    component Level: Column {
        id: lv
        property var node
        property int glyph
        property string label: ""
        width: p.width
        spacing: 2
        T { visible: lv.label !== ""; leftPadding: 28; text: lv.label; color: Look.dim; font.pixelSize: Look.small }
        Row {
            width: parent.width
            spacing: 10
            G {
                width: 18
                glyph: lv.glyph
                color: lv.node?.audio?.muted ? Look.faint : Look.text
                TapHandler { onTapped: if (lv.node?.audio) Util.setMuted(lv.node, !lv.node.audio.muted) }
            }
            Slide {
                width: parent.width - 72
                fill: lv.node?.audio?.muted ? Look.faint : Look.accent
                value: lv.node?.audio?.volume ?? 0
                onMoved: v => { if (lv.node?.audio) Util.setVolume(lv.node, v) }
            }
            T { width: 34; horizontalAlignment: Text.AlignRight; text: Math.round((lv.node?.audio?.volume ?? 0) * 100) + "%"; color: Look.dim; anchors.verticalCenter: parent.verticalCenter }
        }
    }
}
