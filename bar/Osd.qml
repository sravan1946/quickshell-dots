import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import qs

// Volume / mic / brightness OSD on the focused monitor. It reacts to the value
// changing, whoever changed it: bar scroll, media keys (hyde-shell), pavucontrol.
// hyde-shell's notify-send OSD is switched off in ~/.local/state/hyde/config
// (VOLUME_NOTIFY / BRIGHTNESS_NOTIFY), so only this one shows.
Scope {
    id: osd

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var src: Pipewire.defaultAudioSource
    PwObjectTracker { objects: [osd.sink, osd.src] }

    property int icon: 0
    property string label: ""
    property real value: 0      // 0..1, more with pavucontrol's boost
    property bool muted: false
    property bool shown: false

    // values arrive as Pipewire and sysfs load; nothing before this was the user
    property bool armed: false
    Timer { interval: Settings.osdArmDelay; running: true; onTriggered: osd.armed = true }

    function show(icon, label, value, muted) {
        if (!armed || Config.quickOpen) return   // quick settings shows these itself
        osd.icon = icon; osd.label = label; osd.value = value; osd.muted = muted
        shown = true
        hide.restart()
    }
    Timer { id: hide; interval: Settings.osdTimeout; onTriggered: osd.shown = false }

    function showSink() {
        const a = sink.audio, v = a.volume
        show(a.muted ? 0xF0581 : Util.headphones(sink) ? 0xF02CB : v < 0.34 ? 0xF057F : v < 0.67 ? 0xF0580 : 0xF057E,
             sink.description || sink.name, v, a.muted)
    }
    function showSrc() {
        const a = src.audio
        show(a.muted ? 0xF036D : 0xF036C, src.description || src.name, a.volume, a.muted)
    }

    Connections {
        target: osd.sink?.audio ?? null
        function onVolumeChanged() { osd.showSink() }
        function onMutedChanged() { osd.showSink() }
    }
    Connections {
        target: osd.src?.audio ?? null
        function onVolumeChanged() { osd.showSrc() }
        function onMutedChanged() { osd.showSrc() }
    }
    Connections {
        target: Brightness
        function onPctChanged() { osd.show(Brightness.pct < 50 ? 0xF00DF : 0xF00E0, "Brightness", Brightness.pct / 100, false) }
    }

    PanelWindow {
        screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0]
        visible: card.opacity > 0
        anchors.bottom: true            // bottom edge only: centred horizontally
        margins.bottom: 72
        implicitWidth: 320
        implicitHeight: 56
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        mask: Region {}                 // fully click-through
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "osd"

        Rectangle {
            id: card
            anchors.fill: parent
            radius: height / 2
            color: Qt.alpha(Theme.mainBg, 0.92)
            border.color: Theme.mainFg
            border.width: 1
            opacity: osd.shown ? 1 : 0
            scale: osd.shown ? 1 : 0.92
            // leaving is quicker than arriving
            Behavior on opacity { id: fade; NumberAnimation { duration: fade.targetValue > 0 ? 200 : 150; easing.type: Easing.OutCubic } }
            Behavior on scale { id: pop; NumberAnimation { duration: pop.targetValue === 1 ? 220 : 150; easing.type: Easing.OutCubic } }

            Row {
                anchors { fill: parent; leftMargin: 20; rightMargin: 20 }
                spacing: 14

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 26
                    horizontalAlignment: Text.AlignHCenter
                    text: Theme.g(osd.icon || 0xF057E)
                    color: osd.muted ? Qt.alpha(Theme.mainFg, 0.5) : Theme.actBg
                    font { family: Theme.font; pixelSize: 22 }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 26 - pctText.width - 2 * parent.spacing
                    spacing: 6

                    Text {
                        width: parent.width
                        text: osd.muted ? osd.label + " · muted" : osd.label
                        elide: Text.ElideRight
                        color: Theme.mainFg
                        opacity: 0.8
                        font { family: Theme.font; pixelSize: 11 }
                    }
                    Rectangle {
                        width: parent.width
                        height: 6
                        radius: 3
                        color: Qt.alpha(Theme.mainFg, 0.18)
                        Rectangle {
                            height: parent.height
                            radius: parent.radius
                            width: parent.width * Math.max(0, Math.min(1, osd.value))
                            color: osd.muted ? Qt.alpha(Theme.mainFg, 0.4) : Theme.mainFg
                            Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                        }
                    }
                }

                Text {
                    id: pctText
                    anchors.verticalCenter: parent.verticalCenter
                    width: 40
                    horizontalAlignment: Text.AlignRight
                    text: Math.round(osd.value * 100) + "%"
                    color: Theme.actFg
                    font { family: Theme.font; pixelSize: 13; bold: true }
                }
            }
        }
    }
}
