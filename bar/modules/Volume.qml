import QtQuick
import Quickshell.Services.Pipewire
import qs
import qs.components

// pulseaudio (output): left = pavucontrol, right = switch sink, middle = mute, scroll = volume.
Mod {
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property int vol: Math.round((sink?.audio?.volume ?? 0) * 100)
    readonly property string ico: Util.headphones(sink)
        ? Theme.g(0xF025) : Util.pick([0xF026, 0xF027, 0xF028], vol)

    PwObjectTracker { objects: [Pipewire.defaultAudioSink] }

    // fixed width ("ico 100"): this is the bar's right edge, so any change shifts every pill;
    // 0xF0581 because the old muted glyph (0xFA80) left Nerd Fonts 3 and fell back to a CJK char
    minChars: 5
    text: sink?.audio?.muted ? Theme.g(0xF0581) : `${ico} ${vol}`
    tip: `${ico} ${sink?.description ?? ""} // ${vol}%`
    onClicked: b => {
        if (b === Qt.LeftButton) Util.run("pavucontrol-qt -t 3 || pavucontrol -t 3")
        else if (b === Qt.RightButton) Util.run("hyde-shell volumecontrol -s ''")
        else if (sink?.audio) sink.audio.muted = !sink.audio.muted
    }
    // set on the node directly (no process per notch); 5% steps capped at 100 like hyde's volumecontrol
    onScrolled: s => { if (sink?.audio) sink.audio.volume = Math.max(0, Math.min(1, (vol + 5 * s) / 100)) }
}
