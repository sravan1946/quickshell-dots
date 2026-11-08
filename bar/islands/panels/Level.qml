import QtQuick
import Quickshell.Services.Pipewire
import qs
import qs.islands

// The volume or brightness (`arg`: "vol" or "bri") dropping out of its icon for a moment while
// it changes, whoever changed it (keys, scroll, pavucontrol). It's a slider too, while it's out.
Panel {
    id: p
    implicitWidth: 240
    readonly property bool vol: arg === "vol"
    readonly property var sink: Pipewire.defaultAudioSink
    PwObjectTracker { objects: [p.sink] }
    readonly property real value: vol ? sink?.audio?.volume ?? 0 : Brightness.pct / 100
    readonly property bool muted: vol && !!sink?.audio?.muted

    Row {
        width: parent.width
        spacing: 10
        G {
            width: 18
            glyph: !p.vol ? 0xF00DF : p.muted ? 0xF0581 : Util.headphones(p.sink) ? 0xF02CB : p.value < 0.34 ? 0xF057F : 0xF057E
            color: p.muted ? Look.faint : Look.text
        }
        Slide {
            width: parent.width - 72
            fill: p.muted ? Look.faint : Look.accent
            value: p.value
            onMoved: v => { if (p.vol) Util.setVolume(p.sink, v); else Brightness.set(v * 100) }
        }
        T { width: 34; horizontalAlignment: Text.AlignRight; text: Math.round(p.value * 100) + "%"; color: Look.dim; anchors.verticalCenter: parent.verticalCenter }
    }
}
