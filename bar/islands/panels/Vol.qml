import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import qs
import qs.islands

// Sound. A card for where it's playing: the device by name (tap it to pick another; they unfold
// in the card), and its level as a fat track with the speaker riding the fill (tap the glyph to
// mute). Under it the mic the same way, slimmer. Then each app playing: its icon (tap to mute
// it), its name, its own level.
Panel {
    id: p
    implicitWidth: 340
    spacing: 12
    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var src: Pipewire.defaultAudioSource
    readonly property var sinks: Pipewire.nodes.values.filter(n => n.audio && n.isSink && !n.isStream)
    readonly property var sources: Pipewire.nodes.values.filter(n => n.audio && !n.isSink && !n.isStream)
    // apps playing: Quickshell counts their streams as sinks (cava's recording stream isn't one)
    readonly property var apps: Pipewire.nodes.values.filter(n => n.audio && n.isStream && n.isSink)
    PwObjectTracker { objects: [p.sink, p.src].concat(p.sinks, p.sources, p.apps) }
    property string picking: ""      // "out" | "in" | "": which device list is unfolded

    // apps by name; devices by profile ("Speaker", not "Ryzen HD Audio Controller Speaker"), with
    // the screen an HDMI output goes to when ALSA knows it ("HDMI 2 · LG FHD")
    function name(n) {
        const app = n?.properties?.["application.name"]
        if (app) return app
        const prof = n?.properties?.["device.profile.description"] || n?.description || n?.nickname || n?.name || ""
        const screen = (n?.description ?? "").match(/\[([^\]]+)\]/)
        return prof.replace(/^HDMI \/ DisplayPort (\d) Output$/, "HDMI $1") + (screen ? "  ·  " + screen[1] : "")
    }
    function appId(n) { return n?.properties?.["application.icon-name"] || n?.properties?.["application.process.binary"] || n?.properties?.["application.name"] || "" }
    function kind(n) { return Util.audioGlyph(n) }
    function where(n) {
        const nm = n?.name ?? ""
        return nm.startsWith("bluez") ? "Bluetooth" : /HDMI/.test(nm) ? "HDMI" : /jamesdsp|jdsp/i.test(nm) ? "Effects" : nm.startsWith("alsa") ? "Built-in" : ""
    }

    // ---- a device and its level, with its picker folded under ----
    component Device: Rectangle {
        id: dev
        property var node
        property var list: []
        property string which
        property bool big: true
        readonly property bool open: p.picking === which
        readonly property bool muted: !!node?.audio?.muted
        width: parent.width
        height: dc.implicitHeight + 24
        radius: 16
        color: Look.raise
        Behavior on height { Anim {} }
        clip: true
        Column {
            id: dc
            x: 12; y: 12
            width: parent.width - 24
            spacing: 10
            // which device: tap to pick another
            Item {
                width: parent.width
                height: 34
                Rectangle {
                    width: 34; height: 34; radius: 17
                    color: Qt.alpha(Look.accent, 0.16)
                    G { anchors.centerIn: parent; glyph: p.kind(dev.node); font.pixelSize: 16; color: Look.accent }
                }
                Column {
                    x: 44
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - x - 30
                    T { width: parent.width; text: dev.node ? p.name(dev.node) : dev.which === "out" ? "No output" : "No microphone"; font.weight: Font.DemiBold; elide: Text.ElideRight }
                    T {
                        text: [dev.which === "out" ? "Output" : "Microphone", p.where(dev.node)].filter(s => s).join("  ·  ")
                            + (dev.muted ? "  ·  muted" : "")
                        color: dev.muted ? Look.alert : Look.faint
                        font.pixelSize: Look.small
                    }
                }
                G {
                    visible: dev.list.length > 1
                    anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                    glyph: 0xF0140
                    font.pixelSize: 18
                    color: ph.hovered || dev.open ? Look.text : Look.faint
                    rotation: dev.open ? 180 : 0
                    Behavior on rotation { Anim { type: "fast" } }
                }
                HoverHandler { id: ph; cursorShape: dev.list.length > 1 ? Qt.PointingHandCursor : Qt.ArrowCursor }
                TapHandler { onTapped: if (dev.list.length > 1) p.picking = dev.open ? "" : dev.which }
            }
            // the picker
            Column {
                visible: dev.open
                width: parent.width
                spacing: 2
                Repeater {
                    model: dev.open ? dev.list : []
                    Rectangle {
                        id: opt
                        required property var modelData
                        readonly property bool cur: modelData === dev.node
                        width: parent.width
                        height: 34
                        radius: 10
                        color: cur ? Qt.alpha(Look.accent, 0.16) : oh.hovered ? Look.hover : "transparent"
                        Behavior on color { Fade {} }
                        G { x: 10; anchors.verticalCenter: parent.verticalCenter; glyph: p.kind(opt.modelData); font.pixelSize: 14; color: opt.cur ? Look.accent : Look.dim }
                        T {
                            x: 36
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - x - 30
                            text: p.name(opt.modelData)
                            font.weight: opt.cur ? Font.DemiBold : Font.Normal
                            elide: Text.ElideRight
                        }
                        G {
                            visible: opt.cur
                            anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                            glyph: 0xF012C
                            font.pixelSize: 14
                            color: Look.accent
                        }
                        HoverHandler { id: oh; cursorShape: Qt.PointingHandCursor }
                        TapHandler {
                            onTapped: {
                                if (dev.which === "out") Pipewire.preferredDefaultAudioSink = opt.modelData
                                else Pipewire.preferredDefaultAudioSource = opt.modelData
                                p.picking = ""
                            }
                        }
                    }
                }
            }
            Track {
                width: parent.width
                implicitHeight: dev.big ? 46 : 36
                radius: dev.big ? 15 : 12
                visible: !!dev.node?.audio
                value: dev.node?.audio?.volume ?? 0
                muted: dev.muted
                step: 0.02
                glyph: dev.which === "in" ? (dev.muted ? 0xF036D : 0xF036C)
                    : dev.muted ? 0xF0581 : value < 0.34 ? 0xF057F : value < 0.67 ? 0xF0580 : 0xF057E
                text: dev.muted ? "—" : Math.round(value * 100) + "%"
                onMoved: v => Util.setVolume(dev.node, v)
                onGlyphTapped: Util.setMuted(dev.node, !dev.muted)
            }
        }
    }

    Device { node: p.sink; list: p.sinks; which: "out" }
    Device { node: p.src; list: p.sources; which: "in"; big: false }

    // ---- apps ----
    Column {
        visible: p.apps.length > 0
        width: parent.width
        spacing: 4
        T {
            x: 2
            bottomPadding: 2
            text: "Apps"
            color: Look.faint
            font.pixelSize: 10
            font.weight: Font.Bold
            font.letterSpacing: 0.8
            font.capitalization: Font.AllUppercase
        }
        Repeater {
            model: ScriptModel { values: p.apps }
            Item {
                id: app
                required property var modelData
                readonly property bool muted: !!modelData.audio?.muted
                width: parent.width
                height: 36
                // the icon: tap to mute this one
                Rectangle {
                    x: 2
                    anchors.verticalCenter: parent.verticalCenter
                    width: 30; height: 30; radius: 15
                    color: am.hovered ? Look.hover : Look.raise
                    Behavior on color { Fade {} }
                    AppIcon { anchors.centerIn: parent; appId: p.appId(app.modelData); size: 18; opacity: app.muted ? 0.35 : 1 }
                    G {
                        visible: app.muted
                        anchors { right: parent.right; bottom: parent.bottom; margins: -3 }
                        glyph: 0xF0581
                        font.pixelSize: 11
                        height: 14
                        color: Look.alert
                    }
                    HoverHandler { id: am; cursorShape: Qt.PointingHandCursor }
                    TapHandler { onTapped: Util.setMuted(app.modelData, !app.muted) }
                }
                T {
                    x: 42
                    anchors.verticalCenter: parent.verticalCenter
                    width: 86
                    text: p.name(app.modelData)
                    color: app.muted ? Look.faint : Look.text
                    elide: Text.ElideRight
                }
                Slide {
                    x: 134
                    width: parent.width - x - 48
                    fill: app.muted ? Look.faint : Look.accent
                    value: app.modelData.audio?.volume ?? 0
                    onMoved: v => Util.setVolume(app.modelData, v)
                }
                T {
                    anchors { right: parent.right; rightMargin: 2; verticalCenter: parent.verticalCenter }
                    width: 38
                    horizontalAlignment: Text.AlignRight
                    text: app.muted ? "—" : Math.round((app.modelData.audio?.volume ?? 0) * 100) + "%"
                    color: Look.dim
                    font.pixelSize: Look.small
                }
            }
        }
    }
}
