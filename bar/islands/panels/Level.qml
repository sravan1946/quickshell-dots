import QtQuick
import Quickshell.Services.Pipewire
import qs
import qs.islands

// The volume or brightness (`arg`: "vol" or "bri") dropping out of its icon for a moment while
// it changes, whoever changed it (keys, scroll, pavucontrol). The same fat track as the panels
// (accent for sound, warm for light), so it's the same thing whether you open it or it pops up.
// It's a slider too while it's out; tap the glyph to mute.
Panel {
    id: p
    implicitWidth: 280
    readonly property bool vol: arg === "vol"
    readonly property var sink: Pipewire.defaultAudioSink
    PwObjectTracker { objects: [p.sink] }
    readonly property real value: vol ? sink?.audio?.volume ?? 0 : Brightness.pct / 100
    readonly property bool muted: vol && !!sink?.audio?.muted

    Track {
        width: parent.width
        value: p.value
        tint: p.vol ? Look.accent : Look.warm
        muted: p.muted
        floor: p.vol ? 0 : 0.01
        step: p.vol ? 0.02 : 0.01
        glyph: !p.vol ? (value < 0.34 ? 0xF00DE : value < 0.67 ? 0xF00DF : 0xF00E0)
            : p.muted ? 0xF0581 : value < 0.34 ? 0xF057F : value < 0.67 ? 0xF0580 : 0xF057E
        text: p.muted ? "—" : Math.round(p.value * 100) + "%"
        onMoved: v => { if (p.vol) Util.setVolume(p.sink, v); else Brightness.set(v * 100) }
        onGlyphTapped: if (p.vol && p.sink?.audio) Util.setMuted(p.sink, !p.muted)
    }
}
